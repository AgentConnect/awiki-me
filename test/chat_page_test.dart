import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('macOS 聊天输入条保持发送能力', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:mac',
      displayName: 'Mac Agent',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1100, 760));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            conversation: conversation,
            embedded: true,
            macStyle: true,
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );

    expect(find.text('身份卡'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField), 'hello mac');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentContent, 'hello mac');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 窄聊天头部保留身份卡入口且不溢出', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:narrow',
      displayName: 'Very Long Mac Agent Conversation Name',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(360, 640));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            conversation: conversation,
            embedded: true,
            macStyle: true,
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.person_crop_square), findsOneWidget);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊头部不显示我的智能体标签', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'group:mac',
      displayName: '融资协作群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'group:mac',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1100, 760));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            conversation: conversation,
            embedded: true,
            macStyle: true,
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('我的智能体'), findsNothing);
    expect(find.text('安全协作中'), findsOneWidget);
    expect(find.text('身份卡'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 聊天头部刷新按钮会同步当前会话消息', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:refresh-button',
      displayName: 'Mac Agent',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final message = ChatMessage(
      localId: 'remote-refresh',
      remoteId: 'remote-refresh',
      threadId: conversation.threadId,
      senderDid: 'did:test:peer',
      content: 'synced message',
      createdAt: DateTime(2026, 4, 5, 12, 1),
      isMine: false,
      sendState: MessageSendState.sent,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:test:peer': <ChatMessage>[message],
    };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1100, 760));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            conversation: conversation,
            embedded: true,
            macStyle: true,
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-refresh-button')));
    await tester.pump();

    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(gateway.listConversationsCalls, 1);
    expect(gateway.fetchDmHistoryCalls, 1);
    expect(find.text('synced message'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('群聊标题优先显示已知群名称', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'group:did:test:group:funding',
      displayName: 'Group did:test:group:funding',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          groupProvider.overrideWith((ref) {
            final controller = GroupController(ref);
            controller.upsertGroup(
              GroupSummary(
                groupId: conversation.groupId!,
                name: '融资协作群',
                description: '',
                memberCount: 3,
                lastMessageAt: null,
              ),
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('funding'), findsNothing);
  });

  testWidgets('聊天输入框回车后直接发送消息', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:1',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentContent, 'hello');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('聊天窗口在会话列表刷新到新消息时补拉历史', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:refresh',
      displayName: 'cgw',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:cgw',
    );
    final reply = ChatMessage(
      localId: 'reply-cgw',
      remoteId: 'reply-cgw',
      threadId: conversation.threadId,
      senderDid: 'did:test:cgw',
      receiverDid: session.did,
      content: '你好。欢迎',
      createdAt: DateTime(2026, 5, 8, 12, 1),
      isMine: false,
      sendState: MessageSendState.sent,
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
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
        'did:test:cgw': <ChatMessage>[reply],
      };

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container.read(conversationListProvider.notifier).refresh();
    await tester.pump();

    expect(find.text('你好。欢迎'), findsOneWidget);
    expect(gateway.fetchDmHistoryCalls, 1);
  });

  testWidgets('消息发送失败时显示失败状态并可重试', (tester) async {
    final gateway = FakeAwikiGateway()..failNextSend = true;
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:failed',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('发送失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('发送失败'), findsNothing);
    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentContent, 'hello');
  });
}
