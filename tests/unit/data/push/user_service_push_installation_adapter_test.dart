import 'dart:convert';

import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/auth/auth_session_coordinator.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/agent_notification_preference.dart';
import 'package:awiki_me/src/data/push/user_service_push_installation_adapter.dart';
import 'package:awiki_me/src/data/services/authenticated_user_service_rpc_client.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/domain/services/remote_push_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const registration = RemotePushRegistration(
    provider: 'aliyun_emas',
    providerDeviceId: 'android-device-123',
    platform: 'android',
    clientProduct: 'awiki-me',
    clientVersion: '0.1.22+32',
    capabilities: <String>['awiki.agent.message.v1'],
    logicalDeviceId: 'logical-device-1',
    appId: 'emas-app-key',
  );

  test(
    'upsert sends only the authenticated safe installation params',
    () async {
      final harness = _AdapterHarness(
        result: _installationResult(status: 'active', disabledAt: null),
      );

      final installation = await harness.adapter.upsert(registration);

      expect(harness.httpClient.requestCount, 1);
      expect(harness.httpClient.lastPath, '/user-service/v1/push/rpc');
      expect(
        harness.httpClient.lastAuthorization,
        'Bearer device-access-token',
      );
      expect(harness.httpClient.lastBody, <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'upsert_installation',
        'params': <String, Object?>{
          'provider': 'aliyun_emas',
          'provider_device_id': 'android-device-123',
          'platform': 'android',
          'logical_device_id': 'logical-device-1',
          'app_id': 'emas-app-key',
          'client_product': 'awiki-me',
          'client_version': '0.1.22+32',
          'capabilities': <String>['awiki.agent.message.v1'],
        },
        'id': 'req-1',
      });
      expect(installation.installationId, 'installation-1');
      expect(installation.provider, 'aliyun_emas');
      expect(installation.providerDeviceId, 'android-device-123');
      expect(installation.platform, 'android');
      expect(installation.logicalDeviceId, 'logical-device-1');
      expect(installation.appId, 'emas-app-key');
      expect(installation.status, 'active');

      final params = harness.httpClient.lastBody!['params']! as Map;
      expect(params, isNot(contains('app_secret')));
      expect(params, isNot(contains('appSecret')));
      expect(params, isNot(contains('bearer_token')));
      expect(params, isNot(contains('token')));
    },
  );

  test('upsert omits absent optional registration identifiers', () async {
    final harness = _AdapterHarness(
      result: _installationResult(
        status: 'active',
        logicalDeviceId: null,
        appId: null,
        disabledAt: null,
      ),
    );

    await harness.adapter.upsert(
      const RemotePushRegistration(
        provider: 'aliyun_emas',
        providerDeviceId: 'android-device-123',
        platform: 'android',
        clientProduct: 'awiki-me',
        clientVersion: '0.1.22+32',
        capabilities: <String>['awiki.agent.message.v1'],
      ),
    );

    expect(harness.httpClient.lastBody!['params'], <String, Object?>{
      'provider': 'aliyun_emas',
      'provider_device_id': 'android-device-123',
      'platform': 'android',
      'client_product': 'awiki-me',
      'client_version': '0.1.22+32',
      'capabilities': <String>['awiki.agent.message.v1'],
    });
  });

  test(
    'disable uses the authenticated endpoint and exact installation id',
    () async {
      final harness = _AdapterHarness(
        result: _installationResult(
          status: 'disabled',
          disabledAt: '2026-07-30T01:00:00Z',
        ),
      );

      final installation = await harness.adapter.disable('installation-1');

      expect(harness.httpClient.lastPath, '/user-service/v1/push/rpc');
      expect(
        harness.httpClient.lastAuthorization,
        'Bearer device-access-token',
      );
      expect(harness.httpClient.lastBody, <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'disable_installation',
        'params': <String, Object?>{'installation_id': 'installation-1'},
        'id': 'req-1',
      });
      expect(installation.installationId, 'installation-1');
      expect(installation.status, 'disabled');
    },
  );

  test(
    'missing authenticated client fails closed without an HTTP fallback',
    () async {
      final httpClient = _RpcHttpClient(
        result: _installationResult(status: 'active', disabledAt: null),
      );
      final utility = AwikiOnboardingUtilityHttpClient(
        baseUrl: 'https://example.test',
        httpClient: httpClient,
      );
      final adapter = UserServicePushInstallationAdapter(
        userServiceUrl: 'https://example.test',
        client: utility,
      );

      await expectLater(
        adapter.upsert(registration),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'push_installation_auth_required',
          ),
        ),
      );
      expect(httpClient.requestCount, 0);
    },
  );

  for (final mismatch in <({String name, String key, Object? value})>[
    (name: 'provider', key: 'provider', value: 'another_provider'),
    (
      name: 'provider DeviceId',
      key: 'provider_device_id',
      value: 'android-device-other',
    ),
    (name: 'platform', key: 'platform', value: 'ios'),
    (
      name: 'logical device id',
      key: 'logical_device_id',
      value: 'logical-device-other',
    ),
    (name: 'AppKey', key: 'app_id', value: 'another-app-key'),
    (name: 'client product', key: 'client_product', value: 'another-client'),
    (name: 'client version', key: 'client_version', value: '0.1.23+33'),
    (
      name: 'capabilities',
      key: 'capabilities',
      value: <String>['another.capability'],
    ),
    (name: 'status', key: 'status', value: 'disabled'),
  ]) {
    test(
      'upsert rejects a response with mismatched ${mismatch.name}',
      () async {
        final result = _installationResult(status: 'active', disabledAt: null);
        final installation = result['installation']! as Map<String, Object?>;
        installation[mismatch.key] = mismatch.value;
        final harness = _AdapterHarness(result: result);

        await expectLater(
          harness.adapter.upsert(registration),
          throwsFormatException,
        );
      },
    );
  }

  test('disable rejects a response for another installation', () async {
    final harness = _AdapterHarness(
      result: _installationResult(
        installationId: 'installation-other',
        status: 'disabled',
        disabledAt: '2026-07-30T01:00:00Z',
      ),
    );

    await expectLater(
      harness.adapter.disable('installation-1'),
      throwsFormatException,
    );
  });

  test('disable rejects a response that is not disabled', () async {
    final harness = _AdapterHarness(
      result: _installationResult(status: 'active', disabledAt: null),
    );

    await expectLater(
      harness.adapter.disable('installation-1'),
      throwsFormatException,
    );
  });

  test('preference read accepts only the closed server response', () async {
    final harness = _AdapterHarness(result: _preferenceResult('unset'));

    final preference = await harness.adapter.getAgentNotificationPreference();

    expect(preference.urgent, AgentNotificationUrgentPreference.unset);
    expect(harness.httpClient.lastBody, <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'get_agent_notification_preference',
      'params': <String, Object?>{'schema': 'awiki.agent.message.v1'},
      'id': 'req-1',
    });
  });

  test(
    'preference mutation requires matching server acknowledgement',
    () async {
      final harness = _AdapterHarness(result: _preferenceResult('enabled'));

      final preference = await harness.adapter.setAgentNotificationPreference(
        urgent: AgentNotificationUrgentPreference.enabled,
      );

      expect(preference.urgent, AgentNotificationUrgentPreference.enabled);
      expect(harness.httpClient.lastBody, <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'set_agent_notification_preference',
        'params': <String, Object?>{
          'schema': 'awiki.agent.message.v1',
          'urgent': 'enabled',
        },
        'id': 'req-1',
      });
    },
  );

  test('preference mutation rejects a stale server acknowledgement', () async {
    final harness = _AdapterHarness(result: _preferenceResult('disabled'));

    await expectLater(
      harness.adapter.setAgentNotificationPreference(
        urgent: AgentNotificationUrgentPreference.enabled,
      ),
      throwsFormatException,
    );
  });
}

Map<String, Object?> _preferenceResult(String urgent) => <String, Object?>{
  'schema': 'awiki.agent.message.v1',
  'urgent': urgent,
  'updated_at': urgent == 'unset' ? null : '2026-08-11T12:00:00Z',
};

Map<String, Object?> _installationResult({
  String installationId = 'installation-1',
  String provider = 'aliyun_emas',
  String providerDeviceId = 'android-device-123',
  String platform = 'android',
  String? logicalDeviceId = 'logical-device-1',
  String? appId = 'emas-app-key',
  String clientProduct = 'awiki-me',
  String clientVersion = '0.1.22+32',
  List<String> capabilities = const <String>['awiki.agent.message.v1'],
  required String status,
  required String? disabledAt,
}) {
  return <String, Object?>{
    'installation': <String, Object?>{
      'installation_id': installationId,
      'owner_did': 'did:wba:example.test:alice',
      'provider': provider,
      'provider_device_id': providerDeviceId,
      'platform': platform,
      'logical_device_id': logicalDeviceId,
      'app_id': appId,
      'client_product': clientProduct,
      'client_version': clientVersion,
      'capabilities': capabilities,
      'status': status,
      'last_seen_at': '2026-07-30T00:00:00Z',
      'disabled_at': disabledAt,
      'created_at': '2026-07-29T00:00:00Z',
      'updated_at': '2026-07-30T00:00:00Z',
    },
  };
}

final class _AdapterHarness {
  _AdapterHarness({required Map<String, Object?> result})
    : httpClient = _RpcHttpClient(result: result) {
    final utility = AwikiOnboardingUtilityHttpClient(
      baseUrl: 'https://example.test',
      httpClient: httpClient,
    );
    adapter = UserServicePushInstallationAdapter(
      userServiceUrl: 'https://example.test',
      client: utility,
      authenticatedClient: AuthenticatedUserServiceRpcClient(
        client: utility,
        sessions: AuthSessionCoordinator(sessions: _Sessions()),
      ),
    );
  }

  final _RpcHttpClient httpClient;
  late final UserServicePushInstallationAdapter adapter;
}

final class _RpcHttpClient extends http.BaseClient {
  _RpcHttpClient({required this.result});

  final Map<String, Object?> result;
  int requestCount = 0;
  String? lastAuthorization;
  String? lastPath;
  Map<String, Object?>? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    lastAuthorization = request.headers['Authorization'];
    lastPath = request.url.path;
    if (request is http.Request) {
      final decoded = jsonDecode(request.body);
      if (decoded is Map) {
        lastBody = decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }
    final bytes = utf8.encode(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'result': result,
        'id': 'req-1',
      }),
    );
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

final class _Sessions
    with AppSessionTransitionGuard
    implements AppSessionService {
  static const session = AppSession(
    did: 'did:wba:example.test:alice',
    identityId: 'identity-1',
    displayName: 'Alice',
    jwtToken: 'device-access-token',
  );

  @override
  Future<AppSession?> currentSession() async => session;

  @override
  Future<AppSession?> refreshSession() async => session;

  @override
  Future<AppSession> activateIdentity(
    AppSession identity, {
    AppSessionTransition? transition,
    Future<void> Function(AppSession session)? initializeIdentitySession,
  }) async {
    final requestedTransition = transition ?? beginSessionTransition();
    if (!isSessionTransitionCurrent(requestedTransition)) {
      throw const AppSessionTransitionSuperseded();
    }
    await initializeIdentitySession?.call(identity);
    markSessionTransitionCommitted(requestedTransition);
    return identity;
  }

  @override
  Future<AppSessionLease?> currentSessionLease() async =>
      sessionLeaseFor(session);

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) =>
      throw UnimplementedError();

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[session];

  @override
  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  }) async => session;

  @override
  Future<void> logout() async {}

  @override
  Future<AppSession?> restoreSession() async => session;
}
