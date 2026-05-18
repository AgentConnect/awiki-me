import 'package:awiki_me/src/im_core/awiki_im_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IM Core error strategy', () {
    test('ImException carries ImErrorDto and stable retry metadata', () {
      final exception = imException(
        ImErrorCode.transportUnavailable,
        'transport offline',
        hint: 'retry later',
        retryable: true,
        details: const <String, Object?>{'transport': 'fake'},
      );

      expect(exception, isA<ImException>());
      expect(exception.error.code, ImErrorCode.transportUnavailable);
      expect(exception.error.message, 'transport offline');
      expect(exception.error.hint, 'retry later');
      expect(exception.error.retryable, isTrue);
      expect(exception.error.details['transport'], 'fake');
      expect(exception.toString(), contains('transportUnavailable'));
    });

    test('ImErrorCode contains the Phase 1 frozen values', () {
      expect(ImErrorCode.values.map((value) => value.name), <String>[
        'unauthenticated',
        'sessionExpired',
        'permissionDenied',
        'targetRequired',
        'groupRequired',
        'messageTextRequired',
        'attachmentRequired',
        'messageNotFound',
        'attachmentNotFound',
        'transportUnavailable',
        'connectionFailed',
        'rpcRejected',
        'unsupported',
        'notReady',
        'featureDisabled',
        'storeCorrupt',
        'migrationRequired',
        'internal',
      ]);
    });

    test('fake validation failures are typed ImException errors', () async {
      final client = FakeAwikiImClient();
      addTearDown(client.close);

      await expectLater(
        client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'not initialized',
          ),
        ),
        throwsA(
          isA<ImException>().having(
            (exception) => exception.error.code,
            'code',
            ImErrorCode.notReady,
          ),
        ),
      );

      await client.initialize(const ImClientConfig(workspaceId: 'errors'));

      await expectLater(
        client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'not authenticated',
          ),
        ),
        throwsA(
          isA<ImException>().having(
            (exception) => exception.error.code,
            'code',
            ImErrorCode.unauthenticated,
          ),
        ),
      );

      await client.setSession(
        const ImSessionContext(
          credentialName: 'alice',
          did: 'did:wba:example:alice:e1_alice',
        ),
      );

      await expectLater(
        client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(),
            text: 'missing target',
          ),
        ),
        throwsA(
          isA<ImException>().having(
            (exception) => exception.error.code,
            'code',
            ImErrorCode.targetRequired,
          ),
        ),
      );

      await expectLater(
        client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
          ),
        ),
        throwsA(
          isA<ImException>().having(
            (exception) => exception.error.code,
            'code',
            ImErrorCode.messageTextRequired,
          ),
        ),
      );
    });

    test('fake errors avoid sensitive token/key/signature details', () async {
      final client = FakeAwikiImClient();
      addTearDown(client.close);

      await client.initialize(const ImClientConfig(workspaceId: 'errors'));
      await client.setSession(
        const ImSessionContext(
          credentialName: 'alice',
          did: 'did:wba:example:alice:e1_alice',
          jwtToken: 'secret-jwt-token',
          importedPrivateKey: ImImportedPrivateKey(
            keyId: 'e1',
            privateKeyPem: '-----BEGIN PRIVATE KEY-----secret',
          ),
        ),
      );

      await expectLater(
        client.directSecure.status(
          peerDidOrHandle: 'did:wba:example:bob:e1_bob',
        ),
        throwsA(
          isA<ImException>()
              .having(
                (exception) => exception.error.code,
                'code',
                ImErrorCode.featureDisabled,
              )
              .having(
                (exception) => exception.error.details.toString(),
                'details',
                isNot(
                  anyOf(
                    contains('jwt'),
                    contains('PRIVATE KEY'),
                    contains('signature'),
                  ),
                ),
              ),
        ),
      );
    });
  });
}
