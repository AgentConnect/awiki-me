import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
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
}
