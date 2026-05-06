import 'dart:convert';

import 'package:awiki_me/src/data/gateways/awiki_anp_gateway.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/services/did_registration_facade.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_support.dart';

void main() {
  test(
    'profile and relationship methods use user service RPC client',
    () async {
      final storage = _InMemorySecureStorage()
        ..seed('awiki_me_session_did', 'did:wba:awiki.ai:alice:e1_sender')
        ..seed('awiki_me_session_token', 'token')
        ..seed('awiki_me_session_credential', 'default')
        ..seed('awiki_me_session_display_name', 'Alice')
        ..seed('awiki_me_session_handle', 'alice');
      final seen = <String, Map<String, Object?>>{};
      final client = MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        final method = payload['method']?.toString() ?? '';
        seen[method] = <String, Object?>{
          'path': request.url.path,
          'authorization': request.headers['Authorization'],
          'params': payload['params'],
        };
        if (method == 'get_me') {
          return _rpcResult(<String, Object?>{
            'did': 'did:wba:awiki.ai:alice:e1_sender',
            'nick_name': 'Alice',
            'bio': 'bio',
            'tags': <String>['ai'],
            'profile_md': '# Alice',
            'handle': 'alice',
          });
        }
        if (method == 'update_me') {
          return _rpcResult(<String, Object?>{
            'did': 'did:wba:awiki.ai:alice:e1_sender',
            'nick_name': 'Alice 2',
            'bio': 'bio 2',
            'tags': <String>['agent'],
            'profile_md': '# Alice 2',
            'handle': 'alice',
          });
        }
        if (method == 'get_public_profile') {
          return _rpcResult(<String, Object?>{
            'did': 'did:wba:awiki.ai:bob:e1_peer',
            'nick_name': 'Bob',
            'handle': 'bob',
          });
        }
        if (method == 'follow' ||
            method == 'unfollow' ||
            method == 'get_status') {
          return _rpcResult(<String, Object?>{
            'did': 'did:wba:awiki.ai:bob:e1_peer',
            'display_name': 'Bob',
            'status': method == 'get_status' ? 'following' : 'ok',
          });
        }
        if (method == 'get_followers' || method == 'get_following') {
          return _rpcResult(<String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'did': 'did:wba:awiki.ai:bob:e1_peer',
                'display_name': 'Bob',
                'relationship': method == 'get_followers'
                    ? 'follower'
                    : 'following',
              },
            ],
          });
        }
        return http.Response('unexpected method $method', 500);
      });
      final gateway = AwikiAnpGateway(
        userServiceUrl: 'https://awiki.ai',
        messageServiceUrl: 'https://awiki.ai',
        secureStorage: storage,
        httpClient: client,
        initialSession: const SessionIdentity(
          did: 'did:wba:awiki.ai:alice:e1_sender',
          credentialName: 'default',
          displayName: 'Alice',
          handle: 'alice',
          jwtToken: 'token',
        ),
      );

      final me = await gateway.loadMyProfile();
      final updated = await gateway.updateProfile(
        const ProfilePatch(
          nickName: 'Alice 2',
          bio: 'bio 2',
          tags: <String>['agent'],
          profileMarkdown: '# Alice 2',
        ),
      );
      final publicProfile = await gateway.loadPublicProfile('bob');
      await gateway.follow('bob');
      await gateway.unfollow('bob');
      final status = await gateway.getRelationshipStatus('bob');
      final followers = await gateway.listFollowers();
      final following = await gateway.listFollowing();

      expect(me.nickName, 'Alice');
      expect(updated.nickName, 'Alice 2');
      expect(publicProfile.did, 'did:wba:awiki.ai:bob:e1_peer');
      expect(status.relationship, 'following');
      expect(followers.single.relationship, 'follower');
      expect(following.single.relationship, 'following');
      for (final entry in seen.entries) {
        expect(entry.value['authorization'], 'Bearer token');
        if (entry.key == 'get_public_profile') {
          expect(entry.value['path'], '/user-service/did/profile/rpc');
        }
        if (entry.key == 'follow' ||
            entry.key == 'unfollow' ||
            entry.key == 'get_status' ||
            entry.key == 'get_followers' ||
            entry.key == 'get_following') {
          expect(entry.value['path'], '/user-service/did/relationships/rpc');
        }
      }
      expect(seen['update_me']!['params'], <String, Object?>{
        'nick_name': 'Alice 2',
        'bio': 'bio 2',
        'tags': <String>['agent'],
        'profile_md': '# Alice 2',
      });
      expect(
        (seen['follow']!['params'] as Map<String, Object?>)['target_did'],
        'did:wba:awiki.ai:bob:e1_peer',
      );
    },
  );

  test(
    'restoreSession refreshes token through user service without legacy RPC',
    () async {
      final storage = _InMemorySecureStorage()
        ..seed('awiki_me_session_did', 'did:wba:awiki.ai:alice:e1_sender')
        ..seed('awiki_me_session_token', 'stale-token')
        ..seed('awiki_me_session_credential', 'default')
        ..seed('awiki_me_session_display_name', 'Alice')
        ..seed('awiki_me_session_handle', 'alice')
        ..seed(
          'awiki_me_session_did_document',
          jsonEncode(<String, Object?>{
            'id': 'did:wba:awiki.ai:alice:e1_sender',
            'authentication': <String>[
              'did:wba:awiki.ai:alice:e1_sender#key-1',
            ],
          }),
        )
        ..seed('awiki_me_session_private_key_pem', 'private-key')
        ..seed('awiki_me_session_did_domain', 'awiki.ai');
      final seen = <String, Map<String, Object?>>{};
      final client = MockClient((request) async {
        final payload = jsonDecode(request.body) as Map<String, Object?>;
        final method = payload['method']?.toString() ?? '';
        seen[method] = <String, Object?>{
          'path': request.url.path,
          'params': payload['params'],
        };
        if (method == 'verify') {
          return _rpcResult(<String, Object?>{
            'did': 'did:wba:awiki.ai:alice:e1_sender',
            'access_token': 'fresh-token',
          });
        }
        return http.Response('unexpected method $method', 500);
      });
      final gateway = AwikiAnpGateway(
        userServiceUrl: 'https://awiki.ai',
        messageServiceUrl: 'https://awiki.ai',
        secureStorage: storage,
        httpClient: client,
        didRegistrationFacade: _FakeDidRegistrationFacade(),
      );

      final session = await gateway.restoreSession();

      expect(session, isNotNull);
      expect(session!.jwtToken, 'fresh-token');
      expect(await storage.read(key: 'awiki_me_session_token'), 'fresh-token');
      expect(seen['verify']!['path'], '/user-service/did-auth/rpc');
      expect(seen.keys, isNot(contains('get_me')));
    },
  );

  test('local credential boundary only accepts e1 DID identities', () async {
    const legacy = SessionIdentity(
      did: 'did:wba:awiki.ai:alice:k1_legacy',
      credentialName: 'legacy',
      displayName: 'Legacy',
      handle: 'legacy',
      jwtToken: 'token',
    );
    const current = SessionIdentity(
      did: 'did:wba:awiki.ai:alice:e1_current',
      credentialName: 'current',
      displayName: 'Current',
      handle: 'current',
      jwtToken: 'token',
    );
    final legacyGateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[legacy, current]
      ..loginResult = legacy
      ..importedCredential = legacy;
    final gateway = AwikiAnpGateway(
      userServiceUrl: 'https://awiki.ai',
      messageServiceUrl: 'https://awiki.ai',
      legacyGateway: legacyGateway,
      httpClient: MockClient((_) async => http.Response('not used', 500)),
    );

    final credentials = await gateway.listLocalCredentials();

    expect(credentials, const <SessionIdentity>[current]);
    expect(
      () => gateway.loginWithLocalCredential('legacy'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Only e1 DID identities'),
        ),
      ),
    );
    expect(
      () => gateway.importCredentialFromZip(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Only e1 DID identities'),
        ),
      ),
    );
  });
}

http.Response _rpcResult(Map<String, Object?> result) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 'req-1',
      'result': result,
    }),
    200,
  );
}

class _InMemorySecureStorage extends FlutterSecureStorage {
  _InMemorySecureStorage();

  final Map<String, String> _values = <String, String>{};

  void seed(String key, String value) {
    _values[key] = value;
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }
}

class _FakeDidRegistrationFacade implements DidRegistrationFacade {
  @override
  Future<Map<String, Object?>> buildRegisterHandleParams({
    String? phone,
    String? otp,
    String? email,
    required String handle,
    String? inviteCode,
    String? nickName,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> generateDidAuthHeader({
    required Map<String, Object?> didDocument,
    required String privateKeyPem,
    required String domain,
  }) async {
    return 'signed-authorization';
  }

  @override
  Future<bool> isSupported() async {
    return true;
  }
}
