import 'package:awiki_me/src/data/services/noop_e2ee_facade.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports unsupported and keeps stateless operations harmless', () async {
    final facade = NoopE2eeFacade();

    expect(await facade.isSupported(), isFalse);
    expect(await facade.exportSessionState(), isEmpty);
    await facade.importSessionState(const <String, Object?>{'ignored': true});
    await facade.initialize(
      const SessionIdentity(
        did: 'did:alice',
        credentialName: 'alice',
        displayName: 'Alice',
      ),
    );

    final result = await facade.processIncomingProtocolMessage(_message());
    expect(result.decryptedMessage, isNull);
    expect(result.protocolResponses, isEmpty);
  });

  test('fails explicitly for encryption and decryption operations', () async {
    final facade = NoopE2eeFacade();

    await expectLater(
      facade.ensureSession('did:bob'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      facade.encryptOutgoing(
        peerDid: 'did:bob',
        originalType: 'text/plain',
        plaintext: 'secret',
      ),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      facade.decryptIncomingMessage(_message()),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

ChatMessage _message() {
  return ChatMessage(
    localId: 'msg-1',
    threadId: 'dm:did:alice:did:bob',
    senderDid: 'did:bob',
    receiverDid: 'did:alice',
    content: 'hello',
    createdAt: DateTime.utc(2026, 6, 15),
    isMine: false,
    sendState: MessageSendState.sent,
  );
}
