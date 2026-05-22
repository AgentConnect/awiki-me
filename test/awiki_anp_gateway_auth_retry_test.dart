import 'dart:convert';

import 'package:awiki_me/src/data/awiki_sdk/awiki_anp_session.dart';
import 'package:awiki_me/src/data/gateways/awiki_anp_gateway.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/repositories/awiki_account_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'relationship status refreshes expired token and retries once',
    () async {
      final account = _FakeAccountGateway();
      final seenTokens = <String>[];
      final client = MockClient((request) async {
        final token = request.headers['Authorization'] ?? '';
        seenTokens.add(token);
        if (seenTokens.length == 1) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'result': null,
              'error': <String, Object?>{
                'code': -32000,
                'message': 'Token has expired',
                'data': null,
              },
              'id': 'req-1',
            }),
            401,
          );
        }
        return http.Response(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 'req-1',
            'result': <String, Object?>{
              'did': 'did:wba:awiki.ai:bob:e1_peer',
              'display_name': 'Bob',
              'status': 'none',
            },
          }),
          200,
        );
      });
      final gateway = AwikiAnpGateway(
        userServiceUrl: 'https://awiki.ai',
        messageServiceUrl: 'https://awiki.ai',
        accountGateway: account,
        httpClient: client,
      );

      final status = await gateway.getRelationshipStatus(
        'did:wba:awiki.ai:bob:e1_peer',
      );

      expect(status.displayName, 'Bob');
      expect(account.refreshCount, 1);
      expect(seenTokens, <String>[
        'Bearer expired-token',
        'Bearer fresh-token',
      ]);
    },
  );

  test(
    'following list uses target DID when owner DID is also present',
    () async {
      final account = _FakeAccountGateway();
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 'req-1',
            'result': <String, Object?>{
              'items': <Object?>[
                <String, Object?>{
                  'did': 'did:wba:awiki.ai:alice:e1_owner',
                  'user_did': 'did:wba:awiki.ai:alice:e1_owner',
                  'target_did': 'did:wba:awiki.ai:bob:e1_peer',
                  'display_name': 'Bob',
                  'relationship': 'following',
                },
              ],
            },
          }),
          200,
        );
      });
      final gateway = AwikiAnpGateway(
        userServiceUrl: 'https://awiki.ai',
        messageServiceUrl: 'https://awiki.ai',
        accountGateway: account,
        httpClient: client,
      );

      final following = await gateway.listFollowing();

      expect(following, hasLength(1));
      expect(following.single.did, 'did:wba:awiki.ai:bob:e1_peer');
      expect(following.single.displayName, 'Bob');
    },
  );

  test('followers list uses follower DID when target DID is owner', () async {
    final account = _FakeAccountGateway();
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'req-1',
          'result': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'did': 'did:wba:awiki.ai:alice:e1_owner',
                'target_did': 'did:wba:awiki.ai:alice:e1_owner',
                'from_did': 'did:wba:awiki.ai:carol:e1_peer',
                'display_name': 'Carol',
                'relationship': 'follower',
              },
            ],
          },
        }),
        200,
      );
    });
    final gateway = AwikiAnpGateway(
      userServiceUrl: 'https://awiki.ai',
      messageServiceUrl: 'https://awiki.ai',
      accountGateway: account,
      httpClient: client,
    );

    final followers = await gateway.listFollowers();

    expect(followers, hasLength(1));
    expect(followers.single.did, 'did:wba:awiki.ai:carol:e1_peer');
    expect(followers.single.displayName, 'Carol');
  });

  test('following list filters legacy K1 DID rows', () async {
    final account = _FakeAccountGateway();
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'req-1',
          'result': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'from_did': 'did:wba:awiki.ai:alice:e1_owner',
                'to_did': 'did:wba:awiki.ai:legacy:k1_peer',
              },
            ],
          },
        }),
        200,
      );
    });
    final gateway = AwikiAnpGateway(
      userServiceUrl: 'https://awiki.ai',
      messageServiceUrl: 'https://awiki.ai',
      accountGateway: account,
      httpClient: client,
    );

    final following = await gateway.listFollowing();

    expect(following, isEmpty);
  });

  test('follow rejects legacy K1 DID before sending request', () async {
    final account = _FakeAccountGateway();
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      return http.Response('{}', 200);
    });
    final gateway = AwikiAnpGateway(
      userServiceUrl: 'https://awiki.ai',
      messageServiceUrl: 'https://awiki.ai',
      accountGateway: account,
      httpClient: client,
    );

    expect(
      () => gateway.follow('did:wba:awiki.ai:legacy:k1_peer'),
      throwsStateError,
    );
    expect(requestCount, 0);
  });
}

class _FakeAccountGateway implements AwikiAccountGateway {
  SessionIdentity _session = const SessionIdentity(
    did: 'did:wba:awiki.ai:alice:e1_owner',
    credentialName: 'alice',
    displayName: 'Alice',
    handle: 'alice',
    jwtToken: 'expired-token',
  );

  int refreshCount = 0;

  @override
  Future<SessionIdentity?> currentSession() async => _session;

  @override
  Future<SessionIdentity?> refreshSession() async {
    refreshCount += 1;
    _session = const SessionIdentity(
      did: 'did:wba:awiki.ai:alice:e1_owner',
      credentialName: 'alice',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'fresh-token',
    );
    return _session;
  }

  @override
  Future<AwikiAnpSession> currentAnpSession({bool requireSigning = false}) {
    return Future<AwikiAnpSession>.value(
      AwikiAnpSession(did: _session.did, jwtToken: _session.jwtToken ?? ''),
    );
  }

  @override
  Future<void> deleteLocalCredential(String credentialName) async {}

  @override
  Future<String?> exportCurrentCredentialAsZip() async => null;

  @override
  Future<SessionIdentity?> importCredentialFromZip() async => null;

  @override
  Future<List<SessionIdentity>> listLocalCredentials() async =>
      <SessionIdentity>[];

  @override
  Future<SessionIdentity> loginWithLocalCredential(
    String credentialName,
  ) async => _session;

  @override
  Future<HandleRegistrationStatus> lookupHandleRegistration({
    required String handle,
  }) async => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<SessionIdentity> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async => throw UnimplementedError();

  @override
  Future<SessionIdentity> registerHandle({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async => throw UnimplementedError();

  @override
  Future<SessionIdentity> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async => throw UnimplementedError();

  @override
  Future<SessionIdentity?> restoreSession() async => _session;

  @override
  Future<bool> checkEmailVerified({required String email}) async => false;

  @override
  Future<void> sendEmailVerification({required String email}) async {}

  @override
  Future<void> sendOtp({required String phone}) async {}
}
