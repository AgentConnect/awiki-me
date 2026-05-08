import 'dart:convert';

import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/awiki_account_service.dart';
import 'package:awiki_me/src/domain/services/did_registration_facade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('registerHandle stores an e1 session and signing material', () async {
    final storage = _MemoryStore();
    final client = MockClient((request) async {
      final payload = jsonDecode(request.body) as Map<String, Object?>;
      expect(request.url.path, '/user-service/did-auth/rpc');
      expect(payload['method'], 'register');
      return http.Response(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': payload['id'],
          'result': <String, Object?>{
            'did': 'did:wba:awiki.ai:alice:e1_test',
            'access_token': 'token',
          },
        }),
        200,
      );
    });
    final service = AwikiAccountService(
      userServiceUrl: 'https://awiki.ai',
      storage: storage,
      didRegistrationFacade: _FakeDidRegistrationFacade(),
      httpClient: client,
    );

    final session = await service.registerHandle(
      phone: '+8613800138000',
      otp: '123456',
      handle: 'alice',
      nickName: 'Alice',
    );
    final restored = await service.restoreSession();
    final anpSession = await service.currentAnpSession(requireSigning: true);

    expect(session.did, 'did:wba:awiki.ai:alice:e1_test');
    expect(restored?.credentialName, 'alice');
    expect(anpSession.didDocument?['id'], session.did);
    expect(anpSession.privateKeyPem, contains('PRIVATE KEY'));
  });

  test('loginWithLocalCredential rejects non-e1 credentials', () async {
    final storage = _MemoryStore();
    await storage.write(
      key: 'awiki_account_credentials',
      value: jsonEncode(<Object?>[
        <String, Object?>{
          'did': 'did:wba:awiki.ai:alice:k1_legacy',
          'credential_name': 'legacy',
          'display_name': 'Legacy',
          'jwt_token': 'token',
        },
      ]),
    );
    final service = AwikiAccountService(
      userServiceUrl: 'https://awiki.ai',
      storage: storage,
      didRegistrationFacade: _FakeDidRegistrationFacade(),
      httpClient: MockClient((_) async => http.Response('not used', 500)),
    );

    expect(await service.listLocalCredentials(), isEmpty);
    expect(
      () => service.loginWithLocalCredential('legacy'),
      throwsA(isA<StateError>()),
    );
  });
}

class _MemoryStore implements AppKeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
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
    final did = 'did:wba:awiki.ai:$handle:e1_test';
    return <String, Object?>{
      'did': did,
      'did_document': <String, Object?>{
        'id': did,
        'authentication': <String>['$did#key-1'],
      },
      'private_key_pem':
          '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
      'domain': 'awiki.ai',
    };
  }

  @override
  Future<String> generateDidAuthHeader({
    required Map<String, Object?> didDocument,
    required String privateKeyPem,
    required String domain,
  }) async {
    return 'DIDWba v="1.1"';
  }

  @override
  Future<bool> isSupported() async => true;
}
