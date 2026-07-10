import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/desktop_cli_peer/support/ui_oracles.dart';

void main() {
  ChatMessage message({
    String localId = 'local-1',
    String? remoteId = 'remote-1',
    String content = 'exact body',
    String senderDid = 'did:test:sender',
    String? receiverDid = 'did:test:receiver',
    String? groupDid,
    MessageSendState sendState = MessageSendState.sent,
    List<ChatMessageMention> mentions = const <ChatMessageMention>[],
  }) {
    return ChatMessage(
      localId: localId,
      remoteId: remoteId,
      threadId: groupDid == null ? 'dm:peer' : 'group:$groupDid',
      senderDid: senderDid,
      receiverDid: receiverDid,
      groupId: groupDid,
      content: content,
      createdAt: DateTime(2026, 7, 10),
      isMine: senderDid == 'did:test:sender',
      sendState: sendState,
      mentions: mentions,
    );
  }

  test('message oracle requires canonical exact-one and terminal fields', () {
    final found = requireExactlyOneMessage(
      messages: <ChatMessage>[message()],
      content: 'exact body',
      messageId: 'remote-1',
      senderDid: 'did:test:sender',
      receiverDid: 'did:test:receiver',
      sendState: MessageSendState.sent,
    );

    expect(found.remoteId, 'remote-1');
  });

  test('message oracle rejects duplicate content instead of using first', () {
    expect(
      () => requireExactlyOneMessage(
        messages: <ChatMessage>[
          message(localId: 'local-1', remoteId: 'remote-1'),
          message(localId: 'local-2', remoteId: 'remote-2'),
        ],
        content: 'exact body',
      ),
      throwsStateError,
    );
  });

  test('conversation oracle rejects duplicate ids and wrong unread math', () {
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:did:test:peer',
      displayName: 'Peer',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 7, 10),
      unreadCount: 1,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    expect(
      () => requireExactlyOneConversation(
        conversations: <ConversationSummary>[conversation],
        conversationId: 'dm:did:test:peer',
        unreadCount: 0,
      ),
      throwsStateError,
    );
    expect(
      () => requireExactlyOneConversation(
        conversations: <ConversationSummary>[conversation, conversation],
        conversationId: 'dm:did:test:peer',
        unreadCount: 1,
      ),
      throwsStateError,
    );
  });

  test('mention oracle verifies one valid structured target', () {
    const content = '@peer hello';
    final withMention = message(
      content: content,
      groupDid: 'did:test:group',
      receiverDid: null,
      mentions: const <ChatMessageMention>[
        ChatMessageMention(
          id: 'mention-1',
          surface: '@peer',
          start: 0,
          end: 5,
          target: ChatMentionTargetDraft.member(
            kind: ChatMentionTargetKind.human,
            did: 'did:test:peer',
          ),
        ),
      ],
    );

    expect(
      () => requireSingleMentionTarget(
        message: withMention,
        targetDid: 'did:test:peer',
      ),
      returnsNormally,
    );
    expect(
      () => requireSingleMentionTarget(
        message: withMention,
        targetDid: 'did:test:other',
      ),
      throwsStateError,
    );
  });
}
