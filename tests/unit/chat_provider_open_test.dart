import 'dart:async';
import 'dart:typed_data';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/thread_message_patch.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  late FakeAwikiGateway gateway;
  late FakeNotificationFacade notificationFacade;
  late FakeMessageSyncService messageSyncService;
  late ProviderContainer container;

  final conversation = ConversationSummary(
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
      };
    notificationFacade = FakeNotificationFacade();
    messageSyncService = FakeMessageSyncService();
    container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(
          gateway,
          messageSyncService: messageSyncService,
        ),
      ],
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

    expect(gateway.fetchLocalDmHistoryCalls, 1);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(gateway.listConversationsCalls, 0);
    final messaging = container.read(messagingServiceProvider);
    expect(messaging, isA<FakeMessagingService>());
    expect((messaging as FakeMessagingService).lastLocalHistoryLimit, 50);
    expect(messageSyncService.threadAfterRequests, hasLength(1));
    expect(
      messageSyncService.threadAfterRequests.single.afterServerSeq,
      isNull,
    );

    final thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.messages, hasLength(1));
    expect(thread.messages.single.content, 'hello');
    expect(thread.isLoading, isFalse);
  });

  test('打开会话加载到首条本地历史后同步最近会话预览', () async {
    final emptyPreviewConversation = conversation.copyWith(
      lastMessagePreview: '',
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[message.copyWith(content: 'Agent 已准备好。')],
    };
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
    expect(gateway.fetchLocalDmHistoryCalls, 1);
  });

  test('本地历史为空时仍回退远端 history', () async {
    gateway.localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    expect(gateway.fetchLocalDmHistoryCalls, 1);
    expect(gateway.fetchDmHistoryCalls, 1);
    final thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.messages.map((item) => item.content), contains('hello'));
    expect(thread.isLoading, isFalse);
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
    messageSyncService.threadAfterMessagesByStableId['dm:did:peer'] =
        <ChatMessage>[newer];

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    expect(messageSyncService.threadAfterRequests.single.afterServerSeq, '10');
    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.map((item) => item.content), ['old', 'new']);
  });

  test('thread-after 失败不会清空本地历史', () async {
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[message],
    };
    messageSyncService.nextThreadAfterError = StateError('thread-after failed');

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    final thread = container.read(chatThreadProvider(conversation.threadId));
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

    patchMessaging.emitPatch(
      ThreadMessagePatch(
        kind: ThreadMessagePatchKind.upsert,
        ownerDid: 'did:me',
        version: 2,
        threadKind: 'direct',
        threadId: 'did:peer',
        message: ChatMessage(
          localId: 'sent-patched',
          remoteId: 'sent-patched',
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

    final messages = patchContainer
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.remoteId, 'sent-patched');
    expect(messages.single.sendState, MessageSendState.sent);
    expect(messages.single.serverSequence, 2);
  });

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
        threadKind: 'direct',
        threadId: 'did:other',
        message: ChatMessage(
          localId: 'wrong-thread',
          remoteId: 'wrong-thread',
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
        .read(chatThreadProvider(conversation.threadId))
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
        threadKind: 'direct',
        threadId: 'did:peer',
        messages: <ChatMessage>[repaired],
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
        threadKind: 'direct',
        threadId: 'did:peer',
        message: repaired,
      ),
    );
    await pumpEventQueue();

    expect(patchMessaging.repairCalls, 1);
    expect(patchMessaging.lastRepairLimit, 100);
    final messages = patchContainer
        .read(chatThreadProvider(conversation.threadId))
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
          threadKind: 'direct',
          threadId: 'did:peer',
          messages: <ChatMessage>[repaired],
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
      expect(patchMessaging.watchCalls, 1);

      await patchMessaging.closePatches();
      await pumpEventQueue();

      final messages = patchContainer
          .read(chatThreadProvider(conversation.threadId))
          .messages;
      expect(patchMessaging.repairCalls, 1);
      expect(patchMessaging.watchCalls, 2);
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
        .applyRealtimeUpdate(local, conversation: conversation);

    await container
        .read(chatThreadsProvider.notifier)
        .syncHistoryForConversation(conversation.copyWith(unreadCount: 3));
    await pumpEventQueue();

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
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
      expect(patchMessaging.watchCalls, 1);

      controller.markConversationHidden(conversation);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(patchMessaging.cancelledWatches, 1);

      controller.markConversationVisible(conversation);
      await pumpEventQueue();
      expect(patchMessaging.watchCalls, 2);
      expect(
        patchContainer
            .read(chatThreadProvider(conversation.threadId))
            .messages
            .map((item) => item.content),
        contains('hello'),
      );
    },
  );

  test('本地历史命中时失败的远端 history 不会被触发', () async {
    gateway
      ..failNextFetchDmHistory = true
      ..localDmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[message],
      };

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    expect(gateway.fetchLocalDmHistoryCalls, 1);
    expect(gateway.fetchDmHistoryCalls, 0);
    final thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.messages, hasLength(1));
    expect(thread.messages.single.content, 'hello');
    expect(thread.isLoading, isFalse);
  });

  test('有稳定 DID 的 handle 会话本地优先按 DID 读取且不触发远端 history', () async {
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
      threadId: 'dm:did:human:$agentDid',
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
      agentDid: <ChatMessage>[outgoing],
      agentHandle: const <ChatMessage>[],
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

    expect(gateway.lastFetchedLocalDmPeerDid, agentDid);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(gateway.lastFetchedDmPeerDid, isNull);
    final thread = container.read(
      chatThreadProvider(agentConversation.threadId),
    );
    expect(thread.messages.map((item) => item.content), contains('在吗'));
  });

  test('已加载线程再次打开不重复拉历史', () async {
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await pumpEventQueue();

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);

    expect(gateway.fetchLocalDmHistoryCalls, 1);
    expect(gateway.fetchDmHistoryCalls, 1);
    expect(messageSyncService.threadAfterRequests, hasLength(2));
    expect(gateway.listConversationsCalls, 0);
  });

  test('首次打开会话会从 realtime alias 预热缓存直接渲染', () async {
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
        .applyRealtimeUpdate(realtimeMessage, conversation: aliasConversation);
    gateway.localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    gateway.dmHistoryByPeerDid = const <String, List<ChatMessage>>{};

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(aliasConversation);
    await pumpEventQueue();

    final messages = container
        .read(chatThreadProvider(aliasConversation.threadId))
        .messages;
    expect(
      messages.map((item) => item.content),
      contains('realtime alias hello'),
    );
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messageSyncService.threadAfterRequests, hasLength(1));
  });

  test('打开未读会话时本地清未读并异步上报，不刷新会话列表', () async {
    final unreadConversation = ConversationSummary(
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

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(unreadConversation);
    await Future<void>.delayed(Duration.zero);

    final conversations = container
        .read(conversationListProvider)
        .conversations;
    expect(conversations.single.unreadCount, 0);
    expect(notificationFacade.lastBadgeCount, 0);
    expect(gateway.markReadCalls, 1);
    expect(gateway.listConversationsCalls, 0);
  });

  test('打开未读会话时远端 mark-read 不支持也不会抛出', () async {
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

    await expectLater(
      markReadContainer
          .read(chatThreadsProvider.notifier)
          .openConversation(unreadConversation),
      completes,
    );
    await Future<void>.delayed(Duration.zero);

    final conversations = markReadContainer
        .read(conversationListProvider)
        .conversations;
    expect(conversations.single.unreadCount, 0);
    expect(notificationFacade.lastBadgeCount, 0);
    expect(throwingGateway.markReadCalls, 1);
  });

  test('当前可见会话收到新的未读摘要时本地清未读并异步上报', () async {
    final visibleConversation = conversation.copyWith(
      lastMessagePreview: 'new while visible',
      lastMessageAt: DateTime(2026, 5, 8, 10, 5),
      unreadCount: 2,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: 'msg-visible-unread',
    );
    container
        .read(conversationListProvider.notifier)
        .upsertConversation(visibleConversation);
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
          reason: 'visible_summary_update',
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
    expect(gateway.markReadCalls, 1);
    expect(gateway.lastMarkReadThreadId, 'dm:did:peer');
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.map((item) => item.content), contains('你好'));
    expect(messages.map((item) => item.content), isNot(contains('你好。欢迎')));
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('发送后不依赖刷新也会保留最近会话', () async {
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
    expect(conversations.single.lastMessagePreview, '你好');
    expect(conversations.single.targetDid, conversation.targetDid);
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('发送时刷新后的线程标识不会分裂当前打开会话的消息列表', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    final openedConversation = ConversationSummary(
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
    sendContainer
        .read(conversationListProvider.notifier)
        .upsertConversation(refreshedConversation);

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
    expect(openedThread.messages.map((item) => item.content), contains('你好'));
    expect(openedThread.isAgentProcessing, isTrue);
    expect(refreshedThread.messages, isEmpty);
    expect(gateway.lastSentPeerDid, agentHandle);
    expect(
      sendContainer
          .read(conversationListProvider)
          .conversations
          .single
          .lastMessagePreview,
      '你好',
    );
  });

  test('发送后不会让旧远端概览覆盖本地最新预览', () async {
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
    expect(latest.lastMessagePreview, '正在处理的问题');
    expect(latest.lastMessageAt.isAfter(staleConversation.lastMessageAt), true);
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
      chatThreadProvider(conversation.threadId),
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

    var thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.messages.single.sendState, MessageSendState.sending);
    expect(thread.agentPendingTurns, isEmpty);

    await sendFuture;

    thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.messages.single.sendState, MessageSendState.sent);
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(
      thread.pendingAgentTurnForMessage(thread.messages.single),
      isNotNull,
    );
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

    var thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.agentPendingTurns.single.agentDid, 'did:peer');
    expect(thread.agentPendingTurns.single.remoteMessageId, isNotEmpty);
    expect(
      thread.pendingAgentTurnForMessage(thread.messages.single),
      isNotNull,
    );

    sendContainer
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-reply-1',
            remoteId: 'agent-reply-1',
            threadId: conversation.threadId,
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '已经总结完成。',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.agentPendingTurns, isEmpty);
    expect(
      thread.messages.map((message) => message.content),
      contains('已经总结完成。'),
    );
  });

  test('智能体实时回复使用刷新后的线程标识时仍合并到当前打开会话', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    final openedConversation = ConversationSummary(
      threadId: 'dm:did:me:$agentDid',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentDid,
    );
    final realtimeConversation = ConversationSummary(
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

    var openedThread = sendContainer.read(
      chatThreadProvider(openedConversation.threadId),
    );
    expect(openedThread.isAgentProcessing, isTrue);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
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
          conversation: realtimeConversation,
        );

    openedThread = sendContainer.read(
      chatThreadProvider(openedConversation.threadId),
    );
    expect(openedThread.agentPendingTurns, isEmpty);
    expect(
      openedThread.messages.map((message) => message.content),
      contains('我在。'),
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

    await sendContainer
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: conversation,
          content: '新的问题',
          expectedAgentReplyDid: 'did:peer',
        );

    final startedAt = sendContainer
        .read(chatThreadProvider(conversation.threadId))
        .agentPendingTurns
        .single
        .startedAt;
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
      chatThreadProvider(conversation.threadId),
    );
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
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

    var thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.pendingAgentReplyCount, 2);
    final firstMessage = thread.messages.firstWhere(
      (message) => message.content == '第一个问题',
    );
    final secondMessage = thread.messages.firstWhere(
      (message) => message.content == '第二个问题',
    );
    expect(thread.pendingAgentTurnForMessage(firstMessage), isNotNull);
    expect(thread.pendingAgentTurnForMessage(secondMessage), isNotNull);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-reply-a',
            remoteId: 'agent-reply-a',
            threadId: conversation.threadId,
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '第一个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.pendingAgentTurnForMessage(firstMessage), isNull);
    expect(thread.pendingAgentTurnForMessage(secondMessage), isNotNull);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-reply-a',
            remoteId: 'agent-reply-a',
            threadId: conversation.threadId,
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '第一个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.isAgentProcessing, isTrue);
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.pendingAgentTurnForMessage(secondMessage), isNotNull);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-reply-b',
            remoteId: 'agent-reply-b',
            threadId: conversation.threadId,
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '第二个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(chatThreadProvider(conversation.threadId));
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(
      messages.map((item) => item.content),
      containsAll(<String>['5', '6', '7']),
    );
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
    messageSyncService.threadAfterMessagesByStableId['dm:did:peer'] =
        <ChatMessage>[serverMessage];
    container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(pending);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(
          ConversationSummary(
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.where((item) => item.content == '5'), hasLength(1));
    expect(messages.single.remoteId, 'remote-5');
    expect(messages.single.sendState, MessageSendState.sent);
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.where((item) => item.content == '1'), hasLength(1));
    expect(messages.single.remoteId, 'server-message-1');
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
    gateway.groupHistoryByGroupId = <String, List<ChatMessage>>{
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
    gateway.groupHistoryByGroupId = <String, List<ChatMessage>>{
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    final attachmentMessages = messages
        .where((message) => message.attachment?.filename == 'report.pdf')
        .toList();
    expect(attachmentMessages, hasLength(1));
    expect(attachmentMessages.single.sendState, MessageSendState.sent);
    expect(attachmentMessages.single.previewText, '报告');
    expect(gateway.lastSentPeerDid, 'did:peer');
    expect(gateway.lastSentAttachment?.filename, 'report.pdf');
    expect(gateway.lastSentAttachmentCaption, '报告');
    expect(gateway.lastSentAttachmentIdempotencyKey, startsWith('pending-'));
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

    var thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    final sentAttachment = thread.messages.singleWhere(
      (message) => message.attachment?.filename == 'report.md',
    );
    expect(sentAttachment.remoteId, 'sent-agent-attachment');
    expect(sentAttachment.localId, 'sent-agent-attachment');
    expect(thread.pendingAgentReplyCount, 1);
    expect(
      thread.agentPendingTurns.single.localMessageId,
      startsWith('pending-'),
    );
    expect(
      thread.agentPendingTurns.single.remoteMessageId,
      'sent-agent-attachment',
    );
    expect(thread.pendingAgentTurnForMessage(sentAttachment), isNotNull);

    sendContainer
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-attachment-reply',
            remoteId: 'agent-attachment-reply',
            threadId: conversation.threadId,
            senderDid: 'did:peer',
            receiverDid: 'did:me',
            content: '附件里写的是 A。',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );

    thread = sendContainer.read(chatThreadProvider(conversation.threadId));
    expect(thread.agentPendingTurns, isEmpty);
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
    expect(gateway.lastSentGroupId, 'did:test:group');
    expect(gateway.lastSentAttachmentCaption, '@codex 看看这个文件');
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
      chatThreadProvider(conversation.threadId),
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
        .read(chatThreadProvider(conversation.threadId))
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages, hasLength(1));
    expect(messages.single.attachment?.filename, 'report.md');
    expect(messages.single.sendState, MessageSendState.sent);
    expect(flakyGateway.listConversationsCalls, 0);
    expect(flakyGateway.fetchDmHistoryCalls, 0);
  });

  test('发送群聊附件使用群目标并更新会话预览', () async {
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

    expect(gateway.lastSentGroupId, groupId);
    final conversations = sendContainer
        .read(conversationListProvider)
        .conversations;
    expect(conversations.single.lastMessagePreview, '[附件] diagram.png');
  });

  test('没有本地路径的失败附件不会触发无效重试', () async {
    final failedAttachment = ChatMessage(
      localId: 'failed-mobile-attachment',
      threadId: conversation.threadId,
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
        .applyRealtimeUpdate(failedAttachment);

    await container
        .read(chatThreadsProvider.notifier)
        .retryMessage(conversation: conversation, message: failedAttachment);

    expect(gateway.lastSentAttachment, isNull);
    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.single.sendState, MessageSendState.failed);
  });

  test('文本重试成功后不触发 full refresh 或 force history 补拉', () async {
    final failedMessage = ChatMessage(
      localId: 'failed-text',
      threadId: conversation.threadId,
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
          threadId: conversation.threadId,
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
    container
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(failedMessage);

    await container
        .read(chatThreadsProvider.notifier)
        .retryMessage(conversation: conversation, message: failedMessage);
    await Future<void>.delayed(Duration.zero);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.map((item) => item.content), contains('重试文本'));
    expect(messages.map((item) => item.content), isNot(contains('远端补拉消息')));
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('附件重试成功后不触发 full refresh 或 force history 补拉', () async {
    final failedAttachment = ChatMessage(
      localId: 'failed-attachment-retry',
      threadId: conversation.threadId,
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
          threadId: conversation.threadId,
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
    container
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(failedAttachment);

    await container
        .read(chatThreadsProvider.notifier)
        .retryMessage(conversation: conversation, message: failedAttachment);
    await Future<void>.delayed(Duration.zero);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    final sentAttachment = messages.singleWhere(
      (message) => message.attachment?.filename == 'retry.pdf',
    );
    expect(sentAttachment.sendState, MessageSendState.sent);
    expect(gateway.lastSentAttachment?.filename, 'retry.pdf');
    expect(messages.map((item) => item.content), isNot(contains('附件远端补拉消息')));
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
  });

  test('历史刷新后仍未回补的过期 pending 会转为失败', () async {
    final pending = ChatMessage(
      localId: 'pending-stale',
      threadId: conversation.threadId,
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
    container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(pending);

    await container
        .read(chatThreadsProvider.notifier)
        .refreshConversation(conversation);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.single.localId, 'pending-stale');
    expect(messages.single.sendState, MessageSendState.failed);
  });

  test('附件 pending 不会被 30 秒文本发送超时提前判失败', () async {
    final pending = ChatMessage(
      localId: 'pending-attachment-still-sending',
      threadId: conversation.threadId,
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
    container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(pending);

    await container
        .read(chatThreadsProvider.notifier)
        .refreshConversation(conversation);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.single.localId, 'pending-attachment-still-sending');
    expect(messages.single.sendState, MessageSendState.sending);
  });

  test('会话列表已有新预览时再次打开走 thread-after 不走远端 history', () async {
    final localOnly = ChatMessage(
      localId: 'sent-local',
      remoteId: 'sent-local',
      threadId: conversation.threadId,
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
      threadId: conversation.threadId,
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
    messageSyncService.threadAfterMessagesByStableId['dm:did:peer'] =
        <ChatMessage>[reply];
    container.read(chatThreadsProvider.notifier).applyRealtimeUpdate(localOnly);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(
          ConversationSummary(
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.map((item) => item.content), contains('你好。欢迎'));
    expect(gateway.fetchLocalDmHistoryCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messageSyncService.threadAfterRequests, hasLength(1));
    expect(messageSyncService.threadAfterRequests.single.afterServerSeq, '5');
  });

  test('历史加载中收到新的会话概览时会排队再补拉一次', () async {
    final firstReply = ChatMessage(
      localId: 'reply-old',
      remoteId: 'reply-old',
      threadId: conversation.threadId,
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
      threadId: conversation.threadId,
      senderDid: 'did:peer',
      senderName: 'Peer',
      receiverDid: 'did:me',
      content: '最新回复',
      createdAt: DateTime(2026, 5, 8, 10, 2),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    gateway
      ..fetchDmHistoryCompleter = Completer<void>()
      ..dmHistoryBatchesByPeerDid = <String, List<List<ChatMessage>>>{
        'did:peer': <List<ChatMessage>>[
          <ChatMessage>[firstReply],
          <ChatMessage>[firstReply, latestReply],
        ],
      };

    final firstLoad = container
        .read(chatThreadsProvider.notifier)
        .syncHistoryForConversation(conversation);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(chatThreadProvider(conversation.threadId)).isLoading,
      true,
    );

    await container
        .read(chatThreadsProvider.notifier)
        .syncHistoryForConversation(
          conversation.copyWith(
            lastMessagePreview: latestReply.content,
            lastMessageAt: latestReply.createdAt,
          ),
        );

    gateway.fetchDmHistoryCompleter!.complete();
    await firstLoad;
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.map((item) => item.content), contains('最新回复'));
    expect(gateway.fetchDmHistoryCalls, 2);
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
        .upsertConversation(
          conversation.copyWith(targetPeer: 'peer.anpclaw.com'),
        );

    await container
        .read(conversationListProvider.notifier)
        .deleteFromRecents(
          conversation.copyWith(targetPeer: 'peer.anpclaw.com'),
        );

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          conversation.copyWith(
            threadId: 'dm:peer-scope:peer',
            targetDid: null,
            targetPeer: 'peer.anpclaw.com',
            lastMessagePreview: '旧消息',
            lastMessageAt: conversation.lastMessageAt,
          ),
        );
    expect(container.read(conversationListProvider).conversations, isEmpty);

    container
        .read(conversationListProvider.notifier)
        .upsertConversation(
          conversation.copyWith(
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

  test('本地 DID 会话和刷新的 full handle 会话会合并为同一个智能体会话', () async {
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
    expect(conversations.single.threadId, 'dm:peer-scope:v1:runtime');
    expect(conversations.single.targetDid, agentDid);
    expect(conversations.single.targetPeer, agentHandle);
    expect(conversations.single.displayName, '改名后的智能体');
  });

  test('已读的同一目标会话刷新为 canonical thread 后不会重新变未读', () async {
    const agentDid = 'did:agent:runtime';
    const agentHandle = 'zhuocheng-test-hermes.anpclaw.com';
    final readConversation = ConversationSummary(
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

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(readConversation);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(conversationListProvider).conversations.single.unreadCount,
      0,
    );
    expect(gateway.lastMarkReadThreadId, 'dm:$agentDid');

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
        .single;
    expect(refreshed.threadId, 'dm:peer-scope:v1:zhuocheng-test-hermes');
    expect(refreshed.unreadCount, 0);
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
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(gateway.listConversationsCalls, 0);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(messages.map((item) => item.content), contains('第一条'));
    expect(messages.map((item) => item.content), contains('第二条'));
    expect(messages.map((item) => item.content), isNot(contains('批量回复')));
  });
}

class _ThrowingMarkReadGateway extends FakeAwikiGateway {
  @override
  Future<void> markRead(String threadId) {
    markReadCalls += 1;
    throw UnsupportedError('IM Core markThreadRead is not available yet');
  }
}

class _PatchMessagingService
    implements
        MessagingService,
        LocalHistoryMessagingService,
        ThreadPatchMessagingService {
  _PatchMessagingService({
    required this.localHistory,
    ThreadMessagePatch? repairPatch,
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
  ThreadMessagePatch repairPatch;
  final StreamController<ThreadMessagePatch> _patches =
      StreamController<ThreadMessagePatch>.broadcast();
  int repairCalls = 0;
  int? lastRepairLimit;
  int watchCalls = 0;
  int cancelledWatches = 0;

  void emitPatch(ThreadMessagePatch patch) {
    _patches.add(patch);
  }

  void emitError(Object error) {
    _patches.addError(error);
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
  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  }) async {
    repairCalls += 1;
    lastRepairLimit = limit;
    return repairPatch;
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
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? idempotencyKey,
  }) async {
    return _sentMessage(thread: thread, content: text);
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
