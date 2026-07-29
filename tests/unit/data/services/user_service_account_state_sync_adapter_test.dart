import 'dart:convert';

import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/auth/auth_session_coordinator.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/ports/account_state_sync_port.dart';
import 'package:awiki_me/src/data/services/authenticated_user_service_rpc_client.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:awiki_me/src/data/services/user_service_account_state_sync_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('requires an explicit device-access authenticated client', () async {
    final adapter = UserServiceAccountStateSyncAdapter(
      userServiceUrl: 'https://example.test',
    );

    await expectLater(
      adapter.loadManifest(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'account_state_device_access_auth_required',
        ),
      ),
    );
  });

  test('parses arbitrary precision manifest versions as strings', () async {
    final httpClient = _RpcHttpClient();
    final utility = AwikiOnboardingUtilityHttpClient(
      baseUrl: 'https://example.test',
      httpClient: httpClient,
    );
    final adapter = UserServiceAccountStateSyncAdapter(
      userServiceUrl: 'https://example.test',
      client: utility,
      authenticatedClient: AuthenticatedUserServiceRpcClient(
        client: utility,
        sessions: AuthSessionCoordinator(sessions: _Sessions()),
      ),
    );

    final manifest = await adapter.loadManifest();

    expect(manifest.identityGeneration, '999999999999999999999999999999999999');
    expect(manifest.versionFor(manifest.versions.keys.first), isNotEmpty);
    expect(httpClient.lastAuthorization, 'Bearer device-access-token');
    expect(httpClient.lastPath, '/user-service/account-state/rpc');
  });

  test('rejects unknown manifest fields instead of guessing schema', () async {
    final httpClient = _RpcHttpClient(extraManifestKey: true);
    final utility = AwikiOnboardingUtilityHttpClient(
      baseUrl: 'https://example.test',
      httpClient: httpClient,
    );
    final adapter = UserServiceAccountStateSyncAdapter(
      userServiceUrl: 'https://example.test',
      client: utility,
      authenticatedClient: AuthenticatedUserServiceRpcClient(
        client: utility,
        sessions: AuthSessionCoordinator(sessions: _Sessions()),
      ),
    );

    await expectLater(adapter.loadManifest(), throwsFormatException);
  });

  test(
    'production-style Registry loader preserves u64 max as String',
    () async {
      final adapter =
          UserServiceAccountStateSyncAdapter(
            userServiceUrl: 'https://example.test',
          ).withDeviceRegistryLoader(
            () async => AccountStateDeviceRegistrySnapshot(
              did: 'did:wba:example.test:alice',
              registryVersion: '18446744073709551615',
              devices: const <AccountStateDeviceRegistryEntry>[],
            ),
          );

      final registry = await adapter.loadDeviceRegistry();

      expect(registry.registryVersion, '18446744073709551615');
    },
  );
}

class _RpcHttpClient extends http.BaseClient {
  _RpcHttpClient({this.extraManifestKey = false});

  final bool extraManifestKey;
  String? lastAuthorization;
  String? lastPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastAuthorization = request.headers['Authorization'];
    lastPath = request.url.path;
    final result = <String, Object?>{
      'account_id': 'account-1',
      'current_did': 'did:wba:example.test:alice',
      'identity_generation': '999999999999999999999999999999999999',
      'versions': <String, Object?>{
        'profile': '1',
        'agent_inventory': '2',
        'agent_status': '3',
        'device_registry': '4',
      },
      'server_time': '2026-07-29T00:00:00Z',
      if (extraManifestKey) 'unexpected': true,
    };
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

class _Sessions implements AppSessionService {
  final AppSession session = const AppSession(
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
  Future<AppSession> activateIdentity(AppSession identity) async => identity;

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) =>
      throw UnimplementedError();

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[session];

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) async =>
      session;

  @override
  Future<void> logout() async {}

  @override
  Future<AppSession?> restoreSession() async => session;
}
