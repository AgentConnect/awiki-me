import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_conversation_read_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';
import 'package:awiki_me/src/application/models/thread_message_patch.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  late FakeAwikiGateway gateway;
  late FakeNotificationFacade notificationFacade;
  late FakeMessageSyncService messageSyncService;
  late ProviderContainer container;

  final conversation = ConversationSummary(
    conversationId: 'dm:did:peer',
    threadId: 'dm:did:me:did:peer',
    displayName: 'Peer',
    lastMessagePreview: 'hello',
    lastMessageAt: DateTime(2026, 5, 8, 10, 0),
    unreadCount: 0,
    isGroup: false,
    targetDid: 'did:peer',
  );

  final message = ChatMessage(
    localId: 'msg-1',
    remoteId: 'msg-1',
    threadId: 'dm:did:me:did:peer',
    senderDid: 'did:peer',
    content: 'hello',
    createdAt: DateTime(2026, 5, 8, 10, 0),
    isMine: false,
    sendState: MessageSendState.sent,
  );

  setUp(() {
    gateway = FakeAwikiGateway()
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[message],
      }
      ..conversations = <ConversationSummary>[conversation];
    notificationFacade = FakeNotificationFacade();
    messageSyncService = FakeMessageSyncService();
    final messagingService = FakeMessagingService(gateway);
    _seedConversationProjection(messagingService, conversation, <ChatMessage>[
      message,
    ]);
    messageSyncService.onConversationAfterPersisted =
        (String conversationId, List<ChatMessage> messages) {
          return messagingService.persistConversationMessages(
            conversationId,
            messages,
          );
        };
    container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
        ),
        messagingServiceProvider.overrideWithValue(messagingService),
      ],
    );
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:me',
            credentialName: 'me.json',
            displayName: 'Me',
            handle: 'me',
          ),
        );
    addTearDown(container.dispose);
  });

  test('首次打开空线程时本地历史命中不触发远端 history', () async {
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[message],
    };

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);

    await pumpEventQueue();

    final messaging = container.read(messagingServiceProvider);
    expect(messaging, isA<FakeMessagingService>());
    expect(
      (messaging as FakeMessagingService).conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(gateway.listConversationsCalls, greaterThanOrEqualTo(1));
    expect(messaging.lastConversationTimelineLimit, 50);
    expect(messageSyncService.conversationAfterRequests, isNotEmpty);
    expect(
      messageSyncService.conversationAfterRequests.single.afterServerSeq,
      isNull,
    );
    expect(messageSyncService.threadAfterRequests, isEmpty);

    final thread = container.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.messages, hasLength(1));
    expect(thread.messages.single.content, 'hello');
    expect(thread.isLoading, isFalse);
  });

  test('打开会话加载到首条本地历史后同步最近会话预览', () async {
    final emptyPreviewConversation = conversation.copyWith(
      lastMessagePreview: '',
    );
    final projectedMessage = message.copyWith(content: 'Agent 已准备好。');
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[projectedMessage],
    };
    gateway.conversations = <ConversationSummary>[emptyPreviewConversation];
    _seedContainerConversationProjection(
      container,
      emptyPreviewConversation,
      <ChatMessage>[projectedMessage],
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(emptyPreviewConversation);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(emptyPreviewConversation);
    await pumpEventQueue();

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    expect(conversations.single.lastMessagePreview, 'Agent 已准备好。');
    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
  });

  test('本地历史为空时走 conversation-after 回补', () async {
    gateway.localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      message,
    ]);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messageSyncService.conversationAfterRequests, isNotEmpty);
    expect(messageSyncService.threadAfterRequests, isEmpty);
    final thread = container.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.messages.map((item) => item.content), contains('hello'));
    expect(thread.isLoading, isFalse);
  });

  test('首次打开已有内存尾消息的会话仍从本地投影合并历史', () async {
    final older = ChatMessage(
      localId: 'local-10',
      remoteId: 'local-10',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'old local',
      createdAt: DateTime(2026, 5, 8, 9, 59),
      isMine: false,
      serverSequence: 10,
      sendState: MessageSendState.sent,
    );
    final realtime = ChatMessage(
      localId: 'remote-11',
      remoteId: 'remote-11',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'new realtime',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      serverSequence: 11,
      sendState: MessageSendState.sent,
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[older, realtime],
    };
    _seedContainerConversationProjection(container, conversation, <ChatMessage>[
      older,
      realtime,
    ]);

    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          realtime.copyWith(
            conversationId: conversation.effectiveConversationId,
          ),
          threadId: _timelineThreadId(conversation),
        );
    expect(
      container
          .read(chatThreadProvider(_timelineThreadId(conversation)))
          .messages
          .map((item) => item.content),
      ['new realtime'],
    );

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(
          conversation.copyWith(lastMessageAt: realtime.createdAt),
        );
    await pumpEventQueue();

    final thread = container.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(thread.messages.map((item) => item.content), [
      'old local',
      'new realtime',
    ]);
    expect(thread.isHydratingLocalHistory, isFalse);
  });

  test('runtime realtime reply does not fan out into controller thread', () {
    const agentDid = 'did:wba:awiki.ai:agent:runtime:test';
    const agentHandle = 'test-agent.awiki.ai';
    final controllerConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:controller',
      displayName: 'Controller',
      lastMessagePreview: '今天几号了',
      lastMessageAt: DateTime(2026, 7, 3, 7, 9),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final runtimeConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Runtime Agent',
      lastMessagePreview: '今天是 2026年7月3日。',
      lastMessageAt: DateTime(2026, 7, 3, 7, 10),
      unreadCount: 1,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final existingControllerMessage = ChatMessage(
      localId: 'controller-msg',
      remoteId: 'controller-msg',
      threadId: controllerConversation.threadId,
      senderDid: 'did:me',
      receiverDid: agentDid,
      content: '今天几号了',
      createdAt: controllerConversation.lastMessageAt,
      isMine: true,
      sendState: MessageSendState.sent,
    );
    final runtimeReply = ChatMessage(
      localId: 'runtime-final',
      remoteId: 'runtime-final',
      threadId: runtimeConversation.threadId,
      senderDid: agentDid,
      receiverDid: 'did:me',
      content: '今天是 2026年7月3日。',
      createdAt: runtimeConversation.lastMessageAt,
      isMine: false,
      serverSequence: 2899,
      sendState: MessageSendState.sent,
    );

    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(existingControllerMessage);
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(runtimeReply);

    expect(
      container
          .read(chatThreadProvider(controllerConversation.threadId))
          .messages
          .map((item) => item.content),
      ['今天几号了'],
    );
    expect(
      container
          .read(chatThreadProvider(runtimeConversation.threadId))
          .messages
          .map((item) => item.content),
      ['今天是 2026年7月3日。'],
    );
  });

  test('runtime realtime reply ignores stale controller conversation hint', () {
    const agentDid = 'did:wba:awiki.ai:agent:runtime:test';
    const agentHandle = 'test-agent.awiki.ai';
    final controllerConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:controller',
      displayName: 'Controller',
      lastMessagePreview: '今天几号了',
      lastMessageAt: DateTime(2026, 7, 3, 7, 9),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final runtimeConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Runtime Agent',
      lastMessagePreview: '今天是 2026年7月3日。',
      lastMessageAt: DateTime(2026, 7, 3, 7, 10),
      unreadCount: 1,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final controllerMessage = ChatMessage(
      localId: 'controller-msg',
      remoteId: 'controller-msg',
      threadId: controllerConversation.threadId,
      senderDid: 'did:me',
      receiverDid: agentDid,
      content: '今天几号了',
      createdAt: controllerConversation.lastMessageAt,
      isMine: true,
      sendState: MessageSendState.sent,
    );
    final runtimeReply = ChatMessage(
      localId: 'runtime-final',
      remoteId: 'runtime-final',
      threadId: runtimeConversation.threadId,
      senderDid: agentDid,
      receiverDid: 'did:me',
      content: '今天是 2026年7月3日。',
      createdAt: runtimeConversation.lastMessageAt,
      isMine: false,
      serverSequence: 2899,
      sendState: MessageSendState.sent,
    );
    final controller = container.read(chatThreadsProvider.notifier);

    controller.debugSeedMessageForTesting(controllerMessage);
    controller.debugSeedMessageForTesting(runtimeReply);

    expect(
      container
          .read(chatThreadProvider(controllerConversation.threadId))
          .messages
          .map((item) => item.content),
      ['今天几号了'],
    );
    expect(
      container
          .read(chatThreadProvider(runtimeConversation.threadId))
          .messages
          .map((item) => item.content),
      ['今天是 2026年7月3日。'],
    );
  });

  test('peer-scoped direct conversations do not share composer drafts', () {
    const agentDid = 'did:wba:awiki.ai:agent:runtime:test';
    const agentHandle = 'test-agent.awiki.ai';
    final controllerConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:controller',
      displayName: 'Controller',
      lastMessagePreview: 'controller preview',
      lastMessageAt: DateTime(2026, 7, 3, 7, 9),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final runtimeConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Runtime Agent',
      lastMessagePreview: 'runtime preview',
      lastMessageAt: DateTime(2026, 7, 3, 7, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );

    final drafts = container.read(chatComposerDraftsProvider.notifier);
    drafts.setText(controllerConversation, 'controller draft');

    expect(drafts.draftFor(controllerConversation).text, 'controller draft');
    expect(drafts.draftFor(runtimeConversation).isEmpty, isTrue);

    drafts.setText(runtimeConversation, 'runtime draft');

    expect(drafts.draftFor(controllerConversation).text, 'controller draft');
    expect(drafts.draftFor(runtimeConversation).text, 'runtime draft');
  });

  test(
    'ambiguous agent run status does not attach to peer-scoped conversations',
    () {
      const agentDid = 'did:wba:awiki.ai:agent:runtime:test';
      const agentHandle = 'test-agent.awiki.ai';
      final controllerConversation = ConversationSummary(
        threadId: 'dm:peer-scope:v1:controller',
        displayName: 'Controller',
        lastMessagePreview: 'controller preview',
        lastMessageAt: DateTime(2026, 7, 3, 7, 9),
        unreadCount: 0,
        isGroup: false,
        targetDid: agentDid,
        targetPeer: agentHandle,
      );
      final runtimeConversation = ConversationSummary(
        threadId: 'dm:peer-scope:v1:runtime',
        displayName: 'Runtime Agent',
        lastMessagePreview: 'runtime preview',
        lastMessageAt: DateTime(2026, 7, 3, 7, 10),
        unreadCount: 0,
        isGroup: false,
        targetDid: agentDid,
        targetPeer: agentHandle,
      );
      final conversations = container.read(conversationListProvider.notifier);
      conversations.upsertConversation(controllerConversation);
      conversations.upsertConversation(runtimeConversation);

      container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
        const <String, Object?>{
          'schema': 'awiki.agent.status.v1',
          'status_scope': 'run',
          'runs': <Object?>[
            <String, Object?>{
              'run_id': 'run_ambiguous_peer_scoped',
              'runtime_agent_did': agentDid,
              'status': 'running',
            },
          ],
        },
      );

      expect(
        container
            .read(chatThreadProvider(controllerConversation.threadId))
            .pendingAgentReplyCount,
        0,
      );
      expect(
        container
            .read(chatThreadProvider(runtimeConversation.threadId))
            .pendingAgentReplyCount,
        0,
      );
      final fallbackThread = container.read(
        chatThreadProvider('direct:$agentDid'),
      );
      expect(fallbackThread.pendingAgentReplyCount, 1);
      expect(fallbackThread.agentPendingTurns.single.agentDid, agentDid);
    },
  );

  test('本地历史混合有无 serverSequence 时按时间线稳定排序', () async {
    final askedTime = ChatMessage(
      localId: 'local-question-time',
      remoteId: 'local-question-time',
      threadId: conversation.threadId,
      senderDid: 'did:me',
      receiverDid: 'did:peer',
      content: '现在几点',
      createdAt: DateTime(2026, 5, 8, 10, 0),
      isMine: true,
      sendState: MessageSendState.sent,
    );
    final timeReply = ChatMessage(
      localId: 'remote-time-reply',
      remoteId: 'remote-time-reply',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: '现在时间是 10:01',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      serverSequence: 101,
      sendState: MessageSendState.sent,
    );
    final followUp = ChatMessage(
      localId: 'local-follow-up',
      remoteId: 'local-follow-up',
      threadId: conversation.threadId,
      senderDid: 'did:me',
      receiverDid: 'did:peer',
      content: 'nihao',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: true,
      sendState: MessageSendState.sent,
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[askedTime, timeReply, followUp],
    };
    _seedContainerConversationProjection(container, conversation, <ChatMessage>[
      askedTime,
      timeReply,
      followUp,
    ]);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(
          conversation.copyWith(
            lastMessagePreview: followUp.content,
            lastMessageAt: followUp.createdAt,
          ),
        );
    await pumpEventQueue();

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), <String>[
      '现在几点',
      '现在时间是 10:01',
      'nihao',
    ]);
  });

  test('thread-after 补全已有消息 serverSequence 后不改变可见时间线顺序', () async {
    final askedTime = ChatMessage(
      localId: 'local-question-time',
      remoteId: 'local-question-time',
      threadId: conversation.threadId,
      senderDid: 'did:me',
      receiverDid: 'did:peer',
      content: '现在几点',
      createdAt: DateTime(2026, 5, 8, 10, 0),
      isMine: true,
      sendState: MessageSendState.sent,
    );
    final timeReplyWithoutSeq = ChatMessage(
      localId: 'remote-time-reply',
      remoteId: 'remote-time-reply',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: '现在时间是 10:01',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    final followUp = ChatMessage(
      localId: 'local-follow-up',
      remoteId: 'local-follow-up',
      threadId: conversation.threadId,
      senderDid: 'did:me',
      receiverDid: 'did:peer',
      content: 'nihao',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: true,
      sendState: MessageSendState.sent,
    );
    final timeReplyWithSeq = timeReplyWithoutSeq.copyWith(serverSequence: 101);
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[askedTime, timeReplyWithoutSeq, followUp],
    };
    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      timeReplyWithSeq,
    ]);
    _seedContainerConversationProjection(container, conversation, <ChatMessage>[
      askedTime,
      timeReplyWithoutSeq,
      followUp,
    ]);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(
          conversation.copyWith(
            lastMessagePreview: followUp.content,
            lastMessageAt: followUp.createdAt,
          ),
        );
    await pumpEventQueue();

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), <String>[
      '现在几点',
      '现在时间是 10:01',
      'nihao',
    ]);
    expect(
      messages
          .singleWhere((item) => item.content == '现在时间是 10:01')
          .serverSequence,
      101,
    );
  });

  test('打开会话后按本地最大 serverSequence 调用 thread-after 补新', () async {
    final local = ChatMessage(
      localId: 'local-1',
      remoteId: 'local-1',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'old',
      createdAt: DateTime(2026, 5, 8, 9, 59),
      isMine: false,
      serverSequence: 10,
      sendState: MessageSendState.sent,
    );
    final newer = ChatMessage(
      localId: 'remote-11',
      remoteId: 'remote-11',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'new',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      serverSequence: 11,
      sendState: MessageSendState.sent,
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[local],
    };
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[local],
    };
    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      newer,
    ]);
    _seedContainerConversationProjection(container, conversation, <ChatMessage>[
      local,
    ]);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    expect(
      messageSyncService.conversationAfterRequests.single.afterServerSeq,
      '10',
    );
    expect(messageSyncService.threadAfterRequests, isEmpty);
    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), ['old', 'new']);
  });

  test('thread-after 失败不会清空本地历史', () async {
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[message],
    };
    _seedContainerConversationProjection(container, conversation, <ChatMessage>[
      message,
    ]);
    messageSyncService.nextThreadAfterError = StateError('thread-after failed');

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    final thread = container.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.messages.single.content, 'hello');
  });

  test('thread patch upsert updates sent result without duplicating', () async {
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    await patchContainer
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();
    await patchContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: 'hello patch');
    await pumpEventQueue();

    expect(patchMessaging.sendConversationTextCalls, 1);
    expect(
      patchMessaging.lastSendConversation?.conversationId,
      conversation.effectiveConversationId,
    );
    expect(patchMessaging.lastClientMessageId, isNotEmpty);
    expect(
      patchContainer
          .read(chatThreadProvider(_timelineThreadId(conversation)))
          .messages,
      isEmpty,
    );

    final clientMessageId = patchMessaging.lastClientMessageId!;
    patchMessaging.emitPatch(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.upsert,
        ownerDid: 'did:me',
        version: 2,
        threadKind: 'conversation',
        threadId: conversation.effectiveConversationId,
        conversationId: conversation.effectiveConversationId,
        message: ChatMessage(
          localId: clientMessageId,
          remoteId: clientMessageId,
          conversationId: conversation.effectiveConversationId,
          threadId: conversation.threadId,
          senderDid: 'did:me',
          receiverDid: 'did:peer',
          content: 'hello patch',
          createdAt: DateTime.now(),
          isMine: true,
          sendState: MessageSendState.sending,
        ),
      ),
    );
    await pumpEventQueue();

    var messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.localId, clientMessageId);
    expect(messages.single.sendState, MessageSendState.sending);

    patchMessaging.emitPatch(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.upsert,
        ownerDid: 'did:me',
        version: 3,
        threadKind: 'conversation',
        threadId: conversation.effectiveConversationId,
        conversationId: conversation.effectiveConversationId,
        message: ChatMessage(
          localId: clientMessageId,
          remoteId: 'sent-patched',
          conversationId: conversation.effectiveConversationId,
          threadId: conversation.threadId,
          senderDid: 'did:me',
          receiverDid: 'did:peer',
          content: 'hello patch',
          createdAt: DateTime.now(),
          isMine: true,
          sendState: MessageSendState.sent,
          serverSequence: 2,
        ),
      ),
    );
    await pumpEventQueue();

    messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.remoteId, 'sent-patched');
    expect(messages.single.sendState, MessageSendState.sent);
    expect(messages.single.serverSequence, 2);
  });

  test(
    'send result settles a pending patch without waiting for final patch',
    () async {
      final patchMessaging = _PatchMessagingService(
        localHistory: <ChatMessage>[],
        emitPendingBeforeTextResult: true,
      );
      final patchContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          ...fakeApplicationServiceOverrides(gateway),
          messagingServiceProvider.overrideWithValue(patchMessaging),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:me',
                credentialName: 'me.json',
                displayName: 'Me',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(patchContainer.dispose);

      await patchContainer
          .read(chatThreadsProvider.notifier)
          .openConversation(conversation);
      await pumpEventQueue();
      final repairCallsBeforeSend = patchMessaging.repairConversationCalls;
      await patchContainer
          .read(chatThreadsProvider.notifier)
          .sendMessage(conversation: conversation, content: 'settle result');
      await pumpEventQueue();

      final messages = patchContainer
          .read(chatThreadProvider(_timelineThreadId(conversation)))
          .messages;
      expect(messages, hasLength(1));
      expect(messages.single.content, 'settle result');
      expect(messages.single.sendState, MessageSendState.sent);
      expect(patchMessaging.repairConversationCalls, repairCallsBeforeSend);
    },
  );

  test('send error settles a pending patch as failed', () async {
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
      emitPendingBeforeTextResult: true,
      textSendError: StateError('send failed'),
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    await patchContainer
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();
    final repairCallsBeforeSend = patchMessaging.repairConversationCalls;
    await patchContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: 'failed result');
    await pumpEventQueue();

    final messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.content, 'failed result');
    expect(messages.single.sendState, MessageSendState.failed);
    expect(patchMessaging.repairConversationCalls, repairCallsBeforeSend);
  });

  test('群聊回执先于本地失败 echo 到达时只展示已发送消息', () async {
    const groupDid = 'did:example:groups:xlgs';
    final groupConversation = ConversationSummary(
      conversationId: 'group:$groupDid',
      threadId: 'group:$groupDid',
      displayName: 'xlgs',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 8, 19, 49),
      unreadCount: 0,
      isGroup: true,
      groupId: groupDid,
    );
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    await patchContainer
        .read(chatThreadsProvider.notifier)
        .openConversation(groupConversation);
    await pumpEventQueue();

    final sentAt = DateTime(2026, 7, 8, 19, 49);
    patchMessaging.emitPatch(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.upsert,
        ownerDid: 'did:me',
        version: 2,
        threadKind: 'conversation',
        threadId: groupConversation.effectiveConversationId,
        conversationId: groupConversation.effectiveConversationId,
        message: ChatMessage(
          localId: '$groupDid:42',
          remoteId: '$groupDid:42',
          conversationId: groupConversation.effectiveConversationId,
          threadId: groupConversation.threadId,
          senderDid: 'did:me',
          groupId: groupDid,
          content: '后面我们在这里多发发消息',
          createdAt: sentAt,
          isMine: true,
          sendState: MessageSendState.sent,
          serverSequence: 42,
        ),
      ),
    );
    await pumpEventQueue();

    patchMessaging.emitPatch(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.upsert,
        ownerDid: 'did:me',
        version: 3,
        threadKind: 'conversation',
        threadId: groupConversation.effectiveConversationId,
        conversationId: groupConversation.effectiveConversationId,
        message: ChatMessage(
          localId: 'msg-local-timeout',
          remoteId: 'msg-local-timeout',
          conversationId: groupConversation.effectiveConversationId,
          threadId: groupConversation.threadId,
          senderDid: 'did:me',
          groupId: groupDid,
          content: '后面我们在这里多发发消息',
          createdAt: sentAt.add(const Duration(seconds: 20)),
          isMine: true,
          sendState: MessageSendState.failed,
        ),
      ),
    );
    await pumpEventQueue();

    final messages = patchContainer
        .read(chatThreadProvider(groupConversation.effectiveConversationId))
        .messages;
    expect(
      messages.where((item) => item.content == '后面我们在这里多发发消息'),
      hasLength(1),
    );
    final displayed = messages.singleWhere(
      (item) => item.content == '后面我们在这里多发发消息',
    );
    expect(displayed.localId, '$groupDid:42');
    expect(displayed.sendState, MessageSendState.sent);
    expect(displayed.serverSequence, 42);
  });

  test('可见会话摘要领先时补齐当前线程消息', () async {
    final oldMessage = ChatMessage(
      localId: 'msg-old',
      remoteId: 'msg-old',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'old visible',
      createdAt: DateTime(2026, 5, 8, 10),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 10,
    );
    final agentReply = ChatMessage(
      localId: 'msg-agent-reply',
      remoteId: 'msg-agent-reply',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'agent reply',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 11,
    );
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[oldMessage],
      repairPatch: ThreadMessagePatch(
        kind: ThreadMessagePatchKind.reset,
        ownerDid: 'did:me',
        version: 2,
        threadKind: 'conversation',
        threadId: conversation.effectiveConversationId,
        conversationId: conversation.effectiveConversationId,
        messages: _withConversationId(<ChatMessage>[
          oldMessage,
          agentReply,
        ], conversation.effectiveConversationId),
      ),
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
        ),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    final controller = patchContainer.read(chatThreadsProvider.notifier);
    await controller.openConversation(conversation);
    controller.markConversationVisible(
      conversation,
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue();

    final updatedConversation = conversation.copyWith(
      lastMessagePreview: agentReply.content,
      lastMessageAt: agentReply.createdAt,
      unreadCount: 1,
    );
    await controller.syncVisibleConversationAfterSummaryUpdate(
      updatedConversation,
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue();

    final messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), [
      'old visible',
      'agent reply',
    ]);
    expect(patchMessaging.repairConversationCalls, greaterThanOrEqualTo(1));
    expect(patchMessaging.repairCalls, 0);
    expect(messageSyncService.conversationAfterRequests, hasLength(1));
    expect(messageSyncService.threadAfterRequests, isEmpty);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      updatedConversation.effectiveConversationId,
    );
  });

  test('visible stale guard ignores repair completion after dispose', () async {
    final oldMessage = message.copyWith(
      content: 'old visible',
      createdAt: DateTime(2026, 5, 8, 10, 0),
      serverSequence: 10,
      conversationId: conversation.effectiveConversationId,
    );
    final repairCompleter = Completer<void>();
    final messagingService = FakeMessagingService(gateway)
      ..repairConversationTimelineCompleter = repairCompleter;
    _seedConversationProjection(messagingService, conversation, <ChatMessage>[
      oldMessage,
    ]);
    final staleGuardContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
          messagingService: messagingService,
        ),
        messagingServiceProvider.overrideWithValue(messagingService),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(staleGuardContainer.dispose);

    final controller = staleGuardContainer.read(chatThreadsProvider.notifier);
    await controller.openConversation(conversation);
    controller.markConversationVisible(
      conversation,
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue();

    final updatedConversation = conversation.copyWith(
      lastMessagePreview: 'new visible after dispose',
      lastMessageAt: DateTime(2026, 5, 8, 10, 5),
      unreadCount: 1,
    );
    final staleGuard = controller.syncVisibleConversationAfterSummaryUpdate(
      updatedConversation,
      displayThreadId: _timelineThreadId(conversation),
    );
    await Future<void>.delayed(Duration.zero);

    staleGuardContainer.dispose();
    repairCompleter.complete();

    await expectLater(staleGuard, completes);
  });

  test('可见会话摘要未领先当前消息时不触发补齐', () async {
    final currentMessage = ChatMessage(
      localId: 'msg-current',
      remoteId: 'msg-current',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'current',
      createdAt: DateTime(2026, 5, 8, 10, 5),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 12,
    );
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[currentMessage],
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
        ),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    final controller = patchContainer.read(chatThreadsProvider.notifier);
    await controller.openConversation(conversation);
    controller.markConversationVisible(
      conversation,
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue();
    final threadAfterCallsAfterOpen =
        messageSyncService.threadAfterRequests.length;

    await controller.syncVisibleConversationAfterSummaryUpdate(
      conversation.copyWith(
        lastMessagePreview: 'same or older',
        lastMessageAt: DateTime(2026, 5, 8, 10, 4),
        unreadCount: 1,
      ),
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue();

    expect(patchMessaging.repairCalls, 0);
    expect(
      messageSyncService.threadAfterRequests,
      hasLength(threadAfterCallsAfterOpen),
    );
  });

  test('打开会话会先用最新消息快照预热并通过 thread-after 补齐多条消息', () async {
    final firstReply = ChatMessage(
      localId: 'msg-first-reply',
      remoteId: 'msg-first-reply',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'first reply',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 11,
    );
    final latestReply = ChatMessage(
      localId: 'msg-latest-reply',
      remoteId: 'msg-latest-reply',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'latest reply',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 12,
    );
    final localSeed = message.copyWith(serverSequence: 10);
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[localSeed],
    );
    _connectConversationProjectionPersistence(
      messageSyncService,
      patchMessaging,
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
        ),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    final snapshotConversation = conversation.copyWith(
      lastMessagePreview: latestReply.content,
      lastMessageAt: latestReply.createdAt,
      unreadCount: 2,
      lastMessageSnapshot: latestReply,
    );
    _seedConversationAfter(
      messageSyncService,
      snapshotConversation,
      <ChatMessage>[firstReply, latestReply],
    );

    final controller = patchContainer.read(chatThreadsProvider.notifier);
    await controller.openConversation(snapshotConversation);

    final immediateMessages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(immediateMessages.map((item) => item.remoteId), ['msg-1']);

    await pumpEventQueue(times: 3);

    final messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.remoteId), [
      'msg-1',
      'msg-first-reply',
      'msg-latest-reply',
    ]);
    expect(
      messages.where((item) => item.remoteId == 'msg-latest-reply'),
      hasLength(1),
    );
  });

  test('peer-scoped 会话打开时忽略其他 storage thread 的最新快照', () async {
    const agentDid = 'did:agent:runtime:zhuochengtestcodex0703';
    const agentHandle = 'zhuochengtestcodex0703.awiki.ai';
    final controllerConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:controller',
      displayName: 'zhuocheng',
      lastMessagePreview: '今天几号了',
      lastMessageAt: DateTime(2026, 7, 3, 7, 9),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
      lastMessageSnapshot: ChatMessage(
        localId: 'runtime-weather-reply',
        remoteId: 'runtime-weather-reply',
        threadId: 'dm:peer-scope:v1:runtime',
        senderDid: agentDid,
        receiverDid: 'did:me',
        content: '杭州明天 **2026年7月4日，星期六** 天气整体偏热',
        createdAt: DateTime(2026, 7, 3, 8, 51),
        isMine: false,
        serverSequence: 2899,
        sendState: MessageSendState.sent,
      ),
    );
    gateway.localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    gateway.dmHistoryByPeerDid = const <String, List<ChatMessage>>{};

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(controllerConversation);
    await pumpEventQueue(times: 3);

    final messages = container
        .read(chatThreadProvider(controllerConversation.threadId))
        .messages;
    expect(
      messages.map((message) => message.content),
      isNot(contains('杭州明天 **2026年7月4日，星期六** 天气整体偏热')),
    );
  });

  test('可见会话摘要带最新消息快照时先合并快照再用补齐兜底', () async {
    final middleReply = ChatMessage(
      localId: 'msg-visible-middle',
      remoteId: 'msg-visible-middle',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'visible middle reply',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 12,
    );
    final latestReply = ChatMessage(
      localId: 'msg-visible-snapshot',
      remoteId: 'msg-visible-snapshot',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'visible snapshot reply',
      createdAt: DateTime(2026, 5, 8, 10, 3),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 13,
    );
    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      middleReply,
      latestReply,
    ]);
    final patchMessaging = _PatchMessagingService(
      localHistory: const <ChatMessage>[],
    );
    _connectConversationProjectionPersistence(
      messageSyncService,
      patchMessaging,
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
        ),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    final controller = patchContainer.read(chatThreadsProvider.notifier);
    controller.markConversationVisible(
      conversation,
      displayThreadId: _timelineThreadId(conversation),
    );
    await controller.syncVisibleConversationAfterSummaryUpdate(
      conversation.copyWith(
        lastMessagePreview: latestReply.content,
        lastMessageAt: latestReply.createdAt,
        unreadCount: 1,
        lastMessageSnapshot: latestReply,
      ),
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue();

    final messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.remoteId), [
      'msg-visible-middle',
      'msg-visible-snapshot',
    ]);
    expect(patchMessaging.repairConversationCalls, greaterThanOrEqualTo(1));
    expect(patchMessaging.repairCalls, 0);
    expect(messageSyncService.conversationAfterRequests, hasLength(1));
    expect(messageSyncService.threadAfterRequests, isEmpty);
    expect(
      messageSyncService.conversationAfterRequests.single.afterServerSeq,
      isNull,
    );
  });

  test('可见会话摘要只带最新快照时仍按原水位补齐中间多条消息', () async {
    final oldMessage = ChatMessage(
      localId: 'msg-old-visible',
      remoteId: 'msg-old-visible',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'old visible',
      createdAt: DateTime(2026, 5, 8, 10),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 10,
    );
    final middleReply = ChatMessage(
      localId: 'msg-middle-visible',
      remoteId: 'msg-middle-visible',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'middle visible',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 11,
    );
    final latestReply = ChatMessage(
      localId: 'msg-latest-visible',
      remoteId: 'msg-latest-visible',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'latest visible',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 12,
    );
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[oldMessage],
      repairPatch: ThreadMessagePatch(
        kind: ThreadMessagePatchKind.reset,
        ownerDid: 'did:me',
        version: 2,
        threadKind: 'conversation',
        threadId: conversation.effectiveConversationId,
        conversationId: conversation.effectiveConversationId,
        messages: _withConversationId(<ChatMessage>[
          oldMessage,
        ], conversation.effectiveConversationId),
      ),
    );
    _seedPatchConversationProjection(
      patchMessaging,
      conversation,
      <ChatMessage>[oldMessage, middleReply, latestReply],
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
        ),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    final controller = patchContainer.read(chatThreadsProvider.notifier);
    await controller.openConversation(conversation);
    controller.markConversationVisible(
      conversation,
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue();

    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      oldMessage,
      middleReply,
      latestReply,
    ]);
    await controller.syncVisibleConversationAfterSummaryUpdate(
      conversation.copyWith(
        lastMessagePreview: latestReply.content,
        lastMessageAt: latestReply.createdAt,
        unreadCount: 2,
        lastMessageSnapshot: latestReply,
      ),
      displayThreadId: _timelineThreadId(conversation),
    );
    await pumpEventQueue(times: 3);

    final messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.remoteId), [
      'msg-old-visible',
      'msg-middle-visible',
      'msg-latest-visible',
    ]);
    expect(
      messageSyncService.conversationAfterRequests.last.afterServerSeq,
      '12',
    );
    expect(messageSyncService.threadAfterRequests, isEmpty);
  });

  test(
    'thread patch low fidelity upsert does not downgrade existing attachment semantics',
    () async {
      const mention = ChatMessageMention(
        id: 'men_patch_agent',
        surface: '@codex',
        start: 0,
        end: 6,
        target: ChatMentionTargetDraft.member(
          kind: ChatMentionTargetKind.agent,
          did: 'did:agent:codex',
          handle: 'codex',
          displayName: 'CodeX',
        ),
      );
      final mentionPayload = ChatMentionPayload.toP9Json(
        text: '@codex 看看这个文件',
        draftMentions: const <ChatMentionDraft>[
          ChatMentionDraft(
            localId: 'men_patch_agent',
            surface: '@codex',
            start: 0,
            end: 6,
            target: ChatMentionTargetDraft.member(
              kind: ChatMentionTargetKind.agent,
              did: 'did:agent:codex',
              handle: 'codex',
              displayName: 'CodeX',
            ),
          ),
        ],
      );
      final existingAttachment = ChatMessage(
        localId: 'sent-patched-attachment',
        remoteId: 'sent-patched-attachment',
        threadId: conversation.threadId,
        senderDid: 'did:me',
        receiverDid: 'did:peer',
        content: '@codex 看看这个文件',
        originalType: 'application/anp-attachment-manifest+json',
        createdAt: DateTime(2026, 5, 8, 10),
        isMine: true,
        sendState: MessageSendState.sent,
        attachment: const ChatAttachment(
          attachmentId: 'att-patch',
          filename: 'patch-report.md',
          mimeType: 'text/markdown',
          caption: '@codex 看看这个文件',
          localPath: '/tmp/patch-report.md',
          hasLocalSource: true,
        ),
        payloadJson: jsonEncode(mentionPayload),
        mentions: const <ChatMessageMention>[mention],
      );
      final patchMessaging = _PatchMessagingService(
        localHistory: <ChatMessage>[existingAttachment],
      );
      final patchContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          ...fakeApplicationServiceOverrides(gateway),
          messagingServiceProvider.overrideWithValue(patchMessaging),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:me',
                credentialName: 'me.json',
                displayName: 'Me',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(patchContainer.dispose);

      await patchContainer
          .read(chatThreadsProvider.notifier)
          .openConversation(conversation);
      await pumpEventQueue();

      patchMessaging.emitPatch(
        ThreadMessagePatch(
          kind: ThreadMessagePatchKind.upsert,
          ownerDid: 'did:me',
          version: 2,
          threadKind: 'conversation',
          threadId: conversation.effectiveConversationId,
          conversationId: conversation.effectiveConversationId,
          message: ChatMessage(
            localId: 'sent-patched-attachment',
            remoteId: 'sent-patched-attachment',
            conversationId: conversation.effectiveConversationId,
            threadId: _timelineThreadId(conversation),
            senderDid: 'did:me',
            receiverDid: 'did:peer',
            content: '@codex 看看这个文件',
            createdAt: DateTime(2026, 5, 8, 10, 0, 1),
            isMine: true,
            sendState: MessageSendState.sent,
            serverSequence: 3,
          ),
        ),
      );
      await pumpEventQueue();

      final messages = patchContainer
          .read(chatThreadProvider(_timelineThreadId(conversation)))
          .messages;
      expect(messages, hasLength(1));
      final message = messages.single;
      expect(message.serverSequence, 3);
      expect(message.originalType, 'application/anp-attachment-manifest+json');
      expect(message.attachment?.filename, 'patch-report.md');
      expect(message.attachment?.localPath, '/tmp/patch-report.md');
      expect(message.mentions, hasLength(1));
      expect(message.payloadJson, isNotNull);
    },
  );

  test('thread patch ignores mismatched thread', () async {
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[message],
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    await patchContainer
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    patchMessaging.emitPatch(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.upsert,
        ownerDid: 'did:me',
        version: 2,
        threadKind: 'conversation',
        threadId: 'dm:did:other',
        conversationId: 'dm:did:other',
        message: ChatMessage(
          localId: 'wrong-thread',
          remoteId: 'wrong-thread',
          conversationId: 'dm:did:other',
          threadId: 'dm:did:me:did:other',
          senderDid: 'did:other',
          receiverDid: 'did:me',
          content: 'wrong thread',
          createdAt: DateTime(2026, 5, 8, 10, 3),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ),
    );
    await pumpEventQueue();

    final messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.content, 'hello');
  });

  test('thread patch version gap repairs from store snapshot', () async {
    final repaired = ChatMessage(
      localId: 'repaired-1',
      remoteId: 'repaired-1',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'repaired',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
      repairPatch: ThreadMessagePatch(
        kind: ThreadMessagePatchKind.reset,
        ownerDid: 'did:me',
        version: 3,
        threadKind: 'conversation',
        threadId: conversation.effectiveConversationId,
        conversationId: conversation.effectiveConversationId,
        messages: _withConversationId(<ChatMessage>[
          repaired,
        ], conversation.effectiveConversationId),
      ),
    );
    final patchContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(patchContainer.dispose);

    await patchContainer
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();
    patchMessaging.emitPatch(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.upsert,
        ownerDid: 'did:me',
        version: 5,
        threadKind: 'conversation',
        threadId: conversation.effectiveConversationId,
        conversationId: conversation.effectiveConversationId,
        message: repaired.copyWith(
          conversationId: conversation.effectiveConversationId,
        ),
      ),
    );
    await pumpEventQueue();

    expect(patchMessaging.repairConversationCalls, greaterThanOrEqualTo(1));
    expect(patchMessaging.lastRepairConversationLimit, 100);
    expect(patchMessaging.repairCalls, 0);
    final messages = patchContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), contains('repaired'));
  });

  test(
    'thread patch stream done repairs from store and resubscribes without full history',
    () async {
      final repaired = ChatMessage(
        localId: 'stream-repair-1',
        remoteId: 'stream-repair-1',
        threadId: conversation.threadId,
        senderDid: 'did:peer',
        receiverDid: 'did:me',
        content: 'stream repaired message',
        createdAt: DateTime(2026, 5, 8, 10, 2),
        isMine: false,
        sendState: MessageSendState.sent,
        serverSequence: 2,
      );
      final patchMessaging = _PatchMessagingService(
        localHistory: <ChatMessage>[],
        repairPatch: ThreadMessagePatch(
          kind: ThreadMessagePatchKind.reset,
          ownerDid: 'did:me',
          version: 2,
          threadKind: 'conversation',
          threadId: conversation.effectiveConversationId,
          conversationId: conversation.effectiveConversationId,
          messages: _withConversationId(<ChatMessage>[
            repaired,
          ], conversation.effectiveConversationId),
        ),
      );
      gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[
          repaired.copyWith(content: '不应该走 full history'),
        ],
      };
      final patchContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          ...fakeApplicationServiceOverrides(
            gateway,
            messageSyncService: messageSyncService,
          ),
          messagingServiceProvider.overrideWithValue(patchMessaging),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:me',
                credentialName: 'me.json',
                displayName: 'Me',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(patchContainer.dispose);

      patchContainer
          .read(chatThreadsProvider.notifier)
          .markConversationVisible(conversation);
      await pumpEventQueue();
      expect(patchMessaging.watchConversationCalls, 1);
      expect(patchMessaging.watchCalls, 0);

      await patchMessaging.closePatches();
      await pumpEventQueue();

      final messages = patchContainer
          .read(chatThreadProvider(_timelineThreadId(conversation)))
          .messages;
      expect(patchMessaging.repairConversationCalls, 1);
      expect(patchMessaging.repairCalls, 0);
      expect(patchMessaging.watchConversationCalls, 2);
      expect(patchMessaging.watchCalls, 0);
      expect(gateway.fetchDmHistoryCalls, 0);
      expect(messageSyncService.threadAfterRequests, isEmpty);
      expect(
        messages.map((item) => item.content),
        contains('stream repaired message'),
      );
      expect(
        messages.map((item) => item.content),
        isNot(contains('不应该走 full history')),
      );
    },
  );

  test('未读摘要不会单独触发 history load', () async {
    final local = ChatMessage(
      localId: 'local-visible',
      remoteId: 'local-visible',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'local visible message',
      createdAt: conversation.lastMessageAt,
      isMine: false,
      sendState: MessageSendState.sent,
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          local.copyWith(conversationId: conversation.effectiveConversationId),
          threadId: _timelineThreadId(conversation),
        );

    await container
        .read(chatThreadsProvider.notifier)
        .syncHistoryForConversation(conversation.copyWith(unreadCount: 3));
    await pumpEventQueue();

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(
      messages.map((item) => item.content),
      contains('local visible message'),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test(
    'hidden conversation cancels patch subscription after TTL and reopen restores',
    () async {
      final patchMessaging = _PatchMessagingService(
        localHistory: <ChatMessage>[message],
      );
      final patchContainer = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          notificationFacadeProvider.overrideWithValue(notificationFacade),
          ...fakeApplicationServiceOverrides(gateway),
          messagingServiceProvider.overrideWithValue(patchMessaging),
          chatThreadsProvider.overrideWith(
            (ref) => ChatThreadsController(
              ref,
              cachePolicy: const ThreadMemoryCachePolicy(
                warmSubscriptionTtl: Duration(milliseconds: 20),
              ),
            ),
          ),
          sessionProvider.overrideWith((ref) {
            final controller = SessionController();
            controller.setSession(
              const SessionIdentity(
                did: 'did:me',
                credentialName: 'me.json',
                displayName: 'Me',
              ),
            );
            return controller;
          }),
        ],
      );
      addTearDown(patchContainer.dispose);

      final controller = patchContainer.read(chatThreadsProvider.notifier);
      controller.markConversationVisible(conversation);
      await pumpEventQueue();
      expect(patchMessaging.watchConversationCalls, 1);
      expect(patchMessaging.watchCalls, 0);

      controller.markConversationHidden(conversation);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(patchMessaging.cancelledWatches, 1);

      controller.markConversationVisible(conversation);
      await pumpEventQueue();
      expect(patchMessaging.watchConversationCalls, 2);
      expect(patchMessaging.watchCalls, 0);
      expect(
        patchContainer
            .read(chatThreadProvider(_timelineThreadId(conversation)))
            .messages
            .map((item) => item.content),
        contains('hello'),
      );
    },
  );

  test('core timeline 命中时失败的 legacy 远端 history 不会被触发', () async {
    gateway
      ..failNextFetchDmHistory = true
      ..localDmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[message],
      };

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    final thread = container.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.messages, hasLength(1));
    expect(thread.messages.single.content, 'hello');
    expect(thread.isLoading, isFalse);
  });

  test('peer-scope 会话本地历史按精确 storage thread 读取且不触发远端 history', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    final agentConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:zhuocheng-test-hermes',
      displayName: 'Hermes',
      lastMessagePreview: '我在',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final outgoing = ChatMessage(
      localId: 'msg-user',
      remoteId: 'msg-user',
      threadId: agentConversation.threadId,
      senderDid: 'did:human',
      receiverDid: agentDid,
      content: '在吗',
      createdAt: DateTime(2026, 5, 8, 10),
      isMine: true,
      sendState: MessageSendState.sent,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      agentDid: <ChatMessage>[outgoing],
      agentHandle: const <ChatMessage>[],
    };
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      agentDid: const <ChatMessage>[],
      agentHandle: const <ChatMessage>[],
      'peer-scope:v1:zhuocheng-test-hermes': <ChatMessage>[outgoing],
    };
    gateway.publicProfilesByQuery[agentHandle] = const UserProfile(
      did: agentDid,
      displayName: 'Hermes',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: agentHandle,
      fullHandle: agentHandle,
      subjectType: 'agent',
    );

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(agentConversation);
    await pumpEventQueue();

    expect(
      gateway.lastFetchedLocalDmPeerDid,
      'peer-scope:v1:zhuocheng-test-hermes',
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(gateway.lastFetchedDmPeerDid, isNull);
    final thread = container.read(
      chatThreadProvider(agentConversation.threadId),
    );
    expect(thread.messages.map((item) => item.content), contains('在吗'));
  });

  test('peer-scope 本地历史和增量同步使用同一个精确 storage thread', () async {
    final canonicalConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:codex1',
      displayName: 'Codex1',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 6, 30, 8, 58),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:codex:runtime',
      targetPeer: 'codex1.awiki.info',
    );
    final localMessage = ChatMessage(
      localId: 'local-canonical-1',
      remoteId: 'remote-canonical-1',
      threadId: canonicalConversation.threadId,
      senderDid: 'did:codex:runtime',
      receiverDid: 'did:me',
      content: 'canonical local',
      createdAt: canonicalConversation.lastMessageAt,
      isMine: false,
      serverSequence: 16828,
      sendState: MessageSendState.sent,
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'peer-scope:v1:codex1': <ChatMessage>[localMessage],
      'codex1.awiki.info': const <ChatMessage>[],
      'did:codex:runtime': const <ChatMessage>[],
    };
    _seedContainerConversationProjection(
      container,
      canonicalConversation,
      <ChatMessage>[localMessage],
    );

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(canonicalConversation);
    await pumpEventQueue();

    final messaging =
        container.read(messagingServiceProvider) as FakeMessagingService;
    expect(messaging.conversationTimelineCalls, greaterThanOrEqualTo(1));
    expect(
      messaging.lastConversationTimelineId,
      canonicalConversation.effectiveConversationId,
    );
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messageSyncService.conversationAfterRequests, hasLength(1));
    expect(
      messageSyncService
          .conversationAfterRequests
          .single
          .conversation
          .conversationId,
      canonicalConversation.effectiveConversationId,
    );
    expect(
      messageSyncService.conversationAfterRequests.single.afterServerSeq,
      '16828',
    );
    expect(messageSyncService.threadAfterRequests, isEmpty);
    expect(
      container
          .read(chatThreadProvider(_timelineThreadId(canonicalConversation)))
          .messages
          .map((item) => item.content),
      ['canonical local'],
    );
  });

  test(
    'peer-scope projection 为空时走 conversation-after 而不回退远端 thread history',
    () async {
      final canonicalConversation = ConversationSummary(
        threadId: 'dm:peer-scope:v1:codex-empty',
        displayName: 'Codex Empty',
        lastMessagePreview: 'waiting',
        lastMessageAt: DateTime(2026, 7, 4, 22, 55),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:codex:runtime-empty',
        targetPeer: 'codex-empty.awiki.info',
      );
      gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:codex:runtime-empty': <ChatMessage>[
          ChatMessage(
            localId: 'remote-should-not-load',
            remoteId: 'remote-should-not-load',
            threadId: canonicalConversation.threadId,
            senderDid: 'did:codex:runtime-empty',
            receiverDid: 'did:me',
            content: 'should not call remote thread history',
            createdAt: canonicalConversation.lastMessageAt,
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        ],
      };
      _seedContainerConversationProjection(
        container,
        canonicalConversation,
        const <ChatMessage>[],
      );

      await container
          .read(chatThreadsProvider.notifier)
          .openConversation(canonicalConversation);
      await pumpEventQueue();

      final messaging =
          container.read(messagingServiceProvider) as FakeMessagingService;
      expect(messaging.conversationTimelineCalls, greaterThanOrEqualTo(1));
      expect(
        messaging.lastConversationTimelineId,
        canonicalConversation.effectiveConversationId,
      );
      expect(gateway.fetchLocalDmHistoryCalls, 0);
      expect(gateway.fetchDmHistoryCalls, 0);
      expect(messageSyncService.conversationAfterRequests, hasLength(1));
      expect(
        messageSyncService
            .conversationAfterRequests
            .single
            .conversation
            .conversationId,
        canonicalConversation.effectiveConversationId,
      );
      expect(messageSyncService.threadAfterRequests, isEmpty);
      expect(
        container
            .read(chatThreadProvider(_timelineThreadId(canonicalConversation)))
            .messages,
        isEmpty,
      );
      expect(container.read(uiFeedbackProvider), isNull);
    },
  );

  test('peer-scope 强制同步时跳过未支持的远端 thread history', () async {
    final canonicalConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:codex-force',
      displayName: 'Codex Force',
      lastMessagePreview: 'newer summary',
      lastMessageAt: DateTime(2026, 7, 4, 23, 1),
      unreadCount: 1,
      isGroup: false,
      targetDid: 'did:codex:runtime-force',
      targetPeer: 'codex-force.awiki.info',
    );

    await container
        .read(chatThreadsProvider.notifier)
        .syncHistoryForConversation(
          canonicalConversation,
          force: true,
          reportFailure: true,
        );
    await pumpEventQueue();

    expect(gateway.fetchDmHistoryCalls, 0);
    expect(container.read(uiFeedbackProvider), isNull);
  });

  test('peer-scope 会话打开时保留同一 storage thread 的完整本地历史', () async {
    final canonicalConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:codex1',
      displayName: 'Codex1',
      lastMessagePreview: 'latest reply',
      lastMessageAt: DateTime(2026, 7, 3, 19, 26),
      unreadCount: 1,
      isGroup: false,
      targetDid: 'did:codex:runtime',
      targetPeer: 'codex1.awiki.info',
    );
    ChatMessage message({
      required String id,
      required String content,
      required DateTime at,
      required bool isMine,
      int? seq,
    }) {
      return ChatMessage(
        localId: id,
        remoteId: id,
        threadId: canonicalConversation.threadId,
        senderDid: isMine ? 'did:me' : 'did:codex:runtime',
        receiverDid: isMine ? 'did:codex:runtime' : 'did:me',
        content: content,
        createdAt: at,
        isMine: isMine,
        serverSequence: seq,
        sendState: MessageSendState.sent,
      );
    }

    final projectedMessages = <ChatMessage>[
      message(
        id: 'q-1',
        content: 'first question',
        at: DateTime(2026, 7, 3, 18, 53),
        isMine: true,
        seq: 3109,
      ),
      message(
        id: 'a-1',
        content: 'first answer',
        at: DateTime(2026, 7, 3, 18, 53, 16),
        isMine: false,
        seq: 3111,
      ),
      message(
        id: 'q-2',
        content: 'latest question',
        at: DateTime(2026, 7, 3, 19, 26, 11),
        isMine: true,
        seq: 3130,
      ),
      message(
        id: 'a-2',
        content: 'latest reply',
        at: DateTime(2026, 7, 3, 19, 26, 18),
        isMine: false,
        seq: 3132,
      ),
    ];
    _seedContainerConversationProjection(
      container,
      canonicalConversation,
      projectedMessages,
    );

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(canonicalConversation);
    await pumpEventQueue();

    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .lastConversationTimelineId,
      canonicalConversation.effectiveConversationId,
    );
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(
      container
          .read(chatThreadProvider(_timelineThreadId(canonicalConversation)))
          .messages
          .map((item) => item.content),
      <String>[
        'first question',
        'first answer',
        'latest question',
        'latest reply',
      ],
    );
  });

  test('已加载线程再次打开不重复拉历史', () async {
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);

    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(
      messageSyncService.conversationAfterRequests.length,
      greaterThanOrEqualTo(2),
    );
    expect(messageSyncService.threadAfterRequests, isEmpty);
    expect(gateway.listConversationsCalls, greaterThanOrEqualTo(1));
  });

  test('peer-scoped realtime cache does not prewarm handle alias', () async {
    final aliasConversation = conversation.copyWith(
      threadId: 'direct-handle:peer.awiki.info',
      targetPeer: 'peer.awiki.info',
    );
    final realtimeMessage = ChatMessage(
      localId: 'rt-alias-1',
      remoteId: 'rt-alias-1',
      threadId: 'dm:peer-scope:v1:peer',
      senderDid: 'did:peer',
      content: 'realtime alias hello',
      createdAt: message.createdAt,
      isMine: false,
      sendState: MessageSendState.sent,
      receiverDid: 'did:me',
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(realtimeMessage);
    gateway.localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    gateway.dmHistoryByPeerDid = const <String, List<ChatMessage>>{};

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(aliasConversation);
    await pumpEventQueue();

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(aliasConversation)))
        .messages;
    expect(
      messages.map((item) => item.content),
      isNot(contains('realtime alias hello')),
    );
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messageSyncService.conversationAfterRequests, isNotEmpty);
    expect(messageSyncService.threadAfterRequests, isEmpty);
  });

  test('本地和增量都没有消息时不会在 timeline 仍需补拉前上报已读', () async {
    final unreadConversation = conversation.copyWith(
      lastMessageAt: DateTime(2026, 5, 8, 10, 5),
      unreadCount: 2,
    );
    gateway.localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    gateway.dmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    gateway.conversations = <ConversationSummary>[unreadConversation];
    _seedContainerConversationProjection(
      container,
      unreadConversation,
      const <ChatMessage>[],
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(unreadConversation);
    await pumpEventQueue();

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    if (conversations.isNotEmpty) {
      expect(
        conversations
            .singleWhere(
              (item) =>
                  item.effectiveConversationId ==
                  unreadConversation.effectiveConversationId,
            )
            .unreadCount,
        2,
      );
    }
    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messageSyncService.conversationAfterRequests, isNotEmpty);
    expect(messageSyncService.threadAfterRequests, isEmpty);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 0);
    expect(gateway.lastMarkConversationReadWatermark, isNull);
  });

  test('conversation-after 回补出消息后按 conversationId 上报已读', () async {
    final unreadConversation = conversation.copyWith(
      lastMessageAt: DateTime(2026, 5, 8, 10, 5),
      unreadCount: 2,
    );
    final synced = ChatMessage(
      localId: 'remote-22',
      remoteId: 'remote-22',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'synced before read ack',
      createdAt: unreadConversation.lastMessageAt,
      isMine: false,
      serverSequence: 22,
      sendState: MessageSendState.sent,
    );
    gateway.localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    gateway.dmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    _seedConversationAfter(
      messageSyncService,
      unreadConversation,
      <ChatMessage>[synced],
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(unreadConversation);
    await pumpEventQueue();

    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      unreadConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'remote-22',
      sequence: '22',
    );
  });

  test('可见会话收到未读 summary 更新时按 conversationId 补 ACK', () async {
    final visibleMessage = ChatMessage(
      localId: 'remote-visible-summary',
      remoteId: 'remote-visible-summary',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'visible summary unread',
      createdAt: DateTime(2026, 5, 8, 10, 6),
      isMine: false,
      serverSequence: 31,
      sendState: MessageSendState.sent,
    );
    final unreadConversation = conversation.copyWith(
      lastMessagePreview: visibleMessage.content,
      lastMessageAt: visibleMessage.createdAt,
      unreadCount: 1,
      lastMessageSnapshot: visibleMessage,
    );
    final controller = container.read(chatThreadsProvider.notifier);
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);
    controller.debugSeedMessageForTesting(
      visibleMessage.copyWith(
        conversationId: unreadConversation.effectiveConversationId,
      ),
      threadId: _timelineThreadId(unreadConversation),
    );
    controller.markConversationVisible(
      unreadConversation,
      displayThreadId: _timelineThreadId(unreadConversation),
    );

    await controller.syncVisibleConversationAfterSummaryUpdate(
      unreadConversation,
      displayThreadId: _timelineThreadId(unreadConversation),
    );
    await pumpEventQueue();

    final updated = container
        .read(conversationListProvider)
        .conversations
        .singleWhere(
          (item) =>
              item.effectiveConversationId ==
              unreadConversation.effectiveConversationId,
        );
    expect(updated.unreadCount, 0);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      unreadConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'remote-visible-summary',
      sequence: '31',
    );
  });

  test('可见会话收到未读 summary 更新时列表不闪现未读', () async {
    final initial = conversation.copyWith(
      lastMessagePreview: 'old visible',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
    );
    final visibleMessage = ChatMessage(
      localId: 'remote-visible-no-flicker',
      remoteId: 'remote-visible-no-flicker',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'visible summary unread no flicker',
      createdAt: DateTime(2026, 5, 8, 10, 6),
      isMine: false,
      serverSequence: 31,
      sendState: MessageSendState.sent,
    );
    final unreadUpdate = initial.copyWith(
      lastMessagePreview: visibleMessage.content,
      lastMessageAt: visibleMessage.createdAt,
      unreadCount: 1,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: visibleMessage.remoteId,
      lastMessageSnapshot: visibleMessage,
    );
    final controller = container.read(chatThreadsProvider.notifier);
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(initial);
    controller.markConversationVisible(
      initial,
      displayThreadId: _timelineThreadId(initial),
    );
    controller.debugSeedMessageForTesting(
      visibleMessage.copyWith(conversationId: initial.effectiveConversationId),
      threadId: _timelineThreadId(initial),
    );
    final unreadEmissions = <int>[];
    final subscription = container.listen<ConversationListState>(
      conversationListProvider,
      (_, next) => unreadEmissions.add(next.conversations.single.unreadCount),
    );
    addTearDown(subscription.close);

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadUpdate);
    final published = container
        .read(conversationListProvider)
        .conversations
        .single;
    await controller.syncVisibleConversationAfterSummaryUpdate(
      published,
      displayThreadId: _timelineThreadId(initial),
    );
    await pumpEventQueue();

    final updated = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(updated.unreadCount, 0);
    expect(updated.unreadMentionCount, 0);
    expect(updated.firstUnreadMentionMessageId, isNull);
    expect(unreadEmissions, isNot(contains(1)));
    expect(notificationFacade.lastBadgeCount, 0);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      initial.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'remote-visible-no-flicker',
      sequence: '31',
    );
  });

  test('后台可见会话收到未读 summary 更新时不会自动标为已读', () async {
    final initial = conversation.copyWith(
      lastMessagePreview: 'old visible',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
    );
    final visibleMessage = ChatMessage(
      localId: 'remote-background-summary',
      remoteId: 'remote-background-summary',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'background summary unread',
      createdAt: DateTime(2026, 5, 8, 10, 6),
      isMine: false,
      serverSequence: 33,
      sendState: MessageSendState.sent,
    );
    final unreadUpdate = initial.copyWith(
      lastMessagePreview: visibleMessage.content,
      lastMessageAt: visibleMessage.createdAt,
      unreadCount: 1,
      lastMessageSnapshot: visibleMessage,
    );
    final controller = container.read(chatThreadsProvider.notifier);
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(initial);
    controller.markConversationVisible(
      initial,
      displayThreadId: _timelineThreadId(initial),
    );
    container
        .read(appLifecycleProvider.notifier)
        .setLifecycle(AppLifecycleState.inactive);

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadUpdate);
    controller.debugSeedMessageForTesting(
      visibleMessage.copyWith(conversationId: initial.effectiveConversationId),
      threadId: _timelineThreadId(initial),
    );
    final published = container
        .read(conversationListProvider)
        .conversations
        .single;
    await controller.syncVisibleConversationAfterSummaryUpdate(
      published,
      displayThreadId: _timelineThreadId(initial),
    );
    await pumpEventQueue();

    final updated = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(updated.unreadCount, 1);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 0);
  });

  test('后台收到的当前会话未读消息在回到前台后才标为已读', () async {
    final initial = conversation.copyWith(
      lastMessagePreview: 'old visible',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
    );
    final visibleMessage = ChatMessage(
      localId: 'remote-resumed-summary',
      remoteId: 'remote-resumed-summary',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'resumed summary unread',
      createdAt: DateTime(2026, 5, 8, 10, 6),
      isMine: false,
      serverSequence: 34,
      sendState: MessageSendState.sent,
    );
    final unreadUpdate = initial.copyWith(
      lastMessagePreview: visibleMessage.content,
      lastMessageAt: visibleMessage.createdAt,
      unreadCount: 1,
      lastMessageSnapshot: visibleMessage,
    );
    final controller = container.read(chatThreadsProvider.notifier);
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(initial);
    controller.markConversationVisible(
      initial,
      displayThreadId: _timelineThreadId(initial),
    );
    container
        .read(appLifecycleProvider.notifier)
        .setLifecycle(AppLifecycleState.inactive);
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadUpdate);
    controller.debugSeedMessageForTesting(
      visibleMessage.copyWith(conversationId: initial.effectiveConversationId),
      threadId: _timelineThreadId(initial),
    );
    final published = container
        .read(conversationListProvider)
        .conversations
        .single;
    await controller.syncVisibleConversationAfterSummaryUpdate(
      published,
      displayThreadId: _timelineThreadId(initial),
    );
    await pumpEventQueue();

    expect(
      container.read(conversationListProvider).conversations.single.unreadCount,
      1,
    );
    expect(gateway.markConversationReadCalls, 0);

    container
        .read(appLifecycleProvider.notifier)
        .setLifecycle(AppLifecycleState.resumed);
    await pumpEventQueue();

    final updated = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(updated.unreadCount, 0);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      initial.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'remote-resumed-summary',
      sequence: '34',
    );
  });

  test('重复打开当前可见未读会话时按 conversationId 补 ACK', () async {
    final visibleMessage = ChatMessage(
      localId: 'remote-visible-open',
      remoteId: 'remote-visible-open',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'visible open unread',
      createdAt: DateTime(2026, 5, 8, 10, 7),
      isMine: false,
      serverSequence: 32,
      sendState: MessageSendState.sent,
    );
    final unreadConversation = conversation.copyWith(
      lastMessagePreview: visibleMessage.content,
      lastMessageAt: visibleMessage.createdAt,
      unreadCount: 1,
      lastMessageSnapshot: visibleMessage,
    );
    final controller = container.read(chatThreadsProvider.notifier);
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);
    controller.debugSeedMessageForTesting(
      visibleMessage.copyWith(
        conversationId: unreadConversation.effectiveConversationId,
      ),
      threadId: _timelineThreadId(unreadConversation),
    );
    controller.markConversationVisible(
      unreadConversation,
      displayThreadId: _timelineThreadId(unreadConversation),
    );

    await controller.openConversation(
      unreadConversation,
      displayThreadId: _timelineThreadId(unreadConversation),
    );
    await pumpEventQueue();

    final updated = container
        .read(conversationListProvider)
        .conversations
        .singleWhere(
          (item) =>
              item.effectiveConversationId ==
              unreadConversation.effectiveConversationId,
        );
    expect(updated.unreadCount, 0);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      unreadConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'remote-visible-open',
      sequence: '32',
    );
  });

  test('延迟的已读 ack 不会把 ack 后进入的 agent 回复清为已读', () async {
    final oldUnread = ChatMessage(
      localId: 'remote-10',
      remoteId: 'remote-10',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'old unread',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      serverSequence: 10,
      sendState: MessageSendState.sent,
    );
    final unreadConversation = conversation.copyWith(
      lastMessagePreview: oldUnread.content,
      lastMessageAt: oldUnread.createdAt,
      unreadCount: 1,
      lastMessageSnapshot: oldUnread,
    );
    final laterAgentReply = ChatMessage(
      localId: 'remote-11',
      remoteId: 'remote-11',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'new agent reply',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      serverSequence: 11,
      sendState: MessageSendState.sent,
    );
    gateway
      ..fetchLocalDmHistoryCompleter = Completer<void>()
      ..localDmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[oldUnread],
      };
    _seedContainerConversationProjection(
      container,
      unreadConversation,
      <ChatMessage>[oldUnread],
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);

    final controller = container.read(chatThreadsProvider.notifier);

    await controller.openConversation(unreadConversation);
    await Future<void>.delayed(Duration.zero);
    controller.markConversationVisible(unreadConversation);
    controller.acknowledgeVisibleConversationRead(unreadConversation);
    await Future<void>.delayed(Duration.zero);
    controller.markConversationHidden(
      unreadConversation,
      displayThreadId: _timelineThreadId(unreadConversation),
    );

    final advancedConversation = unreadConversation.copyWith(
      lastMessagePreview: laterAgentReply.content,
      lastMessageAt: laterAgentReply.createdAt,
      unreadCount: 1,
      lastMessageSnapshot: laterAgentReply,
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(advancedConversation);
    controller.debugSeedMessageForTesting(
      laterAgentReply.copyWith(
        conversationId: unreadConversation.effectiveConversationId,
      ),
      threadId: _timelineThreadId(unreadConversation),
    );
    gateway.fetchLocalDmHistoryCompleter?.complete();
    await pumpEventQueue();

    final latestConversations = container
        .read(conversationListProvider)
        .conversations;
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      unreadConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'remote-10',
      sequence: '10',
    );
    if (latestConversations.isNotEmpty) {
      expect(
        latestConversations.single.lastMessagePreview,
        laterAgentReply.content,
      );
      expect(latestConversations.single.unreadCount, 1);
    }
  });

  test('打开未读会话加载到可见消息后异步按 conversationId 上报已读', () async {
    final unreadConversation = ConversationSummary(
      conversationId: conversation.conversationId,
      threadId: conversation.threadId,
      displayName: conversation.displayName,
      lastMessagePreview: conversation.lastMessagePreview,
      lastMessageAt: conversation.lastMessageAt,
      unreadCount: 2,
      isGroup: conversation.isGroup,
      targetDid: conversation.targetDid,
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[message],
    };
    _seedContainerConversationProjection(
      container,
      unreadConversation,
      <ChatMessage>[message],
    );

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(unreadConversation);
    await pumpEventQueue();

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations.single.unreadCount, 0);
    expect(notificationFacade.lastBadgeCount, 0);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      unreadConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: message.remoteId,
      sequence: message.serverSequence?.toString(),
    );
    expect(gateway.listConversationsCalls, greaterThanOrEqualTo(1));
  });

  test('打开未读会话在本地历史水合后按 conversationId 上报已读', () async {
    final older = ChatMessage(
      localId: 'local-10',
      remoteId: 'local-10',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'old',
      createdAt: DateTime(2026, 5, 8, 9, 59),
      isMine: false,
      serverSequence: 10,
      sendState: MessageSendState.sent,
    );
    final latest = ChatMessage(
      localId: 'remote-11',
      remoteId: 'remote-11',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'latest',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      serverSequence: 11,
      sendState: MessageSendState.sent,
    );
    final unreadConversation = conversation.copyWith(
      lastMessagePreview: latest.content,
      lastMessageAt: latest.createdAt,
      unreadCount: 2,
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[older, latest],
    };
    _seedContainerConversationProjection(
      container,
      unreadConversation,
      <ChatMessage>[older, latest],
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(unreadConversation);
    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(unreadConversation);
    await pumpEventQueue();

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    if (conversations.isNotEmpty) {
      expect(conversations.single.unreadCount, 0);
    }
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      unreadConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'remote-11',
      sequence: '11',
    );
  });

  test('peer-scope 会话历史使用精确 storage thread，已读使用 conversationId', () async {
    const agentDid = 'did:agent:runtime:codex1';
    const agentHandle = 'codex1.awiki.info';
    final unreadPeerScopedConversation = ConversationSummary(
      conversationId: 'dm:peer-scope:v1:codex1',
      threadId: 'dm:peer-scope:v1:codex1',
      displayName: 'Codex1',
      lastMessagePreview: 'hello from peer scoped thread',
      lastMessageAt: DateTime(2026, 5, 8, 10, 2),
      unreadCount: 1,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final latest = ChatMessage(
      localId: 'peer-scoped-local-12',
      remoteId: 'peer-scoped-local-12',
      threadId: unreadPeerScopedConversation.threadId,
      senderDid: agentDid,
      receiverDid: 'did:me',
      content: unreadPeerScopedConversation.lastMessagePreview,
      createdAt: unreadPeerScopedConversation.lastMessageAt,
      isMine: false,
      serverSequence: 12,
      sendState: MessageSendState.sent,
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'peer-scope:v1:codex1': <ChatMessage>[latest],
    };
    _seedContainerConversationProjection(
      container,
      unreadPeerScopedConversation,
      <ChatMessage>[latest],
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadPeerScopedConversation);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(unreadPeerScopedConversation);
    container
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(unreadPeerScopedConversation);
    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(unreadPeerScopedConversation);
    await pumpEventQueue();

    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .lastConversationTimelineId,
      unreadPeerScopedConversation.effectiveConversationId,
    );
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      unreadPeerScopedConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'peer-scoped-local-12',
      sequence: '12',
    );
  });

  test('打开未读会话时远端 mark-read 不支持也不会抛出或误清未读', () async {
    final throwingGateway = _ThrowingMarkReadGateway()
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[message],
      };
    final markReadContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(throwingGateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(throwingGateway),
      ],
    );
    addTearDown(markReadContainer.dispose);
    final unreadConversation = ConversationSummary(
      conversationId: conversation.conversationId,
      threadId: conversation.threadId,
      displayName: conversation.displayName,
      lastMessagePreview: conversation.lastMessagePreview,
      lastMessageAt: conversation.lastMessageAt,
      unreadCount: 2,
      isGroup: conversation.isGroup,
      targetDid: conversation.targetDid,
    );
    markReadContainer
        .read(conversationListProvider.notifier)
        .upsertConversation(unreadConversation);
    throwingGateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[message],
    };

    await expectLater(
      markReadContainer
          .read(chatThreadsProvider.notifier)
          .openConversation(unreadConversation),
      completes,
    );
    markReadContainer
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(unreadConversation);
    markReadContainer
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(unreadConversation);
    await Future<void>.delayed(Duration.zero);

    final conversations = markReadContainer
        .read(conversationListProvider)
        .conversations;
    if (conversations.isNotEmpty) {
      expect(conversations.single.unreadCount, 2);
    }
    expect(throwingGateway.markReadCalls, 0);
    expect(throwingGateway.markConversationReadCalls, 1);
  });

  test('当前可见会话收到新的可见消息时按 conversationId 上报并清未读', () async {
    final visibleConversation = conversation.copyWith(
      lastMessagePreview: 'new while visible',
      lastMessageAt: DateTime(2026, 5, 8, 10, 5),
      unreadCount: 2,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: 'msg-visible-unread',
    );
    final visibleMessage = ChatMessage(
      localId: 'msg-visible-unread',
      remoteId: 'msg-visible-unread',
      threadId: visibleConversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: 'new while visible',
      createdAt: visibleConversation.lastMessageAt,
      isMine: false,
      serverSequence: 11,
      sendState: MessageSendState.sent,
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(visibleConversation);
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(visibleMessage);
    container
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(
          visibleConversation,
          displayThreadId: visibleConversation.threadId,
        );

    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(
          visibleConversation,
          displayThreadId: visibleConversation.threadId,
          reason: 'visible_message_added',
          forcePersistentAck: true,
        );
    await Future<void>.delayed(Duration.zero);

    final updated = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(updated.unreadCount, 0);
    expect(updated.unreadMentionCount, 0);
    expect(updated.firstUnreadMentionMessageId, isNull);
    expect(notificationFacade.lastBadgeCount, 0);
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      visibleConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'msg-visible-unread',
      sequence: '11',
    );
  });

  test('发送后不触发 full refresh 或 force history 补拉', () async {
    final reply = ChatMessage(
      localId: 'reply-1',
      remoteId: 'reply-1',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      senderName: 'Peer',
      receiverDid: 'did:me',
      content: '你好。欢迎',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    final refreshedConversation = ConversationSummary(
      threadId: conversation.threadId,
      displayName: conversation.displayName,
      lastMessagePreview: reply.content,
      lastMessageAt: reply.createdAt,
      unreadCount: 1,
      isGroup: false,
      targetDid: conversation.targetDid,
    );
    gateway
      ..conversations = <ConversationSummary>[refreshedConversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[reply],
      };
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: '你好');
    await Future<void>.delayed(Duration.zero);

    final messages = sendContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages, isEmpty);
    expect(messages.map((item) => item.content), isNot(contains('你好。欢迎')));
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('发送后不会直接覆盖最近会话预览，等待 core summary patch', () async {
    gateway.conversations = const <ConversationSummary>[];
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);
    sendContainer
        .read(conversationListProvider.notifier)
        .upsertConversation(conversation);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: '你好');
    await Future<void>.delayed(Duration.zero);

    final conversations = sendContainer
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    expect(conversations.single.threadId, conversation.threadId);
    expect(
      conversations.single.lastMessagePreview,
      conversation.lastMessagePreview,
    );
    expect(conversations.single.targetDid, conversation.targetDid);
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('发送时刷新后的线程标识不会分裂当前打开会话的消息列表', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    final openedConversation = ConversationSummary(
      conversationId: 'dm:did:me:$agentDid',
      threadId: 'dm:did:me:$agentDid',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentDid,
    );
    final refreshedConversation = ConversationSummary(
      conversationId: 'dm:peer-scope:v1:zhuocheng-test-hermes',
      threadId: 'dm:peer-scope:v1:zhuocheng-test-hermes',
      displayName: 'Hermes',
      lastMessagePreview: '旧预览',
      lastMessageAt: DateTime(2026, 5, 8, 10, 1),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);
    gateway.nextSentThreadId = refreshedConversation.threadId;
    sendContainer
        .read(conversationListProvider.notifier)
        .upsertConversation(refreshedConversation);
    sendContainer
        .read(selectedConversationProvider.notifier)
        .selectConversation(openedConversation);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: refreshedConversation,
          displayThreadId: openedConversation.threadId,
          content: '你好',
          expectedAgentReplyDid: agentDid,
        );
    await Future<void>.delayed(Duration.zero);

    final openedThread = sendContainer.read(
      chatThreadProvider(openedConversation.threadId),
    );
    final refreshedThread = sendContainer.read(
      chatThreadProvider(refreshedConversation.threadId),
    );
    expect(openedThread.messages, isEmpty);
    expect(refreshedThread.messages, isEmpty);
    expect(openedThread.isAgentProcessing, isTrue);
    expect(refreshedThread.isAgentProcessing, isFalse);
    expect(
      gateway.lastSentThreadId,
      refreshedConversation.effectiveConversationId,
    );
    expect(
      sendContainer.read(selectedConversationProvider)?.threadId,
      openedConversation.threadId,
    );
    expect(
      sendContainer
          .read(conversationListProvider)
          .conversations
          .single
          .lastMessagePreview,
      '旧预览',
    );
  });

  test('发送后不会用本地 pending 预览覆盖 core 会话摘要', () async {
    final staleConversation = ConversationSummary(
      threadId: conversation.threadId,
      displayName: conversation.displayName,
      lastMessagePreview: '旧消息',
      lastMessageAt: DateTime.now().subtract(const Duration(minutes: 1)),
      unreadCount: 0,
      isGroup: false,
      targetDid: conversation.targetDid,
    );
    gateway.conversations = <ConversationSummary>[staleConversation];
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);
    sendContainer
        .read(conversationListProvider.notifier)
        .upsertConversation(conversation);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: '正在处理的问题',
          expectedAgentReplyDid: 'did:peer',
        );
    await Future<void>.delayed(Duration.zero);

    final latest = sendContainer
        .read(conversationListProvider)
        .conversations
        .single;
    expect(latest.lastMessagePreview, conversation.lastMessagePreview);
    expect(latest.lastMessageAt, conversation.lastMessageAt);
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('普通私聊发送成功后不会显示智能体处理中状态', () async {
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: '你好');

    final thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.agentPendingTurns, isEmpty);
  });

  test('发送给智能体时必须等消息投递成功后才进入处理中状态', () async {
    gateway.sendDelay = const Duration(milliseconds: 50);
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    final sendFuture = sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: '总结一下',
          expectedAgentReplyDid: 'did:peer',
        );
    await Future<void>.delayed(Duration.zero);

    var thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.messages, isEmpty);
    expect(thread.agentPendingTurns, isEmpty);

    await sendFuture;

    thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.messages, isEmpty);
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
  });

  test('发送给智能体成功后显示处理中，收到智能体回复后清除', () async {
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: '总结一下',
          expectedAgentReplyDid: 'did:peer',
        );

    final timelineThreadId = _timelineThreadId(conversation);
    var thread = sendContainer.read(chatThreadProvider(timelineThreadId));
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.agentPendingTurns.single.agentDid, 'did:peer');
    expect(thread.agentPendingTurns.single.remoteMessageId, isNotEmpty);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-reply-1',
            remoteId: 'agent-reply-1',
            threadId: timelineThreadId,
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '已经总结完成。',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(chatThreadProvider(timelineThreadId));
    expect(thread.agentPendingTurns, isEmpty);
    expect(
      thread.messages.map((message) => message.content),
      contains('已经总结完成。'),
    );
  });

  test('智能体实时回复使用不同 storage thread 时不会污染当前打开会话', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    final openedConversation = ConversationSummary(
      conversationId: 'dm:did:me:$agentDid',
      threadId: 'dm:did:me:$agentDid',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentDid,
    );
    final openedThreadId = _timelineThreadId(openedConversation);
    final realtimeConversation = ConversationSummary(
      conversationId: 'dm:peer-scope:v1:zhuocheng-test-hermes',
      threadId: 'dm:peer-scope:v1:zhuocheng-test-hermes',
      displayName: 'Hermes',
      lastMessagePreview: '我在。',
      lastMessageAt: DateTime(2026, 5, 8, 10, 2),
      unreadCount: 1,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: openedConversation,
          content: '在吗？',
          expectedAgentReplyDid: agentDid,
        );

    var openedThread = sendContainer.read(chatThreadProvider(openedThreadId));
    expect(openedThread.isAgentProcessing, isTrue);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-reply-canonical',
            remoteId: 'agent-reply-canonical',
            threadId: realtimeConversation.threadId,
            senderDid: agentDid,
            receiverDid: 'did:me',
            content: '我在。',
            createdAt: realtimeConversation.lastMessageAt,
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    openedThread = sendContainer.read(chatThreadProvider(openedThreadId));
    expect(openedThread.isAgentProcessing, isTrue);
    expect(
      openedThread.messages.map((message) => message.content),
      isNot(contains('我在。')),
    );
    final canonicalThread = sendContainer.read(
      chatThreadProvider(realtimeConversation.threadId),
    );
    expect(canonicalThread.messages.map((message) => message.content), ['我在。']);
    expect(
      canonicalThread.messages.single.threadId,
      realtimeConversation.threadId,
    );
  });

  test('发送给智能体后的旧历史回补不会误清处理中状态', () async {
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    final startedAt = DateTime(2026, 5, 8, 10, 2);
    sendContainer.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'run',
        'conversation_id': _timelineThreadId(conversation),
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_old_history_refresh',
            'runtime_agent_did': 'did:peer',
            'status': 'running',
            'source_message_id': 'sent-question',
            'started_at': startedAt.toUtc().toIso8601String(),
          },
        ],
      },
    );

    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[
        ChatMessage(
          localId: 'old-agent-reply',
          remoteId: 'old-agent-reply',
          threadId: conversation.threadId,
          senderDid: 'did:peer',
          receiverDid: 'did:me',
          content: '上一轮回复',
          createdAt: startedAt.subtract(const Duration(minutes: 1)),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .refreshConversation(conversation);

    final thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.agentPendingTurns.single.remoteMessageId, 'sent-question');
  });

  test('连续发给智能体时按回复数量递减处理中状态', () async {
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: '第一个问题',
          expectedAgentReplyDid: 'did:peer',
        );
    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: '第二个问题',
          expectedAgentReplyDid: 'did:peer',
        );

    var thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.pendingAgentReplyCount, 2);
    final firstTurn = thread.agentPendingTurns[0];
    final secondTurn = thread.agentPendingTurns[1];
    expect(firstTurn.localMessageId, isNot(secondTurn.localMessageId));

    sendContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-reply-a',
            remoteId: 'agent-reply-a',
            threadId: _timelineThreadId(conversation),
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '第一个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(
      thread.agentPendingTurns.map((turn) => turn.localMessageId),
      isNot(contains(firstTurn.localMessageId)),
    );
    expect(
      thread.agentPendingTurns.map((turn) => turn.localMessageId),
      contains(secondTurn.localMessageId),
    );

    sendContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-reply-a',
            remoteId: 'agent-reply-a',
            threadId: _timelineThreadId(conversation),
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '第一个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(
      thread.agentPendingTurns.map((turn) => turn.localMessageId),
      contains(secondTurn.localMessageId),
    );

    sendContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-reply-b',
            remoteId: 'agent-reply-b',
            threadId: _timelineThreadId(conversation),
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '第二个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.agentPendingTurns, isEmpty);
  });

  test('连续发送不会用旧快照覆盖后续 pending', () async {
    gateway.sendDelay = const Duration(milliseconds: 10);
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await Future.wait(<Future<void>>[
      sendContainer
          .read(chatThreadsProvider.notifier)
          .sendMessage(conversation: conversation, content: '5'),
      sendContainer
          .read(chatThreadsProvider.notifier)
          .sendMessage(conversation: conversation, content: '6'),
      sendContainer
          .read(chatThreadsProvider.notifier)
          .sendMessage(conversation: conversation, content: '7'),
    ]);
    await Future<void>.delayed(Duration.zero);

    final messages = sendContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages, isEmpty);
    expect(
      messages.where((item) => item.sendState == MessageSendState.sending),
      isEmpty,
    );
  });

  test('thread-after 回补会用服务端已发送消息替换同内容 pending', () async {
    final pending = ChatMessage(
      localId: 'pending-1',
      threadId: conversation.threadId,
      senderDid: 'did:me',
      receiverDid: conversation.targetDid,
      content: '5',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: true,
      sendState: MessageSendState.sending,
    );
    final serverMessage = ChatMessage(
      localId: 'remote-5',
      remoteId: 'remote-5',
      threadId: conversation.threadId,
      senderDid: 'did:me',
      receiverDid: conversation.targetDid,
      content: '5',
      createdAt: DateTime(2026, 5, 8, 10, 1, 8),
      isMine: true,
      sendState: MessageSendState.sent,
      serverSequence: 5,
    );
    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      serverMessage,
    ]);
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(pending);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(
          ConversationSummary(
            conversationId: conversation.conversationId,
            threadId: conversation.threadId,
            displayName: conversation.displayName,
            lastMessagePreview: '5',
            lastMessageAt: DateTime(2026, 5, 8, 10, 2),
            unreadCount: 0,
            isGroup: false,
            targetDid: conversation.targetDid,
          ),
        );
    await pumpEventQueue();

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.where((item) => item.content == '5'), hasLength(1));
    final sent = messages.singleWhere((item) => item.content == '5');
    expect(sent.remoteId, 'remote-5');
    expect(sent.sendState, MessageSendState.sent);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('历史回补不会把同一条已发送消息重复展示', () async {
    final sentAt = DateTime.now();
    gateway
      ..loginResult = const SessionIdentity(
        did: 'did:me',
        credentialName: 'me.json',
        displayName: 'Me',
        handle: 'me',
      )
      ..conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: conversation.threadId,
          displayName: conversation.displayName,
          lastMessagePreview: '1',
          lastMessageAt: sentAt,
          unreadCount: 0,
          isGroup: false,
          targetDid: conversation.targetDid,
        ),
      ]
      ..nextSentMessageId = 'server-message-1'
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[
          ChatMessage(
            localId: 'server-message-1',
            remoteId: 'server-message-1',
            threadId: conversation.threadId,
            senderDid: 'did:me',
            receiverDid: conversation.targetDid,
            content: '1',
            createdAt: sentAt,
            isMine: true,
            sendState: MessageSendState.sent,
          ),
        ],
      };
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: '1');
    await Future<void>.delayed(Duration.zero);

    final messages = sendContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.where((item) => item.content == '1'), isEmpty);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('打开群聊时不会展示空的群系统事件气泡', () async {
    const groupId = 'did:test:group:empty';
    final groupConversation = ConversationSummary(
      threadId: 'group:$groupId',
      displayName: '空事件群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    gateway.localGroupHistoryByGroupId = <String, List<ChatMessage>>{
      groupId: <ChatMessage>[
        ChatMessage(
          localId: 'group-create-event',
          remoteId: 'group-create-event',
          threadId: groupConversation.threadId,
          senderDid: 'did:me',
          groupId: groupId,
          content: '',
          originalType: 'application/json',
          createdAt: DateTime(2026, 5, 8, 10, 0),
          isMine: true,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(groupConversation);
    await Future<void>.delayed(Duration.zero);

    final thread = container.read(
      chatThreadProvider(groupConversation.threadId),
    );
    expect(thread.messages, isEmpty);
  });

  test('可见群聊刷新本地投影后展示成员加入系统事件', () async {
    const groupId = 'did:test:group:feedback';
    final groupConversation = ConversationSummary(
      conversationId: 'group:$groupId',
      threadId: 'group:$groupId',
      displayName: '反馈群',
      lastMessagePreview: '旧消息',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final oldMessage = ChatMessage(
      localId: 'group-feedback-message-1',
      remoteId: 'group-feedback-message-1',
      conversationId: groupConversation.effectiveConversationId,
      threadId: groupConversation.threadId,
      senderDid: 'did:member:old',
      groupId: groupId,
      content: '旧消息',
      createdAt: DateTime(2026, 5, 8, 10, 0),
      isMine: false,
      sendState: MessageSendState.sent,
      serverSequence: 1,
    );
    _seedContainerConversationProjection(
      container,
      groupConversation,
      <ChatMessage>[oldMessage],
    );

    final controller = container.read(chatThreadsProvider.notifier);
    await controller.openConversation(groupConversation);
    controller.markConversationVisible(
      groupConversation,
      displayThreadId: _timelineThreadId(groupConversation),
    );
    await pumpEventQueue();

    final initialThread = container.read(
      chatThreadProvider(_timelineThreadId(groupConversation)),
    );
    expect(initialThread.messages.map((item) => item.content), contains('旧消息'));
    expect(
      initialThread.messages.where((item) => item.isGroupSystemEvent),
      isEmpty,
    );

    final messagingService =
        container.read(messagingServiceProvider) as FakeMessagingService;
    final callsBeforeRefresh = messagingService.conversationTimelineCalls;
    await messagingService.persistConversationMessages(
      groupConversation.effectiveConversationId,
      <ChatMessage>[
        ChatMessage(
          localId: 'group-feedback-event-2',
          remoteId: 'group-feedback-event-2',
          conversationId: groupConversation.effectiveConversationId,
          threadId: groupConversation.threadId,
          senderDid: 'did:me',
          groupId: groupId,
          content: '',
          originalType: 'application/json',
          payloadJson: jsonEncode(<String, Object?>{
            'schema': 'awiki.group.system_event.v1',
            'type': 'member_added',
            'group_did': groupId,
            'group_event_seq': '2',
            'actor_did': 'did:me',
            'subject_did': 'did:member:new',
            'changed_at': '2026-05-08T10:01:00.000Z',
          }),
          createdAt: DateTime(2026, 5, 8, 10, 1),
          isMine: true,
          sendState: MessageSendState.sent,
          serverSequence: 2,
        ),
      ],
    );

    await controller.refreshVisibleLocalProjections();
    await pumpEventQueue();

    final refreshedThread = container.read(
      chatThreadProvider(_timelineThreadId(groupConversation)),
    );
    expect(
      refreshedThread.messages.map((item) => item.content),
      contains('旧消息'),
    );
    final systemEvents = refreshedThread.messages
        .where((item) => item.isGroupSystemEvent)
        .toList(growable: false);
    expect(systemEvents, hasLength(1));
    expect(systemEvents.single.groupSystemEvent?.isMemberAdded, isTrue);
    expect(systemEvents.single.groupSystemEvent?.subjectDid, 'did:member:new');
    expect(
      messagingService.conversationTimelineCalls,
      greaterThan(callsBeforeRefresh),
    );
    expect(
      messagingService.lastConversationTimelineId,
      groupConversation.effectiveConversationId,
    );
  });

  test('打开群聊时附件消息不会被文本过滤移除', () async {
    const groupId = 'did:test:group:attachments';
    final groupConversation = ConversationSummary(
      threadId: 'group:$groupId',
      displayName: '附件群',
      lastMessagePreview: '[附件] report.pdf',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    gateway.localGroupHistoryByGroupId = <String, List<ChatMessage>>{
      groupId: <ChatMessage>[
        ChatMessage(
          localId: 'group-attachment',
          remoteId: 'group-attachment',
          threadId: groupConversation.threadId,
          senderDid: 'did:peer',
          groupId: groupId,
          content: '',
          originalType: 'application/anp-attachment-manifest+json',
          createdAt: DateTime(2026, 5, 8, 10, 0),
          isMine: false,
          sendState: MessageSendState.sent,
          attachment: const ChatAttachment(
            attachmentId: 'att-1',
            filename: 'report.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 1024,
          ),
        ),
      ],
    };

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(groupConversation);
    await Future<void>.delayed(Duration.zero);

    final thread = container.read(
      chatThreadProvider(groupConversation.threadId),
    );
    expect(thread.messages, hasLength(1));
    final sentAttachment = thread.messages.singleWhere(
      (message) => message.attachment?.filename == 'report.pdf',
    );
    expect(sentAttachment.attachment?.filename, 'report.pdf');
  });

  test('发送私聊附件会生成 pending 并用服务端附件消息替换', () async {
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: conversation,
          attachment: AttachmentDraft(
            filename: 'report.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            sizeBytes: 3,
          ),
          caption: '报告',
        );
    await Future<void>.delayed(Duration.zero);

    final messages = sendContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    final attachmentMessages = messages
        .where((message) => message.attachment?.filename == 'report.pdf')
        .toList();
    expect(attachmentMessages, hasLength(1));
    expect(attachmentMessages.single.sendState, MessageSendState.sent);
    expect(attachmentMessages.single.previewText, '报告');
    final messaging =
        sendContainer.read(messagingServiceProvider) as FakeMessagingService;
    expect(messaging.sendConversationAttachmentCalls, 1);
    expect(
      messaging.lastAttachmentConversation?.conversationId,
      conversation.effectiveConversationId,
    );
    expect(
      messaging.lastSentAttachmentClientMessageId,
      startsWith('msg-awiki-me-'),
    );
    expect(
      messaging.lastSentAttachmentIdempotencyKey,
      startsWith('op-msg-awiki-me-'),
    );
    expect(gateway.lastSentPeerDid, 'did:peer');
    expect(gateway.lastSentAttachment?.filename, 'report.pdf');
    expect(gateway.lastSentAttachmentCaption, '报告');
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('发送给智能体的附件会按本地消息绑定处理中状态并在回复后清除', () async {
    gateway.nextSentMessageId = 'sent-agent-attachment';
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: conversation,
          attachment: AttachmentDraft(
            filename: 'report.md',
            mimeType: 'text/markdown',
            bytes: Uint8List.fromList(<int>[35, 32, 65]),
            sizeBytes: 3,
          ),
          caption: '看看附件',
          expectedAgentReplyDid: 'did:peer',
        );
    await Future<void>.delayed(Duration.zero);

    var thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    final sentAttachment = thread.messages.singleWhere(
      (message) => message.attachment?.filename == 'report.md',
    );
    expect(sentAttachment.localId, startsWith('msg-awiki-me-'));
    expect(sentAttachment.remoteId, 'sent-agent-attachment');
    expect(thread.pendingAgentReplyCount, 1);
    expect(
      thread.agentPendingTurns.single.localMessageId,
      startsWith('msg-awiki-me-'),
    );
    expect(
      thread.agentPendingTurns.single.remoteMessageId,
      sentAttachment.remoteId,
    );
    expect(thread.pendingAgentTurnForMessage(sentAttachment), isNotNull);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-attachment-reply',
            remoteId: 'agent-attachment-reply',
            threadId: _timelineThreadId(conversation),
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '附件里写的是 A。',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.agentPendingTurns, isEmpty);
  });

  test('私聊人类附件发送结果为低保真文本时仍保留附件消息', () async {
    final lowFidelityMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(lowFidelityMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: conversation,
          attachment: AttachmentDraft(
            filename: 'human-report.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            sizeBytes: 3,
          ),
          caption: '给你报告',
        );
    await pumpEventQueue();

    final thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    expect(thread.messages, hasLength(1));
    final sentAttachment = thread.messages.single;
    expect(sentAttachment.localId, startsWith('msg-awiki-me-'));
    expect(sentAttachment.remoteId, sentAttachment.localId);
    expect(
      sentAttachment.originalType,
      'application/anp-attachment-manifest+json',
    );
    expect(sentAttachment.attachment?.filename, 'human-report.pdf');
    expect(sentAttachment.attachment?.caption, '给你报告');
    expect(sentAttachment.content, '给你报告');
    expect(sentAttachment.mentions, isEmpty);
    expect(thread.agentPendingTurns, isEmpty);
  });

  test('私聊智能体附件发送结果为低保真文本时仍保留附件和处理中状态', () async {
    final lowFidelityMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(lowFidelityMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: conversation,
          attachment: AttachmentDraft(
            filename: 'agent-report.md',
            mimeType: 'text/markdown',
            bytes: Uint8List.fromList(<int>[35, 32, 65]),
            sizeBytes: 3,
          ),
          caption: '看看附件',
          expectedAgentReplyDid: 'did:peer',
        );
    await pumpEventQueue();

    final thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    final sentAttachment = thread.messages.single;
    expect(sentAttachment.localId, startsWith('msg-awiki-me-'));
    expect(sentAttachment.remoteId, sentAttachment.localId);
    expect(
      sentAttachment.originalType,
      'application/anp-attachment-manifest+json',
    );
    expect(sentAttachment.attachment?.filename, 'agent-report.md');
    expect(sentAttachment.attachment?.caption, '看看附件');
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.pendingAgentTurnForMessage(sentAttachment), isNotNull);
    expect(
      thread.agentPendingTurns.single.remoteMessageId,
      sentAttachment.localId,
    );
  });

  test('群聊附件 caption 中 @智能体会保留结构化 mention 并显示处理中', () async {
    gateway.nextSentMessageId = 'sent-group-agent-attachment';
    final groupConversation = ConversationSummary(
      threadId: 'group:did:test:group',
      displayName: 'Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group',
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    const mention = ChatMentionDraft(
      localId: 'men_agent',
      surface: '@codex',
      start: 0,
      end: 6,
      target: ChatMentionTargetDraft.member(
        kind: ChatMentionTargetKind.agent,
        did: 'did:agent:codex',
        handle: 'codex',
        displayName: 'CodeX',
      ),
    );

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: groupConversation,
          attachment: AttachmentDraft(
            filename: 'report.md',
            mimeType: 'text/markdown',
            bytes: Uint8List.fromList(<int>[35, 32, 65]),
            sizeBytes: 3,
          ),
          caption: '@codex 看看这个文件',
          mentions: const <ChatMentionDraft>[mention],
        );
    await Future<void>.delayed(Duration.zero);

    final thread = sendContainer.read(
      chatThreadProvider(groupConversation.threadId),
    );
    final sentAttachment = thread.messages.singleWhere(
      (message) => message.attachment?.filename == 'report.md',
    );
    expect(sentAttachment.content, '@codex 看看这个文件');
    expect(sentAttachment.mentions, hasLength(1));
    expect(
      sentAttachment.mentions.single.target.kind,
      ChatMentionTargetKind.agent,
    );
    expect(sentAttachment.payloadJson, isNotNull);
    expect(
      ChatMentionPayload.tryParsePayloadJson(sentAttachment.payloadJson)?.text,
      '@codex 看看这个文件',
    );
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.agentPendingTurns.single.agentDid, 'did:agent:codex');
    expect(thread.agentPendingTurns.single.mentionId, 'men_agent');
    expect(
      thread.pendingAgentTurnForMessage(sentAttachment)?.agentHandle,
      'codex',
    );
    final messaging =
        sendContainer.read(messagingServiceProvider) as FakeMessagingService;
    expect(messaging.sendConversationAttachmentCalls, 1);
    expect(
      messaging.lastAttachmentConversation?.conversationId,
      groupConversation.effectiveConversationId,
    );
    expect(gateway.lastSentGroupId, 'did:test:group');
    expect(gateway.lastSentAttachmentCaption, '@codex 看看这个文件');
  });

  test('群聊附件 @普通用户低保真发送结果保留附件和 mention 且不触发智能体处理中', () async {
    final lowFidelityMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:did:test:group-human',
      displayName: 'Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group-human',
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(lowFidelityMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    const mention = ChatMentionDraft(
      localId: 'men_human',
      surface: '@alice',
      start: 0,
      end: 6,
      target: ChatMentionTargetDraft.member(
        kind: ChatMentionTargetKind.human,
        did: 'did:human:alice',
        handle: 'alice',
        displayName: 'Alice',
      ),
    );

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: groupConversation,
          attachment: AttachmentDraft(
            filename: 'human-mention.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            sizeBytes: 3,
          ),
          caption: '@alice 看看这个文件',
          mentions: const <ChatMentionDraft>[mention],
        );
    await pumpEventQueue();

    final thread = sendContainer.read(
      chatThreadProvider(groupConversation.threadId),
    );
    final sentAttachment = thread.messages.single;
    expect(
      sentAttachment.originalType,
      'application/anp-attachment-manifest+json',
    );
    expect(sentAttachment.attachment?.filename, 'human-mention.pdf');
    expect(sentAttachment.attachment?.caption, '@alice 看看这个文件');
    expect(sentAttachment.content, '@alice 看看这个文件');
    expect(sentAttachment.mentions, hasLength(1));
    expect(
      sentAttachment.mentions.single.target.kind,
      ChatMentionTargetKind.human,
    );
    expect(
      ChatMentionPayload.tryParsePayloadJson(sentAttachment.payloadJson)?.text,
      '@alice 看看这个文件',
    );
    expect(thread.agentPendingTurns, isEmpty);
    expect(thread.isAgentProcessing, isFalse);
  });

  test('群聊附件 @智能体低保真发送结果保留附件和 mention 且显示处理中', () async {
    final lowFidelityMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:did:test:group-agent-low',
      displayName: 'Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group-agent-low',
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(lowFidelityMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    const mention = ChatMentionDraft(
      localId: 'men_agent_low',
      surface: '@codex',
      start: 0,
      end: 6,
      target: ChatMentionTargetDraft.member(
        kind: ChatMentionTargetKind.agent,
        did: 'did:agent:codex',
        handle: 'codex',
        displayName: 'CodeX',
      ),
    );

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: groupConversation,
          attachment: AttachmentDraft(
            filename: 'agent-mention.md',
            mimeType: 'text/markdown',
            bytes: Uint8List.fromList(<int>[35, 32, 65]),
            sizeBytes: 3,
          ),
          caption: '@codex 看看这个文件',
          mentions: const <ChatMentionDraft>[mention],
        );
    await pumpEventQueue();

    final thread = sendContainer.read(
      chatThreadProvider(groupConversation.threadId),
    );
    final sentAttachment = thread.messages.single;
    expect(
      sentAttachment.originalType,
      'application/anp-attachment-manifest+json',
    );
    expect(sentAttachment.attachment?.filename, 'agent-mention.md');
    expect(sentAttachment.attachment?.caption, '@codex 看看这个文件');
    expect(sentAttachment.content, '@codex 看看这个文件');
    expect(sentAttachment.mentions, hasLength(1));
    expect(
      sentAttachment.mentions.single.target.kind,
      ChatMentionTargetKind.agent,
    );
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.pendingAgentTurnForMessage(sentAttachment), isNotNull);
    expect(thread.agentPendingTurns.single.mentionId, 'men_agent_low');
  });

  test('普通用户附件不会误显示智能体处理中状态', () async {
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);
    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: conversation,
          attachment: AttachmentDraft(
            filename: 'report.pdf',
            mimeType: 'application/pdf',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            sizeBytes: 3,
          ),
          caption: '报告',
        );
    await Future<void>.delayed(Duration.zero);

    final thread = sendContainer.read(
      chatThreadProvider(_timelineThreadId(conversation)),
    );
    final sentAttachment = thread.messages.singleWhere(
      (message) => message.attachment?.filename == 'report.pdf',
    );
    expect(sentAttachment.attachment?.filename, 'report.pdf');
    expect(thread.agentPendingTurns, isEmpty);
    expect(thread.isAgentProcessing, isFalse);
  });

  test('服务端附件消息不带本地路径时发送成功后仍保留本地缓存路径', () async {
    gateway.includeLocalPathInSentAttachment = false;
    gateway.nextSentMessageId = 'sent-report';
    final cache = FakeAttachmentCacheService();
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          attachmentCacheService: cache,
        ),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: conversation,
          attachment: const AttachmentDraft(
            filename: 'report.pdf',
            mimeType: 'application/pdf',
            localPath: '/tmp/original-report.pdf',
            sizeBytes: 3,
          ),
          caption: '报告',
        );
    await Future<void>.delayed(Duration.zero);

    final messages = sendContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    final sentAttachment = messages.singleWhere(
      (message) => message.attachment?.filename == 'report.pdf',
    );
    expect(sentAttachment.remoteId, 'sent-report');
    expect(sentAttachment.attachment?.localPath, isNotNull);
    expect(sentAttachment.attachment?.localPath, contains('sent-report'));
    expect(sentAttachment.attachment?.hasLocalSource, isTrue);
    expect(cache.cacheLocalSourceCalls, 1);
    expect(cache.lastSourcePath, '/tmp/original-report.pdf');
  });

  test('附件发送成功后不触发 full refresh', () async {
    final flakyGateway = FakeAwikiGateway()
      ..loginResult = const SessionIdentity(
        did: 'did:me',
        credentialName: 'me.json',
        displayName: 'Me',
        handle: 'me',
      )
      ..failNextListConversations = true;
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(flakyGateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(flakyGateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: conversation,
          attachment: AttachmentDraft(
            filename: 'report.md',
            mimeType: 'text/markdown',
            bytes: Uint8List.fromList(<int>[35, 32, 65]),
            sizeBytes: 3,
          ),
          caption: '报告',
        );
    await Future<void>.delayed(Duration.zero);

    final messages = sendContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.attachment?.filename, 'report.md');
    expect(messages.single.sendState, MessageSendState.sent);
    expect(flakyGateway.listConversationsCalls, 0);
    expect(flakyGateway.fetchDmHistoryCalls, 0);
  });

  test('发送群聊附件使用 conversation id 且不手动更新会话预览', () async {
    const groupId = 'did:test:group:send-attachment';
    final groupConversation = ConversationSummary(
      threadId: 'group:$groupId',
      displayName: '附件群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);
    gateway.conversations = <ConversationSummary>[groupConversation];
    await sendContainer.read(conversationListProvider.notifier).refresh();
    final listConversationsCallsBeforeSend = gateway.listConversationsCalls;

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendAttachment(
          conversation: groupConversation,
          attachment: AttachmentDraft(
            filename: 'diagram.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
            sizeBytes: 4,
          ),
        );
    await Future<void>.delayed(Duration.zero);

    final messaging =
        sendContainer.read(messagingServiceProvider) as FakeMessagingService;
    expect(messaging.sendConversationAttachmentCalls, 1);
    expect(
      messaging.lastAttachmentConversation?.conversationId,
      groupConversation.effectiveConversationId,
    );
    expect(gateway.lastSentGroupId, groupId);
    final conversations = sendContainer
        .read(conversationListProvider)
        .conversations;
    expect(conversations.single.lastMessagePreview, '');
    expect(gateway.listConversationsCalls, listConversationsCallsBeforeSend);
  });

  test('没有本地路径的失败附件不会触发无效重试', () async {
    final failedAttachment = ChatMessage(
      localId: 'failed-mobile-attachment',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:me',
      receiverDid: conversation.targetDid,
      content: '',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: true,
      sendState: MessageSendState.failed,
      attachment: const ChatAttachment(
        attachmentId: 'pending-attachment',
        filename: 'mobile.bin',
        mimeType: 'application/octet-stream',
      ),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          failedAttachment,
          threadId: _timelineThreadId(conversation),
        );

    await container
        .read(chatThreadsProvider.notifier)
        .retryMessage(conversation: conversation, message: failedAttachment);

    expect(gateway.lastSentAttachment, isNull);
    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.single.sendState, MessageSendState.failed);
  });

  test('文本重试成功后不触发 full refresh 或 force history 补拉', () async {
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final retryContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(retryContainer.dispose);
    final failedMessage = ChatMessage(
      localId: 'failed-text',
      remoteId: 'failed-text',
      conversationId: conversation.effectiveConversationId,
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:me',
      receiverDid: conversation.targetDid,
      content: '重试文本',
      originalType: 'text',
      createdAt: DateTime(2026, 5, 8, 10, 3),
      isMine: true,
      sendState: MessageSendState.failed,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[
        ChatMessage(
          localId: 'remote-retry-reply',
          remoteId: 'remote-retry-reply',
          threadId: _timelineThreadId(conversation),
          senderDid: 'did:peer',
          receiverDid: 'did:me',
          content: '远端补拉消息',
          originalType: 'text',
          createdAt: DateTime(2026, 5, 8, 10, 4),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    };
    retryContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          failedMessage,
          threadId: _timelineThreadId(conversation),
        );

    await retryContainer
        .read(chatThreadsProvider.notifier)
        .retryMessage(conversation: conversation, message: failedMessage);
    await Future<void>.delayed(Duration.zero);

    expect(patchMessaging.sendConversationTextCalls, 1);
    expect(
      patchMessaging.lastSendConversation?.conversationId,
      conversation.effectiveConversationId,
    );
    expect(patchMessaging.lastClientMessageId, 'failed-text');
    expect(patchMessaging.lastIdempotencyKey, 'retry-failed-text');
    expect(patchMessaging.lastSendContent, '重试文本');
    final messages = retryContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), contains('重试文本'));
    expect(
      messages.singleWhere((item) => item.content == '重试文本').sendState,
      MessageSendState.sent,
    );
    expect(messages.map((item) => item.content), isNot(contains('远端补拉消息')));
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('附件重试成功后不触发 full refresh 或 force history 补拉', () async {
    final patchMessaging = _PatchMessagingService(
      localHistory: <ChatMessage>[],
    );
    final retryContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        messagingServiceProvider.overrideWithValue(patchMessaging),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(retryContainer.dispose);
    final failedAttachment = ChatMessage(
      localId: 'failed-attachment-retry',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:me',
      receiverDid: conversation.targetDid,
      content: '附件说明',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime(2026, 5, 8, 10, 4),
      isMine: true,
      sendState: MessageSendState.failed,
      attachment: const ChatAttachment(
        attachmentId: 'pending-attachment-retry',
        filename: 'retry.pdf',
        mimeType: 'application/pdf',
        localPath: '/tmp/retry.pdf',
        caption: '附件说明',
      ),
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[
        ChatMessage(
          localId: 'remote-attachment-retry-reply',
          remoteId: 'remote-attachment-retry-reply',
          threadId: _timelineThreadId(conversation),
          senderDid: 'did:peer',
          receiverDid: 'did:me',
          content: '附件远端补拉消息',
          originalType: 'text',
          createdAt: DateTime(2026, 5, 8, 10, 5),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    };
    retryContainer
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          failedAttachment,
          threadId: _timelineThreadId(conversation),
        );

    await retryContainer
        .read(chatThreadsProvider.notifier)
        .retryMessage(conversation: conversation, message: failedAttachment);
    await Future<void>.delayed(Duration.zero);

    expect(patchMessaging.sendConversationAttachmentCalls, 1);
    expect(
      patchMessaging.lastSendAttachmentConversation?.conversationId,
      conversation.effectiveConversationId,
    );
    expect(patchMessaging.lastClientMessageId, 'failed-attachment-retry');
    expect(patchMessaging.lastIdempotencyKey, 'retry-failed-attachment-retry');
    expect(gateway.lastSentAttachment, isNull);
    final messages = retryContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    final sentAttachment = messages.singleWhere(
      (message) => message.attachment?.filename == 'retry.pdf',
    );
    expect(sentAttachment.sendState, MessageSendState.sent);
    expect(messages.map((item) => item.content), isNot(contains('附件远端补拉消息')));
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('历史刷新后仍未回补的过期 pending 会转为失败', () async {
    final pending = ChatMessage(
      localId: 'pending-stale',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:me',
      receiverDid: conversation.targetDid,
      content: '7',
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      isMine: true,
      sendState: MessageSendState.sending,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': const <ChatMessage>[],
    };
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          pending,
          threadId: _timelineThreadId(conversation),
        );

    await container
        .read(chatThreadsProvider.notifier)
        .refreshConversation(conversation);

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    final stale = messages.singleWhere(
      (item) => item.localId == 'pending-stale',
    );
    expect(stale.sendState, MessageSendState.failed);
  });

  test('附件 pending 不会被 30 秒文本发送超时提前判失败', () async {
    final pending = ChatMessage(
      localId: 'pending-attachment-still-sending',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:me',
      receiverDid: conversation.targetDid,
      content: '',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      isMine: true,
      sendState: MessageSendState.sending,
      attachment: const ChatAttachment(
        attachmentId: 'pending-attachment',
        filename: 'large.mov',
        mimeType: 'video/quicktime',
        localPath: '/tmp/large.mov',
      ),
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': const <ChatMessage>[],
    };
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          pending,
          threadId: _timelineThreadId(conversation),
        );

    await container
        .read(chatThreadsProvider.notifier)
        .refreshConversation(conversation);

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    final attachment = messages.singleWhere(
      (item) => item.localId == 'pending-attachment-still-sending',
    );
    expect(attachment.sendState, MessageSendState.sending);
  });

  test('会话列表已有新预览时再次打开走 thread-after 不走远端 history', () async {
    final localOnly = ChatMessage(
      localId: 'sent-local',
      remoteId: 'sent-local',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:me',
      receiverDid: 'did:peer',
      content: '你好',
      createdAt: DateTime(2026, 5, 8, 10, 0),
      isMine: true,
      serverSequence: 5,
      sendState: MessageSendState.sent,
    );
    final reply = ChatMessage(
      localId: 'reply-2',
      remoteId: 'reply-2',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:peer',
      senderName: 'Peer',
      receiverDid: 'did:me',
      content: '你好。欢迎',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      serverSequence: 6,
      sendState: MessageSendState.sent,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[localOnly, reply],
    };
    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      reply,
    ]);
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          localOnly,
          threadId: _timelineThreadId(conversation),
        );

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(
          ConversationSummary(
            conversationId: conversation.conversationId,
            threadId: conversation.threadId,
            displayName: conversation.displayName,
            lastMessagePreview: reply.content,
            lastMessageAt: reply.createdAt,
            unreadCount: 1,
            isGroup: false,
            targetDid: conversation.targetDid,
          ),
        );
    await Future<void>.delayed(Duration.zero);

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), contains('你好。欢迎'));
    expect(
      (container.read(messagingServiceProvider) as FakeMessagingService)
          .conversationTimelineCalls,
      greaterThanOrEqualTo(1),
    );
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messageSyncService.conversationAfterRequests, hasLength(1));
    expect(
      messageSyncService.conversationAfterRequests.single.afterServerSeq,
      '5',
    );
    expect(messageSyncService.threadAfterRequests, isEmpty);
  });

  test('历史加载中收到新的会话概览时会排队再补拉一次', () async {
    final firstReply = ChatMessage(
      localId: 'reply-old',
      remoteId: 'reply-old',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:peer',
      senderName: 'Peer',
      receiverDid: 'did:me',
      content: '旧回复',
      createdAt: DateTime(2026, 5, 8, 10, 1),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    final latestReply = ChatMessage(
      localId: 'reply-latest',
      remoteId: 'reply-latest',
      threadId: _timelineThreadId(conversation),
      senderDid: 'did:peer',
      senderName: 'Peer',
      receiverDid: 'did:me',
      content: '最新回复',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      firstReply,
    ]);

    final firstLoad = container
        .read(chatThreadsProvider.notifier)
        .syncHistoryForConversation(conversation);
    await Future<void>.delayed(Duration.zero);

    _seedConversationAfter(messageSyncService, conversation, <ChatMessage>[
      firstReply,
      latestReply,
    ]);
    await container
        .read(chatThreadsProvider.notifier)
        .syncHistoryForConversation(
          conversation.copyWith(
            lastMessagePreview: latestReply.content,
            lastMessageAt: latestReply.createdAt,
          ),
        );
    await firstLoad;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final messages = container
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(messages.map((item) => item.content), contains('最新回复'));
    expect(messageSyncService.conversationAfterRequests, hasLength(2));
    expect(messageSyncService.threadAfterRequests, isEmpty);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('群列表刷新后会把已知群名称同步到会话列表', () async {
    const groupId = 'did:test:group:funding';
    final groupConversation = ConversationSummary(
      threadId: 'group:$groupId',
      displayName: 'Group $groupId',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 5, 8, 10, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(groupConversation);
    container
        .read(groupProvider.notifier)
        .upsertGroup(
          const GroupSummary(
            groupId: groupId,
            name: '融资协作群',
            description: '',
            memberCount: 3,
            lastMessageAt: null,
          ),
        );

    expect(
      container.read(conversationListProvider).conversations.single.displayName,
      '融资协作群',
    );
  });

  test('刷新最近会话时不会把已知群名称降级成群 DID', () async {
    const groupId = 'did:test:group:funding';
    final knownGroupConversation = ConversationSummary(
      threadId: 'group:$groupId',
      displayName: '融资协作群',
      lastMessagePreview: '旧消息',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    gateway.conversations = <ConversationSummary>[
      ConversationSummary(
        threadId: 'group:$groupId',
        displayName: groupId,
        lastMessagePreview: '新消息',
        lastMessageAt: DateTime(2026, 5, 8, 10, 5),
        unreadCount: 3,
        isGroup: true,
        groupId: groupId,
      ),
    ];
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(knownGroupConversation);
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:me',
            credentialName: 'me.json',
            displayName: 'Me',
            handle: 'me',
          ),
        );

    await container.read(conversationListProvider.notifier).refresh();

    final refreshed = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(refreshed.displayName, '融资协作群');
    expect(refreshed.lastMessagePreview, '新消息');
    expect(refreshed.unreadCount, 3);
  });

  test('实时群消息不会把已知群名称降级成群 DID', () {
    const groupId = 'did:test:group:funding';
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          ConversationSummary(
            threadId: 'group:$groupId',
            displayName: '融资协作群',
            lastMessagePreview: '旧消息',
            lastMessageAt: DateTime(2026, 5, 8, 10),
            unreadCount: 0,
            isGroup: true,
            groupId: groupId,
          ),
        );

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          ConversationSummary(
            threadId: 'group:$groupId',
            displayName: groupId,
            lastMessagePreview: '实时新消息',
            lastMessageAt: DateTime(2026, 5, 8, 10, 6),
            unreadCount: 1,
            isGroup: true,
            groupId: groupId,
          ),
        );

    final refreshed = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(refreshed.displayName, '融资协作群');
    expect(refreshed.lastMessagePreview, '实时新消息');
    expect(refreshed.unreadCount, 1);
  });

  test('实时私聊消息不会把已知智能体名称降级成 handle', () {
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          ConversationSummary(
            threadId: 'dm:did:me:did:agent:runtime',
            displayName: '写作助手',
            lastMessagePreview: '旧消息',
            lastMessageAt: DateTime(2026, 5, 8, 10),
            unreadCount: 0,
            isGroup: false,
            targetDid: 'did:agent:runtime',
          ),
        );

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          ConversationSummary(
            threadId: 'dm:did:me:did:agent:runtime',
            displayName: 'awiki-agent-random',
            lastMessagePreview: '实时新消息',
            lastMessageAt: DateTime(2026, 5, 8, 10, 6),
            unreadCount: 1,
            isGroup: false,
            targetDid: 'did:agent:runtime',
          ),
        );

    final refreshed = container
        .read(conversationListProvider)
        .conversations
        .single;
    expect(refreshed.displayName, '写作助手');
    expect(refreshed.lastMessagePreview, '实时新消息');
    expect(refreshed.unreadCount, 1);
  });

  test('删除最近会话只移出列表并清空当前选中会话', () async {
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:me',
            credentialName: 'me.json',
            displayName: 'Me',
            handle: 'me',
          ),
        );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(conversation);
    container
        .read(selectedConversationProvider.notifier)
        .selectConversation(conversation);

    await container
        .read(conversationListProvider.notifier)
        .deleteFromRecents(conversation);

    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(container.read(selectedConversationProvider), isNull);
    expect(notificationFacade.lastBadgeCount, 0);
    expect(gateway.deleteLocalThreadCalls, 1);
    expect(gateway.lastDeletedLocalThreadId, 'direct-did:did:peer');
  });

  test('删除最近会话后旧实时不复活，新实时会重新显示', () async {
    final peerScopedConversation = conversation.copyWith(
      threadId: 'dm:peer-scope:v1:peer',
      targetDid: null,
      targetPeer: 'peer.anpclaw.com',
    );
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:me',
            credentialName: 'me.json',
            displayName: 'Me',
            handle: 'me',
          ),
        );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(peerScopedConversation);

    await container
        .read(conversationListProvider.notifier)
        .deleteFromRecents(peerScopedConversation);

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          peerScopedConversation.copyWith(
            lastMessagePreview: '旧消息',
            lastMessageAt: conversation.lastMessageAt,
          ),
        );
    expect(container.read(conversationListProvider).conversations, isEmpty);

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          peerScopedConversation.copyWith(
            lastMessagePreview: '新消息',
            lastMessageAt: DateTime.now().add(const Duration(seconds: 1)),
          ),
        );

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    expect(conversations.single.lastMessagePreview, '新消息');
  });

  test('刷新的 peer-scoped 会话替换本地 legacy DID 会话', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          ConversationSummary(
            threadId: 'dm:did:human:$agentDid',
            displayName: 'zhuocheng-test-hermes',
            lastMessagePreview: '本地消息',
            lastMessageAt: DateTime(2026, 5, 8, 10),
            unreadCount: 0,
            isGroup: false,
            targetDid: agentDid,
            targetPeer: agentDid,
          ),
        );
    gateway.conversations = <ConversationSummary>[
      ConversationSummary(
        threadId: 'dm:peer-scope:v1:runtime',
        displayName: '改名后的智能体',
        lastMessagePreview: '刷新消息',
        lastMessageAt: DateTime(2026, 5, 8, 10, 1),
        unreadCount: 1,
        isGroup: false,
        targetDid: agentDid,
        targetPeer: agentHandle,
      ),
    ];
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:human',
            credentialName: 'human.json',
            displayName: 'Me',
            handle: 'zhuocheng',
          ),
        );

    await container.read(conversationListProvider.notifier).refresh();

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations, hasLength(1));
    final byThread = {
      for (final conversation in conversations)
        conversation.threadId: conversation,
    };
    expect(byThread['dm:peer-scope:v1:runtime']?.lastMessagePreview, '刷新消息');
    expect(byThread['dm:peer-scope:v1:runtime']?.targetDid, agentDid);
    expect(byThread['dm:peer-scope:v1:runtime']?.targetPeer, agentHandle);
    expect(byThread['dm:peer-scope:v1:runtime']?.displayName, '改名后的智能体');
  });

  test('legacy DID 会话已读不会错误清空新的 peer-scoped 未读', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    final readConversation = ConversationSummary(
      conversationId: 'dm:$agentDid',
      threadId: 'dm:did:human:$agentDid',
      displayName: 'Hermes',
      lastMessagePreview: '我在。',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 1,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentDid,
    );
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:human',
            credentialName: 'human.json',
            displayName: 'Me',
            handle: 'zhuocheng',
          ),
        );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(readConversation);
    gateway.conversations = <ConversationSummary>[readConversation];
    _seedContainerConversationProjection(
      container,
      readConversation,
      <ChatMessage>[
        ChatMessage(
          localId: 'agent-msg',
          remoteId: 'agent-msg',
          threadId: readConversation.threadId,
          senderDid: agentDid,
          receiverDid: 'did:human',
          content: readConversation.lastMessagePreview,
          createdAt: readConversation.lastMessageAt,
          isMine: false,
          serverSequence: 1,
          sendState: MessageSendState.sent,
        ),
      ],
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      agentDid: <ChatMessage>[
        ChatMessage(
          localId: 'agent-msg',
          remoteId: 'agent-msg',
          threadId: readConversation.threadId,
          senderDid: agentDid,
          receiverDid: 'did:human',
          content: readConversation.lastMessagePreview,
          createdAt: readConversation.lastMessageAt,
          isMine: false,
          serverSequence: 1,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(readConversation);
    container
        .read(chatThreadsProvider.notifier)
        .markConversationVisible(readConversation);
    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(readConversation);
    await pumpEventQueue();

    expect(
      container
          .read(conversationListProvider)
          .conversations
          .singleWhere(
            (item) =>
                item.effectiveConversationId ==
                readConversation.effectiveConversationId,
          )
          .unreadCount,
      1,
    );
    expect(gateway.markReadCalls, 0);
    expect(gateway.markConversationReadCalls, 1);
    expect(
      gateway.lastMarkConversationReadConversationId,
      readConversation.effectiveConversationId,
    );
    _expectLastConversationReadWatermark(
      gateway,
      messageId: 'agent-msg',
      sequence: '1',
    );

    gateway.conversations = <ConversationSummary>[
      ConversationSummary(
        threadId: 'dm:peer-scope:v1:zhuocheng-test-hermes',
        displayName: 'Hermes',
        lastMessagePreview: '我在。',
        lastMessageAt: readConversation.lastMessageAt,
        unreadCount: 1,
        isGroup: false,
        targetDid: agentDid,
        targetPeer: agentHandle,
      ),
    ];

    await container.read(conversationListProvider.notifier).refresh();

    final refreshed = container
        .read(conversationListProvider)
        .conversations
        .singleWhere(
          (conversation) =>
              conversation.threadId == 'dm:peer-scope:v1:zhuocheng-test-hermes',
        );
    expect(refreshed.threadId, 'dm:peer-scope:v1:zhuocheng-test-hermes');
    expect(refreshed.unreadCount, 1);
    expect(
      container
          .read(conversationListProvider)
          .conversations
          .where((conversation) => conversation.targetDid == agentDid),
      hasLength(1),
    );
  });

  test('连续发送不会触发会话刷新或远端历史 reconcile', () async {
    final reply = ChatMessage(
      localId: 'reply-batched',
      remoteId: 'reply-batched',
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      receiverDid: 'did:me',
      content: '批量回复',
      createdAt: DateTime(2026, 5, 8, 10, 3),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    gateway
      ..conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: conversation.threadId,
          displayName: conversation.displayName,
          lastMessagePreview: reply.content,
          lastMessageAt: reply.createdAt,
          unreadCount: 1,
          isGroup: false,
          targetDid: conversation.targetDid,
        ),
      ]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[reply],
      };
    final sendContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
        sessionProvider.overrideWith((ref) {
          final controller = SessionController();
          controller.setSession(
            const SessionIdentity(
              did: 'did:me',
              credentialName: 'me.json',
              displayName: 'Me',
              handle: 'me',
            ),
          );
          return controller;
        }),
      ],
    );
    addTearDown(sendContainer.dispose);

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: '第一条');
    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(conversation: conversation, content: '第二条');

    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    await Future<void>.delayed(Duration.zero);

    final messages = sendContainer
        .read(chatThreadProvider(_timelineThreadId(conversation)))
        .messages;
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messages, isEmpty);
    expect(messages.map((item) => item.content), isNot(contains('批量回复')));
  });
}

class _ThrowingMarkReadGateway extends FakeAwikiGateway {
  @override
  Future<void> markConversationRead(
    String conversationId, {
    AppThreadReadWatermark? watermark,
  }) {
    markConversationReadCalls += 1;
    lastMarkConversationReadConversationId = conversationId;
    lastMarkConversationReadWatermark = watermark;
    throw UnsupportedError('IM Core markConversationRead is not available yet');
  }
}

class _PatchMessagingService
    implements
        MessagingService,
        LocalHistoryMessagingService,
        ThreadPatchMessagingService,
        ConversationTimelineMessagingService {
  _PatchMessagingService({
    required this.localHistory,
    ThreadMessagePatch? repairPatch,
    this.emitPendingBeforeTextResult = false,
    this.textSendError,
  }) : repairPatch =
           repairPatch ??
           const ThreadMessagePatch(
             kind: ThreadMessagePatchKind.reset,
             ownerDid: 'did:me',
             version: 1,
             threadKind: 'direct',
             threadId: 'did:peer',
           );

  final List<ChatMessage> localHistory;
  final bool emitPendingBeforeTextResult;
  final Object? textSendError;
  ThreadMessagePatch repairPatch;
  final Map<String, List<ChatMessage>> projectionByConversationId =
      <String, List<ChatMessage>>{};
  final StreamController<ThreadMessagePatch> _patches =
      StreamController<ThreadMessagePatch>.broadcast();
  int repairCalls = 0;
  int repairConversationCalls = 0;
  int? lastRepairLimit;
  int? lastRepairConversationLimit;
  int watchCalls = 0;
  int watchConversationCalls = 0;
  int cancelledWatches = 0;
  String? lastConversationTimelineId;
  int sendConversationAttachmentCalls = 0;
  int sendConversationTextCalls = 0;
  int sendConversationMentionTextCalls = 0;
  AppConversationReadRef? lastSendConversation;
  AppConversationReadRef? lastSendAttachmentConversation;
  String? lastSendContent;
  List<ChatMentionDraft> lastSendMentions = const <ChatMentionDraft>[];
  String? lastClientMessageId;
  String? lastIdempotencyKey;

  void emitPatch(ThreadMessagePatch patch) {
    _patches.add(patch);
  }

  void emitError(Object error) {
    _patches.addError(error);
  }

  void persistConversationMessages(
    String conversationId,
    List<ChatMessage> messages,
  ) {
    final current = projectionByConversationId[conversationId] ?? localHistory;
    projectionByConversationId[conversationId] = _mergePatchProjectionMessages(
      current,
      _withConversationId(messages, conversationId),
    );
  }

  Future<void> closePatches() => _patches.close();

  @override
  Stream<ThreadMessagePatch> watchThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  }) {
    watchCalls += 1;
    return Stream<ThreadMessagePatch>.multi((controller) {
      controller.add(
        ThreadMessagePatch(
          kind: ThreadMessagePatchKind.reset,
          ownerDid: 'did:me',
          version: 1,
          threadKind: _patchThreadKind(thread),
          threadId: _patchThreadId(thread),
          messages: localHistory,
        ),
      );
      final subscription = _patches.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () {
        cancelledWatches += 1;
        return subscription.cancel();
      };
    });
  }

  @override
  Stream<ThreadMessagePatch> watchConversationTimelinePatches(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) {
    watchConversationCalls += 1;
    lastConversationTimelineId = conversation.conversationId;
    return Stream<ThreadMessagePatch>.multi((controller) {
      controller.add(
        ThreadMessagePatch(
          kind: ThreadMessagePatchKind.reset,
          ownerDid: 'did:me',
          version: 1,
          threadKind: 'conversation',
          threadId: conversation.conversationId,
          conversationId: conversation.conversationId,
          messages:
              projectionByConversationId[conversation.conversationId] ??
              _withConversationId(localHistory, conversation.conversationId),
        ),
      );
      final subscription = _patches.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () {
        cancelledWatches += 1;
        return subscription.cancel();
      };
    });
  }

  @override
  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  }) async {
    repairCalls += 1;
    lastRepairLimit = limit;
    return repairPatch;
  }

  @override
  Future<ThreadMessagePatch> repairConversationTimelineStore(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) async {
    repairConversationCalls += 1;
    lastRepairConversationLimit = limit;
    lastConversationTimelineId = conversation.conversationId;
    final projected = projectionByConversationId[conversation.conversationId];
    if (projected == null) {
      return _patchWithConversationId(repairPatch, conversation.conversationId);
    }
    return ThreadMessagePatch(
      kind: ThreadMessagePatchKind.reset,
      ownerDid: 'did:me',
      version: repairPatch.version,
      threadKind: 'conversation',
      threadId: conversation.conversationId,
      conversationId: conversation.conversationId,
      messages: projected,
    );
  }

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) async {
    return AttachmentDownloadResult(attachmentId: attachmentId ?? 'a1');
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    return localHistory;
  }

  @override
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    return localHistory;
  }

  @override
  Future<List<ChatMessage>> loadConversationTimeline(
    AppConversationReadRef conversation, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) async {
    lastConversationTimelineId = conversation.conversationId;
    return projectionByConversationId[conversation.conversationId] ??
        _withConversationId(localHistory, conversation.conversationId);
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) async {
    return failed.copyWith(sendState: MessageSendState.sent);
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? idempotencyKey,
  }) async {
    return _sentMessage(thread: thread, content: caption ?? '');
  }

  @override
  Future<ChatMessage> sendConversationAttachment({
    required AppConversationReadRef conversation,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? clientMessageId,
    String? idempotencyKey,
  }) async {
    sendConversationAttachmentCalls += 1;
    lastSendConversation = conversation;
    lastSendAttachmentConversation = conversation;
    lastSendContent = caption ?? '';
    lastSendMentions = mentions;
    lastClientMessageId = clientMessageId;
    lastIdempotencyKey = idempotencyKey;
    final mentionPayload = mentions.isEmpty || caption == null
        ? null
        : ChatMentionPayload.toP9Json(text: caption, draftMentions: mentions);
    return _sentConversationMessage(
      conversation: conversation,
      content: caption ?? '',
      clientMessageId: clientMessageId,
      payloadJson: mentionPayload == null ? null : jsonEncode(mentionPayload),
      mentions: <ChatMessageMention>[
        for (final mention in mentions) ChatMessageMention.fromDraft(mention),
      ],
      attachment: ChatAttachment(
        attachmentId: clientMessageId ?? 'attachment-patched',
        filename: attachment.filename,
        mimeType: attachment.mimeType,
        sizeBytes: attachment.sizeBytes,
        caption: caption,
      ),
      originalType: 'application/anp-attachment-manifest+json',
    );
  }

  @override
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? idempotencyKey,
  }) async {
    return _sentMessage(thread: thread, content: text);
  }

  @override
  Future<ChatMessage> sendConversationMentionText({
    required AppConversationReadRef conversation,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? clientMessageId,
    String? idempotencyKey,
  }) async {
    sendConversationMentionTextCalls += 1;
    lastSendConversation = conversation;
    lastSendContent = text;
    lastSendMentions = mentions;
    lastClientMessageId = clientMessageId;
    lastIdempotencyKey = idempotencyKey;
    return _sentConversationMessage(
      conversation: conversation,
      content: text,
      clientMessageId: clientMessageId,
      payloadJson: jsonEncode(
        ChatMentionPayload.toP9Json(text: text, draftMentions: mentions),
      ),
      mentions: <ChatMessageMention>[
        for (final mention in mentions) ChatMessageMention.fromDraft(mention),
      ],
    );
  }

  @override
  Future<ChatMessage> sendConversationText({
    required AppConversationReadRef conversation,
    required String content,
    String? clientMessageId,
    String? idempotencyKey,
  }) async {
    sendConversationTextCalls += 1;
    lastSendConversation = conversation;
    lastSendContent = content;
    lastSendMentions = const <ChatMentionDraft>[];
    lastClientMessageId = clientMessageId;
    lastIdempotencyKey = idempotencyKey;
    final sent = _sentConversationMessage(
      conversation: conversation,
      content: content,
      clientMessageId: clientMessageId,
    );
    if (emitPendingBeforeTextResult) {
      emitPatch(
        ThreadMessagePatch(
          kind: ThreadMessagePatchKind.upsert,
          ownerDid: 'did:me',
          version: 2,
          threadKind: 'conversation',
          threadId: conversation.conversationId,
          conversationId: conversation.conversationId,
          message: sent.copyWith(sendState: MessageSendState.sending),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    final error = textSendError;
    if (error != null) {
      throw error;
    }
    return sent;
  }

  @override
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) async {
    return _sentMessage(
      thread: thread,
      content: payload['text']?.toString() ?? '',
    );
  }

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) async {
    return _sentMessage(thread: thread, content: content);
  }
}

void _connectConversationProjectionPersistence(
  FakeMessageSyncService syncService,
  _PatchMessagingService messagingService,
) {
  syncService.onConversationAfterPersisted =
      (String conversationId, List<ChatMessage> messages) {
        messagingService.persistConversationMessages(conversationId, messages);
      };
}

void _seedContainerConversationProjection(
  ProviderContainer container,
  ConversationSummary conversation,
  List<ChatMessage> messages,
) {
  final messaging = container.read(messagingServiceProvider);
  if (messaging is! FakeMessagingService) {
    throw StateError('Expected FakeMessagingService for test projection seed.');
  }
  _seedConversationProjection(messaging, conversation, messages);
}

void _seedConversationProjection(
  FakeMessagingService messaging,
  ConversationSummary conversation,
  List<ChatMessage> messages,
) {
  final conversationId = conversation.effectiveConversationId;
  messaging.conversationTimelineById[conversationId] = _withConversationId(
    messages,
    conversationId,
  );
}

void _seedPatchConversationProjection(
  _PatchMessagingService messaging,
  ConversationSummary conversation,
  List<ChatMessage> messages,
) {
  final conversationId = conversation.effectiveConversationId;
  messaging.projectionByConversationId[conversationId] = _withConversationId(
    messages,
    conversationId,
  );
}

void _seedConversationAfter(
  FakeMessageSyncService syncService,
  ConversationSummary conversation,
  List<ChatMessage> messages,
) {
  final conversationId = conversation.effectiveConversationId;
  syncService.conversationAfterMessagesById[conversationId] =
      _withConversationId(messages, conversationId);
}

String _timelineThreadId(ConversationSummary conversation) =>
    conversation.effectiveConversationId;

ChatMessage _sentMessage({
  required AppThreadRef thread,
  required String content,
}) {
  final groupDid = thread is AppGroupThreadRef ? thread.groupDid : null;
  final receiverDid = thread is AppDirectThreadRef
      ? thread.peerDidOrHandle
      : null;
  const messageId = 'sent-patched';
  return ChatMessage(
    localId: messageId,
    remoteId: messageId,
    threadId: thread.stableId,
    senderDid: 'did:me',
    receiverDid: receiverDid,
    groupId: groupDid,
    content: content,
    originalType: 'text',
    createdAt: DateTime.now(),
    isMine: true,
    sendState: MessageSendState.sent,
  );
}

ChatMessage _sentConversationMessage({
  required AppConversationReadRef conversation,
  required String content,
  String? clientMessageId,
  String? payloadJson,
  List<ChatMessageMention> mentions = const <ChatMessageMention>[],
  ChatAttachment? attachment,
  String? originalType,
}) {
  final messageId = clientMessageId?.trim().isNotEmpty == true
      ? clientMessageId!.trim()
      : 'sent-patched';
  return ChatMessage(
    localId: messageId,
    remoteId: messageId,
    conversationId: conversation.conversationId,
    threadId: conversation.conversationId,
    senderDid: 'did:me',
    content: content,
    originalType:
        originalType ?? (payloadJson == null ? 'text' : 'application/json'),
    createdAt: DateTime.now(),
    isMine: true,
    sendState: MessageSendState.sent,
    payloadJson: payloadJson,
    mentions: mentions,
    attachment: attachment,
  );
}

List<ChatMessage> _mergePatchProjectionMessages(
  List<ChatMessage> current,
  List<ChatMessage> incoming,
) {
  final merged = <ChatMessage>[...current];
  for (final message in incoming) {
    final index = merged.indexWhere((candidate) {
      final candidateId = _patchStableMessageId(candidate);
      final messageId = _patchStableMessageId(message);
      if (candidateId.isNotEmpty && candidateId == messageId) {
        return true;
      }
      return candidate.content.trim().isNotEmpty &&
          candidate.content == message.content &&
          candidate.senderDid == message.senderDid &&
          candidate.receiverDid == message.receiverDid &&
          candidate.createdAt.isAtSameMomentAs(message.createdAt);
    });
    if (index >= 0) {
      merged[index] = message;
    } else {
      merged.add(message);
    }
  }
  merged.sort(_comparePatchMessagesForTimeline);
  return merged;
}

String _patchStableMessageId(ChatMessage message) {
  final remoteId = message.remoteId?.trim();
  if (remoteId != null && remoteId.isNotEmpty) {
    return remoteId;
  }
  return message.localId.trim();
}

int _comparePatchMessagesForTimeline(ChatMessage a, ChatMessage b) {
  final timeCompare = a.createdAt.compareTo(b.createdAt);
  if (timeCompare != 0) {
    return timeCompare;
  }
  final aSeq = a.serverSequence;
  final bSeq = b.serverSequence;
  if (aSeq != null && bSeq != null && aSeq != bSeq) {
    return aSeq.compareTo(bSeq);
  }
  final idCompare = _patchStableMessageId(
    a,
  ).compareTo(_patchStableMessageId(b));
  if (idCompare != 0) {
    return idCompare;
  }
  return a.localId.compareTo(b.localId);
}

List<ChatMessage> _withConversationId(
  List<ChatMessage> messages,
  String conversationId,
) {
  return <ChatMessage>[
    for (final message in messages)
      message.conversationId == conversationId
          ? message
          : _messageWithConversationId(message, conversationId),
  ];
}

ChatMessage _messageWithConversationId(
  ChatMessage message,
  String conversationId,
) {
  return ChatMessage(
    localId: message.localId,
    remoteId: message.remoteId,
    conversationId: conversationId,
    threadId: message.threadId,
    senderDid: message.senderDid,
    senderName: message.senderName,
    receiverDid: message.receiverDid,
    groupId: message.groupId,
    content: message.content,
    originalType: message.originalType,
    createdAt: message.createdAt,
    isMine: message.isMine,
    sendState: message.sendState,
    serverSequence: message.serverSequence,
    isEncrypted: message.isEncrypted,
    payloadJson: message.payloadJson,
    mentions: message.mentions,
    attachment: message.attachment,
  );
}

ThreadMessagePatch _patchWithConversationId(
  ThreadMessagePatch patch,
  String conversationId,
) {
  return ThreadMessagePatch(
    kind: patch.kind,
    ownerDid: patch.ownerDid,
    version: patch.version,
    threadKind: patch.threadKind,
    threadId: patch.threadId,
    conversationId: patch.conversationId ?? conversationId,
    messages: _withConversationId(patch.messages, conversationId),
    message: patch.message == null
        ? null
        : _messageWithConversationId(patch.message!, conversationId),
    index: patch.index,
    messageId: patch.messageId,
    reason: patch.reason,
  );
}

String _patchThreadKind(AppThreadRef thread) {
  return switch (thread) {
    AppDirectThreadRef() => 'direct',
    AppGroupThreadRef() => 'group',
    AppMessageThreadRef() => 'thread',
  };
}

String _patchThreadId(AppThreadRef thread) {
  return switch (thread) {
    AppDirectThreadRef(:final peerDidOrHandle) => peerDidOrHandle,
    AppGroupThreadRef(:final groupDid) => groupDid,
    AppMessageThreadRef(:final threadId) => threadId,
  };
}

void _expectLastConversationReadWatermark(
  FakeAwikiGateway gateway, {
  String? messageId,
  String? sequence,
}) {
  final watermark = gateway.lastMarkConversationReadWatermark;
  expect(watermark, isNotNull);
  expect(watermark!.lastReadMessageId, messageId);
  expect(watermark.lastReadThreadSeq, sequence);
  expect(watermark.readAt, isNotNull);
}
