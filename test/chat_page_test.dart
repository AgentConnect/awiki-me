import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
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

  testWidgets('附件按钮会选择文件并发送附件消息', (tester) async {
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
    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentAttachment?.filename, 'report.pdf');
    expect(find.text('report.pdf'), findsOneWidget);
  });
}

String _dateLabel(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$month-$day';
}
