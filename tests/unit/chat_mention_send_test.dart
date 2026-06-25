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
    const text = '@alice 请看';
    const mention = ChatMentionDraft(
      localId: 'men_alice',
      surface: '@alice',
      start: 0,
      end: '@alice'.length,
      target: ChatMentionTargetDraft.member(
        kind: ChatMentionTargetKind.human,
        did: 'did:wba:awiki.info:user:alice',
        handle: 'alice',
      ),
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
    expect(json['id'], 'men_alice');
    expect(json['target'], <String, Object?>{
      'kind': 'human',
      'did': 'did:wba:awiki.info:user:alice',
    });
    expect(json.containsKey('sender'), isFalse);
    expect(json.containsKey('proof'), isFalse);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.last.content, text);
    expect(messages.last.payloadJson, isNotNull);
    expect(messages.last.mentions.single.surface, '@alice');

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
      expect(container.read(pendingAgentDidsProvider), contains(agentDid));

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
      expect(
        container.read(pendingAgentDidsProvider),
        isNot(contains(agentDid)),
      );
    },
  );

  test('running run status creates and clears pending turn', () {
    const agentDid = 'did:wba:awiki.info:agent:runtime:hermes:e1_agent';

    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'run',
        'conversation_id': conversation.threadId,
        'task_id': 'task_group_status',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_group_status',
            'message_id': 'task_group_status',
            'source_message_id': 'msg_group_status',
            'mention_id': 'men_agent',
            'runtime_agent_did': agentDid,
            'conversation_id': conversation.threadId,
            'status': 'running',
            'started_at': DateTime(2026, 6, 14, 21).toIso8601String(),
          },
        ],
      },
    );

    var thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.agentPendingTurns.single.agentDid, agentDid);
    expect(thread.agentPendingTurns.single.remoteMessageId, 'msg_group_status');
    expect(container.read(pendingAgentDidsProvider), contains(agentDid));

    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'run',
        'conversation_id': conversation.threadId,
        'task_id': 'task_group_status',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_group_status',
            'message_id': 'task_group_status',
            'source_message_id': 'msg_group_status',
            'mention_id': 'men_agent',
            'runtime_agent_did': agentDid,
            'conversation_id': conversation.threadId,
            'status': 'finished',
          },
        ],
      },
    );

    thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.pendingAgentReplyCount, 0);
    expect(container.read(pendingAgentDidsProvider), isNot(contains(agentDid)));
  });

  test('snapshot run status restores pending turn', () {
    const agentDid = 'did:wba:awiki.info:agent:runtime:codex:e1_agent';

    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'snapshot',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_snapshot_codex',
            'message_id': 'msg_snapshot_codex',
            'runtime_agent_did': agentDid,
            'runtime_agent_handle': 'codex',
            'conversation_id': conversation.threadId,
            'status': 'running',
            'started_at': DateTime(2026, 6, 14, 21, 30).toIso8601String(),
          },
        ],
      },
    );

    final thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.agentPendingTurns.single.agentDid, agentDid);
    expect(thread.agentPendingTurns.single.agentHandle, 'codex');
    expect(
      thread.agentPendingTurns.single.remoteMessageId,
      'msg_snapshot_codex',
    );
    expect(container.read(pendingAgentDidsProvider), contains(agentDid));
  });

  test('controller activity status does not create chat pending turn', () {
    const agentDid = 'did:wba:awiki.info:agent:runtime:hermes:e1_agent';

    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      const <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'runtime_activity',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_external_activity',
            'runtime_agent_did': agentDid,
            'requester_did': 'did:wba:awiki.info:user:bob',
            'trigger_kind': 'external_direct',
            'status': 'running',
          },
        ],
      },
    );

    final thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.pendingAgentReplyCount, 0);
    expect(container.read(pendingAgentDidsProvider), isNot(contains(agentDid)));
  });

  test(
    'direct run status uses agent conversation when daemon conversation id is requester scoped',
    () {
      const agentDid = 'did:wba:awiki.info:agent:runtime:hermes:e1_agent';
      final agentConversation = ConversationSummary(
        threadId: 'direct:$agentDid',
        displayName: 'Hermes',
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 6, 14, 21),
        unreadCount: 0,
        isGroup: false,
        targetDid: agentDid,
        targetPeer: agentDid,
      );
      container
          .read(conversationListProvider.notifier)
          .restoreConversationBestEffort(agentConversation);

      container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'run',
          'conversation_id': 'direct:did:wba:awiki.info:user:me',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_external_direct',
              'message_id': 'task_external_direct',
              'source_message_id': 'msg_external_direct',
              'runtime_agent_did': agentDid,
              'conversation_id': 'direct:did:wba:awiki.info:user:me',
              'status': 'running',
            },
          ],
        },
      );

      final thread = container.read(
        chatThreadProvider(agentConversation.threadId),
      );
      expect(thread.pendingAgentReplyCount, 1);
      expect(thread.agentPendingTurns.single.agentDid, agentDid);
      expect(
        thread.agentPendingTurns.single.remoteMessageId,
        'msg_external_direct',
      );
    },
  );

  test(
    'run status clears only the matching group agent mention turn',
    () async {
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
      gateway.nextSentMessageIds = <String>[
        'msg_group_mention_1',
        'msg_group_mention_2',
      ];

      await container
          .read(chatThreadsProvider.notifier)
          .sendMessage(
            conversation: conversation,
            content: '@hermes 第一个问题',
            mentions: const <ChatMentionDraft>[mention],
          );
      await container
          .read(chatThreadsProvider.notifier)
          .sendMessage(
            conversation: conversation,
            content: '@hermes 第二个问题',
            mentions: const <ChatMentionDraft>[mention],
          );

      var thread = container.read(chatThreadProvider(conversation.threadId));
      expect(thread.pendingAgentReplyCount, 2);
      final firstMessage = thread.messages.firstWhere(
        (message) => message.remoteId == 'msg_group_mention_1',
      );
      final secondMessage = thread.messages.firstWhere(
        (message) => message.remoteId == 'msg_group_mention_2',
      );
      expect(thread.pendingAgentTurnForMessage(firstMessage), isNotNull);
      expect(thread.pendingAgentTurnForMessage(secondMessage), isNotNull);

      container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
        <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'run',
          'conversation_id': conversation.threadId,
          'task_id': 'task_group_mention_1',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_group_mention_1',
              'message_id': 'task_group_mention_1',
              'source_message_id': 'msg_group_mention_1',
              'mention_id': 'men_agent',
              'runtime_agent_did': agentDid,
              'conversation_id': conversation.threadId,
              'status': 'finished',
            },
          ],
        },
      );

      thread = container.read(chatThreadProvider(conversation.threadId));
      expect(thread.pendingAgentReplyCount, 1);
      expect(thread.pendingAgentTurnForMessage(firstMessage), isNull);
      expect(thread.pendingAgentTurnForMessage(secondMessage), isNotNull);
    },
  );

  test(
    'run status without source metadata does not clear group mention turns',
    () async {
      const agentDid = 'did:wba:awiki.info:agent:runtime:hermes:e1_agent';
      gateway.nextSentMessageId = 'msg_group_mention_1';

      await container
          .read(chatThreadsProvider.notifier)
          .sendMessage(
            conversation: conversation,
            content: '@hermes 请处理',
            mentions: const <ChatMentionDraft>[
              ChatMentionDraft(
                localId: 'men_agent',
                surface: '@hermes',
                start: 0,
                end: '@hermes'.length,
                target: ChatMentionTargetDraft.member(
                  kind: ChatMentionTargetKind.agent,
                  did: agentDid,
                  handle: 'hermes',
                ),
              ),
            ],
          );

      container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'run',
          'conversation_id': 'group:did:wba:awiki.info:group:mention',
          'task_id': 'task_without_source',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_without_source',
              'runtime_agent_did': agentDid,
              'conversation_id': 'group:did:wba:awiki.info:group:mention',
              'status': 'finished',
            },
          ],
        },
      );

      final thread = container.read(chatThreadProvider(conversation.threadId));
      expect(thread.pendingAgentReplyCount, 1);
      expect(
        thread.pendingAgentTurnForMessage(thread.messages.single),
        isNotNull,
      );
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
