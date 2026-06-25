import 'dart:async';
import 'dart:typed_data';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
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
    container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(gateway),
      ],
    );
    addTearDown(container.dispose);
  });

  test('首次打开空线程时后台加载历史，不阻塞 openConversation', () async {
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);

    expect(gateway.fetchDmHistoryCalls, 1);
    expect(gateway.listConversationsCalls, 0);

    await Future<void>.delayed(Duration.zero);

    final thread = container.read(chatThreadProvider(conversation.threadId));
    expect(thread.messages, hasLength(1));
    expect(thread.isLoading, isFalse);
  });

  test('已加载线程再次打开不重复拉历史', () async {
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);

    expect(gateway.fetchDmHistoryCalls, 1);
    expect(gateway.listConversationsCalls, 0);
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

  test('发送后会同步历史以展示服务端快速返回的对方消息', () async {
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
    expect(
      messages.map((item) => item.content),
      containsAll(<String>['你好', '你好。欢迎']),
    );
    expect(gateway.fetchDmHistoryCalls, 1);
  });

  test('发送后刷新未返回当前会话时仍保留最近会话', () async {
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
    expect(gateway.listConversationsCalls, 1);
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

  test('发送后刷新返回旧概览时不会覆盖本地最新预览', () async {
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

    final latest = sendContainer
        .read(conversationListProvider)
        .conversations
        .single;
    expect(latest.lastMessagePreview, '正在处理的问题');
    expect(latest.lastMessageAt.isAfter(staleConversation.lastMessageAt), true);
    expect(gateway.listConversationsCalls, 1);
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
    expect(
      sendContainer
          .read(chatThreadProvider(realtimeConversation.threadId))
          .messages,
      isEmpty,
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

  test('历史回补会用服务端已发送消息替换同内容 pending', () async {
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
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[serverMessage],
    };
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
    await Future<void>.delayed(Duration.zero);

    final messages = container
        .read(chatThreadProvider(conversation.threadId))
        .messages;
    expect(messages.where((item) => item.content == '5'), hasLength(1));
    expect(messages.single.remoteId, 'remote-5');
    expect(messages.single.sendState, MessageSendState.sent);
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
    expect(thread.messages.single.attachment?.filename, 'report.pdf');
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

  test('附件发送成功后会话刷新失败不会覆盖发送结果', () async {
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
    expect(flakyGateway.listConversationsCalls, 1);
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

  test('会话列表已有新预览时再次打开会补拉历史', () async {
    final localOnly = ChatMessage(
      localId: 'sent-local',
      remoteId: 'sent-local',
      threadId: conversation.threadId,
      senderDid: 'did:me',
      receiverDid: 'did:peer',
      content: '你好',
      createdAt: DateTime(2026, 5, 8, 10, 0),
      isMine: true,
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
      sendState: MessageSendState.sent,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:peer': <ChatMessage>[localOnly, reply],
    };
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
    expect(gateway.fetchDmHistoryCalls, 1);
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

  test('刷新最近会话失败时保留现有列表并退出加载态', () async {
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
    gateway.failNextListConversations = true;

    await expectLater(
      container.read(conversationListProvider.notifier).refresh(),
      throwsA(isA<StateError>()),
    );

    final state = container.read(conversationListProvider);
    expect(state.isLoading, isFalse);
    expect(state.conversations, hasLength(1));
    expect(state.conversations.single.threadId, conversation.threadId);
  });

  test('刷新最近会话请求卡住时超时退出加载态并保留现有列表', () async {
    final timeoutGateway = FakeAwikiGateway()
      ..listConversationsCompleter = Completer<List<ConversationSummary>>();
    final timeoutContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(timeoutGateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(timeoutGateway),
        conversationListProvider.overrideWith(
          (ref) => ConversationListController(
            ref,
            refreshTimeout: const Duration(milliseconds: 1),
          ),
        ),
      ],
    );
    addTearDown(timeoutContainer.dispose);
    timeoutContainer
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:me',
            credentialName: 'me.json',
            displayName: 'Me',
            handle: 'me',
          ),
        );
    timeoutContainer
        .read(conversationListProvider.notifier)
        .upsertConversation(conversation);

    await expectLater(
      timeoutContainer.read(conversationListProvider.notifier).refresh(),
      throwsA(isA<TimeoutException>()),
    );

    final state = timeoutContainer.read(conversationListProvider);
    expect(state.isLoading, isFalse);
    expect(state.conversations, hasLength(1));
    expect(state.conversations.single.threadId, conversation.threadId);
    expect(timeoutGateway.listConversationsCalls, 1);
  });

  test('最近会话 ensureLoaded 在空列表时触发一次加载并复用进行中的请求', () async {
    final loadingGateway = FakeAwikiGateway()
      ..listConversationsCompleter = Completer<List<ConversationSummary>>();
    final loadingContainer = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(loadingGateway),
        notificationFacadeProvider.overrideWithValue(notificationFacade),
        ...fakeApplicationServiceOverrides(loadingGateway),
      ],
    );
    addTearDown(loadingContainer.dispose);
    loadingContainer
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:me',
            credentialName: 'me.json',
            displayName: 'Me',
            handle: 'me',
          ),
        );

    final firstLoad = loadingContainer
        .read(conversationListProvider.notifier)
        .ensureLoaded();
    final secondLoad = loadingContainer
        .read(conversationListProvider.notifier)
        .ensureLoaded();

    await Future<void>.delayed(Duration.zero);
    expect(loadingContainer.read(conversationListProvider).isLoading, isTrue);
    expect(loadingGateway.listConversationsCalls, 1);

    loadingGateway.listConversationsCompleter!.complete(<ConversationSummary>[
      conversation,
    ]);
    await Future.wait(<Future<void>>[firstLoad, secondLoad]);

    final state = loadingContainer.read(conversationListProvider);
    expect(state.isLoading, isFalse);
    expect(state.conversations.single.threadId, conversation.threadId);
    expect(loadingGateway.listConversationsCalls, 1);
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
    expect(gateway.lastDeletedLocalThreadId, 'direct:did:peer');
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
}

class _ThrowingMarkReadGateway extends FakeAwikiGateway {
  @override
  Future<void> markRead(String threadId) {
    markReadCalls += 1;
    throw UnsupportedError('IM Core markThreadRead is not available yet');
  }
}
