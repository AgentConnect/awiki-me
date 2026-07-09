import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/conversation_patch.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test(
    'refreshFastLocal emits base conversations before enrichment finishes',
    () async {
      final service = _SlowEnrichConversationService(
        base: <ConversationSummary>[
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'did:bob',
            unreadCount: 2,
          ),
        ],
        enriched: <ConversationSummary>[
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'Bob',
            unreadCount: 2,
          ),
        ],
      );
      final notifications = FakeNotificationFacade();
      final container = ProviderContainer(
        overrides: <Override>[
          conversationServiceProvider.overrideWithValue(service),
          notificationFacadeProvider.overrideWithValue(notifications),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:alice',
                credentialName: 'alice',
                displayName: 'Alice',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(conversationListProvider.notifier)
          .refreshFastLocal()
          .timeout(const Duration(milliseconds: 50));

      expect(service.fastCalls, 1);
      expect(service.enrichCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'did:bob',
      );
      expect(notifications.lastBadgeCount, 2);

      service.completeEnrichment();
      await Future<void>.delayed(Duration.zero);

      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'Bob',
      );
    },
  );

  test(
    'refresh merge replaces legacy direct DID row with peer-scoped identity',
    () async {
      final baseTime = DateTime.utc(2026, 6, 27, 2);
      final local = <ConversationSummary>[
        for (var i = 0; i < 500; i += 1)
          _conversation(
            threadId: 'dm:local:$i',
            displayName: 'Local $i',
            targetDid: 'did:local:$i',
          ).copyWith(
            lastMessagePreview: 'local $i',
            lastMessageAt: baseTime.subtract(Duration(minutes: i + 1)),
          ),
        _conversation(
          threadId: 'dm:did:human:did:agent',
          displayName: 'Hermes',
          targetDid: 'did:agent',
          targetPeer: 'did:agent',
        ).copyWith(
          lastMessagePreview: '旧回复',
          lastMessageAt: baseTime,
          unreadCount: 0,
        ),
      ];
      final refreshed = <ConversationSummary>[
        _conversation(
          threadId: 'dm:peer-scope:v1:hermes',
          displayName: 'Hermes Remote',
          targetDid: 'did:agent',
          targetPeer: 'hermes.awiki.example',
        ).copyWith(
          lastMessagePreview: '新回复',
          lastMessageAt: baseTime.add(const Duration(minutes: 1)),
          unreadCount: 1,
        ),
      ];
      final service = _StaticConversationService(conversations: refreshed);
      final container = ProviderContainer(
        overrides: <Override>[
          conversationServiceProvider.overrideWithValue(service),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:human',
                credentialName: 'human',
                displayName: 'Human',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      for (final conversation in local) {
        notifier.upsertConversation(conversation);
      }

      await notifier.refresh();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(
        conversations.where((item) => item.targetDid == 'did:agent'),
        hasLength(1),
      );
      final agent = conversations.singleWhere(
        (item) => item.threadId == 'dm:peer-scope:v1:hermes',
      );
      expect(agent.lastMessagePreview, '新回复');
      expect(conversations.length, local.length);
      expect(service.listCalls, 1);
    },
  );

  test(
    'public upsert does not flash conversations rejected by normalization',
    () async {
      final notifications = FakeNotificationFacade();
      final rejected =
          _conversation(
            threadId: 'dm:daemon-control',
            displayName: 'Daemon',
            targetDid: 'did:agent:daemon',
          ).copyWith(
            lastMessagePayloadJson:
                '{"schema":"awiki.agent.status.v1","status_scope":"daemon"}',
          );
      final service = _NormalizingConversationService(
        normalize: (conversation) async =>
            conversation.threadId == rejected.threadId ? null : conversation,
      );
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:human',
      );
      addTearDown(container.dispose);

      container
          .read(conversationListProvider.notifier)
          .upsertConversation(rejected);

      expect(container.read(conversationListProvider).conversations, isEmpty);
      await pumpEventQueue();
      expect(container.read(conversationListProvider).conversations, isEmpty);
      expect(notifications.lastBadgeCount, 0);
    },
  );

  test(
    'ambiguous peer-scoped direct targets are not merged by target alias',
    () {
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: _StaticConversationService(conversations: const []),
        notifications: notifications,
        ownerDid: 'did:human',
      );
      addTearDown(container.dispose);

      const agentDid = 'did:agent:runtime';
      const agentHandle = 'hermes.awiki.example';
      final controllerConversation =
          _conversation(
            threadId: 'dm:peer-scope:v1:controller',
            displayName: 'Controller',
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: 'controller preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 7, 9),
          );
      final runtimeConversation =
          _conversation(
            threadId: 'dm:peer-scope:v1:runtime',
            displayName: 'Runtime',
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: 'runtime preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 7, 10),
          );
      final genericUpdate =
          _conversation(
            threadId: 'direct:$agentDid',
            displayName: 'Generic',
            targetDid: agentDid,
            targetPeer: agentDid,
          ).copyWith(
            lastMessagePreview: 'generic update',
            lastMessageAt: DateTime.utc(2026, 7, 3, 7, 11),
          );

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(controllerConversation);
      notifier.upsertConversation(runtimeConversation);
      notifier.upsertConversation(genericUpdate);

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(3));
      expect(
        conversations
            .singleWhere(
              (item) => item.threadId == controllerConversation.threadId,
            )
            .lastMessagePreview,
        'controller preview',
      );
      expect(
        conversations
            .singleWhere(
              (item) => item.threadId == runtimeConversation.threadId,
            )
            .lastMessagePreview,
        'runtime preview',
      );
      expect(
        conversations
            .singleWhere((item) => item.threadId == genericUpdate.threadId)
            .lastMessagePreview,
        'generic update',
      );
    },
  );

  test(
    'explicit conversation ids keep rows distinct across direct aliases',
    () {
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: _StaticConversationService(conversations: const []),
        notifications: notifications,
        ownerDid: 'did:human',
      );
      addTearDown(container.dispose);

      final first =
          _conversation(
            conversationId: 'conv:controller',
            threadId: 'dm:peer-scope:v1:controller',
            displayName: 'Controller',
            targetDid: 'did:agent',
            targetPeer: 'agent.awiki.example',
          ).copyWith(
            lastMessagePreview: 'controller preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 7, 9),
          );
      final second =
          _conversation(
            conversationId: 'conv:runtime',
            threadId: 'direct:did:agent',
            displayName: 'Runtime',
            targetDid: 'did:agent',
            targetPeer: 'agent.awiki.example',
          ).copyWith(
            lastMessagePreview: 'runtime preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 7, 10),
          );

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(first);
      notifier.upsertConversation(second);

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(2));
      expect(
        conversations.map((item) => item.conversationId),
        containsAll(<String>['conv:controller', 'conv:runtime']),
      );
    },
  );

  test(
    'peer-scoped refresh replaces explicit legacy direct conversation id',
    () async {
      final notifications = FakeNotificationFacade();
      const agentDid = 'did:agent:runtime';
      final legacy =
          _conversation(
            conversationId: 'dm:$agentDid',
            threadId: 'dm:did:human:$agentDid',
            displayName: 'Hermes legacy',
            unreadCount: 0,
            targetDid: agentDid,
            targetPeer: agentDid,
          ).copyWith(
            lastMessagePreview: '旧回复',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12),
          );
      final runtime =
          _conversation(
            threadId: 'dm:peer-scope:v1:hermes-runtime',
            displayName: 'Hermes',
            unreadCount: 1,
            targetDid: agentDid,
            targetPeer: 'hermes.awiki.example',
          ).copyWith(
            lastMessagePreview: '新回复',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
          );
      final container = _conversationContainer(
        service: _StaticConversationService(
          conversations: <ConversationSummary>[runtime],
        ),
        notifications: notifications,
        ownerDid: 'did:human',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(legacy);

      await notifier.refresh();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(1));
      expect(conversations.single.threadId, runtime.threadId);
      expect(conversations.single.unreadCount, 1);
    },
  );

  test(
    'peer-scoped realtime reply refreshes recents from core projection',
    () async {
      final notifications = FakeNotificationFacade();
      const agentDid = 'did:agent:runtime:hermes';
      const agentHandle = 'hermes';
      const agentFullHandle = 'hermes.awiki.info';
      final service = _MutableConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:human',
        agents: const <AgentSummary>[
          AgentSummary(
            agentDid: agentDid,
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: agentHandle,
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final pendingAlias =
          _conversation(
            threadId: 'dm:pending:$agentFullHandle',
            displayName: 'Hermes',
            targetDid: agentDid,
            targetPeer: agentFullHandle,
          ).copyWith(
            lastMessagePreview: '在吗？',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12),
          );
      final coreProjection =
          _conversation(
            conversationId: 'conv:hermes-runtime',
            threadId: 'dm:peer-scope:v1:hermes-runtime',
            displayName: 'Hermes',
            targetDid: agentDid,
            targetPeer: agentFullHandle,
            unreadCount: 1,
          ).copyWith(
            lastMessagePreview: '在的',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
          );
      final runtimeHint = coreProjection.copyWith(
        targetDid: agentHandle,
        targetPeer: agentHandle,
      );
      final runtimeReply = ChatMessage(
        localId: 'runtime-reply-1',
        remoteId: 'runtime-reply-1',
        threadId: runtimeHint.threadId,
        senderDid: agentDid,
        senderName: 'Hermes',
        receiverDid: 'did:human',
        content: '在的',
        createdAt: runtimeHint.lastMessageAt,
        isMine: false,
        sendState: MessageSendState.sent,
      );

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(pendingAlias);
      expect(
        container.read(conversationListProvider).conversations.single.threadId,
        pendingAlias.threadId,
      );

      service.currentConversations = <ConversationSummary>[coreProjection];
      notifier.upsertRealtimeMessageBestEffort(
        runtimeHint,
        message: runtimeReply,
      );
      await pumpEventQueue();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(2));
      expect(service.fastCalls, 1);
      final refreshed = conversations.singleWhere(
        (item) => item.conversationId == 'conv:hermes-runtime',
      );
      expect(refreshed.threadId, coreProjection.threadId);
      expect(refreshed.targetDid, agentDid);
      expect(refreshed.targetPeer, agentFullHandle);
      expect(refreshed.lastMessagePreview, '在的');
      expect(refreshed.unreadCount, 1);
      expect(notifications.lastBadgeCount, 1);
    },
  );

  test(
    'ambiguous local handle realtime hint waits for core projection',
    () async {
      final notifications = FakeNotificationFacade();
      const firstDid = 'did:agent:runtime:hermes-a';
      const secondDid = 'did:agent:runtime:hermes-b';
      const localHandle = 'hermes';
      const firstFullHandle = 'hermes.awiki.info';
      final service = _MutableConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:human',
        agents: const <AgentSummary>[
          AgentSummary(
            agentDid: firstDid,
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon-a',
            runtime: 'hermes',
            handle: localHandle,
            displayName: 'Hermes A',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
          AgentSummary(
            agentDid: secondDid,
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon-b',
            runtime: 'hermes',
            handle: 'hermes.awiki.ai',
            displayName: 'Hermes B',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final pendingAlias =
          _conversation(
            threadId: 'dm:pending:$firstFullHandle',
            displayName: 'Hermes A',
            targetDid: firstDid,
            targetPeer: firstFullHandle,
          ).copyWith(
            lastMessagePreview: '在吗？',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12),
          );
      final runtimeHint =
          _conversation(
            threadId: 'dm:peer-scope:v1:ambiguous-hermes',
            displayName: localHandle,
            targetDid: localHandle,
            targetPeer: localHandle,
            unreadCount: 1,
          ).copyWith(
            lastMessagePreview: '在的',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
          );
      final runtimeReply = ChatMessage(
        localId: 'runtime-reply-ambiguous',
        remoteId: 'runtime-reply-ambiguous',
        threadId: runtimeHint.threadId,
        senderDid: firstDid,
        senderName: 'Hermes',
        receiverDid: 'did:human',
        content: '在的',
        createdAt: runtimeHint.lastMessageAt,
        isMine: false,
        sendState: MessageSendState.sent,
      );

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(pendingAlias);
      notifier.upsertRealtimeMessageBestEffort(
        runtimeHint,
        message: runtimeReply,
      );
      await pumpEventQueue();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(service.fastCalls, 1);
      expect(conversations, hasLength(1));
      expect(conversations.single.threadId, pendingAlias.threadId);
      expect(conversations.single.lastMessagePreview, '在吗？');
    },
  );

  test(
    'runtime realtime hint does not expand local handle in list layer',
    () async {
      final notifications = FakeNotificationFacade();
      const agentDid = 'did:agent:runtime:codex';
      const agentHandle = 'codex-local';
      final service = _MutableConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:human',
        environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
        agents: const <AgentSummary>[
          AgentSummary(
            agentDid: agentDid,
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'codex',
            handle: agentHandle,
            displayName: 'Codex',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final runtimeHint =
          _conversation(
            threadId: 'dm:peer-scope:v1:codex-local',
            displayName: agentHandle,
            targetDid: agentHandle,
            targetPeer: agentHandle,
            unreadCount: 1,
          ).copyWith(
            lastMessagePreview: 'ready',
            lastMessageAt: DateTime.utc(2026, 7, 5, 1),
          );
      final runtimeReply = ChatMessage(
        localId: 'runtime-reply-domain',
        remoteId: 'runtime-reply-domain',
        threadId: runtimeHint.threadId,
        senderDid: agentDid,
        senderName: 'Codex',
        receiverDid: 'did:human',
        content: 'ready',
        createdAt: runtimeHint.lastMessageAt,
        isMine: false,
        sendState: MessageSendState.sent,
      );

      container
          .read(conversationListProvider.notifier)
          .upsertRealtimeMessageBestEffort(runtimeHint, message: runtimeReply);
      await pumpEventQueue();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(service.fastCalls, 1);
      expect(conversations, isEmpty);
    },
  );

  test(
    'explicit non-runtime did realtime hint is not corrected in list layer',
    () async {
      final notifications = FakeNotificationFacade();
      const agentDid = 'did:agent:runtime:hermes';
      const agentFullHandle = 'hermes.awiki.info';
      final service = _MutableConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:human',
        agents: const <AgentSummary>[
          AgentSummary(
            agentDid: agentDid,
            kind: AgentKind.runtime,
            daemonAgentDid: 'did:agent:daemon',
            runtime: 'hermes',
            handle: 'hermes',
            displayName: 'Hermes',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final pendingAlias =
          _conversation(
            threadId: 'dm:pending:$agentFullHandle',
            displayName: 'Hermes',
            targetDid: agentDid,
            targetPeer: agentFullHandle,
          ).copyWith(
            lastMessagePreview: '在吗？',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12),
          );
      final humanHint =
          _conversation(
            threadId: 'dm:peer-scope:v1:human',
            displayName: 'Hermes',
            targetDid: 'did:human:hermes',
            targetPeer: agentFullHandle,
            unreadCount: 1,
          ).copyWith(
            lastMessagePreview: 'human reply',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
          );
      final humanReply = ChatMessage(
        localId: 'human-reply',
        remoteId: 'human-reply',
        threadId: humanHint.threadId,
        senderDid: 'did:human:hermes',
        senderName: 'Hermes',
        receiverDid: 'did:human',
        content: 'human reply',
        createdAt: humanHint.lastMessageAt,
        isMine: false,
        sendState: MessageSendState.sent,
      );

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(pendingAlias);
      notifier.upsertRealtimeMessageBestEffort(humanHint, message: humanReply);
      await pumpEventQueue();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(service.fastCalls, 1);
      expect(conversations, hasLength(1));
      expect(conversations.single.threadId, pendingAlias.threadId);
      expect(conversations.single.targetDid, agentDid);
    },
  );

  test(
    'direct alias upsert keeps single existing peer-scoped presentation row',
    () {
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: _StaticConversationService(conversations: const []),
        notifications: notifications,
        ownerDid: 'did:human',
      );
      addTearDown(container.dispose);

      const agentDid = 'did:agent:runtime:hermes';
      const agentHandle = 'hermes.awiki.example';
      final runtime =
          _conversation(
            threadId: 'dm:peer-scope:v1:hermes-runtime',
            displayName: 'Hermes',
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: '在的',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
          );
      final alias =
          _conversation(
            threadId: 'direct:$agentDid',
            displayName: 'Hermes',
            targetDid: agentDid,
            targetPeer: agentDid,
          ).copyWith(
            lastMessagePreview: '新的本地输入',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 2),
          );

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(runtime);
      notifier.upsertConversation(alias);

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(1));
      expect(conversations.single.threadId, runtime.threadId);
      expect(conversations.single.lastMessagePreview, '新的本地输入');
    },
  );

  test('selected direct alias migrates to peer-scoped presentation row', () {
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: _StaticConversationService(conversations: const []),
      notifications: notifications,
      ownerDid: 'did:human',
    );
    addTearDown(container.dispose);

    const agentDid = 'did:agent:runtime:hermes';
    const agentHandle = 'hermes.awiki.example';
    final pendingAlias =
        _conversation(
          threadId: 'dm:pending:$agentHandle',
          displayName: 'Hermes',
          targetDid: agentDid,
          targetPeer: agentHandle,
        ).copyWith(
          lastMessagePreview: '在吗？',
          lastMessageAt: DateTime.utc(2026, 7, 3, 12),
        );
    final runtime =
        _conversation(
          threadId: 'dm:peer-scope:v1:hermes-runtime',
          displayName: 'Hermes',
          targetDid: agentDid,
          targetPeer: agentHandle,
          unreadCount: 1,
        ).copyWith(
          lastMessagePreview: '在的',
          lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
        );

    final notifier = container.read(conversationListProvider.notifier);
    notifier.upsertConversation(pendingAlias);
    container
        .read(selectedConversationProvider.notifier)
        .selectConversation(pendingAlias);
    notifier.upsertConversation(runtime);

    final selected = container.read(selectedConversationProvider);
    expect(selected?.threadId, runtime.threadId);
    expect(selected?.lastMessagePreview, '在的');
    expect(selected?.displayName, 'Hermes');
  });

  test(
    'generic direct alias does not collapse ambiguous peer-scoped targets',
    () {
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: _StaticConversationService(conversations: const []),
        notifications: notifications,
        ownerDid: 'did:human',
      );
      addTearDown(container.dispose);

      const agentDid = 'did:agent:runtime:hermes';
      const agentHandle = 'hermes.awiki.example';
      final controller =
          _conversation(
            threadId: 'dm:peer-scope:v1:controller',
            displayName: 'Controller',
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: 'controller preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12),
          );
      final runtime =
          _conversation(
            threadId: 'dm:peer-scope:v1:runtime',
            displayName: 'Runtime',
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: 'runtime preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
          );
      final generic =
          _conversation(
            threadId: 'direct:$agentDid',
            displayName: 'Generic',
            targetDid: agentDid,
            targetPeer: agentDid,
          ).copyWith(
            lastMessagePreview: 'generic preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 2),
          );

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(controller);
      notifier.upsertConversation(runtime);
      notifier.upsertConversation(generic);

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(3));
      expect(
        conversations.map((item) => item.threadId),
        containsAll(<String>[
          controller.threadId,
          runtime.threadId,
          generic.threadId,
        ]),
      );
    },
  );

  test(
    'refresh generic direct alias does not consume ambiguous peer-scoped rows',
    () async {
      final notifications = FakeNotificationFacade();
      const agentDid = 'did:agent:runtime:hermes';
      const agentHandle = 'hermes.awiki.example';
      final controller =
          _conversation(
            threadId: 'dm:peer-scope:v1:controller',
            displayName: 'Controller',
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: 'controller preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12),
          );
      final runtime =
          _conversation(
            threadId: 'dm:peer-scope:v1:runtime',
            displayName: 'Runtime',
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: 'runtime preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 1),
          );
      final generic =
          _conversation(
            threadId: 'direct:$agentDid',
            displayName: 'Generic',
            targetDid: agentDid,
            targetPeer: agentDid,
          ).copyWith(
            lastMessagePreview: 'generic preview',
            lastMessageAt: DateTime.utc(2026, 7, 3, 12, 2),
          );
      final container = _conversationContainer(
        service: _StaticConversationService(
          conversations: <ConversationSummary>[generic],
        ),
        notifications: notifications,
        ownerDid: 'did:human',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(controller);
      notifier.upsertConversation(runtime);

      await notifier.refresh();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(conversations, hasLength(3));
      expect(
        conversations.map((item) => item.threadId),
        containsAll(<String>[
          controller.threadId,
          runtime.threadId,
          generic.threadId,
        ]),
      );
    },
  );

  test(
    'non-empty refreshed preview can replace newer empty local preview',
    () async {
      final baseTime = DateTime.utc(2026, 6, 27, 2);
      final local =
          _conversation(
            threadId: 'dm:did:human:did:agent',
            displayName: 'Hermes',
            targetDid: 'did:agent',
            targetPeer: 'did:agent',
          ).copyWith(
            lastMessagePreview: '',
            lastMessageAt: baseTime.add(const Duration(minutes: 1)),
          );
      final refreshed = _conversation(
        threadId: 'dm:peer-scope:v1:hermes',
        displayName: 'Hermes Remote',
        targetDid: 'did:agent',
        targetPeer: 'hermes.awiki.example',
      ).copyWith(lastMessagePreview: 'Agent 已准备好。', lastMessageAt: baseTime);
      final service = _StaticConversationService(
        conversations: <ConversationSummary>[refreshed],
      );
      final container = ProviderContainer(
        overrides: <Override>[
          conversationServiceProvider.overrideWithValue(service),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:human',
                credentialName: 'human',
                displayName: 'Human',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(local);

      await notifier.refresh();

      final merged = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(merged.lastMessagePreview, 'Agent 已准备好。');
      expect(merged.threadId, 'dm:peer-scope:v1:hermes');
    },
  );

  test(
    'empty refreshed group preview does not overwrite visible local preview',
    () async {
      final baseTime = DateTime.utc(2026, 7, 3, 7, 8, 52);
      final local = _conversation(
        threadId: 'group:did:wba:awiki.ai:groups:8b13',
        displayName: '群聊',
        isGroup: true,
        groupId: 'did:wba:awiki.ai:groups:8b13',
      ).copyWith(lastMessagePreview: '111', lastMessageAt: baseTime);
      final refreshed =
          _conversation(
            threadId: local.threadId,
            displayName: local.displayName,
            isGroup: true,
            groupId: local.groupId,
          ).copyWith(
            lastMessagePreview: '',
            lastMessageAt: baseTime.add(const Duration(seconds: 1)),
          );
      final service = _StaticConversationService(
        conversations: <ConversationSummary>[refreshed],
      );
      final container = _conversationContainer(
        service: service,
        notifications: FakeNotificationFacade(),
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(local);
      await notifier.refresh();

      final conversation = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(conversation.lastMessagePreview, '111');
      expect(conversation.lastMessageAt, baseTime);
    },
  );

  test('mark read is no-op when conversation is already read', () async {
    final service = _StaticConversationService(conversations: const []);
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final conversation = _conversation(
      threadId: 'dm:alice:bob',
      displayName: 'Bob',
      unreadCount: 0,
    );
    final notifier = container.read(conversationListProvider.notifier);
    notifier.upsertConversation(conversation);
    await Future<void>.delayed(Duration.zero);

    var emissions = 0;
    final subscription = container.listen<ConversationListState>(
      conversationListProvider,
      (_, _) => emissions += 1,
    );
    addTearDown(subscription.close);

    notifier.markConversationReadLocal(conversation);

    expect(emissions, 0);
    expect(notifications.lastBadgeCount, 0);
  });

  test('mark read only clears the exact storage thread', () async {
    final service = _StaticConversationService(conversations: const []);
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final controllerConversation =
        _conversation(
          threadId: 'dm:peer-scope:v1:controller',
          displayName: 'Controller',
          unreadCount: 3,
          targetDid: 'did:agent:runtime',
          targetPeer: 'agent.awiki.ai',
        ).copyWith(
          lastMessageSnapshot: _messageSnapshot(
            threadId: 'dm:peer-scope:v1:controller',
            remoteId: 'remote-controller',
            serverSequence: 10,
          ),
        );
    final runtimeConversation =
        _conversation(
          threadId: 'dm:peer-scope:v1:runtime',
          displayName: 'Runtime Agent',
          unreadCount: 2,
          targetDid: 'did:agent:runtime',
          targetPeer: 'agent.awiki.ai',
        ).copyWith(
          lastMessageSnapshot: _messageSnapshot(
            threadId: 'dm:peer-scope:v1:runtime',
            remoteId: 'remote-runtime',
            serverSequence: 11,
          ),
        );
    final notifier = container.read(conversationListProvider.notifier);
    notifier.upsertConversation(controllerConversation);
    notifier.upsertConversation(runtimeConversation);
    await Future<void>.delayed(Duration.zero);

    notifier.markConversationReadLocal(
      runtimeConversation,
      watermark: _watermarkForConversation(runtimeConversation),
    );

    final byThread = {
      for (final item in container.read(conversationListProvider).conversations)
        item.threadId: item,
    };
    expect(
      byThread[controllerConversation.threadId]?.unreadCount,
      controllerConversation.unreadCount,
    );
    expect(byThread[runtimeConversation.threadId]?.unreadCount, 0);
    expect(notifications.lastBadgeCount, controllerConversation.unreadCount);
  });

  test(
    'mark read local suppresses stale unread refresh for same message',
    () async {
      final messageAt = DateTime.utc(2026, 6, 27, 2);
      final refreshedUnread =
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'Bob',
            unreadCount: 2,
            lastMessageAt: messageAt,
          ).copyWith(
            lastMessageSnapshot: ChatMessage(
              localId: 'local-1',
              remoteId: 'remote-1',
              threadId: 'dm:alice:bob',
              senderDid: 'did:bob',
              receiverDid: 'did:alice',
              content: 'hello',
              createdAt: messageAt,
              isMine: false,
              serverSequence: 10,
              sendState: MessageSendState.sent,
            ),
          );
      final service = _MutableConversationService(
        conversations: <ConversationSummary>[refreshedUnread],
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(refreshedUnread);
      await Future<void>.delayed(Duration.zero);

      notifier.markConversationReadLocal(
        refreshedUnread,
        watermark: _watermarkForConversation(refreshedUnread),
      );
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .unreadCount,
        0,
      );

      await notifier.refresh();

      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .unreadCount,
        0,
      );
      expect(notifications.lastBadgeCount, 0);
    },
  );

  test('mark read local does not suppress newer core unread refresh', () async {
    final firstMessageAt = DateTime.utc(2026, 6, 27, 2);
    final secondMessageAt = firstMessageAt.add(const Duration(seconds: 1));
    final firstUnread =
        _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob',
          unreadCount: 1,
          lastMessageAt: firstMessageAt,
        ).copyWith(
          lastMessageSnapshot: ChatMessage(
            localId: 'local-1',
            remoteId: 'remote-1',
            threadId: 'dm:alice:bob',
            senderDid: 'did:bob',
            receiverDid: 'did:alice',
            content: 'hello',
            createdAt: firstMessageAt,
            isMine: false,
            serverSequence: 10,
            sendState: MessageSendState.sent,
          ),
        );
    final service = _MutableConversationService(
      conversations: <ConversationSummary>[firstUnread],
    );
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    notifier.upsertConversation(firstUnread);
    await Future<void>.delayed(Duration.zero);

    notifier.markConversationReadLocal(
      firstUnread,
      watermark: _watermarkForConversation(firstUnread),
    );
    expect(
      container.read(conversationListProvider).conversations.single.unreadCount,
      0,
    );

    final newerUnread = firstUnread.copyWith(
      lastMessagePreview: 'new hello',
      lastMessageAt: secondMessageAt,
      unreadCount: 1,
      lastMessageSnapshot: ChatMessage(
        localId: 'local-2',
        remoteId: 'remote-2',
        threadId: 'dm:alice:bob',
        senderDid: 'did:bob',
        receiverDid: 'did:alice',
        content: 'new hello',
        createdAt: secondMessageAt,
        isMine: false,
        serverSequence: 11,
        sendState: MessageSendState.sent,
      ),
    );
    service.currentConversations = <ConversationSummary>[newerUnread];

    await notifier.refresh();

    expect(
      container.read(conversationListProvider).conversations.single.unreadCount,
      1,
    );
    expect(notifications.lastBadgeCount, 1);
  });

  test(
    'new remote latest with transient zero unread does not flash read',
    () async {
      final firstMessageAt = DateTime.utc(2026, 6, 27, 2);
      final secondMessageAt = firstMessageAt.add(const Duration(seconds: 1));
      final firstRead =
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'Bob',
            unreadCount: 0,
            lastMessageAt: firstMessageAt,
          ).copyWith(
            lastMessagePreview: 'old hello',
            lastMessageSnapshot: ChatMessage(
              localId: 'local-old',
              remoteId: 'remote-old',
              threadId: 'dm:alice:bob',
              senderDid: 'did:bob',
              receiverDid: 'did:alice',
              content: 'old hello',
              createdAt: firstMessageAt,
              isMine: false,
              serverSequence: 10,
              sendState: MessageSendState.sent,
            ),
          );
      final transientZero = firstRead.copyWith(
        lastMessagePreview: 'new hello',
        lastMessageAt: secondMessageAt,
        unreadCount: 0,
        lastMessageSnapshot: ChatMessage(
          localId: 'local-new',
          remoteId: 'remote-new',
          threadId: 'dm:alice:bob',
          senderDid: 'did:bob',
          receiverDid: 'did:alice',
          content: 'new hello',
          createdAt: secondMessageAt,
          isMine: false,
          serverSequence: 11,
          sendState: MessageSendState.sent,
        ),
      );
      final confirmedUnread = transientZero.copyWith(unreadCount: 1);
      final service = _PatchConversationService(
        conversations: <ConversationSummary>[confirmedUnread],
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(firstRead);
      await Future<void>.delayed(Duration.zero);

      final unreadEmissions = <int>[];
      final subscription = container.listen<ConversationListState>(
        conversationListProvider,
        (_, next) => unreadEmissions.add(next.unreadCount),
      );
      addTearDown(subscription.close);

      notifier.upsertConversation(transientZero);
      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.reset,
          ownerDid: 'did:alice',
          version: 1,
          unreadTotal: 1,
          items: <ConversationSummary>[confirmedUnread],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await notifier.refresh();

      expect(
        container.read(conversationListProvider).conversations.single,
        isA<ConversationSummary>()
            .having((item) => item.lastMessagePreview, 'preview', 'new hello')
            .having((item) => item.unreadCount, 'unread', 1),
      );
      expect(unreadEmissions, isNot(contains(0)));
      expect(notifications.lastBadgeCount, 1);
    },
  );

  test(
    'old zero unread refresh does not clear newer unread without read watermark',
    () async {
      final firstMessageAt = DateTime.utc(2026, 6, 27, 2);
      final secondMessageAt = firstMessageAt.add(const Duration(seconds: 1));
      final firstRead =
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'Bob',
            unreadCount: 0,
            lastMessageAt: firstMessageAt,
          ).copyWith(
            lastMessagePreview: 'old hello',
            lastMessageSnapshot: ChatMessage(
              localId: 'local-old',
              remoteId: 'remote-old',
              threadId: 'dm:alice:bob',
              senderDid: 'did:bob',
              receiverDid: 'did:alice',
              content: 'old hello',
              createdAt: firstMessageAt,
              isMine: false,
              serverSequence: 10,
              sendState: MessageSendState.sent,
            ),
          );
      final newerUnread = firstRead.copyWith(
        lastMessagePreview: 'new hello',
        lastMessageAt: secondMessageAt,
        unreadCount: 1,
        lastMessageSnapshot: ChatMessage(
          localId: 'local-new',
          remoteId: 'remote-new',
          threadId: 'dm:alice:bob',
          senderDid: 'did:bob',
          receiverDid: 'did:alice',
          content: 'new hello',
          createdAt: secondMessageAt,
          isMine: false,
          serverSequence: 11,
          sendState: MessageSendState.sent,
        ),
      );
      final service = _MutableConversationService(
        conversations: <ConversationSummary>[newerUnread],
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(firstRead);
      notifier.upsertConversation(newerUnread);
      service.currentConversations = <ConversationSummary>[firstRead];

      await notifier.refresh();

      expect(container.read(conversationListProvider).unreadCount, 1);
      expect(notifications.lastBadgeCount, 1);
    },
  );

  test(
    'visible conversation keeps unread presentation stable across refresh sources',
    () async {
      final initialAt = DateTime.utc(2026, 6, 27, 2);
      final replyAt = initialAt.add(const Duration(seconds: 1));
      final initial = _conversation(
        conversationId: 'group:hangzhou-weather',
        threadId: 'group:hangzhou-weather',
        displayName: 'Hangzhou group',
        lastMessageAt: initialAt,
        isGroup: true,
        groupId: 'hangzhou-weather',
      ).copyWith(lastMessagePreview: 'old visible');
      final unreadReply = initial.copyWith(
        lastMessagePreview: 'today is July 6',
        lastMessageAt: replyAt,
        unreadCount: 1,
        unreadMentionCount: 1,
        firstUnreadMentionMessageId: 'remote-visible-group',
        lastMessageSnapshot: ChatMessage(
          localId: 'remote-visible-group',
          remoteId: 'remote-visible-group',
          threadId: initial.threadId,
          senderDid: 'did:agent',
          groupId: initial.groupId,
          content: 'today is July 6',
          createdAt: replyAt,
          isMine: false,
          serverSequence: 42,
          sendState: MessageSendState.sent,
        ),
      );
      final service = _MutableConversationService(
        conversations: <ConversationSummary>[unreadReply],
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(initial);
      notifier.markConversationVisibleLocal(
        unreadReply,
        watermark: const AppThreadReadWatermark(
          lastReadMessageId: 'remote-visible-group',
          lastReadThreadSeq: '42',
        ),
      );
      final unreadEmissions = <int>[];
      final subscription = container.listen<ConversationListState>(
        conversationListProvider,
        (_, next) {
          unreadEmissions.add(next.conversations.single.unreadCount);
        },
      );
      addTearDown(subscription.close);

      notifier.upsertConversation(unreadReply);
      await notifier.refreshFastLocal();
      await notifier.refresh();
      container
          .read(conversationListProvider.notifier)
          .applyGroupNames(<GroupSummary>[
            GroupSummary(
              groupId: 'hangzhou-weather',
              displayName: 'Hangzhou Weather',
              description: '',
              memberCount: 2,
              lastMessageAt: replyAt,
            ),
          ]);

      final conversation = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(conversation.lastMessagePreview, 'today is July 6');
      expect(conversation.unreadCount, 0);
      expect(conversation.unreadMentionCount, 0);
      expect(conversation.firstUnreadMentionMessageId, isNull);
      expect(unreadEmissions, isNot(contains(1)));
      expect(notifications.lastBadgeCount, 0);
    },
  );

  test(
    'visible conversation projects stable incoming message read before publish',
    () async {
      final initialAt = DateTime.utc(2026, 6, 27, 2);
      final replyAt = initialAt.add(const Duration(seconds: 1));
      final initial = _conversation(
        conversationId: 'group:visible-before-publish',
        threadId: 'group:visible-before-publish',
        displayName: 'Visible group',
        lastMessageAt: initialAt,
        isGroup: true,
        groupId: 'visible-before-publish',
      ).copyWith(lastMessagePreview: 'old visible');
      final unreadReply = initial.copyWith(
        lastMessagePreview: 'new visible reply',
        lastMessageAt: replyAt,
        unreadCount: 1,
        unreadMentionCount: 1,
        firstUnreadMentionMessageId: 'remote-visible-before-publish',
        lastMessageSnapshot: ChatMessage(
          localId: 'remote-visible-before-publish',
          remoteId: 'remote-visible-before-publish',
          threadId: initial.threadId,
          senderDid: 'did:agent',
          groupId: initial.groupId,
          content: 'new visible reply',
          createdAt: replyAt,
          isMine: false,
          serverSequence: 44,
          sendState: MessageSendState.sent,
        ),
      );
      final service = _MutableConversationService(
        conversations: <ConversationSummary>[unreadReply],
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(initial);
      notifier.markConversationVisibleLocal(initial);
      final unreadEmissions = <int>[];
      final subscription = container.listen<ConversationListState>(
        conversationListProvider,
        (_, next) => unreadEmissions.add(next.conversations.single.unreadCount),
      );
      addTearDown(subscription.close);

      notifier.upsertConversation(unreadReply);
      await notifier.refresh();

      final conversation = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(conversation.lastMessagePreview, 'new visible reply');
      expect(conversation.unreadCount, 0);
      expect(conversation.unreadMentionCount, 0);
      expect(conversation.firstUnreadMentionMessageId, isNull);
      expect(unreadEmissions, isNot(contains(1)));
      expect(notifications.lastBadgeCount, 0);
    },
  );

  test(
    'hidden conversation can become unread again after visible state ends',
    () {
      final initialAt = DateTime.utc(2026, 6, 27, 2);
      final replyAt = initialAt.add(const Duration(seconds: 1));
      final initial = _conversation(
        conversationId: 'group:hidden-after-visible',
        threadId: 'group:hidden-after-visible',
        displayName: 'Hidden after visible',
        lastMessageAt: initialAt,
        isGroup: true,
        groupId: 'hidden-after-visible',
      ).copyWith(lastMessagePreview: 'old visible');
      final unreadReply = initial.copyWith(
        lastMessagePreview: 'new hidden reply',
        lastMessageAt: replyAt,
        unreadCount: 1,
        lastMessageSnapshot: ChatMessage(
          localId: 'remote-hidden-after-visible',
          remoteId: 'remote-hidden-after-visible',
          threadId: initial.threadId,
          senderDid: 'did:agent',
          groupId: initial.groupId,
          content: 'new hidden reply',
          createdAt: replyAt,
          isMine: false,
          serverSequence: 45,
          sendState: MessageSendState.sent,
        ),
      );
      final container = _conversationContainer(
        service: _StaticConversationService(conversations: const []),
        notifications: FakeNotificationFacade(),
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(initial);
      notifier.markConversationVisibleLocal(initial);
      notifier.markConversationHiddenLocal(initial);

      notifier.upsertConversation(unreadReply);

      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .unreadCount,
        1,
      );
    },
  );

  test(
    'visible conversation survives alias migration and repeated patch unread',
    () async {
      final initialAt = DateTime.utc(2026, 6, 27, 2);
      final replyAt = initialAt.add(const Duration(seconds: 1));
      const ownerDid = 'did:human';
      const agentDid = 'did:agent:hermes';
      const agentHandle = 'hermes.awiki.test';
      final alias = _conversation(
        threadId: 'dm:pending:$agentHandle',
        displayName: 'Hermes alias',
        lastMessageAt: initialAt,
        targetDid: '',
        targetPeer: agentHandle,
      ).copyWith(lastMessagePreview: 'old visible');
      final peerScopedUnread =
          _conversation(
            conversationId: 'dm:peer-scope:v1:hermes',
            threadId: 'dm:peer-scope:v1:hermes',
            displayName: 'Hermes',
            unreadCount: 1,
            lastMessageAt: replyAt,
            targetDid: agentDid,
            targetPeer: agentHandle,
          ).copyWith(
            lastMessagePreview: 'new visible reply',
            lastMessageSnapshot: ChatMessage(
              localId: 'remote-visible-agent',
              remoteId: 'remote-visible-agent',
              threadId: 'dm:peer-scope:v1:hermes',
              senderDid: agentDid,
              receiverDid: ownerDid,
              content: 'new visible reply',
              createdAt: replyAt,
              isMine: false,
              serverSequence: 43,
              sendState: MessageSendState.sent,
            ),
          );
      final service = _PatchConversationService(
        conversations: <ConversationSummary>[peerScopedUnread],
        repaired: <ConversationSummary>[peerScopedUnread],
        repairVersion: 2,
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: ownerDid,
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      notifier.upsertConversation(alias);
      notifier.markConversationVisibleLocal(
        alias,
        watermark: const AppThreadReadWatermark(
          lastReadMessageId: 'remote-visible-agent',
          lastReadThreadSeq: '43',
        ),
      );
      await notifier.refreshFastLocal();
      final unreadEmissions = <int>[];
      final subscription = container.listen<ConversationListState>(
        conversationListProvider,
        (_, next) {
          unreadEmissions.add(next.conversations.single.unreadCount);
        },
      );
      addTearDown(subscription.close);

      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: ownerDid,
          version: 1,
          unreadTotal: 1,
          item: peerScopedUnread,
        ),
      );
      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.reset,
          ownerDid: ownerDid,
          version: 2,
          unreadTotal: 1,
          items: <ConversationSummary>[peerScopedUnread],
        ),
      );
      service.emitPatch(
        const ConversationListPatch(
          kind: ConversationListPatchKind.repairRequired,
          ownerDid: ownerDid,
          version: 3,
          unreadTotal: 1,
          reason: 'test',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final conversation = container
          .read(conversationListProvider)
          .conversations
          .single;
      expect(conversation.threadId, 'dm:peer-scope:v1:hermes');
      expect(conversation.lastMessagePreview, 'new visible reply');
      expect(conversation.unreadCount, 0);
      expect(unreadEmissions, isNot(contains(1)));
      expect(notifications.lastBadgeCount, 0);
    },
  );

  test('read watermark covers same summary after later refresh', () async {
    final messageAt = DateTime.utc(2026, 6, 27, 2);
    final conversation =
        _conversation(
          conversationId: 'group:watermark',
          threadId: 'group:watermark',
          displayName: 'Watermark Group',
          unreadCount: 1,
          lastMessageAt: messageAt,
          isGroup: true,
          groupId: 'watermark',
        ).copyWith(
          lastMessagePreview: 'covered by seq',
          lastMessageSnapshot: ChatMessage(
            localId: 'local-covered',
            remoteId: 'remote-covered',
            threadId: 'group:watermark',
            senderDid: 'did:agent',
            groupId: 'watermark',
            content: 'covered by seq',
            createdAt: messageAt.subtract(const Duration(milliseconds: 200)),
            isMine: false,
            serverSequence: 10,
            sendState: MessageSendState.sent,
          ),
        );
    final service = _MutableConversationService(
      conversations: <ConversationSummary>[conversation],
    );
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    notifier.upsertConversation(conversation);
    notifier.markConversationReadLocal(
      conversation,
      watermark: AppThreadReadWatermark(
        lastReadMessageId: 'remote-covered',
        lastReadThreadSeq: '10',
        readAt: messageAt.subtract(const Duration(milliseconds: 200)),
      ),
    );
    await notifier.refresh();

    final updated = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(updated.unreadCount, 0);
    expect(notifications.lastBadgeCount, 0);
  });

  test(
    'refreshFastLocal shows snapshot before SQLite hydrate finishes',
    () async {
      final hydrateCompleter = Completer<List<ConversationSummary>>();
      final service = _CompleterConversationService(
        snapshot: <ConversationSummary>[
          _conversation(
            threadId: 'dm:alice:bob',
            displayName: 'Bob snapshot',
            unreadCount: 4,
          ),
        ],
        hydrateCompleter: hydrateCompleter,
      );
      final notifications = FakeNotificationFacade();
      final container = ProviderContainer(
        overrides: <Override>[
          conversationServiceProvider.overrideWithValue(service),
          notificationFacadeProvider.overrideWithValue(notifications),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:alice',
                credentialName: 'alice',
                displayName: 'Alice',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(container.dispose);

      final refresh = container
          .read(conversationListProvider.notifier)
          .refreshFastLocal();
      await Future<void>.delayed(Duration.zero);

      expect(service.snapshotCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'Bob snapshot',
      );
      expect(container.read(conversationListProvider).isLoading, isTrue);
      expect(notifications.lastBadgeCount, 4);

      hydrateCompleter.complete(<ConversationSummary>[
        _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob hydrate',
          unreadCount: 1,
        ),
      ]);
      await refresh;

      expect(service.fastCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .single
            .displayName,
        'Bob hydrate',
      );
      expect(container.read(conversationListProvider).unreadCount, 1);
    },
  );

  test('conversation patch upsert updates one row and badge count', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
    );
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();

    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 3,
        item: _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob',
          unreadCount: 3,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    expect(conversations.single.displayName, 'Bob');
    expect(conversations.single.unreadCount, 3);
    expect(notifications.lastBadgeCount, 3);
    expect(service.watchCalls, 1);
  });

  test('conversation patch upsert respects local hidden waterline', () async {
    final seed = _conversation(
      threadId: 'dm:alice:bob',
      displayName: 'Bob',
      unreadCount: 1,
      lastMessageAt: DateTime.utc(2026, 6, 27, 2),
    );
    final service = _PatchConversationService(
      conversations: <ConversationSummary>[seed],
    );
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    await notifier.refreshFastLocal();
    await notifier.deleteFromRecents(seed);

    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(notifications.lastBadgeCount, 0);

    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 1,
        item: seed.copyWith(lastMessagePreview: 'stale hidden row'),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(conversationListProvider).conversations, isEmpty);

    final newerMessageAt = DateTime.now().toUtc().add(
      const Duration(minutes: 1),
    );
    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 2,
        unreadTotal: 2,
        item: seed.copyWith(
          lastMessagePreview: 'new message after hide',
          lastMessageAt: newerMessageAt,
          unreadCount: 2,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    expect(conversations.single.lastMessagePreview, 'new message after hide');
    expect(conversations.single.unreadCount, 2);
    expect(notifications.lastBadgeCount, 2);
  });

  test(
    'conversation patch reorder does not bypass stable ordering or repair',
    () async {
      final service = _PatchConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: FakeNotificationFacade(),
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      await container
          .read(conversationListProvider.notifier)
          .refreshFastLocal();
      for (final patch in <ConversationListPatch>[
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: 1,
          unreadTotal: 0,
          item: _conversation(
            threadId: 'thread-a',
            displayName: 'A',
            targetDid: 'did:a',
          ),
        ),
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: 2,
          unreadTotal: 0,
          item: _conversation(
            threadId: 'thread-b',
            displayName: 'B',
            targetDid: 'did:b',
          ),
        ),
        const ConversationListPatch(
          kind: ConversationListPatchKind.reorder,
          ownerDid: 'did:alice',
          version: 3,
          unreadTotal: 0,
          threadId: 'thread-b',
          index: 0,
        ),
      ]) {
        service.emitPatch(patch);
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        container
            .read(conversationListProvider)
            .conversations
            .map((item) => item.threadId),
        <String>['thread-a', 'thread-b'],
      );
      expect(service.repairCalls, 0);
    },
  );

  test('conversation patch remove targets canonical conversation id', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
    );
    final container = _conversationContainer(
      service: service,
      notifications: FakeNotificationFacade(),
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();
    for (final conversation in <ConversationSummary>[
      _conversation(
        conversationId: 'conv:a',
        threadId: 'legacy-thread-a',
        displayName: 'A',
        targetDid: 'did:same',
        targetPeer: 'same.awiki.example',
      ),
      _conversation(
        conversationId: 'conv:b',
        threadId: 'legacy-thread-b',
        displayName: 'B',
        targetDid: 'did:same',
        targetPeer: 'same.awiki.example',
      ),
    ]) {
      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: conversation.conversationId == 'conv:a' ? 1 : 2,
          unreadTotal: 0,
          item: conversation,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    service.emitPatch(
      const ConversationListPatch(
        kind: ConversationListPatchKind.remove,
        ownerDid: 'did:alice',
        version: 3,
        unreadTotal: 0,
        conversationId: 'conv:a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final rows = container.read(conversationListProvider).conversations;
    expect(rows.map((item) => item.conversationId), <String>['conv:b']);
  });

  test(
    'conversation patch reorder resolves canonical conversation id',
    () async {
      final service = _PatchConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: FakeNotificationFacade(),
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      await notifier.refreshFastLocal();
      for (final conversation in <ConversationSummary>[
        _conversation(
          conversationId: 'conv:a',
          threadId: 'legacy-thread-a',
          displayName: 'A',
          targetDid: 'did:a',
          lastMessageAt: DateTime.utc(2026, 6, 27, 2),
        ),
        _conversation(
          conversationId: 'conv:b',
          threadId: 'legacy-thread-b',
          displayName: 'B',
          targetDid: 'did:b',
          lastMessageAt: DateTime.utc(2026, 6, 27, 2),
        ),
      ]) {
        service.emitPatch(
          ConversationListPatch(
            kind: ConversationListPatchKind.upsert,
            ownerDid: 'did:alice',
            version: conversation.conversationId == 'conv:a' ? 1 : 2,
            unreadTotal: 0,
            item: conversation,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      service.emitPatch(
        const ConversationListPatch(
          kind: ConversationListPatchKind.reorder,
          ownerDid: 'did:alice',
          version: 3,
          unreadTotal: 0,
          conversationId: 'conv:b',
          index: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.repairCalls, 0);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .map((item) => item.conversationId),
        <String>['conv:a', 'conv:b'],
      );
    },
  );

  test(
    'conversation patch repairRequired falls back to repaired list',
    () async {
      final repaired = <ConversationSummary>[
        _conversation(
          threadId: 'dm:alice:carol',
          displayName: 'Carol repaired',
          unreadCount: 2,
        ),
      ];
      final service = _PatchConversationService(
        conversations: const <ConversationSummary>[],
        repaired: repaired,
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      await container
          .read(conversationListProvider.notifier)
          .refreshFastLocal();

      service.emitPatch(
        const ConversationListPatch(
          kind: ConversationListPatchKind.repairRequired,
          ownerDid: 'did:alice',
          version: 1,
          unreadTotal: 2,
          reason: 'subscriber_lag',
        ),
      );
      await pumpEventQueue();

      final conversations = container
          .read(conversationListProvider)
          .conversations;
      expect(service.repairCalls, 1);
      expect(conversations, hasLength(1));
      expect(conversations.single.displayName, 'Carol repaired');
      expect(notifications.lastBadgeCount, 2);
    },
  );

  test('conversation patch repair resumes from repaired version', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
      repaired: <ConversationSummary>[
        _conversation(
          threadId: 'thread-repaired',
          displayName: 'Repaired',
          targetDid: 'did:repaired',
        ),
      ],
      repairVersion: 5,
    );
    final container = _conversationContainer(
      service: service,
      notifications: FakeNotificationFacade(),
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();

    service.emitPatch(
      const ConversationListPatch(
        kind: ConversationListPatchKind.repairRequired,
        ownerDid: 'did:alice',
        version: 3,
        unreadTotal: 0,
        reason: 'subscriber_lag',
      ),
    );
    await pumpEventQueue();
    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 6,
        unreadTotal: 1,
        item: _conversation(
          threadId: 'thread-after-repair',
          displayName: 'After repair',
          targetDid: 'did:after-repair',
          unreadCount: 1,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(service.repairCalls, 1);
    expect(
      container
          .read(conversationListProvider)
          .conversations
          .map((item) => item.threadId),
      containsAll(<String>['thread-repaired', 'thread-after-repair']),
    );
  });

  test(
    'conversation patch repair does not commit version when apply is stale',
    () async {
      final repairGate = Completer<ConversationStoreRepairResult>();
      final service = _PatchConversationService(
        conversations: const <ConversationSummary>[],
        repairResult: repairGate.future,
      );
      final notifications = FakeNotificationFacade();
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      final notifier = container.read(conversationListProvider.notifier);
      await notifier.refreshFastLocal();
      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: 1,
          unreadTotal: 0,
          item: _conversation(
            threadId: 'thread-one',
            displayName: 'One',
            targetDid: 'did:one',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      service.emitPatch(
        const ConversationListPatch(
          kind: ConversationListPatchKind.repairRequired,
          ownerDid: 'did:alice',
          version: 2,
          unreadTotal: 0,
          reason: 'stale_test',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:bob',
              credentialName: 'bob',
              displayName: 'Bob',
            ),
          );
      repairGate.complete(
        ConversationStoreRepairResult(
          conversations: <ConversationSummary>[
            _conversation(
              threadId: 'thread-repair-stale',
              displayName: 'Stale repair',
              targetDid: 'did:stale',
            ),
          ],
          version: 2,
        ),
      );
      await pumpEventQueue();

      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:alice',
              credentialName: 'alice',
              displayName: 'Alice',
            ),
          );
      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: 2,
          unreadTotal: 1,
          item: _conversation(
            threadId: 'thread-two',
            displayName: 'Two',
            targetDid: 'did:two',
            unreadCount: 1,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.repairCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .map((item) => item.threadId),
        containsAll(<String>['thread-one', 'thread-two']),
      );
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .map((item) => item.threadId),
        isNot(contains('thread-repair-stale')),
      );
      expect(notifications.lastBadgeCount, 1);
    },
  );

  test(
    'conversation patch gap does not advance version before repair lands',
    () async {
      final service = _PatchConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: FakeNotificationFacade(),
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);

      await container
          .read(conversationListProvider.notifier)
          .refreshFastLocal();

      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: 1,
          unreadTotal: 0,
          item: _conversation(
            threadId: 'thread-one',
            displayName: 'One',
            targetDid: 'did:one',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: 3,
          unreadTotal: 0,
          item: _conversation(
            threadId: 'thread-three',
            displayName: 'Three',
            targetDid: 'did:three',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      service.emitPatch(
        ConversationListPatch(
          kind: ConversationListPatchKind.upsert,
          ownerDid: 'did:alice',
          version: 2,
          unreadTotal: 1,
          item: _conversation(
            threadId: 'thread-two',
            displayName: 'Two',
            targetDid: 'did:two',
            unreadCount: 1,
          ),
        ),
      );
      await pumpEventQueue();

      expect(service.repairCalls, 1);
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .map((item) => item.threadId),
        contains('thread-two'),
      );
      expect(
        container
            .read(conversationListProvider)
            .conversations
            .map((item) => item.threadId),
        isNot(contains('thread-three')),
      );
    },
  );

  test('conversation patch stream does not repopulate after clear', () async {
    final service = _PatchConversationService(
      conversations: const <ConversationSummary>[],
    );
    final container = _conversationContainer(
      service: service,
      notifications: FakeNotificationFacade(),
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    await notifier.refreshFastLocal();
    await notifier.clear();

    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 1,
        item: _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob stale',
          unreadCount: 1,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(service.cancelled, isTrue);
  });

  test('clear does not wait for hung patch stream cancellation', () async {
    final service = _HangingCancelPatchConversationService(
      conversations: const <ConversationSummary>[],
    );
    final container = _conversationContainer(
      service: service,
      notifications: FakeNotificationFacade(),
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);

    final notifier = container.read(conversationListProvider.notifier);
    await notifier.refreshFastLocal();

    await expectLater(
      notifier.clear().timeout(const Duration(milliseconds: 100)),
      completes,
    );
    expect(service.cancelRequested, isTrue);

    service.emitPatch(
      ConversationListPatch(
        kind: ConversationListPatchKind.upsert,
        ownerDid: 'did:alice',
        version: 1,
        unreadTotal: 1,
        item: _conversation(
          threadId: 'dm:alice:bob',
          displayName: 'Bob stale',
          unreadCount: 1,
        ),
      ),
    );
    await pumpEventQueue();

    expect(container.read(conversationListProvider).conversations, isEmpty);
  });

  test('fast hydrate removes stale snapshot-only conversations', () async {
    final service = _StaticConversationService(
      conversations: const <ConversationSummary>[],
      snapshot: <ConversationSummary>[
        _conversation(
          threadId: 'dm:alice:stale',
          displayName: 'Stale snapshot',
          targetDid: 'did:stale',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: <Override>[
        conversationServiceProvider.overrideWithValue(service),
        notificationFacadeProvider.overrideWithValue(FakeNotificationFacade()),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:alice',
              credentialName: 'alice',
              displayName: 'Alice',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(container.dispose);

    await container.read(conversationListProvider.notifier).refreshFastLocal();

    expect(service.snapshotCalls, 1);
    expect(container.read(conversationListProvider).conversations, isEmpty);
  });

  test('snapshot bootstrap does not repopulate after clear', () async {
    final snapshotCompleter = Completer<List<ConversationSummary>>();
    final hydrateCompleter = Completer<List<ConversationSummary>>();
    final service = _CompleterConversationService(
      snapshot: const <ConversationSummary>[],
      snapshotCompleter: snapshotCompleter,
      hydrateCompleter: hydrateCompleter,
    );
    final notifications = FakeNotificationFacade();
    final container = ProviderContainer(
      overrides: <Override>[
        conversationServiceProvider.overrideWithValue(service),
        notificationFacadeProvider.overrideWithValue(notifications),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:alice',
              credentialName: 'alice',
              displayName: 'Alice',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(container.dispose);

    final refresh = container.read(conversationListProvider.notifier);
    final refreshFuture = refresh.refreshFastLocal();
    await Future<void>.delayed(Duration.zero);

    await refresh.clear();
    snapshotCompleter.complete(<ConversationSummary>[
      _conversation(
        threadId: 'dm:alice:stale',
        displayName: 'Stale snapshot',
        unreadCount: 9,
      ),
    ]);
    hydrateCompleter.complete(const <ConversationSummary>[]);
    await refreshFuture;

    expect(service.snapshotCalls, 1);
    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(notifications.lastBadgeCount, 0);
  });

  test('realtime message refreshes unread from core projection', () async {
    final notifications = FakeNotificationFacade();
    final service = _MutableConversationService(
      conversations: const <ConversationSummary>[],
    );
    final container = _conversationContainer(
      service: service,
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);
    final notifier = container.read(conversationListProvider.notifier);
    final local = _conversation(
      threadId: 'group:team',
      displayName: 'Team',
      unreadCount: 3,
      isGroup: true,
      groupId: 'team',
    ).copyWith(unreadMentionCount: 1, firstUnreadMentionMessageId: 'mention-1');
    notifier.upsertConversation(local);

    service.currentConversations = <ConversationSummary>[
      local.copyWith(
        lastMessagePreview: 'new realtime',
        lastMessageAt: DateTime.utc(2026, 6, 27, 2, 1),
        unreadCount: 1,
        unreadMentionCount: 0,
        firstUnreadMentionMessageId: null,
      ),
    ];
    notifier.upsertRealtimeMessageBestEffort(
      service.currentConversations.single,
      message: ChatMessage(
        localId: 'realtime-1',
        remoteId: 'realtime-1',
        threadId: 'group:team',
        senderDid: 'did:bob',
        senderName: 'Bob',
        receiverDid: 'did:alice',
        groupId: 'team',
        content: 'new realtime',
        createdAt: DateTime.utc(2026, 6, 27, 2, 1),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
    );
    await pumpEventQueue();

    final updated = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(service.fastCalls, 1);
    expect(updated.lastMessagePreview, 'new realtime');
    expect(updated.unreadCount, 1);
    expect(updated.unreadMentionCount, 0);
    expect(updated.firstUnreadMentionMessageId, isNull);
    expect(notifications.lastBadgeCount, 1);
  });

  test(
    'realtime peer-scoped message replaces legacy target only after core refresh',
    () async {
      final notifications = FakeNotificationFacade();
      final service = _MutableConversationService(
        conversations: const <ConversationSummary>[],
      );
      final container = _conversationContainer(
        service: service,
        notifications: notifications,
        ownerDid: 'did:alice',
      );
      addTearDown(container.dispose);
      final notifier = container.read(conversationListProvider.notifier);
      final legacy = _conversation(
        threadId: 'dm:did:alice:did:agent',
        displayName: 'Agent legacy',
        targetDid: 'did:agent',
        targetPeer: 'did:agent',
      );
      notifier.upsertConversation(legacy);

      notifier.upsertRealtimeMessageBestEffort(
        _conversation(
          threadId: 'direct:did:agent',
          displayName: 'Agent',
          unreadCount: 1,
          targetDid: 'did:agent',
          targetPeer: 'agent.awiki.example',
          lastMessageAt: DateTime.utc(2026, 6, 27, 2, 2),
        ).copyWith(lastMessagePreview: 'runtime reply'),
        message: ChatMessage(
          localId: 'runtime-1',
          remoteId: 'runtime-1',
          threadId: 'dm:peer-scope:v1:agent',
          senderDid: 'did:agent',
          senderName: 'Agent',
          receiverDid: 'did:alice',
          content: 'runtime reply',
          createdAt: DateTime.utc(2026, 6, 27, 2, 2),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      );
      await pumpEventQueue();
      expect(
        container.read(conversationListProvider).conversations.single.threadId,
        'dm:did:alice:did:agent',
      );

      service.currentConversations = <ConversationSummary>[
        _conversation(
          conversationId: 'conv:agent',
          threadId: 'dm:peer-scope:v1:agent',
          displayName: 'Agent',
          unreadCount: 1,
          targetDid: 'did:agent',
          targetPeer: 'agent.awiki.example',
          lastMessageAt: DateTime.utc(2026, 6, 27, 2, 2),
        ).copyWith(lastMessagePreview: 'runtime reply'),
      ];
      notifier.upsertRealtimeMessageBestEffort(
        service.currentConversations.single,
        message: ChatMessage(
          localId: 'runtime-1',
          remoteId: 'runtime-1',
          threadId: 'dm:peer-scope:v1:agent',
          senderDid: 'did:agent',
          senderName: 'Agent',
          receiverDid: 'did:alice',
          content: 'runtime reply',
          createdAt: DateTime.utc(2026, 6, 27, 2, 2),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      );
      await pumpEventQueue();

      final rows = container.read(conversationListProvider).conversations;
      expect(service.fastCalls, 2);
      expect(
        rows.map((item) => item.threadId),
        contains('dm:peer-scope:v1:agent'),
      );
      final refreshed = rows.singleWhere(
        (item) => item.conversationId == 'conv:agent',
      );
      expect(refreshed.lastMessagePreview, 'runtime reply');
      expect(refreshed.unreadCount, 1);
      expect(notifications.lastBadgeCount, 1);
    },
  );

  test('conversation upserts use stable unread-first ordering', () async {
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: _StaticConversationService(conversations: const []),
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);
    final notifier = container.read(conversationListProvider.notifier);
    final baseTime = DateTime.utc(2026, 6, 27, 2);

    notifier.upsertConversation(
      _conversation(
        threadId: 'dm:read-newer',
        displayName: 'Read newer',
        targetDid: 'did:read-newer',
        lastMessageAt: baseTime.add(const Duration(minutes: 2)),
      ),
    );
    notifier.upsertConversation(
      _conversation(
        threadId: 'dm:unread-older',
        displayName: 'Unread older',
        unreadCount: 1,
        targetDid: 'did:unread-older',
        lastMessageAt: baseTime,
      ),
    );
    notifier.upsertConversation(
      _conversation(
        threadId: 'dm:mention-oldest',
        displayName: 'Mention oldest',
        unreadCount: 1,
        targetDid: 'did:mention-oldest',
        lastMessageAt: baseTime.subtract(const Duration(minutes: 1)),
      ).copyWith(unreadMentionCount: 1),
    );

    expect(
      container
          .read(conversationListProvider)
          .conversations
          .map((item) => item.threadId),
      <String>['dm:mention-oldest', 'dm:unread-older', 'dm:read-newer'],
    );
  });

  test('conversation ordering has a deterministic tie-breaker', () {
    final notifications = FakeNotificationFacade();
    final container = _conversationContainer(
      service: _StaticConversationService(conversations: const []),
      notifications: notifications,
      ownerDid: 'did:alice',
    );
    addTearDown(container.dispose);
    final notifier = container.read(conversationListProvider.notifier);
    final sameTime = DateTime.utc(2026, 6, 27, 2);

    notifier.upsertConversation(
      _conversation(
        threadId: 'dm:z-thread',
        displayName: 'Zed',
        targetDid: 'did:z',
        lastMessageAt: sameTime,
      ),
    );
    notifier.upsertConversation(
      _conversation(
        threadId: 'dm:a-thread',
        displayName: 'Amy',
        targetDid: 'did:a',
        lastMessageAt: sameTime,
      ),
    );

    expect(
      container
          .read(conversationListProvider)
          .conversations
          .map((item) => item.threadId),
      <String>['dm:a-thread', 'dm:z-thread'],
    );
  });
}

ConversationSummary _conversation({
  String? conversationId,
  required String threadId,
  required String displayName,
  int unreadCount = 0,
  String targetDid = 'did:bob',
  String? targetPeer,
  bool isGroup = false,
  String? groupId,
  DateTime? lastMessageAt,
}) {
  return ConversationSummary(
    conversationId: conversationId,
    threadId: threadId,
    displayName: displayName,
    lastMessagePreview: 'hello',
    lastMessageAt: lastMessageAt ?? DateTime.utc(2026, 6, 27, 2),
    unreadCount: unreadCount,
    isGroup: isGroup,
    targetDid: isGroup ? null : targetDid,
    targetPeer: isGroup ? null : targetPeer,
    groupId: groupId,
  );
}

ChatMessage _messageSnapshot({
  required String threadId,
  required String remoteId,
  int? serverSequence,
  DateTime? createdAt,
}) {
  return ChatMessage(
    localId: remoteId,
    remoteId: remoteId,
    threadId: threadId,
    senderDid: 'did:bob',
    receiverDid: 'did:alice',
    content: 'hello',
    createdAt: createdAt ?? DateTime.utc(2026, 6, 27, 2),
    isMine: false,
    serverSequence: serverSequence,
    sendState: MessageSendState.sent,
  );
}

ProviderContainer _conversationContainer({
  required ConversationService service,
  required FakeNotificationFacade notifications,
  required String ownerDid,
  List<AgentSummary> agents = const <AgentSummary>[],
  AwikiEnvironmentConfig? environment,
}) {
  return ProviderContainer(
    overrides: <Override>[
      if (environment != null)
        awikiEnvironmentConfigProvider.overrideWithValue(environment),
      conversationServiceProvider.overrideWithValue(service),
      notificationFacadeProvider.overrideWithValue(notifications),
      agentsProvider.overrideWith(
        (ref) => _StaticAgentsController(ref, agents),
      ),
      sessionProvider.overrideWith((ref) {
        final controller = SessionController();
        controller.setSession(
          SessionIdentity(
            did: ownerDid,
            credentialName: 'alice',
            displayName: 'Alice',
          ),
        );
        return controller;
      }),
    ],
  );
}

class _StaticAgentsController extends AgentsController {
  _StaticAgentsController(super.ref, List<AgentSummary> agents) {
    state = AgentsState(agents: agents);
  }
}

class _SlowEnrichConversationService implements ConversationService {
  _SlowEnrichConversationService({required this.base, required this.enriched});

  final List<ConversationSummary> base;
  final List<ConversationSummary> enriched;
  final Completer<void> _enrichCompleter = Completer<void>();
  int fastCalls = 0;
  int snapshotCalls = 0;
  int enrichCalls = 0;

  void completeEnrichment() {
    if (!_enrichCompleter.isCompleted) {
      _enrichCompleter.complete();
    }
  }

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    snapshotCalls += 1;
    return const <ConversationSummary>[];
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    return StreamController<ConversationListPatch>().stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return ConversationStoreRepairResult(conversations: base, version: 1);
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return base;
  }

  @override
  Future<ConversationPage> listConversationSummariesFastPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversationSummariesFast(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    enrichCalls += 1;
    await _enrichCompleter.future;
    return enriched;
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return base;
  }

  @override
  Future<ConversationPage> listConversationsPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversations(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    return conversation;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}
}

AppThreadReadWatermark? _watermarkForConversation(
  ConversationSummary conversation,
) {
  final snapshot = conversation.lastMessageSnapshot;
  if (snapshot == null) {
    return null;
  }
  final remoteId = snapshot.remoteId?.trim();
  return AppThreadReadWatermark(
    lastReadMessageId: remoteId?.isNotEmpty ?? false ? remoteId : null,
    lastReadThreadSeq: snapshot.serverSequence?.toString(),
    readAt: snapshot.createdAt.toUtc(),
  );
}

class _StaticConversationService implements ConversationService {
  _StaticConversationService({
    required this.conversations,
    this.snapshot = const <ConversationSummary>[],
  });

  final List<ConversationSummary> conversations;
  final List<ConversationSummary> snapshot;
  int fastCalls = 0;
  int listCalls = 0;
  int snapshotCalls = 0;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    snapshotCalls += 1;
    return snapshot;
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    return StreamController<ConversationListPatch>().stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return ConversationStoreRepairResult(
      conversations: conversations,
      version: 1,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    listCalls += 1;
    return conversations;
  }

  @override
  Future<ConversationPage> listConversationsPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversations(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return conversations;
  }

  @override
  Future<ConversationPage> listConversationSummariesFastPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    return ConversationPage(
      items: await listConversationSummariesFast(
        ownerDid: ownerDid,
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      hasMore: false,
    );
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    return conversations;
  }

  @override
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  }) async {}

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    return conversation;
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {}
}

class _MutableConversationService extends _StaticConversationService {
  _MutableConversationService({required super.conversations})
    : currentConversations = conversations;

  List<ConversationSummary> currentConversations;

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return ConversationStoreRepairResult(
      conversations: currentConversations,
      version: 1,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    listCalls += 1;
    return currentConversations;
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return currentConversations;
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    return conversations;
  }
}

class _NormalizingConversationService extends _StaticConversationService {
  _NormalizingConversationService({required this.normalize})
    : super(conversations: const <ConversationSummary>[]);

  final Future<ConversationSummary?> Function(ConversationSummary conversation)
  normalize;

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) {
    return normalize(conversation);
  }
}

class _CompleterConversationService extends _StaticConversationService {
  _CompleterConversationService({
    required super.snapshot,
    this.snapshotCompleter,
    required this.hydrateCompleter,
  }) : super(conversations: const <ConversationSummary>[]);

  final Completer<List<ConversationSummary>>? snapshotCompleter;
  final Completer<List<ConversationSummary>> hydrateCompleter;

  @override
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    snapshotCalls += 1;
    final completer = snapshotCompleter;
    if (completer != null) {
      return completer.future;
    }
    return snapshot;
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    fastCalls += 1;
    return hydrateCompleter.future;
  }
}

class _PatchConversationService extends _StaticConversationService {
  _PatchConversationService({
    required super.conversations,
    this.repaired = const <ConversationSummary>[],
    this.repairVersion = 1,
    this.repairResult,
  });

  final List<ConversationSummary> repaired;
  final int repairVersion;
  final Future<ConversationStoreRepairResult>? repairResult;
  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);
  int watchCalls = 0;
  int repairCalls = 0;
  bool cancelled = false;

  void emitPatch(ConversationListPatch patch) {
    _patches.add(patch);
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    watchCalls += 1;
    late final StreamController<ConversationListPatch> controller;
    late final StreamSubscription<ConversationListPatch> subscription;
    controller = StreamController<ConversationListPatch>(
      sync: true,
      onListen: () {
        subscription = _patches.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        cancelled = true;
        await subscription.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    repairCalls += 1;
    final result = repairResult;
    if (result != null) {
      return result;
    }
    return ConversationStoreRepairResult(
      conversations: repaired,
      version: repairVersion,
    );
  }
}

class _HangingCancelPatchConversationService
    extends _StaticConversationService {
  _HangingCancelPatchConversationService({required super.conversations});

  final StreamController<ConversationListPatch> _patches =
      StreamController<ConversationListPatch>.broadcast(sync: true);
  final Completer<void> _cancelCompleter = Completer<void>();
  bool cancelRequested = false;

  void emitPatch(ConversationListPatch patch) {
    _patches.add(patch);
  }

  @override
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) {
    late final StreamController<ConversationListPatch> controller;
    late final StreamSubscription<ConversationListPatch> subscription;
    controller = StreamController<ConversationListPatch>(
      sync: true,
      onListen: () {
        subscription = _patches.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () {
        cancelRequested = true;
        return _cancelCompleter.future.whenComplete(subscription.cancel);
      },
    );
    return controller.stream;
  }
}
