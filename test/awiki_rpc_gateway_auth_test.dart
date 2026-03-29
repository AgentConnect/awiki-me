import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/data/gateways/awiki_rpc_gateway.dart';
import 'package:awiki_me/src/domain/services/did_registration_facade.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('restoreSession 刷新 token 后会回写本地 auth.json', () async {
    final tempDir = await Directory.systemTemp.createTemp('awiki-auth-test-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final credentialDir = Directory('${tempDir.path}/alice');
    await credentialDir.create(recursive: true);
    await File('${tempDir.path}/index.json').writeAsString(
      jsonEncode(<String, Object?>{
        'schema_version': 3,
        'default_credential_name': 'alice',
        'credentials': <String, Object?>{
          'alice': <String, Object?>{
            'credential_name': 'alice',
            'dir_name': 'alice',
            'did': 'did:test:alice',
            'name': 'Alice',
            'handle': 'alice',
            'created_at': '2026-03-29T00:00:00Z',
            'is_default': true,
          },
        },
      }),
    );
    await File('${credentialDir.path}/identity.json').writeAsString(
      jsonEncode(<String, Object?>{
        'did': 'did:test:alice',
        'name': 'Alice',
        'handle': 'alice',
      }),
    );
    await File('${credentialDir.path}/auth.json').writeAsString(
      jsonEncode(<String, Object?>{
        'jwt_token': 'stale-token',
      }),
    );
    await File('${credentialDir.path}/did_document.json').writeAsString(
      jsonEncode(<String, Object?>{
        'id': 'did:test:alice',
      }),
    );
    await File('${credentialDir.path}/key-1-private.pem')
        .writeAsString('private-key');

    final storage = _InMemorySecureStorage()
      ..seed('awiki_me_session_did', 'did:test:alice')
      ..seed('awiki_me_session_token', 'stale-token')
      ..seed('awiki_me_session_credential', 'alice')
      ..seed('awiki_me_session_display_name', 'Alice')
      ..seed('awiki_me_session_handle', 'alice');

    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final method = body['method']?.toString();
      final authHeader =
          request.headers['authorization'] ?? request.headers['Authorization'];
      if (request.url.path == '/user-service/did-auth/rpc' &&
          method == 'verify') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'result': <String, Object?>{
              'access_token': 'fresh-token',
              'did': 'did:test:alice',
            },
          }),
          200,
        );
      }
      if (request.url.path == '/user-service/did/profile/rpc' &&
          method == 'get_me') {
        if (authHeader == 'Bearer fresh-token') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': 1,
              'result': <String, Object?>{
                'did': 'did:test:alice',
                'nick_name': 'Alice',
                'bio': 'bio',
                'tags': <String>['ai'],
                'profile_md': '# Alice',
                'handle': 'alice',
              },
            }),
            200,
          );
        }
        return http.Response('unauthorized', 401);
      }
      return http.Response('not found', 404);
    });

    final gateway = AwikiRpcGateway(
      userServiceUrl: 'https://example.com',
      messageServiceUrl: 'https://example.com',
      secureStorage: storage,
      didRegistrationFacade: _FakeDidRegistrationFacade(),
      httpClient: client,
      localCredentialsRootPath: tempDir.path,
    );

    final session = await gateway.restoreSession();
    expect(session, isNotNull);
    expect(session!.jwtToken, 'fresh-token');

    final authPayload = jsonDecode(
      await File('${credentialDir.path}/auth.json').readAsString(),
    ) as Map<String, Object?>;
    expect(authPayload['jwt_token'], 'fresh-token');

    final profile = await gateway.loadMyProfile();
    expect(profile.nickName, 'Alice');
    expect(await storage.read(key: 'awiki_me_session_token'), 'fresh-token');
  });
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
