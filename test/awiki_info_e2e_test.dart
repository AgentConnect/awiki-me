import 'dart:convert';

import 'package:awiki_me/src/data/awiki_sdk/awiki_anp_session.dart';
import 'package:awiki_me/src/data/awiki_sdk/awiki_message_client.dart';
import 'package:awiki_me/src/data/awiki_sdk/awiki_service_client.dart';
import 'package:awiki_me/src/data/gateways/awiki_anp_gateway.dart';
import 'package:awiki_me/src/data/services/dart_did_registration_facade.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const runE2e = bool.fromEnvironment('RUN_AWIKI_INFO_E2E');
  test(
    'awiki.info registration and authenticated service smoke',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final handle = 'me-e2e-$now';
      final client = http.Client();
      final storage = _InMemorySecureStorage();
      addTearDown(client.close);
      final gateway = AwikiAnpGateway(
        userServiceUrl: 'https://awiki.info',
        messageServiceUrl: 'https://awiki.info',
        secureStorage: storage,
        didRegistrationFacade: DartDidRegistrationFacade(domain: 'awiki.info'),
        httpClient: client,
      );
      final messages = AwikiMessageClient(
        serviceClient: AwikiServiceClient(
          baseUrl: 'https://awiki.info',
          httpClient: client,
        ),
      );

      await gateway.sendOtp(phone: '+8610022229999');
      final session = await gateway.registerHandle(
        phone: '+8610022229999',
        otp: '987580',
        handle: handle,
        nickName: 'AWiki Me E2E',
      );
      expect(session.did, startsWith('did:wba:awiki.info:$handle:e1_'));
      expect(session.jwtToken, isNotEmpty);

      final me = await gateway.loadMyProfile();
      expect(me.did, session.did);
      expect(me.handle, handle);

      final public = await gateway.loadPublicProfile(handle);
      expect(public.did, session.did);

      final inboxSession = AwikiAnpSession(
        did: session.did,
        jwtToken: session.jwtToken ?? '',
      );
      final inbox = await messages.getInbox(session: inboxSession, limit: 1);
      expect(inbox, isA<Map<String, Object?>>());

      final didDocumentRaw = await storage.read(
        key: 'awiki_me_session_did_document',
      );
      final privateKeyPem =
          await storage.read(key: 'awiki_me_session_private_key_pem') ?? '';
      expect(didDocumentRaw, isNotEmpty);
      expect(privateKeyPem, isNotEmpty);
      final sendResult = await messages.sendDirect(
        session: AwikiAnpSession(
          did: session.did,
          jwtToken: session.jwtToken ?? '',
          didDocument: (jsonDecode(didDocumentRaw!) as Map<Object?, Object?>)
              .map<String, Object?>(
                (key, value) => MapEntry(key.toString(), value),
              ),
          privateKeyPem: privateKeyPem,
        ),
        targetDid: session.did,
        text: 'awiki-me awiki.info e2e smoke $now',
      );
      expect(sendResult['message_id']?.toString(), isNotEmpty);
    },
    skip: runE2e ? false : 'Set RUN_AWIKI_INFO_E2E=true to hit awiki.info.',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _InMemorySecureStorage extends FlutterSecureStorage {
  _InMemorySecureStorage();

  final Map<String, String> _values = <String, String>{};

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
