import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_agent_identity.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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

  testWidgets('macOS 聊天头部操作按钮使用一致的轻量样式', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:header-actions',
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
            onMacConversationInfoTap: () {},
            macIdentityPanelActive: true,
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final refreshIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chat-refresh-button')),
        matching: find.byIcon(CupertinoIcons.refresh),
      ),
    );
    final identityIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chat-identity-card-button')),
        matching: find.byIcon(CupertinoIcons.person_crop_square),
      ),
    );
    final infoIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chat-conversation-info-button')),
        matching: find.byIcon(CupertinoIcons.sidebar_right),
      ),
    );
    final identityLabel = tester.widget<Text>(find.text('身份卡'));

    expect(infoIcon.color, refreshIcon.color);
    expect(identityIcon.size, refreshIcon.size);
    expect(infoIcon.size, refreshIcon.size);
    expect(infoIcon.weight, refreshIcon.weight);
    expect(refreshIcon.weight, 500);
    expect(identityIcon.color, isNot(refreshIcon.color));
    expect(identityIcon.weight, greaterThan(refreshIcon.weight!));
    expect(identityLabel.style?.fontWeight, FontWeight.w600);

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
    expect(find.text('群聊信息'), findsOneWidget);
    expect(find.text('身份卡'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('普通直聊不会显示智能体标记', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:human-peer',
      displayName: '真人用户',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:human',
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

    expect(find.text('真人用户'), findsOneWidget);
    expect(find.text('我的智能体'), findsNothing);
    expect(find.text('智能体'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('公开 Profile 标记为 agent 时移动端头部显示智能体标记', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:remote-agent',
      displayName: '远端智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:remote-agent',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          peerIdentityServiceProvider.overrideWithValue(
            FakePeerIdentityService(
              identities: const <String, PeerAgentIdentity>{
                'did:test:remote-agent': PeerAgentIdentity.agent(
                  agentKind: PeerAgentKind.runtime,
                ),
              },
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('远端智能体'), findsOneWidget);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('我的智能体'), findsNothing);
    expect(find.byType(AvatarBadge), findsNothing);
    expect(find.text('关注'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('聊天头部关注按钮会把对方加入我关注的列表', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:follow-button',
      displayName: 'Peer',
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(gateway.lastFollowedDidOrHandle, 'did:test:peer');
    expect(find.text('已关注'), findsOneWidget);
  });

  testWidgets('聊天头部关注失败时保持未关注并提示错误', (tester) async {
    final gateway = FakeAwikiGateway()..failNextFollow = true;
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:follow-failed',
      displayName: 'Peer',
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(find.text('关注'), findsOneWidget);
    expect(find.text('已关注'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    expect(container.read(uiFeedbackProvider)?.danger, isTrue);
    expect(gateway.following, isEmpty);
  });

  testWidgets('聊天头部已关注按钮取消关注前需要确认', (tester) async {
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:peer',
          displayName: 'Peer',
          relationship: 'following',
        ),
      ];
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:unfollow-button',
      displayName: 'Peer',
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
        providerOverrides: <Override>[
          friendsProvider.overrideWith((ref) {
            final controller = FriendsController(ref);
            controller.state = const FriendsState(
              following: <RelationshipSummary>[
                RelationshipSummary(
                  did: 'did:test:peer',
                  displayName: 'Peer',
                  relationship: 'following',
                ),
              ],
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('已关注'));
    await tester.pump();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(gateway.lastUnfollowedDidOrHandle, isNull);

    await tester.tap(find.text('取消关注').last);
    await tester.pump();

    expect(gateway.lastUnfollowedDidOrHandle, 'did:test:peer');
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
                membershipStatus: 'active',
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

  testWidgets('已不在群聊时禁用发送输入区', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'group:did:test:group:removed',
      displayName: '历史群聊',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:removed',
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
                name: '历史群聊',
                description: '',
                memberCount: 3,
                lastMessageAt: null,
                myRole: 'member',
                membershipStatus: 'removed',
              ),
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你已不在这个群聊中，不能继续发送消息'), findsOneWidget);
    expect(find.byKey(const Key('chat-send-button')), findsNothing);
    expect(find.byKey(const Key('chat-attachment-button')), findsNothing);
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

  testWidgets('文本消息内容支持系统原生选中复制', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:selectable-text-message',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      conversation.targetDid!: <ChatMessage>[
        ChatMessage(
          localId: 'selectable-text-message',
          remoteId: 'selectable-text-message',
          threadId: conversation.threadId,
          senderDid: conversation.targetDid!,
          receiverDid: session.did,
          content: '这是一条可以复制的消息',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text('这是一条可以复制的消息'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('对方文本消息按 Markdown 渲染并保留可选中复制', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:incoming-markdown',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    const markdown = '**重点**\n\n- 第一项';
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      conversation.targetDid!: <ChatMessage>[
        ChatMessage(
          localId: 'incoming-markdown',
          remoteId: 'incoming-markdown',
          threadId: conversation.threadId,
          senderDid: conversation.targetDid!,
          receiverDid: session.did,
          content: markdown,
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.data, markdown);
    expect(body.selectable, isTrue);
  });

  testWidgets('自己发出的 Markdown 样式文本仍按普通文本显示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:outgoing-plain-markdown',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    const text = '**原样显示**';
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      conversation.targetDid!: <ChatMessage>[
        ChatMessage(
          localId: 'outgoing-plain-markdown',
          remoteId: 'outgoing-plain-markdown',
          threadId: conversation.threadId,
          senderDid: session.did,
          receiverDid: conversation.targetDid!,
          content: text,
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: true,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownBody), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text(text),
      ),
      findsOneWidget,
    );
  });

  testWidgets('群聊和 Agent 收到的消息都按 Markdown 渲染', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:incoming-markdown',
      displayName: 'Markdown 群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:incoming-markdown',
    );
    final agentConversation = ConversationSummary(
      threadId: 'dm:agent-markdown',
      displayName: '我的智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 1),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:agent',
    );
    const groupMarkdown = '## 群聊标题\n\n- 群聊事项';
    const agentMarkdown = '```text\nagent result\n```';
    gateway
      ..groupHistoryByGroupId = <String, List<ChatMessage>>{
        groupConversation.groupId!: <ChatMessage>[
          ChatMessage(
            localId: 'group-incoming-markdown',
            remoteId: 'group-incoming-markdown',
            threadId: groupConversation.threadId,
            senderDid: 'did:test:peer',
            groupId: groupConversation.groupId,
            content: groupMarkdown,
            createdAt: DateTime(2026, 4, 5, 12, 1),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        ],
      }
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        agentConversation.targetDid!: <ChatMessage>[
          ChatMessage(
            localId: 'agent-markdown',
            remoteId: 'agent-markdown',
            threadId: agentConversation.threadId,
            senderDid: agentConversation.targetDid!,
            receiverDid: session.did,
            content: agentMarkdown,
            createdAt: DateTime(2026, 4, 5, 12, 2),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        ],
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: groupConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(groupConversation);
    await tester.pumpAndSettle();

    var body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.data, groupMarkdown);
    expect(body.selectable, isTrue);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: agentConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(agentConversation);
    await tester.pumpAndSettle();

    body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.data, agentMarkdown);
    expect(body.selectable, isTrue);
  });

  testWidgets('发送给 Runtime Agent 后在对应消息下显示处理中提示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:agent-processing',
      displayName: '我的智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = const AgentsState(
              agents: <AgentSummary>[
                AgentSummary(
                  agentDid: 'did:agent:runtime',
                  kind: AgentKind.runtime,
                  daemonAgentDid: 'did:agent:daemon',
                  runtime: 'hermes',
                  displayName: '我的智能体',
                  activeState: 'active',
                  latest: AgentLatestStatus(status: 'ready'),
                ),
              ],
            );
            return controller;
          }),
        ],
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), '请总结');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('请总结'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-processing-reply',
            remoteId: 'agent-processing-reply',
            threadId: conversation.threadId,
            senderDid: 'did:agent:runtime',
            receiverDid: session.did,
            content: '总结完成',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('总结完成'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsNothing);
  });

  testWidgets('连续发送给 Runtime Agent 时每条消息独立显示处理中提示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:agent-processing-multiple',
      displayName: '我的智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = const AgentsState(
              agents: <AgentSummary>[
                AgentSummary(
                  agentDid: 'did:agent:runtime',
                  kind: AgentKind.runtime,
                  daemonAgentDid: 'did:agent:daemon',
                  runtime: 'hermes',
                  displayName: '我的智能体',
                  activeState: 'active',
                  latest: AgentLatestStatus(status: 'ready'),
                ),
              ],
            );
            return controller;
          }),
        ],
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), '第一个问题');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(CupertinoTextField), '第二个问题');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('第一个问题'), findsOneWidget);
    expect(find.text('第二个问题'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsNWidgets(2));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-processing-reply-a',
            remoteId: 'agent-processing-reply-a',
            threadId: conversation.threadId,
            senderDid: 'did:agent:runtime',
            receiverDid: session.did,
            content: '第一个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('第一个回答'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsOneWidget);

    container
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-processing-reply-a',
            remoteId: 'agent-processing-reply-a',
            threadId: conversation.threadId,
            senderDid: 'did:agent:runtime',
            receiverDid: session.did,
            content: '第一个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('智能体正在处理...'), findsOneWidget);

    container
        .read(chatThreadsProvider.notifier)
        .applyRealtimeUpdate(
          ChatMessage(
            localId: 'agent-processing-reply-b',
            remoteId: 'agent-processing-reply-b',
            threadId: conversation.threadId,
            senderDid: 'did:agent:runtime',
            receiverDid: session.did,
            content: '第二个回答',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('第二个回答'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsNothing);
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

  testWidgets('聊天窗口居中时间使用消息发送时间的本地时区显示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final utcSentAt = DateTime.utc(2026, 5, 23, 9);
    final localSentAt = utcSentAt.toLocal();
    final conversation = ConversationSummary(
      threadId: 'dm:local-time',
      displayName: 'Tester',
      lastMessagePreview: 'time check',
      lastMessageAt: localSentAt,
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final secondUtcSentAt = utcSentAt.add(const Duration(minutes: 31));
    final secondLocalSentAt = secondUtcSentAt.toLocal();
    final firstMessage = ChatMessage(
      localId: 'msg-local-time-1',
      remoteId: 'msg-local-time-1',
      threadId: conversation.threadId,
      senderDid: 'did:test:peer',
      receiverDid: session.did,
      content: 'time check',
      createdAt: utcSentAt,
      isMine: false,
      sendState: MessageSendState.sent,
    );
    final secondMessage = ChatMessage(
      localId: 'msg-local-time-2',
      remoteId: 'msg-local-time-2',
      threadId: conversation.threadId,
      senderDid: 'did:test:peer',
      receiverDid: session.did,
      content: 'time check again',
      createdAt: secondUtcSentAt,
      isMine: false,
      sendState: MessageSendState.sent,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:test:peer': <ChatMessage>[firstMessage, secondMessage],
    };
    gateway.conversations = <ConversationSummary>[conversation];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container.read(conversationListProvider.notifier).refresh();
    await tester.pumpAndSettle();

    final expectedTime =
        '${localSentAt.hour.toString().padLeft(2, '0')}:${localSentAt.minute.toString().padLeft(2, '0')}';
    expect(
      find.text('${_dateLabel(localSentAt)} $expectedTime'),
      findsOneWidget,
    );
    final secondExpectedTime =
        '${secondLocalSentAt.hour.toString().padLeft(2, '0')}:${secondLocalSentAt.minute.toString().padLeft(2, '0')}';
    expect(
      find.text('${_dateLabel(secondLocalSentAt)} $secondExpectedTime'),
      findsOneWidget,
    );
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

  testWidgets('附件按钮会先暂存附件，点击发送后再发送附件消息', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextPick = AttachmentDraft(
        filename: 'report.pdf',
        mimeType: 'application/pdf',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        sizeBytes: 3,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:attachment',
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
        providerOverrides: <Override>[
          attachmentPickerServiceProvider.overrideWithValue(picker),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();

    expect(picker.pickCalls, 1);
    expect(
      find.byKey(const Key('chat-pending-attachment-preview')),
      findsOneWidget,
    );
    expect(find.text('report.pdf'), findsOneWidget);
    expect(gateway.lastSentThreadId, isNull);
    expect(gateway.lastSentAttachment, isNull);

    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentAttachment?.filename, 'report.pdf');
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('选择附件后输入框保持焦点', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextPick = AttachmentDraft(
        filename: 'focus.md',
        mimeType: 'text/markdown',
        bytes: Uint8List.fromList(<int>[35]),
        sizeBytes: 1,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:attachment-focus',
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
        providerOverrides: <Override>[
          attachmentPickerServiceProvider.overrideWithValue(picker),
        ],
      ),
    );

    await tester.tap(find.byType(CupertinoTextField));
    await tester.pump();
    var input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(input.focusNode?.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();

    expect(find.text('focus.md'), findsOneWidget);
    input = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(input.focusNode?.hasFocus, isTrue);
  });

  testWidgets('macOS 选择附件后输入框保持焦点', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextPick = AttachmentDraft(
        filename: 'mac-focus.md',
        mimeType: 'text/markdown',
        bytes: Uint8List.fromList(<int>[35]),
        sizeBytes: 1,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:mac-attachment-focus',
      displayName: 'Tester',
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
        providerOverrides: <Override>[
          attachmentPickerServiceProvider.overrideWithValue(picker),
        ],
      ),
    );

    await tester.tap(find.byType(CupertinoTextField));
    await tester.pump();
    var input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(input.focusNode?.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();

    expect(find.text('mac-focus.md'), findsOneWidget);
    input = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(input.focusNode?.hasFocus, isTrue);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('暂存附件支持取消，取消后只发送文本', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextPick = AttachmentDraft(
        filename: 'draft.md',
        mimeType: 'text/markdown',
        bytes: Uint8List.fromList(<int>[35, 32, 65]),
        sizeBytes: 3,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:attachment-cancel',
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
        providerOverrides: <Override>[
          attachmentPickerServiceProvider.overrideWithValue(picker),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();
    expect(find.text('draft.md'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('chat-pending-attachment-remove-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('chat-pending-attachment-preview')),
      findsNothing,
    );

    await tester.enterText(find.byType(CupertinoTextField), 'only text');
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastSentAttachment, isNull);
    expect(gateway.lastSentContent, 'only text');
  });

  testWidgets('群聊暂存附件可附带输入文本一起发送', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextPick = AttachmentDraft(
        filename: 'diagram.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        sizeBytes: 4,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'group:attachment-compose',
      displayName: '项目群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:attachment-compose',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          attachmentPickerServiceProvider.overrideWithValue(picker),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '看这个图');
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastSentGroupId, conversation.groupId);
    expect(gateway.lastSentAttachment?.filename, 'diagram.png');
    expect(gateway.lastSentAttachmentCaption, '看这个图');
  });

  testWidgets('发送给 Runtime Agent 的暂存附件会显示处理中提示', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextPick = AttachmentDraft(
        filename: 'brief.md',
        mimeType: 'text/markdown',
        bytes: Uint8List.fromList(<int>[35, 32, 66]),
        sizeBytes: 3,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:agent-attachment-compose',
      displayName: '我的智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          attachmentPickerServiceProvider.overrideWithValue(picker),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = const AgentsState(
              agents: <AgentSummary>[
                AgentSummary(
                  agentDid: 'did:agent:runtime',
                  kind: AgentKind.runtime,
                  daemonAgentDid: 'did:agent:daemon',
                  runtime: 'hermes',
                  displayName: '我的智能体',
                  activeState: 'active',
                  latest: AgentLatestStatus(status: 'ready'),
                ),
              ],
            );
            return controller;
          }),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('chat-attachment-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '请阅读附件');
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(gateway.lastSentAttachment?.filename, 'brief.md');
    expect(gateway.lastSentAttachmentCaption, '请阅读附件');
    expect(find.text('智能体正在处理...'), findsOneWidget);
  });

  testWidgets('输入框支持 Shift+Enter 换行，Enter 发送', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:multiline-input',
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

    await tester.tap(find.byType(CupertinoTextField));
    await tester.enterText(find.byType(CupertinoTextField), '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(gateway.lastSentContent, isNull);
    var input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(input.controller?.text, '第一行\n');

    await tester.enterText(find.byType(CupertinoTextField), '第一行\n第二行');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(gateway.lastSentContent, '第一行\n第二行');
    expect(find.text('第一行\n第二行'), findsOneWidget);
  });

  testWidgets('输入法组合输入时 Enter 不触发发送', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:ime-composing',
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

    await tester.tap(find.byType(CupertinoTextField));
    await tester.enterText(find.byType(CupertinoTextField), 'ni');
    final input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    input.controller!.value = input.controller!.value.copyWith(
      composing: const TextRange(start: 0, end: 2),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(gateway.lastSentContent, isNull);
    expect(input.controller?.text, 'ni');
  });

  testWidgets('群聊左侧消息只在连续发送开头显示发送人 handle', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'group:sender-label',
      displayName: '项目群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:sender-label',
    );
    gateway.groupHistoryByGroupId = <String, List<ChatMessage>>{
      conversation.groupId!: <ChatMessage>[
        ChatMessage(
          localId: 'alice-1',
          remoteId: 'alice-1',
          threadId: conversation.threadId,
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          groupId: conversation.groupId,
          content: '第一条',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        ChatMessage(
          localId: 'alice-2',
          remoteId: 'alice-2',
          threadId: conversation.threadId,
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          groupId: conversation.groupId,
          content: '第二条',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        ChatMessage(
          localId: 'bob-1',
          remoteId: 'bob-1',
          threadId: conversation.threadId,
          senderDid: 'did:wba:awiki.ai:user:bob:e1_key',
          senderName: 'did:wba:awiki.ai:user:bob:e1_key',
          groupId: conversation.groupId,
          content: '第三条',
          createdAt: DateTime(2026, 4, 5, 12, 2),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        ChatMessage(
          localId: 'mine-1',
          remoteId: 'mine-1',
          threadId: conversation.threadId,
          senderDid: session.did,
          senderName: session.handle,
          groupId: conversation.groupId,
          content: '自己发一条',
          createdAt: DateTime(2026, 4, 5, 12, 3),
          isMine: true,
          sendState: MessageSendState.sent,
        ),
        ChatMessage(
          localId: 'alice-3',
          remoteId: 'alice-3',
          threadId: conversation.threadId,
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          groupId: conversation.groupId,
          content: '第四条',
          createdAt: DateTime(2026, 4, 5, 12, 4),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    expect(find.text('第三条'), findsOneWidget);
    expect(find.text('自己发一条'), findsOneWidget);
    expect(find.text('第四条'), findsOneWidget);
    expect(find.text('alice'), findsNWidgets(2));
    expect(find.text('bob'), findsOneWidget);
  });

  testWidgets('私聊和群聊附件消息有文本时显示柔和分隔线', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final dmConversation = ConversationSummary(
      threadId: 'dm:caption-attachment',
      displayName: 'Tester',
      lastMessagePreview: '请看这个文件',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:caption-attachment',
      displayName: '附件群',
      lastMessagePreview: '群里也发一个',
      lastMessageAt: DateTime(2026, 4, 5, 12, 1),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:caption-attachment',
    );
    final dmMessage = ChatMessage(
      localId: 'dm-caption-attachment',
      remoteId: 'dm-caption-attachment',
      threadId: dmConversation.threadId,
      senderDid: 'did:test:peer',
      content: '请看这个文件',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime(2026, 4, 5, 12, 0),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-dm',
        filename: 'brief.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 2048,
        caption: '请看这个文件',
      ),
    );
    final groupMessage = ChatMessage(
      localId: 'group-caption-attachment',
      remoteId: 'group-caption-attachment',
      threadId: groupConversation.threadId,
      senderDid: 'did:test:peer',
      groupId: groupConversation.groupId,
      content: '群里也发一个',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime(2026, 4, 5, 12, 1),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-group',
        filename: 'group-brief.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 4096,
        caption: '群里也发一个',
      ),
    );
    gateway
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:test:peer': <ChatMessage>[dmMessage],
      }
      ..groupHistoryByGroupId = <String, List<ChatMessage>>{
        groupConversation.groupId!: <ChatMessage>[groupMessage],
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: dmConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(dmConversation);
    await tester.pumpAndSettle();

    expect(find.text('请看这个文件'), findsOneWidget);
    expect(find.text('brief.pdf'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-attachment-caption-divider')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: groupConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final groupContainer = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await groupContainer
        .read(chatThreadsProvider.notifier)
        .openConversation(groupConversation);
    await tester.pumpAndSettle();

    expect(find.text('群里也发一个'), findsOneWidget);
    expect(find.text('group-brief.pdf'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-attachment-caption-divider')),
      findsOneWidget,
    );
  });

  testWidgets('附件说明和文件名支持系统原生选中复制', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:selectable-attachment',
      displayName: 'Tester',
      lastMessagePreview: '附件说明',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      conversation.targetDid!: <ChatMessage>[
        ChatMessage(
          localId: 'selectable-attachment',
          remoteId: 'selectable-attachment',
          threadId: conversation.threadId,
          senderDid: conversation.targetDid!,
          receiverDid: session.did,
          content: '附件说明',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
          originalType: 'application/anp-attachment-manifest+json',
          attachment: const ChatAttachment(
            attachmentId: 'att-selectable',
            filename: 'copyable-report.pdf',
            mimeType: 'application/pdf',
            sizeBytes: 2048,
            caption: '附件说明',
          ),
        ),
      ],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text('附件说明'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text('copyable-report.pdf'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('对方附件说明按 Markdown 渲染，文件名仍按普通文本复制', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:attachment-markdown-caption',
      displayName: 'Tester',
      lastMessagePreview: '附件说明',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    const caption = '**附件说明**';
    const filename = 'report_[draft].md';
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      conversation.targetDid!: <ChatMessage>[
        ChatMessage(
          localId: 'attachment-markdown-caption',
          remoteId: 'attachment-markdown-caption',
          threadId: conversation.threadId,
          senderDid: conversation.targetDid!,
          receiverDid: session.did,
          content: caption,
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
          originalType: 'application/anp-attachment-manifest+json',
          attachment: const ChatAttachment(
            attachmentId: 'att-markdown-caption',
            filename: filename,
            mimeType: 'text/markdown',
            sizeBytes: 2048,
            caption: caption,
          ),
        ),
      ],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.data, caption);
    expect(body.selectable, isTrue);
    expect(
      find.descendant(
        of: find.byType(SelectableText),
        matching: find.text(filename),
      ),
      findsOneWidget,
    );
  });

  testWidgets('已删除智能体会话保留历史但禁用发送', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:deleted-agent',
      displayName: '旧智能体',
      lastMessagePreview: '旧回复',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:deleted-runtime',
      peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      conversation.targetDid!: <ChatMessage>[
        ChatMessage(
          localId: 'deleted-agent-history',
          remoteId: 'deleted-agent-history',
          threadId: conversation.threadId,
          senderDid: conversation.targetDid!,
          receiverDid: session.did,
          content: '历史消息仍可查看',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(find.text('智能体已删除'), findsOneWidget);
    expect(find.text('智能体已删除，无法继续发送消息'), findsOneWidget);
    expect(find.text('历史消息仍可查看'), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNothing);
    expect(find.byKey(const Key('chat-attachment-button')), findsNothing);
    expect(find.byKey(const Key('chat-send-button')), findsNothing);
    expect(gateway.lastSentContent, isNull);
  });

  testWidgets('纯附件消息不显示文本附件分隔线', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:attachment-only',
      displayName: 'Tester',
      lastMessagePreview: '[附件] raw.pdf',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final message = ChatMessage(
      localId: 'attachment-only',
      remoteId: 'attachment-only',
      threadId: conversation.threadId,
      senderDid: 'did:test:peer',
      content: '',
      originalType: 'application/anp-attachment-manifest+json',
      createdAt: DateTime(2026, 4, 5, 12, 0),
      isMine: false,
      sendState: MessageSendState.sent,
      attachment: const ChatAttachment(
        attachmentId: 'att-only',
        filename: 'raw.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 1024,
      ),
    );
    gateway.dmHistoryByPeerDid = <String, List<ChatMessage>>{
      'did:test:peer': <ChatMessage>[message],
    };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(find.text('raw.pdf'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-attachment-caption-divider')),
      findsNothing,
    );
  });
}

String _dateLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month-$day';
}
