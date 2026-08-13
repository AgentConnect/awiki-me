// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/push_installation.dart';
import 'package:awiki_me/src/application/ports/push_installation_port.dart';
import 'package:awiki_me/src/application/remote_push_installation_coordinator.dart';
import 'package:awiki_me/src/application/realtime_application_service.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/data/storage/platform_scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository_factory.dart';
import 'package:awiki_me/src/domain/entities/remote_push_event.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/services/remote_push_client.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_support.dart';

void main() {
  test('bootstrap exposes its app-lifetime remote Push dependencies', () {
    final client = _FakeRemotePushClient();
    final coordinator = RemotePushInstallationCoordinator(
      client: client,
      installations: _RecordingPushInstallationPort(<String>[]),
    );
    final gateway = FakeAwikiGateway();
    final bootstrap = AppBootstrap(
      environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
      accountGateway: gateway,
      gateway: gateway,
      realtimeGateway: FakeRealtimeGateway(),
      notificationFacade: FakeNotificationFacade(),
      e2eeFacade: FakeE2eeFacade(),
      localePreferenceService: FakeLocalePreferenceService(),
      updateService: FakeUpdateService(),
      remotePushClient: client,
      remotePushInstallationCoordinator: coordinator,
    );

    expect(bootstrap.remotePushClient, same(client));
    expect(bootstrap.remotePushInstallationCoordinator, same(coordinator));
  });

  test(
    'create composes the app-lifetime client with authenticated installation RPC',
    () async {
      final gateway = FakeAwikiGateway();
      final sessions = FakeAppSessionService(gateway);
      await sessions.activateIdentity(
        const AppSession(
          did: 'did:test:owner',
          identityId: 'owner-a',
          displayName: 'Owner',
          authenticated: true,
          jwtToken: 'bearer-a',
        ),
      );
      final core = _buildBootstrap(
        gateway: gateway,
        appSessionService: sessions,
      );
      final requests = <http.Request>[];
      final httpClient = AwikiOnboardingUtilityHttpClient(
        baseUrl: 'https://awiki.ai',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 'req-1',
              'result': <String, Object?>{
                'installation': <String, Object?>{
                  'installation_id': 'installation-a',
                  'provider': 'aliyun_emas',
                  'provider_device_id': 'provider-device-a',
                  'platform': 'android',
                  'logical_device_id': 'device-a',
                  'app_id': 'app-key-a',
                  'client_product': 'awiki-me',
                  'client_version': '0.1.22+32',
                  'capabilities': <String>['awiki.agent.message.v1'],
                  'status': 'active',
                },
              },
            }),
            200,
          );
        }),
      );
      final client = _FakeRemotePushClient();

      final bootstrap = await AppBootstrap.create(
        remotePushClient: client,
        createCoreBootstrapForTesting: () async => core,
        remotePushHttpClientForTesting: httpClient,
      );
      await bootstrap.remotePushInstallationCoordinator!.bindActiveSession(
        RemotePushInstallationSession(
          storageScopeId: _scopeId,
          ownerDid: 'did:test:owner',
          generation: 1,
          logicalDeviceId: 'device-a',
        ),
      );

      expect(bootstrap.remotePushClient, same(client));
      expect(bootstrap.remotePushInstallationCoordinator, isNotNull);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/user-service/v1/push/rpc');
      expect(requests.single.headers['authorization'], 'Bearer bearer-a');
      expect(
        jsonDecode(requests.single.body),
        containsPair('method', 'upsert_installation'),
      );
    },
  );

  test(
    'bootstrap disables the Push installation before stopping its runtime',
    () async {
      final calls = <String>[];
      final client = _FakeRemotePushClient();
      final coordinator = RemotePushInstallationCoordinator(
        client: client,
        installations: _RecordingPushInstallationPort(calls),
      );
      await coordinator.bindActiveSession(
        RemotePushInstallationSession(
          storageScopeId: _scopeId,
          ownerDid: 'did:test:owner',
          generation: 1,
          logicalDeviceId: 'device-a',
        ),
      );
      calls.clear();
      final gateway = FakeAwikiGateway();
      final bootstrap = AppBootstrap(
        environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
        accountGateway: gateway,
        gateway: gateway,
        realtimeGateway: FakeRealtimeGateway(),
        notificationFacade: FakeNotificationFacade(),
        e2eeFacade: FakeE2eeFacade(),
        localePreferenceService: FakeLocalePreferenceService(),
        updateService: FakeUpdateService(),
        realtimeApplicationService: _RecordingRealtimeService(calls),
        remotePushClient: client,
        remotePushInstallationCoordinator: coordinator,
      );

      await bootstrap.dispose();

      expect(calls, <String>['disable_installation', 'dispose_runtime']);
    },
  );

  test(
    'bootstrap bounds a stuck Push disable and still stops its runtime',
    () async {
      final calls = <String>[];
      final coordinator = _NeverCompletingDisableCoordinator();
      final gateway = FakeAwikiGateway();
      final bootstrap = _buildBootstrap(
        gateway: gateway,
        realtimeApplicationService: _RecordingRealtimeService(calls),
        remotePushClient: _FakeRemotePushClient(),
        remotePushInstallationCoordinator: coordinator,
        remotePushDisposeTimeout: const Duration(milliseconds: 5),
      );
      final stopwatch = Stopwatch()..start();

      await bootstrap.dispose();
      stopwatch.stop();

      expect(coordinator.disableCalls, 1);
      expect(calls, <String>['dispose_runtime']);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    },
  );

  test(
    'macOS debug/profile account store avoids unsigned Keychain writes',
    () async {
      if (!Platform.isMacOS) {
        return;
      }
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-bootstrap-test-',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getApplicationSupportDirectory') {
              return tempDir.path;
            }
            return null;
          });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final store = await AppBootstrap.buildAccountStoreForTesting();
      expect(store, isA<FileAppKeyValueStore>());

      await store.write(key: 'credential', value: 'ok');
      final restored = FileAppKeyValueStore.forFile(
        File('${tempDir.path}/awiki_me_credentials.json'),
      );
      expect(await restored.read(key: 'credential'), 'ok');
    },
  );

  test(
    'explicit root cannot select plaintext scope secrets in normal build',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'awiki-bootstrap-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final repository = buildScopeSecretRepository(appStateRoot: tempDir.path);

      expect(repository, isA<PlatformScopeSecretRepository>());
    },
  );
}

final _scopeId = StorageScopeId.parse('00000000-0000-4000-8000-000000000001');

AppBootstrap _buildBootstrap({
  required FakeAwikiGateway gateway,
  AppSessionService? appSessionService,
  RealtimeApplicationService? realtimeApplicationService,
  RemotePushClient? remotePushClient,
  RemotePushInstallationCoordinator? remotePushInstallationCoordinator,
  Duration remotePushDisposeTimeout = const Duration(seconds: 3),
}) {
  return AppBootstrap(
    environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
    accountGateway: gateway,
    gateway: gateway,
    realtimeGateway: FakeRealtimeGateway(),
    notificationFacade: FakeNotificationFacade(),
    e2eeFacade: FakeE2eeFacade(),
    localePreferenceService: FakeLocalePreferenceService(),
    updateService: FakeUpdateService(),
    appSessionService: appSessionService,
    realtimeApplicationService: realtimeApplicationService,
    remotePushClient: remotePushClient,
    remotePushInstallationCoordinator: remotePushInstallationCoordinator,
    remotePushDisposeTimeout: remotePushDisposeTimeout,
  );
}

final class _FakeRemotePushClient implements RemotePushClient {
  @override
  Stream<RemotePushEvent> get events => const Stream<RemotePushEvent>.empty();

  @override
  List<RemotePushEvent> get pendingEvents => const <RemotePushEvent>[];

  @override
  RemotePushRegistration? get registration => const RemotePushRegistration(
    provider: 'aliyun_emas',
    providerDeviceId: 'provider-device-a',
    platform: 'android',
    clientProduct: 'awiki-me',
    clientVersion: '0.1.22+32',
    capabilities: <String>['awiki.agent.message.v1'],
    appId: 'app-key-a',
  );

  @override
  Future<void> acknowledgePendingEvents(Iterable<String> deliveryIds) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<RemotePushRegistration?> initialize() async => registration;

  @override
  Future<void> pullPendingEvents() async {}
}

final class _RecordingPushInstallationPort implements PushInstallationPort {
  _RecordingPushInstallationPort(this.calls);

  final List<String> calls;

  @override
  Future<PushInstallation> disable(String installationId) async {
    calls.add('disable_installation');
    return const PushInstallation(
      installationId: 'installation-a',
      provider: 'aliyun_emas',
      providerDeviceId: 'provider-device-a',
      platform: 'android',
      status: 'disabled',
      clientProduct: 'awiki-me',
      clientVersion: '0.1.22+32',
      capabilities: <String>['awiki.agent.message.v1'],
      logicalDeviceId: 'device-a',
      appId: 'app-key-a',
    );
  }

  @override
  Future<PushInstallation> upsert(RemotePushRegistration registration) async {
    return PushInstallation(
      installationId: 'installation-a',
      provider: registration.provider,
      providerDeviceId: registration.providerDeviceId,
      platform: registration.platform,
      status: 'active',
      clientProduct: registration.clientProduct,
      clientVersion: registration.clientVersion,
      capabilities: registration.capabilities,
      logicalDeviceId: registration.logicalDeviceId,
      appId: registration.appId,
    );
  }
}

final class _RecordingRealtimeService implements RealtimeApplicationService {
  _RecordingRealtimeService(this.calls);

  final List<String> calls;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates =>
      const Stream<RealtimeConnectionStatus>.empty();

  @override
  bool get isRunning => false;

  @override
  Stream<RealtimeUpdate> get updates => const Stream<RealtimeUpdate>.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    calls.add('dispose_runtime');
  }
}

final class _NeverCompletingDisableCoordinator
    extends RemotePushInstallationCoordinator {
  _NeverCompletingDisableCoordinator()
    : super(
        client: _FakeRemotePushClient(),
        installations: _RecordingPushInstallationPort(<String>[]),
      );

  int disableCalls = 0;

  @override
  Future<void> disableCurrentInstallation() {
    disableCalls += 1;
    return Completer<void>().future;
  }
}
