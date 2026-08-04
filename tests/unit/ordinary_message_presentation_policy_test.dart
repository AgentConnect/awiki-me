import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/ordinary_message_presentation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatMessage message({
    bool isMine = false,
    bool isEncrypted = false,
    String originalType = 'text',
    String? payloadJson,
  }) => ChatMessage(
    localId: 'message-1',
    conversationId: 'dm:peer-scope:v1:peer',
    threadId: 'dm:peer-scope:v1:peer',
    senderDid: 'did:test:peer',
    receiverDid: 'did:test:me',
    content: 'hello',
    createdAt: DateTime.utc(2026, 8, 4),
    isMine: isMine,
    isEncrypted: isEncrypted,
    originalType: originalType,
    payloadJson: payloadJson,
    sendState: MessageSendState.sent,
  );

  test('accepts an ordinary incoming message', () {
    expect(isOrdinaryMessagePresentationEligible(message()), isTrue);
  });

  test('rejects own messages and Agent control payloads', () {
    expect(
      isOrdinaryMessagePresentationEligible(message(isMine: true)),
      isFalse,
    );
    expect(
      isOrdinaryMessagePresentationEligible(
        message(
          originalType: 'application/json',
          payloadJson: '{"schema":"awiki.agent.status.v1"}',
        ),
      ),
      isFalse,
    );
  });

  test('rejects group system events and opaque E2EE payloads', () {
    expect(
      isOrdinaryMessagePresentationEligible(
        message(
          originalType: 'application/json',
          payloadJson:
              '{"schema":"awiki.group.system_event.v1","type":"member_added","group_did":"did:test:group"}',
        ),
      ),
      isFalse,
    );
    expect(
      isOrdinaryMessagePresentationEligible(
        message(
          isEncrypted: true,
          originalType: 'application/awiki-group-e2ee+json',
        ),
      ),
      isFalse,
    );
  });
}
