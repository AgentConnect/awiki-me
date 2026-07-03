import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> conversations,
  ) {
    state = ConversationListState(conversations: conversations);
  }
}

class _StaticAgentsController extends AgentsController {
  _StaticAgentsController(super.ref, List<AgentSummary> agents) {
    state = AgentsState(agents: agents);
  }
}

class _PolicyChatThreadsController extends ChatThreadsController {
  _PolicyChatThreadsController(
    super.ref, {
    required ThreadMemoryCachePolicy policy,
  }) : super(cachePolicy: policy);
}

const _daemon = AgentSummary(
  agentDid: 'did:agent:daemon',
  kind: AgentKind.daemon,
  displayName: 'Message Daemon',
  activeState: 'active',
  latest: AgentLatestStatus(status: 'ready'),
);

const _runtime = AgentSummary(
  agentDid: 'did:agent:runtime',
  kind: AgentKind.runtime,
  daemonAgentDid: 'did:agent:daemon',
  runtime: 'hermes',
  displayName: 'Hermes Message Agent',
  activeState: 'active',
  latest: AgentLatestStatus(status: 'ready'),
);

void main() {
  late FakeAwikiGateway gateway;
  late ProviderContainer container;

  final conversation = ConversationSummary(
    threadId: 'direct:did:human:bob',
    displayName: 'Bob',
    lastMessagePreview: 'hello',
    lastMessageAt: DateTime(2026, 6, 19, 10, 0),
    unreadCount: 0,
    isGroup: false,
    targetDid: 'did:human:bob',
  );
  final message = ChatMessage(
    localId: 'local_msg_1',
    remoteId: 'msg_1',
    threadId: conversation.threadId,
    senderDid: 'did:human:bob',
    receiverDid: 'did:human:alice',
    content: 'hello',
    createdAt: DateTime(2026, 6, 19, 10, 0),
    isMine: false,
    sendState: MessageSendState.sent,
  );
  setUp(() {
    gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:human:bob': <ChatMessage>[message],
      };
    container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        ...fakeApplicationServiceOverrides(gateway),
        conversationListProvider.overrideWith(
          (ref) => _StaticConversationListController(ref, <ConversationSummary>[
            conversation,
          ]),
        ),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:human:alice',
              credentialName: 'alice.json',
              displayName: 'Alice',
            ),
          );
          return controller;
        }),
        agentsProvider.overrideWith(
          (ref) => _StaticAgentsController(ref, const <AgentSummary>[
            _daemon,
            _runtime,
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test(
    'message sync records processing state without rendering raw JSON',
    () async {
      await container
          .read(chatThreadsProvider.notifier)
          .openConversation(conversation);
      await Future<void>.delayed(Duration.zero);

      container
          .read(chatThreadsProvider.notifier)
          .applyMessageAgentControlPayload(const <String, Object?>{
            'schema': 'awiki.message.sync.v1',
            'message_id': 'msg_1',
            'conversation_id': 'direct:did:human:bob',
            'sender_did': 'did:human:bob',
            'owner_did': 'did:human:alice',
            'processing_status': 'dispatched',
            'content_hash': 'sha256:test',
            'retention_class': 'short_excerpt',
          });

      final thread = container.read(chatThreadProvider(conversation.threadId));
      expect(thread.messages, hasLength(1));
      expect(thread.messages.single.content, 'hello');
      expect(thread.messageAgentSyncs, hasLength(1));
      expect(thread.messageAgentSyncs.single.messageId, 'msg_1');
      expect(thread.messageAgentSyncs.single.processingStatus, 'dispatched');
    },
  );

  test(
    'runtime final updates recovery state and clears pending turn',
    () async {
      container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(message);
      container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'run',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_1',
              'runtime_agent_did': 'did:agent:runtime',
              'conversation_id': 'direct:did:human:bob',
              'source_message_id': 'msg_1',
              'status': 'running',
            },
          ],
        },
      );
      expect(
        container
            .read(chatThreadProvider(conversation.threadId))
            .agentPendingTurns,
        isNotEmpty,
      );

      container
          .read(chatThreadsProvider.notifier)
          .applyMessageAgentControlPayload(const <String, Object?>{
            'schema': 'awiki.message.sync.v1',
            'sync_type': 'runtime_final',
            'binding_id': 'binding_1',
            'runtime_agent_did': 'did:agent:runtime',
            'runtime_profile_id': 'profile_1',
            'run_id': 'run_1',
            'source_message_id': 'msg_1',
            'source_conversation_id': 'direct:did:human:bob',
            'state': 'finished',
            'has_text': true,
            'retention_class': 'hash_only',
          });

      final thread = container.read(chatThreadProvider(conversation.threadId));
      expect(thread.agentPendingTurns, isEmpty);
      expect(thread.messageAgentSyncs.single.type, 'runtime_final');
      expect(thread.messageAgentSyncs.single.hasText, isTrue);
    },
  );

  test(
    'runtime final with peer-scope route attaches to loaded source message thread',
    () async {
      container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(message);
      container
          .read(chatThreadsProvider.notifier)
          .debugDropMessagesForTesting(conversation.threadId);

      expect(
        container.read(chatThreadProvider(conversation.threadId)).messages,
        isEmpty,
      );
      expect(
        container
            .read(chatThreadsProvider.notifier)
            .debugThreadIdForSourceMessage('msg_1'),
        conversation.threadId,
      );

      container
          .read(chatThreadsProvider.notifier)
          .applyMessageAgentControlPayload(const <String, Object?>{
            'schema': 'awiki.message.sync.v1',
            'sync_type': 'runtime_final',
            'binding_id': 'binding_1',
            'runtime_agent_did': 'did:agent:runtime',
            'runtime_profile_id': 'profile_1',
            'run_id': 'run_peer_scope',
            'source_message_id': 'msg_1',
            'source_conversation_id': 'dm:peer-scope:v1:stable-bob',
            'state': 'finished',
            'has_text': true,
            'retention_class': 'hash_only',
          });

      final sourceThread = container.read(
        chatThreadProvider(conversation.threadId),
      );
      expect(sourceThread.messages, isEmpty);
      expect(sourceThread.messageAgentSyncs.single.type, 'runtime_final');
      expect(
        sourceThread.messageAgentSyncs.single.conversationId,
        'dm:peer-scope:v1:stable-bob',
      );
      expect(
        container
            .read(chatThreadProvider('dm:peer-scope:v1:stable-bob'))
            .messageAgentSyncs,
        isEmpty,
      );
    },
  );

  test('cache stats isolate peer-scoped conversations and route entries', () {
    final controller = container.read(chatThreadsProvider.notifier);
    controller.applyRealtimeUpdate(message);
    controller.applyRealtimeUpdate(
      ChatMessage(
        localId: 'local_msg_2',
        remoteId: 'msg_2',
        threadId: 'dm:peer-scope:v1:bob',
        senderDid: 'did:human:bob',
        receiverDid: 'did:human:alice',
        content: 'hello again',
        createdAt: DateTime(2026, 6, 19, 10, 1),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversation: conversation.copyWith(threadId: 'dm:peer-scope:v1:bob'),
    );

    final stats = controller.debugCacheStats();
    expect(stats.rawThreadStateCount, greaterThanOrEqualTo(2));
    expect(stats.canonicalThreadCount, 2);
    expect(stats.messageRouteEntryCount, greaterThanOrEqualTo(4));
    expect(stats.totalRetainedMessages, greaterThanOrEqualTo(2));
    expect(
      stats.toJson()['cache.message_route_entry_count'],
      stats.messageRouteEntryCount,
    );
  });

  test('peer-scoped source message route corrects stale direct route', () {
    final controller = container.read(chatThreadsProvider.notifier);
    controller.applyRealtimeUpdate(message);
    expect(
      controller.debugThreadIdForSourceMessage('msg_1'),
      conversation.threadId,
    );

    const peerScopedThreadId = 'dm:peer-scope:v1:stable-bob';
    controller.applyRealtimeUpdate(
      ChatMessage(
        localId: message.localId,
        remoteId: message.remoteId,
        threadId: peerScopedThreadId,
        senderDid: message.senderDid,
        receiverDid: message.receiverDid,
        content: message.content,
        createdAt: message.createdAt,
        isMine: message.isMine,
        sendState: message.sendState,
      ),
      conversation: conversation.copyWith(threadId: peerScopedThreadId),
    );

    expect(
      controller.debugThreadIdForSourceMessage('msg_1'),
      peerScopedThreadId,
    );
  });

  test('delete and clear remove cache metadata and routes', () async {
    final controller = container.read(chatThreadsProvider.notifier);
    container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(message);

    expect(controller.debugCacheStats().messageRouteEntryCount, 2);
    expect(
      controller.debugThreadIdForSourceMessage('msg_1'),
      conversation.threadId,
    );

    await controller.deleteThread(conversation.threadId);

    expect(controller.debugCacheStats().rawThreadStateCount, 0);
    expect(controller.debugCacheStats().canonicalThreadCount, 0);
    expect(controller.debugCacheStats().messageRouteEntryCount, 0);
    expect(controller.debugThreadIdForSourceMessage('msg_1'), isNull);

    controller.applyRealtimeUpdate(message);
    expect(controller.debugCacheStats().messageRouteEntryCount, 2);
    controller.clear();
    expect(controller.debugCacheStats().rawThreadStateCount, 0);
    expect(controller.debugCacheStats().canonicalThreadCount, 0);
    expect(controller.debugCacheStats().messageRouteEntryCount, 0);
  });

  test('trim keeps hot thread tail and message routes', () {
    final trimContainer = _containerWithCachePolicy(
      gateway,
      conversation,
      const ThreadMemoryCachePolicy(
        hotThreadMessageLimit: 3,
        warmThreadMessageLimit: 2,
        coldThreadMessageLimit: 1,
        maxTotalCachedMessages: 20,
        maxCachedCanonicalThreads: 20,
      ),
    );
    addTearDown(trimContainer.dispose);
    final controller = trimContainer.read(chatThreadsProvider.notifier);
    controller.markConversationVisible(conversation);
    for (var i = 0; i < 6; i += 1) {
      controller.applyRealtimeUpdate(
        _chatMessage(
          conversation: conversation,
          localId: 'trim_local_$i',
          remoteId: 'trim_remote_$i',
          content: 'trim $i',
          createdAt: DateTime(2026, 6, 19, 10, i),
        ),
      );
    }

    final thread = trimContainer.read(
      chatThreadProvider(conversation.threadId),
    );
    expect(thread.messages.map((item) => item.content), <String>[
      'trim 3',
      'trim 4',
      'trim 5',
    ]);
    expect(controller.debugCacheStats().trimmedMessageCount, greaterThan(0));
    expect(
      controller.debugThreadIdForSourceMessage('trim_remote_0'),
      conversation.threadId,
    );
  });

  test('trim protects failed and pending app action source messages', () {
    final trimContainer = _containerWithCachePolicy(
      gateway,
      conversation,
      const ThreadMemoryCachePolicy(
        hotThreadMessageLimit: 2,
        warmThreadMessageLimit: 2,
        coldThreadMessageLimit: 1,
        maxTotalCachedMessages: 20,
        maxCachedCanonicalThreads: 20,
      ),
    );
    addTearDown(trimContainer.dispose);
    final controller = trimContainer.read(chatThreadsProvider.notifier);
    controller.applyRealtimeUpdate(
      _chatMessage(
        conversation: conversation,
        localId: 'failed_local',
        remoteId: 'failed_remote',
        content: 'failed',
        sendState: MessageSendState.failed,
        createdAt: DateTime(2026, 6, 19, 10),
      ),
    );
    controller.applyRealtimeUpdate(
      _chatMessage(
        conversation: conversation,
        localId: 'source_local',
        remoteId: 'source_remote',
        content: 'source',
        createdAt: DateTime(2026, 6, 19, 10, 1),
      ),
    );
    controller.applyMessageAgentControlPayload(const <String, Object?>{
      'schema': 'awiki.app.action.v1',
      'action_id': 'act_protected',
      'action': 'message.create_draft',
      'state': 'requires_confirmation',
      'runtime_agent_did': 'did:agent:runtime',
      'source_message_id': 'source_remote',
      'conversation_id': 'direct:did:human:bob',
      'requires_confirmation': true,
      'args': <String, Object?>{'draft_text': 'keep source'},
    });
    for (var i = 0; i < 4; i += 1) {
      controller.applyRealtimeUpdate(
        _chatMessage(
          conversation: conversation,
          localId: 'tail_local_$i',
          remoteId: 'tail_remote_$i',
          content: 'tail $i',
          createdAt: DateTime(2026, 6, 19, 10, i + 2),
        ),
      );
    }

    final contents = trimContainer
        .read(chatThreadProvider(conversation.threadId))
        .messages
        .map((item) => item.content);
    expect(contents, contains('failed'));
    expect(contents, contains('source'));
    expect(contents, contains('tail 3'));
    expect(controller.debugCacheStats().protectedOverflowCount, greaterThan(0));
  });

  test('global quota trims by exact storage conversation', () {
    final trimContainer = _containerWithCachePolicy(
      gateway,
      conversation,
      const ThreadMemoryCachePolicy(
        hotThreadMessageLimit: 5,
        warmThreadMessageLimit: 3,
        coldThreadMessageLimit: 1,
        maxTotalCachedMessages: 4,
        maxCachedCanonicalThreads: 1,
      ),
    );
    addTearDown(trimContainer.dispose);
    final controller = trimContainer.read(chatThreadsProvider.notifier);
    final aliasConversation = conversation.copyWith(
      threadId: 'dm:peer-scope:v1:bob',
    );
    for (var i = 0; i < 3; i += 1) {
      controller.applyRealtimeUpdate(
        _chatMessage(
          conversation: aliasConversation,
          localId: 'alias_local_$i',
          remoteId: 'alias_remote_$i',
          content: 'alias $i',
          createdAt: DateTime(2026, 6, 19, 10, i),
        ),
        conversation: aliasConversation,
      );
    }

    var stats = controller.debugCacheStats();
    expect(stats.canonicalThreadCount, 1);
    expect(stats.totalRetainedMessages, lessThanOrEqualTo(4));

    final otherConversation = ConversationSummary(
      threadId: 'direct:did:human:carol',
      displayName: 'Carol',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 19, 10, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:human:carol',
    );
    controller.applyRealtimeUpdate(
      _chatMessage(
        conversation: otherConversation,
        localId: 'other_local_1',
        remoteId: 'other_remote_1',
        content: 'other',
        createdAt: DateTime(2026, 6, 19, 10, 10),
      ),
      conversation: otherConversation,
    );

    stats = controller.debugCacheStats();
    expect(stats.canonicalThreadCount, 1);
    expect(stats.evictedThreadCount, greaterThan(0));
    expect(stats.totalRetainedMessages, lessThanOrEqualTo(4));
  });

  test(
    'confirm create draft writes composer and sends result to daemon',
    () async {
      container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(message);
      container
          .read(chatThreadsProvider.notifier)
          .applyMessageAgentControlPayload(const <String, Object?>{
            'schema': 'awiki.app.action.v1',
            'action_id': 'act_draft',
            'action': 'message.create_draft',
            'state': 'requires_confirmation',
            'binding_id': 'binding_1',
            'owner_did': 'did:human:alice',
            'app_instance_id': 'app_1',
            'runtime_agent_did': 'did:agent:runtime',
            'runtime_profile_id': 'profile_1',
            'run_id': 'run_1',
            'source_message_id': 'msg_1',
            'conversation_id': 'direct:did:human:bob',
            'requires_confirmation': true,
            'args': <String, Object?>{'draft_text': '收到，我稍后处理。'},
          });

      await container
          .read(chatThreadsProvider.notifier)
          .confirmAppAction(conversation: conversation, actionId: 'act_draft');

      final draft = container
          .read(chatComposerDraftsProvider.notifier)
          .draftFor(conversation);
      expect(draft.text, '收到，我稍后处理。');
      expect(gateway.lastSentPayloadPeerDid, 'did:agent:daemon');
      expect(gateway.lastSentPayloadIdempotencyKey, contains('act_draft'));
      expect(
        gateway.lastSentPayload?['schema'],
        AgentControlPayloads.appActionResultSchema,
      );
      expect(gateway.lastSentPayload?['state'], appActionStateSucceeded);
      expect(
        gateway.lastSentPayload?['runtime_agent_did'],
        'did:agent:runtime',
      );
      final action = container
          .read(chatThreadProvider(conversation.threadId))
          .appActionRecords['act_draft'];
      expect(action?.state, appActionStateSucceeded);
    },
  );

  test(
    'reject action sends rejected result and keeps composer untouched',
    () async {
      container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(message);
      container
          .read(chatThreadsProvider.notifier)
          .applyMessageAgentControlPayload(const <String, Object?>{
            'schema': 'awiki.app.action.v1',
            'action_id': 'act_contact',
            'action': 'contact.update_note',
            'state': 'requires_confirmation',
            'runtime_agent_did': 'did:agent:runtime',
            'run_id': 'run_1',
            'source_message_id': 'msg_1',
            'conversation_id': 'direct:did:human:bob',
            'requires_confirmation': true,
            'args': <String, Object?>{
              'contact_did': 'did:human:bob',
              'note': 'Follow up',
            },
          });

      await container
          .read(chatThreadsProvider.notifier)
          .rejectAppAction(conversation: conversation, actionId: 'act_contact');

      expect(
        container
            .read(chatComposerDraftsProvider.notifier)
            .draftFor(conversation)
            .text,
        isEmpty,
      );
      expect(gateway.lastSentPayloadPeerDid, 'did:agent:daemon');
      expect(gateway.lastSentPayload?['state'], appActionStateRejected);
      expect(gateway.lastSentPayload?['error_code'], 'user_rejected');
    },
  );

  test('confirm fails closed when result target cannot be resolved', () async {
    container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(message);
    container
        .read(chatThreadsProvider.notifier)
        .applyMessageAgentControlPayload(const <String, Object?>{
          'schema': 'awiki.app.action.v1',
          'action_id': 'act_missing_target',
          'action': 'message.create_draft',
          'state': 'requires_confirmation',
          'source_message_id': 'msg_1',
          'conversation_id': 'direct:did:human:bob',
          'requires_confirmation': true,
          'args': <String, Object?>{'draft_text': '收到。'},
        });

    await container
        .read(chatThreadsProvider.notifier)
        .confirmAppAction(
          conversation: conversation,
          actionId: 'act_missing_target',
        );

    final action = container
        .read(chatThreadProvider(conversation.threadId))
        .appActionRecords['act_missing_target'];
    expect(action?.state, appActionStateFailed);
    expect(action?.result?.errorCode, 'app_action_result_target_missing');
    expect(
      container
          .read(chatComposerDraftsProvider.notifier)
          .draftFor(conversation)
          .text,
      isEmpty,
    );
    expect(gateway.lastSentPayload, isNull);
  });
}

ProviderContainer _containerWithCachePolicy(
  FakeAwikiGateway gateway,
  ConversationSummary conversation,
  ThreadMemoryCachePolicy policy,
) {
  return ProviderContainer(
    overrides: <Override>[
      awikiGatewayProvider.overrideWithValue(gateway),
      ...fakeApplicationServiceOverrides(gateway),
      conversationListProvider.overrideWith(
        (ref) => _StaticConversationListController(ref, <ConversationSummary>[
          conversation,
        ]),
      ),
      sessionProvider.overrideWith((ref) {
        final controller = SessionController();
        controller.setSession(
          const SessionIdentity(
            did: 'did:human:alice',
            credentialName: 'alice.json',
            displayName: 'Alice',
          ),
        );
        return controller;
      }),
      agentsProvider.overrideWith(
        (ref) => _StaticAgentsController(ref, const <AgentSummary>[
          _daemon,
          _runtime,
        ]),
      ),
      chatThreadsProvider.overrideWith(
        (ref) => _PolicyChatThreadsController(ref, policy: policy),
      ),
    ],
  );
}

ChatMessage _chatMessage({
  required ConversationSummary conversation,
  required String localId,
  required String remoteId,
  required String content,
  DateTime? createdAt,
  MessageSendState sendState = MessageSendState.sent,
}) {
  return ChatMessage(
    localId: localId,
    remoteId: remoteId,
    threadId: conversation.threadId,
    senderDid: conversation.targetDid ?? 'did:human:bob',
    receiverDid: 'did:human:alice',
    content: content,
    createdAt: createdAt ?? DateTime(2026, 6, 19, 10),
    isMine: false,
    sendState: sendState,
  );
}
