import 'package:flutter_test/flutter_test.dart';

import 'package:awiki_me/src/domain/entities/chat_message.dart';

void main() {
  test('ChatMessage exposes exact structured reply correlation', () {
    final message = ChatMessage(
      localId: 'reply-1',
      threadId: 'direct:agent',
      senderDid: 'did:agent:runtime',
      content: 'done',
      createdAt: DateTime.utc(2026, 8, 10),
      isMine: false,
      sendState: MessageSendState.sent,
      payloadJson:
          '{"text":"done","mentions":[],"annotations":{"awiki_reply_to_message_id":"msg-2"}}',
    );

    expect(message.replyToMessageId, 'msg-2');
  });

  test('ChatMessage rejects malformed or empty reply correlation', () {
    ChatMessage message(String? payloadJson) => ChatMessage(
      localId: 'reply-1',
      threadId: 'direct:agent',
      senderDid: 'did:agent:runtime',
      content: 'done',
      createdAt: DateTime.utc(2026, 8, 10),
      isMine: false,
      sendState: MessageSendState.sent,
      payloadJson: payloadJson,
    );

    expect(message(null).replyToMessageId, isNull);
    expect(message('{').replyToMessageId, isNull);
    expect(
      message(
        '{"annotations":{"awiki_reply_to_message_id":"   "}}',
      ).replyToMessageId,
      isNull,
    );
  });
}
