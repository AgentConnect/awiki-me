import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  late FakeAwikiGateway gateway;
  late ProviderContainer container;
  late ConversationSummary conversation;

  setUp(() {
    gateway = FakeAwikiGateway();
    conversation = ConversationSummary(
      threadId: 'group:did:wba:awiki.info:group:mention',
      displayName: 'Mention Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 14, 20, 55),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:wba:awiki.info:group:mention',
    );
    container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:wba:awiki.info:user:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(container.dispose);
  });

  test('send mention uses P9 payload without sender or proof fields', () async {
    const text = '@所有 Agents 请总结';
    const mention = ChatMentionDraft(
      localId: 'men_agents',
      surface: '@所有 Agents',
      start: 0,
      end: '@所有 Agents'.length,
      target: ChatMentionTargetDraft.groupSelector(ChatMentionSelector.agents),
    );

    await container
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: text,
          mentions: <ChatMentionDraft>[mention],
        );

    expect(gateway.lastSentGroupId, 'did:wba:awiki.info:group:mention');
    expect(gateway.lastSentPayload, isNotNull);
    expect(gateway.lastSentPayload?['text'], text);
    final mentions = gateway.lastSentPayload?['mentions'] as List<Object?>;
    expect(mentions, hasLength(1));
    final json = mentions.single! as Map<String, Object?>;
    expect(json['id'], 'men_agents');
    expect(json['target'], <String, Object?>{
      'kind': 'group_selector',
      'selector': 'agents',
    });
    expect(json.containsKey('sender'), isFalse);
    expect(json.containsKey('proof'), isFalse);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.last.content, text);
    expect(messages.last.payloadJson, isNotNull);
    expect(messages.last.mentions.single.surface, '@所有 Agents');

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations.single.lastMessagePreview, text);
  });

  test(
    'send agent mention creates group pending turn and clears on reply',
    () async {
      const text = '@hermes 请总结';
      const agentDid = 'did:wba:awiki.info:agent:runtime:hermes:e1_agent';
      const mention = ChatMentionDraft(
        localId: 'men_agent',
        surface: '@hermes',
        start: 0,
        end: '@hermes'.length,
        target: ChatMentionTargetDraft.member(
          kind: ChatMentionTargetKind.agent,
          did: agentDid,
          handle: 'hermes',
        ),
      );
      gateway.nextSentMessageId = 'msg_group_mention_1';

      await container
          .read(chatThreadsProvider.notifier)
          .sendMessage(
            conversation: conversation,
            content: text,
            mentions: <ChatMentionDraft>[mention],
          );

      var thread = container.read(chatThreadProvider(conversation.threadId));
      expect(thread.pendingAgentReplyCount, 1);
      expect(thread.agentPendingTurns.single.agentDid, agentDid);
      expect(thread.agentPendingTurns.single.agentHandle, 'hermes');
      expect(thread.agentPendingTurns.single.mentionId, 'men_agent');
      expect(
        thread.agentPendingTurns.single.remoteMessageId,
        'msg_group_mention_1',
      );
      expect(
        thread.pendingAgentTurnForMessage(thread.messages.single),
        isNotNull,
      );

      container
          .read(chatThreadsProvider.notifier)
          .applyRealtimeUpdate(
            ChatMessage(
              localId: 'msg_agent_reply_1',
              remoteId: 'msg_agent_reply_1',
              threadId: conversation.threadId,
              senderDid: agentDid,
              groupId: conversation.groupId,
              content: '@me 总结好了',
              originalType: 'application/json',
              payloadJson:
                  '{"text":"@me 总结好了","mentions":[{"id":"reply_me","range":{"start":0,"end":3,"unit":"unicode_code_point"},"target":{"kind":"human","did":"did:wba:awiki.info:user:me"},"mention_role":"addressee"}],"annotations":{"awiki_reply_to_message_id":"msg_group_mention_1"}}',
              createdAt: DateTime.now(),
              isMine: false,
              sendState: MessageSendState.sent,
            ),
            conversation: conversation,
          );

      thread = container.read(chatThreadProvider(conversation.threadId));
      expect(thread.agentPendingTurns, isEmpty);
    },
  );

  test('send text without mentions keeps old sendText path', () async {
    await container
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: '普通群消息');

    expect(gateway.lastSentContent, '普通群消息');
    expect(gateway.lastSentPayload, isNull);
  });
}
