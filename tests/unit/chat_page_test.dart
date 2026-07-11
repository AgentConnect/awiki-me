// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/attachment_open_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/domain/entities/chat_attachment.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_agent_identity.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_list_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show FontWeight, InlineSpan, RichText, SelectionArea, TextSpan;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

Uint8List _tinyPngBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR42mP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC',
);

Widget _testImageWidgetBuilder({
  String? path,
  Uint8List? bytes,
  double? width,
  double? height,
  required BoxFit fit,
  required Widget errorFallback,
}) {
  return SizedBox(
    width: width ?? 120,
    height: height ?? 80,
    child: const ColoredBox(color: Color(0xFF0B65F8)),
  );
}

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> conversations,
  ) {
    state = ConversationListState(conversations: conversations);
  }

  void replaceConversations(List<ConversationSummary> conversations) {
    state = ConversationListState(conversations: conversations);
  }
}

class _StaticChatThreadsController extends ChatThreadsController {
  _StaticChatThreadsController(
    super.ref,
    Map<String, List<ChatMessage>> messagesByThread,
  ) {
    state = <String, ChatThreadState>{
      for (final entry in messagesByThread.entries)
        entry.key: ChatThreadState(threadId: entry.key, messages: entry.value),
    };
  }

  final List<String> visibleThreadIds = <String>[];
  final List<String> hiddenThreadIds = <String>[];

  @override
  void markConversationVisible(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) {
    visibleThreadIds.add(displayThreadId ?? conversation.threadId);
    super.markConversationVisible(
      conversation,
      displayThreadId: displayThreadId,
    );
  }

  @override
  void markConversationHidden(
    ConversationSummary conversation, {
    String? displayThreadId,
  }) {
    hiddenThreadIds.add(displayThreadId ?? conversation.threadId);
    super.markConversationHidden(
      conversation,
      displayThreadId: displayThreadId,
    );
  }
}

class _DelayedProfileApplicationService implements ProfileApplicationService {
  _DelayedProfileApplicationService(this.completer);

  final Completer<UserProfile> completer;
  int loadPublicProfileCalls = 0;
  String? lastPublicProfileQuery;

  @override
  Future<UserProfile> loadMyProfile() {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    loadPublicProfileCalls += 1;
    lastPublicProfileQuery = didOrHandle;
    return completer.future;
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

class _RecordingAttachmentOpenService extends AttachmentOpenService {
  final openedPaths = <String>[];
  Object? nextError;

  @override
  Future<void> open(String pathOrUri) async {
    openedPaths.add(pathOrUri);
    final error = nextError;
    if (error != null) {
      throw error;
    }
  }
}

Finder _chatMessagesListFinder() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is ListView &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith('chat-messages:'),
  );
}

ScrollableState _chatScrollable(WidgetTester tester) {
  return tester.state<ScrollableState>(
    find.descendant(
      of: _chatMessagesListFinder(),
      matching: find.byType(Scrollable),
    ),
  );
}

double _chatScrollPixels(WidgetTester tester) {
  return _chatScrollable(tester).position.pixels;
}

double _chatScrollMax(WidgetTester tester) {
  return _chatScrollable(tester).position.maxScrollExtent;
}

double _messageContentBottomGap(WidgetTester tester, String localId) {
  final listRect = tester.getRect(_chatMessagesListFinder());
  final messageRect = tester.getRect(
    find.byKey(Key('chat-message-content:$localId')),
  );
  return listRect.bottom - messageRect.bottom;
}

double _expectedMessageContentBottomGap(WidgetTester tester) {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  return width < 720 ? 12 : 12 * 0.74;
}

Future<void> _sendDesktopDropMethod(String method, Object? arguments) async {
  unawaited(
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'desktop_drop',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        ),
  );
  await Future<void>.value();
}

List<ChatMessage> _scrollMessages({
  required String threadId,
  required String peerDid,
  required DateTime startedAt,
  required int count,
}) {
  return <ChatMessage>[
    for (var index = 0; index < count; index += 1)
      ChatMessage(
        localId: '$threadId-msg-$index',
        remoteId: '$threadId-msg-$index',
        threadId: threadId,
        senderDid: peerDid,
        receiverDid: 'did:test:me',
        content:
            'message $index ${'long content '.padRight(90, '${index % 10}')}',
        createdAt: startedAt.add(Duration(minutes: index)),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
  ];
}

void main() {
  testWidgets('ChatView migrates pending direct alias to peer-scoped thread', (
    tester,
  ) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    const agentDid = 'did:agent:runtime:hermes';
    const agentHandle = 'hermes.awiki.example';
    final pendingAlias = ConversationSummary(
      threadId: 'dm:pending:$agentHandle',
      displayName: 'Hermes',
      lastMessagePreview: '在吗？',
      lastMessageAt: DateTime(2026, 7, 3, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final runtimeConversation = pendingAlias.copyWith(
      threadId: 'dm:peer-scope:v1:hermes-runtime',
      lastMessagePreview: '在的',
      lastMessageAt: DateTime(2026, 7, 3, 12, 1),
      unreadCount: 1,
    );
    final pendingMessage = ChatMessage(
      localId: 'pending-only',
      remoteId: 'pending-only',
      threadId: pendingAlias.threadId,
      senderDid: session.did,
      receiverDid: agentDid,
      content: 'partial pending',
      createdAt: pendingAlias.lastMessageAt,
      isMine: true,
      sendState: MessageSendState.sent,
    );
    final runtimeMessage = ChatMessage(
      localId: 'runtime-reply',
      remoteId: 'runtime-reply',
      threadId: runtimeConversation.threadId,
      senderDid: agentDid,
      receiverDid: session.did,
      content: '完整回复',
      createdAt: runtimeConversation.lastMessageAt,
      isMine: false,
      sendState: MessageSendState.sent,
    );
    late _StaticConversationListController listController;
    late _StaticChatThreadsController chatController;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: pendingAlias, embedded: false),
        ),
        gateway: FakeAwikiGateway(),
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith((ref) {
            listController = _StaticConversationListController(
              ref,
              <ConversationSummary>[pendingAlias],
            );
            return listController;
          }),
          chatThreadsProvider.overrideWith((ref) {
            chatController = _StaticChatThreadsController(
              ref,
              <String, List<ChatMessage>>{
                pendingAlias.threadId: <ChatMessage>[pendingMessage],
                runtimeConversation.threadId: <ChatMessage>[runtimeMessage],
              },
            );
            return chatController;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('partial pending'), findsOneWidget);
    expect(find.text('完整回复'), findsNothing);

    listController.replaceConversations(<ConversationSummary>[
      runtimeConversation,
    ]);
    await tester.pumpAndSettle();

    expect(find.text('partial pending'), findsNothing);
    expect(find.text('完整回复'), findsOneWidget);
    expect(chatController.hiddenThreadIds, contains(pendingAlias.threadId));
    expect(
      chatController.visibleThreadIds,
      contains(runtimeConversation.threadId),
    );
  });

  testWidgets('macOS 聊天输入条保持发送能力', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
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
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.text('身份卡'), findsNothing);

    await tester.enterText(find.byType(CupertinoTextField), 'hello mac');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentContent, 'hello mac');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 窄聊天头部不显示信息入口且不溢出', (tester) async {
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

    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.byIcon(CupertinoIcons.person_crop_square), findsNothing);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 聊天头部不显示信息入口按钮', (tester) async {
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
          ),
        ),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-refresh-button')), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.text('身份卡'), findsNothing);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('群聊信息'), findsNothing);

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
    expect(find.text('群聊信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

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
    expect(find.text('关注'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('聊天头像信息弹窗先展示基础信息，profile 返回后补齐资料', (tester) async {
    final profileCompleter = Completer<UserProfile>();
    final profileService = _DelayedProfileApplicationService(profileCompleter);
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:delayed-profile',
      displayName: '本地智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:slow-agent',
    );
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:test:slow-agent',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:test:daemon',
          runtime: 'slow-agent',
          displayName: '本地智能体',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        homepageMarkdownLoader: (_) async => null,
        providerOverrides: <Override>[
          profileApplicationServiceProvider.overrideWithValue(profileService),
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pump();

    expect(profileService.loadPublicProfileCalls, 1);
    expect(profileService.lastPublicProfileQuery, 'did:test:slow-agent');
    expect(find.text('智能体信息'), findsOneWidget);
    expect(find.text('本地智能体'), findsWidgets);
    expect(find.byKey(const Key('peer-info-dialog-did-value')), findsOneWidget);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('资料加载中'), findsOneWidget);
    expect(find.text('正在加载资料…'), findsOneWidget);
    expect(find.text('profile 加载完成后的介绍'), findsNothing);

    const resolvedDid =
        'did:wba:awiki.ai:profile-agent:e1_abcdefghijklmnopqrstuvwxyz0123456789';
    profileCompleter.complete(
      const UserProfile(
        did: resolvedDid,
        nickName: 'Profile Agent',
        bio: 'profile 加载完成后的介绍',
        tags: <String>['agent'],
        profileMarkdown:
            '我的短号(handle)：profile-agent.awiki.ai\n\nDID: $resolvedDid\n\nprofile 加载完成后的介绍',
        handle: 'profile-agent',
        fullHandle: 'profile-agent.awiki.ai',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Profile Agent'), findsOneWidget);
    expect(find.text('profile 加载完成后的介绍'), findsOneWidget);
    expect(find.text('@profile-agent.awiki.ai'), findsOneWidget);
    final didText = tester.widget<Text>(
      find.byKey(const Key('peer-info-dialog-did-value')),
    );
    expect(didText.data, contains('…'));
    expect(didText.data, isNot(resolvedDid));
    expect(
      find.byKey(const Key('peer-info-dialog-copy-did-button')),
      findsOneWidget,
    );
    expect(find.text('我的短号(handle)：profile-agent.awiki.ai'), findsNothing);
    expect(find.text('DID: $resolvedDid'), findsNothing);
    expect(find.text('资料加载中'), findsNothing);
  });

  testWidgets('聊天头部关注按钮会把对方加入我关注的列表', (tester) async {
    final gateway = FakeAwikiGateway()
      ..publicProfile = const UserProfile(
        did: 'did:test:peer',
        nickName: 'Peer',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
      );
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

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('peer-info-close-button')), findsOneWidget);
    expect(find.byKey(const Key('chat-follow-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-follow-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastFollowedDidOrHandle, 'did:test:peer');
    expect(find.text('已关注'), findsOneWidget);
    expect(find.byKey(const Key('chat-unfollow-button')), findsOneWidget);
  });

  testWidgets('聊天头部关注失败时保持未关注并提示错误', (tester) async {
    final gateway = FakeAwikiGateway()
      ..failNextFollow = true
      ..publicProfile = const UserProfile(
        did: 'did:test:peer',
        nickName: 'Peer',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
      );
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

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-follow-button')));
    await tester.pumpAndSettle();

    expect(find.text('关注'), findsOneWidget);
    expect(find.text('已关注'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    expect(container.read(uiFeedbackProvider)?.danger, isTrue);
    expect(gateway.following, isEmpty);
  });

  testWidgets('智能体信息弹窗支持修改当前智能体名称', (tester) async {
    final gateway = FakeAwikiGateway()
      ..publicProfile = const UserProfile(
        did: 'did:agent:runtime',
        nickName: 'Hermes Profile',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'hermes.anpclaw.com',
        fullHandle: 'hermes.anpclaw.com',
      );
    final control = FakeAgentControlService()
      ..agents = <AgentSummary>[
        const AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: 'Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        const AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          handle: 'hermes',
          displayName: '我的智能体',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:rename-runtime-agent',
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
          agentControlServiceProvider.overrideWithValue(control),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = AgentsState(agents: control.agents);
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();

    expect(find.text('智能体信息'), findsOneWidget);
    expect(find.text('我的智能体'), findsWidgets);
    expect(
      find.byKey(const Key('peer-info-agent-rename-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('peer-info-agent-rename-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('agent-rename-field')),
      '更新后的智能体',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(control.lastRenamedAgentDid, 'did:agent:runtime');
    expect(control.lastDisplayName, '更新后的智能体');
    expect(find.text('更新后的智能体'), findsOneWidget);
  });

  testWidgets('聊天头部已关注按钮取消关注前需要确认', (tester) async {
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:peer',
          displayName: 'Peer',
          relationship: 'following',
        ),
      ]
      ..publicProfile = const UserProfile(
        did: 'did:test:peer',
        nickName: 'Peer',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
      );
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

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-unfollow-button')));
    await tester.pump();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(gateway.lastUnfollowedDidOrHandle, isNull);

    expect(find.byKey(const Key('confirm-unfollow-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-unfollow-button')));
    await tester.pump();

    expect(gateway.lastUnfollowedDidOrHandle, 'did:test:peer');
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

  testWidgets('打开空历史直聊时显示可发送的空会话', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:empty-peer',
      threadId: 'dm:empty-history',
      displayName: 'Empty Peer',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:empty-peer',
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(gateway.fetchDmHistoryCalls, 0);
    expect(find.text('Empty Peer'), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byKey(const Key('chat-send-button')), findsOneWidget);
    expect(find.textContaining('发送失败'), findsNothing);
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
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:1',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pumpAndSettle();

    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentContent, 'hello');
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('进入长对话时最后一条消息贴到消息列表底部', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:scroll-bottom-gap',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final messages = _scrollMessages(
      threadId: conversation.threadId,
      peerDid: 'did:test:alice',
      startedAt: DateTime(2026, 4, 5, 10),
      count: 28,
    );

    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            key: ValueKey('chat-view:${conversation.threadId}'),
            conversation: conversation,
            embedded: false,
          ),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith(
            (ref) => _StaticChatThreadsController(
              ref,
              <String, List<ChatMessage>>{conversation.threadId: messages},
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));
    expect(
      _messageContentBottomGap(tester, messages.last.localId),
      moreOrLessEquals(_expectedMessageContentBottomGap(tester), epsilon: 1),
    );
  });

  testWidgets('自己发送消息后即使原本离开底部也会滚到底部', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:alice',
      threadId: 'dm:scroll-send',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final messages = _scrollMessages(
      threadId: conversation.effectiveConversationId,
      peerDid: 'did:test:alice',
      startedAt: DateTime(2026, 4, 5, 10),
      count: 28,
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            key: ValueKey('chat-view:${conversation.threadId}'),
            conversation: conversation,
            embedded: false,
          ),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith(
            (ref) =>
                _StaticChatThreadsController(ref, <String, List<ChatMessage>>{
                  conversation.effectiveConversationId: messages,
                }),
          ),
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(_chatMessagesListFinder(), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(_chatScrollPixels(tester), lessThan(_chatScrollMax(tester) - 96));

    await tester.enterText(find.byType(CupertinoTextField), 'my new message');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pumpAndSettle();

    expect(gateway.lastSentContent, 'my new message');
    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));
  });

  testWidgets('ChatView 挂载切换和卸载会更新会话可见性', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversationA = ConversationSummary(
      threadId: 'dm:visible-a',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final conversationB = ConversationSummary(
      threadId: 'dm:visible-b',
      displayName: 'Bob',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:bob',
    );
    late _StaticChatThreadsController controller;
    late StateSetter setHostState;
    var currentConversation = conversationA;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return CupertinoPageScaffold(
              child: ChatView(
                key: const ValueKey<String>('chat-view-visibility-lifecycle'),
                conversation: currentConversation,
                embedded: false,
              ),
            );
          },
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith((ref) {
            controller = _StaticChatThreadsController(
              ref,
              const <String, List<ChatMessage>>{},
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.visibleThreadIds, <String>[conversationA.threadId]);
    expect(controller.hiddenThreadIds, isEmpty);

    setHostState(() {
      currentConversation = conversationB;
    });
    await tester.pumpAndSettle();

    expect(controller.visibleThreadIds, <String>[
      conversationA.threadId,
      conversationB.threadId,
    ]);
    expect(controller.hiddenThreadIds, <String>[conversationA.threadId]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(controller.hiddenThreadIds, <String>[
      conversationA.threadId,
      conversationB.threadId,
    ]);
  });

  testWidgets('ChatView switches when thread changes even if target is same', (
    tester,
  ) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversationA = ConversationSummary(
      threadId: 'dm:peer-scope:v1:controller',
      displayName: 'Agent Controller',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 3, 7, 9),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:agent',
      targetPeer: 'agent.awiki.ai',
    );
    final conversationB = ConversationSummary(
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Agent Runtime',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 3, 7, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:agent',
      targetPeer: 'agent.awiki.ai',
    );
    late _StaticChatThreadsController controller;
    late StateSetter setHostState;
    var currentConversation = conversationA;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return CupertinoPageScaffold(
              child: ChatView(
                key: const ValueKey<String>('chat-view-same-target-switch'),
                conversation: currentConversation,
                embedded: false,
              ),
            );
          },
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith((ref) {
            controller = _StaticChatThreadsController(
              ref,
              const <String, List<ChatMessage>>{},
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    setHostState(() {
      currentConversation = conversationB;
    });
    await tester.pumpAndSettle();

    expect(controller.visibleThreadIds, <String>[
      conversationA.threadId,
      conversationB.threadId,
    ]);
    expect(controller.hiddenThreadIds, <String>[conversationA.threadId]);
  });

  testWidgets('ChatView 保持打开时的显示线程不被最近会话归一化切换', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final openedConversation = ConversationSummary(
      threadId: 'dm:did:test:me:did:agent:runtime',
      displayName: 'Runtime raw',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
      targetPeer: 'did:agent:runtime',
    );
    final normalizedConversation = openedConversation.copyWith(
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Runtime normalized',
      targetPeer: 'runtime.anpclaw.com',
    );
    final reply = ChatMessage(
      localId: 'reply-opened-thread',
      remoteId: 'reply-opened-thread',
      threadId: openedConversation.threadId,
      senderDid: 'did:agent:runtime',
      receiverDid: session.did,
      content: 'opened thread message',
      createdAt: openedConversation.lastMessageAt,
      isMine: false,
      sendState: MessageSendState.sent,
    );
    late _StaticConversationListController conversationListController;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: openedConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith((ref) {
            conversationListController = _StaticConversationListController(
              ref,
              <ConversationSummary>[openedConversation],
            );
            return conversationListController;
          }),
          chatThreadsProvider.overrideWith(
            (ref) =>
                _StaticChatThreadsController(ref, <String, List<ChatMessage>>{
                  openedConversation.threadId: <ChatMessage>[reply],
                  normalizedConversation.threadId: const <ChatMessage>[],
                }),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>(
          'chat-messages:dm:did:test:me:did:agent:runtime',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('opened thread message'), findsOneWidget);

    conversationListController.replaceConversations(<ConversationSummary>[
      normalizedConversation,
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Runtime normalized'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey<String>(
          'chat-messages:dm:did:test:me:did:agent:runtime',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('chat-messages:dm:peer-scope:v1:runtime'),
      ),
      findsNothing,
    );
    expect(find.text('opened thread message'), findsOneWidget);
  });

  testWidgets('切换会话后保留各自输入草稿并在发送后清空', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversationA = ConversationSummary(
      conversationId: 'dm:did:test:alice',
      threadId: 'dm:draft-a',
      displayName: 'Alice',
      lastMessagePreview: 'alice old preview',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final conversationB = ConversationSummary(
      conversationId: 'dm:did:test:bob',
      threadId: 'dm:draft-b',
      displayName: 'Bob',
      lastMessagePreview: 'bob old preview',
      lastMessageAt: DateTime(2026, 4, 5, 12, 1),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:bob',
    );
    var selected = conversationA;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return CupertinoPageScaffold(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CupertinoButton(
                        key: const Key('open-draft-a'),
                        onPressed: () {
                          setState(() {
                            selected = conversationA;
                          });
                        },
                        child: const Text('Alice'),
                      ),
                      CupertinoButton(
                        key: const Key('open-draft-b'),
                        onPressed: () {
                          setState(() {
                            selected = conversationB;
                          });
                        },
                        child: const Text('Bob'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ChatView(conversation: selected, embedded: false),
                  ),
                ],
              ),
            );
          },
        ),
        gateway: gateway,
        session: session,
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), 'draft for alice');
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-draft-b')));
    await tester.pumpAndSettle();

    var input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(input.controller?.text, isEmpty);

    await tester.enterText(find.byType(CupertinoTextField), 'draft for bob');
    await tester.pump();

    await tester.tap(find.byKey(const Key('open-draft-a')));
    await tester.pumpAndSettle();

    input = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(input.controller?.text, 'draft for alice');

    await tester.tap(find.byKey(const Key('open-draft-b')));
    await tester.pumpAndSettle();

    input = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(input.controller?.text, 'draft for bob');

    await tester.tap(find.byKey(const Key('open-draft-a')));
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(gateway.lastSentThreadId, 'dm:did:test:alice');
    expect(gateway.lastSentContent, 'draft for alice');
    input = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(input.controller?.text, isEmpty);

    await tester.tap(find.byKey(const Key('open-draft-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-draft-a')));
    await tester.pumpAndSettle();

    input = tester.widget<CupertinoTextField>(find.byType(CupertinoTextField));
    expect(input.controller?.text, isEmpty);
  });

  testWidgets('切换会话时消息列表默认滚动到底部且不串用滚动位置', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversationA = ConversationSummary(
      threadId: 'dm:scroll-a',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final conversationB = ConversationSummary(
      threadId: 'dm:scroll-b',
      displayName: 'Bob',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 13),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:bob',
    );
    final messagesA = _scrollMessages(
      threadId: conversationA.threadId,
      peerDid: 'did:test:alice',
      startedAt: DateTime(2026, 4, 5, 10),
      count: 28,
    );
    final messagesB = _scrollMessages(
      threadId: conversationB.threadId,
      peerDid: 'did:test:bob',
      startedAt: DateTime(2026, 4, 5, 11),
      count: 28,
    );
    var selected = conversationA;

    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return CupertinoPageScaffold(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CupertinoButton(
                        key: const Key('open-scroll-a'),
                        onPressed: () {
                          setState(() => selected = conversationA);
                        },
                        child: const Text('Alice'),
                      ),
                      CupertinoButton(
                        key: const Key('open-scroll-b'),
                        onPressed: () {
                          setState(() => selected = conversationB);
                        },
                        child: const Text('Bob'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ChatView(
                      key: ValueKey('chat-view:${selected.threadId}'),
                      conversation: selected,
                      embedded: false,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith(
            (ref) =>
                _StaticChatThreadsController(ref, <String, List<ChatMessage>>{
                  conversationA.threadId: messagesA,
                  conversationB.threadId: messagesB,
                }),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));

    await tester.drag(_chatMessagesListFinder(), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(_chatScrollPixels(tester), lessThan(_chatScrollMax(tester) - 96));

    await tester.tap(find.byKey(const Key('open-scroll-b')));
    await tester.pump();

    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));

    await tester.pumpAndSettle();

    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));

    await tester.drag(_chatMessagesListFinder(), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(_chatScrollPixels(tester), lessThan(_chatScrollMax(tester) - 96));

    await tester.tap(find.byKey(const Key('open-scroll-a')));
    await tester.pump();

    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));

    await tester.pumpAndSettle();

    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));
  });

  testWidgets('打开会话后异步加载首批消息时直接锚定底部', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:alice',
      threadId: 'dm:scroll-async-open',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final messages = _scrollMessages(
      threadId: conversation.threadId,
      peerDid: 'did:test:alice',
      startedAt: DateTime(2026, 4, 5, 10),
      count: 28,
    );
    gateway.localDmHistoryByPeerDid = <String, List<ChatMessage>>{
      conversation.targetDid!: messages,
    };
    gateway.fetchLocalDmHistoryCompleter = Completer<void>();
    late ChatThreadsController controller;

    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            key: ValueKey('chat-view:${conversation.threadId}'),
            conversation: conversation,
            embedded: false,
          ),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith((ref) {
            controller = ChatThreadsController(ref);
            return controller;
          }),
        ],
      ),
    );
    await controller.openConversation(conversation);
    await tester.pump();

    expect(find.textContaining('message 27'), findsNothing);

    gateway.fetchLocalDmHistoryCompleter!.complete();
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('message 27'), findsOneWidget);
    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));
    expect(
      _messageContentBottomGap(tester, messages.last.localId),
      moreOrLessEquals(_expectedMessageContentBottomGap(tester), epsilon: 1),
    );
  });

  testWidgets('用户离开底部时收到新消息不强拉并显示回到底部入口', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:scroll-new-message',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final messages = _scrollMessages(
      threadId: conversation.threadId,
      peerDid: 'did:test:alice',
      startedAt: DateTime(2026, 4, 5, 10),
      count: 28,
    );

    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            key: ValueKey('chat-view:${conversation.threadId}'),
            conversation: conversation,
            embedded: false,
          ),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith(
            (ref) => _StaticChatThreadsController(
              ref,
              <String, List<ChatMessage>>{conversation.threadId: messages},
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(_chatMessagesListFinder(), const Offset(0, 420));
    await tester.pumpAndSettle();
    final beforeIncoming = _chatScrollPixels(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'incoming-while-reading',
            remoteId: 'incoming-while-reading',
            threadId: conversation.threadId,
            senderDid: 'did:test:alice',
            receiverDid: session.did,
            content: 'new message while reading',
            createdAt: DateTime(2026, 4, 5, 12, 30),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(_chatScrollPixels(tester), moreOrLessEquals(beforeIncoming));
    expect(find.byKey(const Key('chat-new-messages-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-new-messages-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat-new-messages-button')), findsNothing);
    expect(_chatScrollPixels(tester), moreOrLessEquals(_chatScrollMax(tester)));
  });

  testWidgets('ChatView 已在底部时收到新消息会推进持久已读水位', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:alice',
      threadId: 'dm:visible-new-message',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    final messages = _scrollMessages(
      threadId: conversation.effectiveConversationId,
      peerDid: 'did:test:alice',
      startedAt: DateTime(2026, 4, 5, 10),
      count: 6,
    );

    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(
            key: ValueKey('chat-view:${conversation.threadId}'),
            conversation: conversation,
            embedded: false,
          ),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith(
            (ref) =>
                _StaticChatThreadsController(ref, <String, List<ChatMessage>>{
                  conversation.effectiveConversationId: messages,
                }),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final initialMarkReadCalls = gateway.markReadCalls;

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'incoming-while-visible',
            remoteId: 'incoming-while-visible',
            conversationId: conversation.effectiveConversationId,
            threadId: conversation.effectiveConversationId,
            senderDid: 'did:test:alice',
            receiverDid: session.did,
            content: 'new message while visible',
            createdAt: DateTime(2026, 4, 5, 12, 30),
            isMine: false,
            serverSequence: 42,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump();
    await tester.pump();

    expect(gateway.markReadCalls, initialMarkReadCalls);

    container
        .read(chatThreadsProvider.notifier)
        .acknowledgeVisibleConversationRead(
          conversation,
          displayThreadId: conversation.effectiveConversationId,
          forcePersistentAck: true,
        );
    await tester.pump();
    await tester.pump();

    expect(gateway.markReadCalls, initialMarkReadCalls);
    expect(gateway.markConversationReadCalls, greaterThanOrEqualTo(1));
    expect(
      gateway.lastMarkConversationReadConversationId,
      conversation.effectiveConversationId,
    );
  });

  testWidgets('最近会话列表显示未发送草稿预览并在草稿清空后恢复原预览', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:draft-preview',
      displayName: 'Alice',
      lastMessagePreview: 'alice old preview',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    gateway.conversations = <ConversationSummary>[conversation];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(embedded: true, bottomInset: 0),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice old preview'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListPage)),
    );
    container
        .read(chatComposerDraftsProvider.notifier)
        .setText(conversation, '**draft** [for alice](https://example.com)');
    await tester.pump();

    expect(find.text('草稿'), findsOneWidget);
    expect(find.text('draft for alice'), findsOneWidget);
    expect(
      find.text('**draft** [for alice](https://example.com)'),
      findsNothing,
    );
    expect(find.text('alice old preview'), findsNothing);

    container
        .read(chatComposerDraftsProvider.notifier)
        .clearDraft(conversation);
    await tester.pump();

    expect(find.text('草稿'), findsNothing);
    expect(find.text('draft for alice'), findsNothing);
    expect(find.text('alice old preview'), findsOneWidget);
  });

  testWidgets('最近会话按未读、草稿、消息时间稳定排序', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final base = DateTime(2026, 4, 5, 12);
    final unread = ConversationSummary(
      threadId: 'dm:sort-unread',
      displayName: 'Unread',
      lastMessagePreview: 'unread old preview',
      lastMessageAt: base.subtract(const Duration(minutes: 20)),
      unreadCount: 1,
      isGroup: false,
      targetDid: 'did:test:unread',
    );
    final draft = ConversationSummary(
      threadId: 'dm:sort-draft',
      displayName: 'Draft',
      lastMessagePreview: 'draft old preview',
      lastMessageAt: base.subtract(const Duration(minutes: 10)),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:draft',
    );
    final read = ConversationSummary(
      threadId: 'dm:sort-read',
      displayName: 'Read',
      lastMessagePreview: 'read latest preview',
      lastMessageAt: base,
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:read',
    );
    gateway.conversations = <ConversationSummary>[read, draft, unread];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(embedded: true, bottomInset: 0),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListPage)),
    );
    container
        .read(chatComposerDraftsProvider.notifier)
        .setText(draft, 'draft content');
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Unread')).dy,
      lessThan(tester.getTopLeft(find.text('Draft')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Draft')).dy,
      lessThan(tester.getTopLeft(find.text('Read')).dy),
    );

    container.read(chatComposerDraftsProvider.notifier).clearDraft(draft);
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Unread')).dy,
      lessThan(tester.getTopLeft(find.text('Read')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Read')).dy,
      lessThan(tester.getTopLeft(find.text('Draft')).dy),
    );
  });

  testWidgets('peer-scoped 最近会话草稿预览只显示在同一线程', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    const agentDid = 'did:wba:awiki.ai:agent:runtime:test';
    const agentHandle = 'test-agent.awiki.ai';
    final controllerConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:controller',
      displayName: 'Controller',
      lastMessagePreview: 'controller old preview',
      lastMessageAt: DateTime(2026, 7, 3, 7, 9),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final runtimeConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Runtime Agent',
      lastMessagePreview: 'runtime old preview',
      lastMessageAt: DateTime(2026, 7, 3, 7, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    gateway.conversations = <ConversationSummary>[
      runtimeConversation,
      controllerConversation,
    ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(embedded: true, bottomInset: 0),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListPage)),
    );
    container
        .read(chatComposerDraftsProvider.notifier)
        .setText(runtimeConversation, 'runtime draft');
    await tester.pump();

    expect(find.text('runtime draft'), findsOneWidget);
    expect(find.text('controller old preview'), findsOneWidget);
    expect(find.text('runtime old preview'), findsNothing);
  });

  testWidgets('最近会话预览按未读、@我、草稿、文本的顺序展示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:preview-tags',
      displayName: 'Alice',
      lastMessagePreview: 'alice mentioned me',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 3,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: 'msg-mention',
      isGroup: false,
      targetDid: 'did:test:alice',
    );
    gateway.conversations = <ConversationSummary>[conversation];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(embedded: true, bottomInset: 0),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListPage)),
    );
    container
        .read(chatComposerDraftsProvider.notifier)
        .setText(conversation, 'draft reply');
    await tester.pump();

    expect(
      find.byKey(const Key('conversation-row-unread-badge')),
      findsNothing,
    );
    expect(find.text('未读 3'), findsOneWidget);
    expect(find.text('@我'), findsOneWidget);
    expect(find.text('草稿'), findsOneWidget);
    expect(find.text('draft reply'), findsOneWidget);

    final unreadLeft = tester.getTopLeft(find.text('未读 3')).dx;
    final mentionLeft = tester.getTopLeft(find.text('@我')).dx;
    final draftLeft = tester.getTopLeft(find.text('草稿')).dx;
    final previewLeft = tester.getTopLeft(find.text('draft reply')).dx;
    expect(unreadLeft, lessThan(mentionLeft));
    expect(mentionLeft, lessThan(draftLeft));
    expect(draftLeft, lessThan(previewLeft));
  });

  testWidgets('发送中消息只在气泡左侧显示转圈标志且发送按钮保持禁用样式', (tester) async {
    final sendCompleter = Completer<void>();
    final gateway = FakeAwikiGateway()
      ..sendTextMessageCompleter = sendCompleter;
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:sending-inline-status',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), 'pending hello');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('pending hello'), findsNothing);
    expect(find.text('发送中...'), findsNothing);
    expect(gateway.sendTextMessageCalls, 1);
    final sendButton = find.byKey(const Key('chat-send-button'));
    expect(
      find.descendant(
        of: sendButton,
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsNothing,
    );

    await tester.tap(sendButton);
    await tester.pump(const Duration(milliseconds: 50));

    expect(gateway.sendTextMessageCalls, 1);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);

    sendCompleter.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('发送中消息等待三秒才显示状态且明确结果后立即隐藏', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:delayed-sending-status',
      displayName: 'Tester',
      lastMessagePreview: 'pending hello',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final sending = ChatMessage(
      localId: 'delayed-sending-message',
      remoteId: 'delayed-sending-message',
      conversationId: conversation.effectiveConversationId,
      threadId: conversation.effectiveConversationId,
      senderDid: session.did,
      receiverDid: conversation.targetDid,
      content: 'pending hello',
      createdAt: DateTime.now(),
      isMine: true,
      sendState: MessageSendState.sending,
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith(
            (ref) =>
                _StaticChatThreadsController(ref, <String, List<ChatMessage>>{
                  conversation.effectiveConversationId: <ChatMessage>[sending],
                }),
          ),
        ],
      ),
    );
    await tester.pump();

    final indicator = find.byKey(
      const Key('chat-sending-indicator:delayed-sending-message'),
    );
    expect(find.text('pending hello'), findsOneWidget);
    expect(indicator, findsNothing);

    await tester.pump(const Duration(milliseconds: 2999));
    expect(indicator, findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(indicator, findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          sending.copyWith(sendState: MessageSendState.sent),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump();

    expect(indicator, findsNothing);
    expect(find.text('发送失败'), findsNothing);
  });

  testWidgets('发送给 Runtime Agent 时投递完成后才显示处理中提示', (tester) async {
    final gateway = FakeAwikiGateway()
      ..sendDelay = const Duration(milliseconds: 80);
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:agent-send-before-processing',
      displayName: '我的智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
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
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('请总结'), findsNothing);
    expect(find.text('发送中...'), findsNothing);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text('智能体正在处理...'), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('智能体正在处理...'), findsOneWidget);
  });

  testWidgets('发送给远端 Agent 私聊时显示处理中提示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:wba:awiki.info:agent:runtime:hermes:e1_agent',
      threadId: 'dm:remote-agent-processing',
      displayName: '远端智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:wba:awiki.info:agent:runtime:hermes:e1_agent',
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), '请处理');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('请处理'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsOneWidget);

    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'remote-agent-reply',
            remoteId: 'remote-agent-reply',
            conversationId: conversation.effectiveConversationId,
            threadId: conversation.effectiveConversationId,
            senderDid: conversation.targetDid!,
            receiverDid: session.did,
            content: '处理完成',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('处理完成'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsNothing);
  });

  testWidgets('发送给普通用户私聊时不显示智能体处理中提示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:wba:awiki.info:user:bob',
      threadId: 'dm:human-no-agent-processing',
      displayName: '普通用户',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:wba:awiki.info:user:bob',
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );

    await tester.enterText(find.byType(CupertinoTextField), '你好');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('你好'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsNothing);
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
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:selectable-text-message',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final messagingService = _messagingServiceWithConversationMessages(
      gateway,
      conversation,
      <ChatMessage>[
        ChatMessage(
          localId: 'selectable-text-message',
          remoteId: 'selectable-text-message',
          threadId: conversation.effectiveConversationId,
          senderDid: conversation.targetDid!,
          receiverDid: session.did,
          content: '这是一条可以复制的消息',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsWidgets);
    expect(
      find.byKey(const Key('chat-message-content:selectable-text-message')),
      findsOneWidget,
    );
    expect(find.text('这是一条可以复制的消息'), findsOneWidget);
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
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:incoming-markdown',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    const markdown = '**重点**\n\n- 第一项';
    final messagingService = _messagingServiceWithConversationMessages(
      gateway,
      conversation,
      <ChatMessage>[
        ChatMessage(
          localId: 'incoming-markdown',
          remoteId: 'incoming-markdown',
          threadId: conversation.effectiveConversationId,
          senderDid: conversation.targetDid!,
          receiverDid: session.did,
          content: markdown,
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
      ],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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
    expect(body.selectable, isFalse);
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
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:outgoing-plain-markdown',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    const text = '**原样显示**';
    final messagingService = _messagingServiceWithConversationMessages(
      gateway,
      conversation,
      <ChatMessage>[
        ChatMessage(
          localId: 'outgoing-plain-markdown',
          remoteId: 'outgoing-plain-markdown',
          threadId: conversation.effectiveConversationId,
          senderDid: session.did,
          receiverDid: conversation.targetDid!,
          content: text,
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: true,
          sendState: MessageSendState.sent,
        ),
      ],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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
    expect(find.text(text), findsOneWidget);
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
      conversationId: 'group:did:test:group:incoming-markdown',
      threadId: 'group:incoming-markdown',
      displayName: 'Markdown 群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:incoming-markdown',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:test:agent',
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
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[groupConversation.effectiveConversationId] =
          <ChatMessage>[
            _messageWithConversation(
              ChatMessage(
                localId: 'group-incoming-markdown',
                remoteId: 'group-incoming-markdown',
                threadId: groupConversation.effectiveConversationId,
                senderDid: 'did:test:peer',
                groupId: groupConversation.groupId,
                content: groupMarkdown,
                createdAt: DateTime(2026, 4, 5, 12, 1),
                isMine: false,
                sendState: MessageSendState.sent,
              ),
              groupConversation,
            ),
          ]
      ..conversationTimelineById[agentConversation.effectiveConversationId] =
          <ChatMessage>[
            _messageWithConversation(
              ChatMessage(
                localId: 'agent-markdown',
                remoteId: 'agent-markdown',
                threadId: agentConversation.effectiveConversationId,
                senderDid: agentConversation.targetDid!,
                receiverDid: session.did,
                content: agentMarkdown,
                createdAt: DateTime(2026, 4, 5, 12, 2),
                isMine: false,
                sendState: MessageSendState.sent,
              ),
              agentConversation,
            ),
          ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: groupConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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
    expect(body.selectable, isFalse);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: agentConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    final agentContainer = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await agentContainer
        .read(chatThreadsProvider.notifier)
        .openConversation(agentConversation);
    await tester.pumpAndSettle();

    body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.data, agentMarkdown);
    expect(body.selectable, isFalse);
  });

  testWidgets('群聊收到带 mention 的 Markdown 消息仍按 Markdown 渲染', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'group:did:test:group:mention-markdown',
      threadId: 'group:mention-markdown',
      displayName: 'Markdown 群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:mention-markdown',
    );
    const text = '@Alice **重点**\n\n- 第一项';
    final messagingService = _messagingServiceWithConversationMessages(
      gateway,
      conversation,
      <ChatMessage>[
        ChatMessage(
          localId: 'group-mention-markdown',
          remoteId: 'group-mention-markdown',
          threadId: conversation.effectiveConversationId,
          senderDid: 'did:test:peer',
          senderName: 'Bob',
          groupId: conversation.groupId,
          content: text,
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
          mentions: const <ChatMessageMention>[
            ChatMessageMention(
              id: 'mention-alice',
              surface: '@Alice',
              start: 0,
              end: 6,
              target: ChatMentionTargetDraft.member(
                kind: ChatMentionTargetKind.human,
                did: 'did:test:alice',
                handle: 'alice',
                displayName: 'Alice',
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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
    expect(body.selectable, isFalse);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            _textSpanHasStyledMention(widget.text, '@Alice'),
      ),
      findsOneWidget,
    );
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
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:agent-processing',
      displayName: '我的智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('请总结'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsOneWidget);

    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-processing-reply',
            remoteId: 'agent-processing-reply',
            conversationId: conversation.effectiveConversationId,
            threadId: conversation.effectiveConversationId,
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

  testWidgets('群聊 @Agent 后在对应消息下显示 handle 处理中提示', (tester) async {
    final gateway = FakeAwikiGateway()
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        'did:test:group:agent-processing': const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:wba:awiki.info:agent:runtime:hermes:e1_agent',
            did: 'did:wba:awiki.info:agent:runtime:hermes:e1_agent',
            handle: 'hermes',
            role: 'member',
            displayName: 'Hermes Agent',
            subjectType: GroupMemberSubjectType.agent,
          ),
        ],
      };
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'group:did:test:group:agent-processing',
      threadId: 'group:did:test:group:agent-processing',
      displayName: 'Agent 群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:agent-processing',
    );
    gateway.nextSentMessageId = 'msg_group_agent_processing_1';
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );

    await tester.enterText(find.byType(CupertinoTextField), '@h');
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('@hermes'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField), '@hermes 请总结');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('@hermes 请总结'), findsOneWidget);
    expect(find.text('@hermes 正在处理...'), findsOneWidget);

    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'group-agent-processing-reply',
            remoteId: 'group-agent-processing-reply',
            conversationId: conversation.effectiveConversationId,
            threadId: conversation.effectiveConversationId,
            senderDid: 'did:wba:awiki.info:agent:runtime:hermes:e1_agent',
            groupId: conversation.groupId,
            content: '@me **总结完成**',
            originalType: 'application/json',
            payloadJson:
                '{"text":"@me **总结完成**","mentions":[{"id":"reply_me","range":{"start":0,"end":3,"unit":"unicode_code_point"},"target":{"kind":"human","did":"did:test:me"},"mention_role":"addressee"}],"annotations":{"awiki_reply_to_message_id":"msg_group_agent_processing_1"}}',
            createdAt: DateTime.now(),
            isMine: false,
            sendState: MessageSendState.sent,
          ),
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && _textSpanHasStyledMention(widget.text, '@me'),
      ),
      findsOneWidget,
    );
    expect(find.text('@hermes 正在处理...'), findsNothing);
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
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:agent-processing-multiple',
      displayName: '我的智能体',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final messagingService = FakeMessagingService(gateway);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(CupertinoTextField), '第二个问题');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          _latestProjectedConversationMessage(messagingService, conversation),
          threadId: conversation.effectiveConversationId,
        );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('第一个问题'), findsOneWidget);
    expect(find.text('第二个问题'), findsOneWidget);
    expect(find.text('智能体正在处理...'), findsNWidgets(2));

    container
        .read(chatThreadsProvider.notifier)
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-processing-reply-a',
            remoteId: 'agent-processing-reply-a',
            conversationId: conversation.effectiveConversationId,
            threadId: conversation.effectiveConversationId,
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
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-processing-reply-a',
            remoteId: 'agent-processing-reply-a',
            conversationId: conversation.effectiveConversationId,
            threadId: conversation.effectiveConversationId,
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
        .debugSeedMessageForTesting(
          ChatMessage(
            localId: 'agent-processing-reply-b',
            remoteId: 'agent-processing-reply-b',
            conversationId: conversation.effectiveConversationId,
            threadId: conversation.effectiveConversationId,
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

  testWidgets('聊天窗口在会话列表刷新到新消息摘要时不清未读不补拉历史', (tester) async {
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
    await tester.pumpAndSettle();

    expect(find.text('你好。欢迎'), findsNothing);
    expect(gateway.fetchDmHistoryCalls, 0);
    // 只有列表摘要更新、消息正文尚未进入当前线程时，不应无水位上报已读；
    // 等 realtime/thread-after/local history 带来可见消息后再携带 watermark ack。
    expect(gateway.markReadCalls, 0);
    expect(
      container.read(conversationListProvider).conversations.single.unreadCount,
      1,
    );
  });

  testWidgets('聊天窗口在会话列表切换为 canonical thread 后不反向补拉历史', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    const agentDid = 'did:test:agent';
    const agentHandle = 'hermes-test.anpclaw.com';
    final openedConversation = ConversationSummary(
      threadId: 'dm:${session.did}:$agentDid',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 8, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentDid,
    );
    final canonicalConversation = ConversationSummary(
      threadId: 'dm:peer-scope:v1:hermes-test',
      displayName: 'Hermes',
      lastMessagePreview: '我在。',
      lastMessageAt: DateTime(2026, 5, 8, 12, 1),
      unreadCount: 1,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final reply = ChatMessage(
      localId: 'reply-agent-canonical',
      remoteId: 'reply-agent-canonical',
      threadId: canonicalConversation.threadId,
      senderDid: agentDid,
      receiverDid: session.did,
      content: '我在。',
      createdAt: canonicalConversation.lastMessageAt,
      isMine: false,
      sendState: MessageSendState.sent,
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: openedConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
      ),
    );

    gateway
      ..conversations = <ConversationSummary>[canonicalConversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        agentHandle: <ChatMessage>[reply],
      };

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container.read(conversationListProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('我在。'), findsNothing);
    expect(gateway.fetchDmHistoryCalls, 0);
    expect(
      container.read(chatThreadProvider(openedConversation.threadId)).messages,
      isEmpty,
    );
    expect(
      container
          .read(chatThreadProvider(canonicalConversation.threadId))
          .messages,
      isEmpty,
    );
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
      conversationId: 'dm:did:test:peer',
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
    final firstMessage = _messageWithConversation(
      ChatMessage(
        localId: 'msg-local-time-1',
        remoteId: 'msg-local-time-1',
        threadId: conversation.effectiveConversationId,
        senderDid: 'did:test:peer',
        receiverDid: session.did,
        content: 'time check',
        createdAt: utcSentAt,
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversation,
    );
    final secondMessage = _messageWithConversation(
      ChatMessage(
        localId: 'msg-local-time-2',
        remoteId: 'msg-local-time-2',
        threadId: conversation.effectiveConversationId,
        senderDid: 'did:test:peer',
        receiverDid: session.did,
        content: 'time check again',
        createdAt: secondUtcSentAt,
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversation,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[firstMessage, secondMessage];
    gateway.conversations = <ConversationSummary>[conversation];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
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

  testWidgets('文本发送失败不创建旧内存失败气泡', (tester) async {
    final gateway = FakeAwikiGateway()..failNextSend = true;
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
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

    expect(find.text('发送失败'), findsNothing);
    expect(find.text('重试'), findsNothing);
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
      conversationId: 'dm:did:test:peer',
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    final messaging =
        container.read(messagingServiceProvider) as FakeMessagingService;
    expect(messaging.sendConversationAttachmentCalls, 1);
    expect(
      messaging.lastAttachmentConversation?.conversationId,
      conversation.effectiveConversationId,
    );
    expect(gateway.lastSentThreadId, 'dm:did:test:peer');
    expect(gateway.lastSentAttachment?.filename, 'report.pdf');
    expect(find.text('report.pdf'), findsOneWidget);
  });

  testWidgets('emoji 面板把表情插入当前选区并可发送', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:emoji',
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
    await tester.enterText(find.byType(CupertinoTextField), 'hello world');
    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    field.controller!.selection = const TextSelection(
      baseOffset: 6,
      extentOffset: 11,
    );

    await tester.tap(find.byKey(const Key('chat-emoji-button')));
    await tester.pump();
    expect(find.byKey(const Key('chat-emoji-picker')), findsOneWidget);

    await tester.tap(_chatMessagesListFinder());
    await tester.pump();
    expect(find.byKey(const Key('chat-emoji-picker')), findsNothing);

    await tester.tap(find.byKey(const Key('chat-emoji-button')));
    await tester.pump();
    expect(find.byKey(const Key('chat-emoji-picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-emoji-option:0')));
    await tester.pump();

    expect(field.controller!.text, 'hello 😀');
    expect(field.controller!.selection.baseOffset, 'hello 😀'.length);
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();
    expect(gateway.lastSentContent, 'hello 😀');
  });

  testWidgets('收到的小图片自动下载并在消息气泡内直接显示', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:inline-image',
      displayName: 'Tester',
      lastMessagePreview: '[图片]',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final message = _messageWithConversation(
      ChatMessage(
        localId: 'inline-image',
        remoteId: 'inline-image',
        threadId: conversation.effectiveConversationId,
        senderDid: conversation.targetDid!,
        receiverDid: session.did,
        content: '',
        createdAt: DateTime(2026, 4, 5, 12, 1),
        isMine: false,
        sendState: MessageSendState.sent,
        originalType: 'application/anp-attachment-manifest+json',
        attachment: const ChatAttachment(
          attachmentId: 'att-inline-image',
          filename: 'photo.png',
          mimeType: 'image/png',
          sizeBytes: 128,
          localPath: null,
        ),
      ),
      conversation,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[message]
      ..nextAttachmentDownloadResult = AttachmentDownloadResult(
        attachmentId: 'att-inline-image',
        filename: 'photo.png',
        mimeType: 'image/png',
        sizeBytes: _tinyPngBytes().length,
        bytes: _tinyPngBytes(),
      );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
          chatImageWidgetBuilderProvider.overrideWithValue(
            _testImageWidgetBuilder,
          ),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(messagingService.downloadAttachmentCalls, 1);
    expect(
      find.byKey(const Key('chat-inline-image:inline-image')),
      findsOneWidget,
    );
    expect(find.text('photo.png'), findsNothing);
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

  testWidgets('拖拽文件到聊天窗口会暂存为附件草稿', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextExternalDraft = AttachmentDraft(
        filename: 'drop-image.png',
        mimeType: 'image/png',
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
      conversationId: 'dm:did:test:drop-peer',
      threadId: 'dm:drop-attachment',
      displayName: 'Drop Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 9, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:drop-peer',
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

    final dropTarget = find.byKey(
      Key(
        'chat-attachment-drop-target:${conversation.effectiveConversationId}',
      ),
    );
    final center = tester.getCenter(dropTarget);
    await _sendDesktopDropMethod('entered', <double>[center.dx, center.dy]);
    await _sendDesktopDropMethod('updated', <double>[center.dx, center.dy]);
    await tester.pump();

    expect(
      find.byKey(const Key('chat-attachment-drop-overlay')),
      findsOneWidget,
    );

    await _sendDesktopDropMethod('performOperation_web', <Map<String, Object?>>[
      <String, Object?>{
        'uri': '',
        'children': <Map<String, Object?>>[],
        'data': Uint8List.fromList(<int>[1, 2, 3]),
        'name': 'drop-image.png',
        'type': 'image/png',
        'size': 3,
        'relativePath': null,
        'lastModified': DateTime(2026, 7, 9).millisecondsSinceEpoch,
      },
    ]);
    await tester.pump();

    expect(picker.externalSourceCalls, 1);
    expect(picker.lastExternalPath, isNull);
    expect(picker.lastExternalFilename, isNull);
    expect(picker.lastExternalMimeType, 'image/png');
    expect(picker.lastExternalBytes, Uint8List.fromList(<int>[1, 2, 3]));
    expect(find.text('drop-image.png'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-pending-attachment-preview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('chat-attachment-drop-overlay')), findsNothing);
    expect(gateway.lastSentAttachment, isNull);
  });

  testWidgets('输入框 Cmd/Ctrl+V 可把剪贴板图片暂存为附件', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextClipboardAttachment = AttachmentDraft(
        filename: 'pasted-image.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[9, 8, 7]),
        sizeBytes: 3,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:paste-peer',
      threadId: 'dm:paste-attachment',
      displayName: 'Paste Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 9, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:paste-peer',
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
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();

    expect(picker.clipboardReadCalls, 1);
    expect(find.text('pasted-image.png'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-pending-attachment-preview')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(CupertinoTextField), '图片说明');
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastSentAttachment?.filename, 'pasted-image.png');
    expect(gateway.lastSentAttachmentCaption, '图片说明');
  });

  testWidgets('输入框粘贴纯文本时不被附件粘贴逻辑吞掉', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': 'plain text'};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:text-paste-peer',
      threadId: 'dm:text-paste',
      displayName: 'Text Paste Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 9, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:text-paste-peer',
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
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(picker.clipboardReadCalls, 1);
    expect(input.controller?.text, 'plain text');
    expect(
      find.byKey(const Key('chat-pending-attachment-preview')),
      findsNothing,
    );
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

  testWidgets('macOS 截图按钮把系统截图暂存为图片附件', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextScreenshot = AttachmentDraft(
        filename: 'screenshot-test.png',
        mimeType: 'image/png',
        bytes: _tinyPngBytes(),
        sizeBytes: _tinyPngBytes().length,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:mac-screenshot',
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
          chatImageWidgetBuilderProvider.overrideWithValue(
            _testImageWidgetBuilder,
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('chat-screenshot-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat-screenshot-button')));
    await tester.pumpAndSettle();

    expect(picker.screenshotCalls, 1);
    expect(picker.lastScreenshotHideApp, isFalse);
    expect(find.text('screenshot-test.png'), findsOneWidget);
    expect(find.byKey(const Key('chat-pending-image-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('chat-pending-attachment-preview')),
      findsOneWidget,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const Key('chat-screenshot-button')));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(picker.screenshotCalls, 2);
    expect(picker.lastScreenshotHideApp, isTrue);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 输入框使用上层文字和下层紧凑工具栏', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:mac-composer-layout',
      displayName: 'Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12),
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

    final textRect = tester.getRect(find.byType(CupertinoTextField));
    final toolRowRect = tester.getRect(
      find.byKey(const Key('chat-composer-tool-row')),
    );
    expect(toolRowRect.top, greaterThanOrEqualTo(textRect.bottom));
    for (final key in const <String>[
      'chat-attachment-button',
      'chat-emoji-button',
      'chat-screenshot-button',
    ]) {
      final size = tester.getSize(find.byKey(Key(key)));
      expect(size.width, lessThan(30));
      expect(size.height, lessThan(30));
    }

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
      conversationId: 'dm:did:test:peer',
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
    await tester.pump();
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
      conversationId: 'group:did:test:group:attachment-compose',
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    final messaging =
        container.read(messagingServiceProvider) as FakeMessagingService;
    expect(messaging.sendConversationAttachmentCalls, 1);
    expect(
      messaging.lastAttachmentConversation?.conversationId,
      conversation.effectiveConversationId,
    );
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

  testWidgets('群聊暂存附件 caption 中 @智能体会发送结构化 mention 并显示处理中', (tester) async {
    final gateway = FakeAwikiGateway();
    final picker = FakeAttachmentPickerService()
      ..nextPick = AttachmentDraft(
        filename: 'report.md',
        mimeType: 'text/markdown',
        bytes: Uint8List.fromList(<int>[35, 32, 82]),
        sizeBytes: 3,
      );
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'group:did:test:group:agent-attachment-compose',
      threadId: 'group:agent-attachment-compose',
      displayName: '项目群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:agent-attachment-compose',
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
    await tester.enterText(find.byType(CupertinoTextField), '@codex 看看这个文件');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    container
        .read(chatComposerDraftsProvider.notifier)
        .setDraft(
          conversation,
          const ChatComposerDraft(
            text: '@codex 看看这个文件',
            mentions: <ChatMentionDraft>[
              ChatMentionDraft(
                localId: 'men_codex',
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
          ),
        );
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat-send-button')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(gateway.lastSentGroupId, conversation.groupId);
    expect(gateway.lastSentAttachment?.filename, 'report.md');
    expect(gateway.lastSentAttachmentCaption, '@codex 看看这个文件');
    expect(find.text('@codex 看看这个文件'), findsOneWidget);
    final thread = container.read(
      chatThreadProvider(conversation.effectiveConversationId),
    );
    expect(thread.pendingAgentReplyCount, 1);
    expect(thread.agentPendingTurns.single.agentDid, 'did:agent:codex');
    expect(find.text('@codex 正在处理...'), findsOneWidget);
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
      conversationId: 'dm:did:test:peer',
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
    expect(find.text('第一行\n第二行'), findsNothing);
  });

  testWidgets('离开长会话时延迟裁剪缓存且不重建已销毁页面', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:cache-dispose',
      displayName: 'Cache Tester',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final messages = _scrollMessages(
      threadId: conversation.effectiveConversationId,
      peerDid: 'did:test:peer',
      startedAt: DateTime(2026, 4, 5, 12, 0),
      count: 8,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          messages;
    late ChatThreadsController controller;
    final showChat = ValueNotifier<bool>(true);
    addTearDown(showChat.dispose);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: showChat,
          builder: (context, visible, _) {
            return CupertinoPageScaffold(
              child: visible
                  ? ChatView(conversation: conversation, embedded: false)
                  : const SizedBox.shrink(),
            );
          },
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
          chatThreadsProvider.overrideWith((ref) {
            controller = ChatThreadsController(
              ref,
              cachePolicy: const ThreadMemoryCachePolicy(
                hotThreadMessageLimit: 8,
                warmThreadMessageLimit: 2,
                coldThreadMessageLimit: 1,
                maxTotalCachedMessages: 50,
                maxCachedCanonicalThreads: 50,
              ),
            );
            return controller;
          }),
        ],
      ),
    );
    await controller.openConversation(conversation);
    await tester.pumpAndSettle();

    expect(
      controller.thread(conversation.effectiveConversationId).messages.length,
      greaterThanOrEqualTo(8),
    );

    showChat.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(tester.takeException(), isNull);
    expect(
      controller.thread(conversation.effectiveConversationId).messages.length,
      lessThanOrEqualTo(2),
    );
    expect(controller.debugCacheStats().trimmedMessageCount, greaterThan(0));
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

  testWidgets('输入法组合输入时发送按钮保持高亮但不会发送', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      threadId: 'dm:ime-composing-send-button',
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
    await tester.pump();
    var sendIcon = tester.widget<AwikiAssetIcon>(
      find.descendant(
        of: find.byKey(const Key('chat-send-button')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AwikiAssetIcon &&
              widget.assetName == 'assets/icons/icon_send.svg',
        ),
      ),
    );
    expect(sendIcon.color, const Color(0xFF0B65F8));

    final input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    input.controller!.value = input.controller!.value.copyWith(
      composing: const TextRange(start: 0, end: 2),
    );
    await tester.pump();

    sendIcon = tester.widget<AwikiAssetIcon>(
      find.descendant(
        of: find.byKey(const Key('chat-send-button')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AwikiAssetIcon &&
              widget.assetName == 'assets/icons/icon_send.svg',
        ),
      ),
    );
    expect(sendIcon.color, const Color(0xFF0B65F8));

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
      conversationId: 'group:did:test:group:sender-label',
      threadId: 'group:sender-label',
      displayName: '项目群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:sender-label',
    );
    final messages = <ChatMessage>[
      _messageWithConversation(
        ChatMessage(
          localId: 'alice-1',
          remoteId: 'alice-1',
          threadId: conversation.effectiveConversationId,
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          groupId: conversation.groupId,
          content: '第一条',
          createdAt: DateTime(2026, 4, 5, 12, 0),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversation,
      ),
      _messageWithConversation(
        ChatMessage(
          localId: 'alice-2',
          remoteId: 'alice-2',
          threadId: conversation.effectiveConversationId,
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          groupId: conversation.groupId,
          content: '第二条',
          createdAt: DateTime(2026, 4, 5, 12, 1),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversation,
      ),
      _messageWithConversation(
        ChatMessage(
          localId: 'bob-1',
          remoteId: 'bob-1',
          threadId: conversation.effectiveConversationId,
          senderDid: 'did:wba:awiki.ai:user:bob:e1_key',
          senderName: 'did:wba:awiki.ai:user:bob:e1_key',
          groupId: conversation.groupId,
          content: '第三条',
          createdAt: DateTime(2026, 4, 5, 12, 2),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversation,
      ),
      _messageWithConversation(
        ChatMessage(
          localId: 'mine-1',
          remoteId: 'mine-1',
          threadId: conversation.effectiveConversationId,
          senderDid: session.did,
          senderName: session.handle,
          groupId: conversation.groupId,
          content: '自己发一条',
          createdAt: DateTime(2026, 4, 5, 12, 3),
          isMine: true,
          sendState: MessageSendState.sent,
        ),
        conversation,
      ),
      _messageWithConversation(
        ChatMessage(
          localId: 'alice-3',
          remoteId: 'alice-3',
          threadId: conversation.effectiveConversationId,
          senderDid: 'did:wba:awiki.ai:user:alice:e1_key',
          groupId: conversation.groupId,
          content: '第四条',
          createdAt: DateTime(2026, 4, 5, 12, 4),
          isMine: false,
          sendState: MessageSendState.sent,
        ),
        conversation,
      ),
    ];
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          messages;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:caption-attachment',
      displayName: 'Tester',
      lastMessagePreview: '请看这个文件',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final groupConversation = ConversationSummary(
      conversationId: 'group:did:test:group:caption-attachment',
      threadId: 'group:caption-attachment',
      displayName: '附件群',
      lastMessagePreview: '群里也发一个',
      lastMessageAt: DateTime(2026, 4, 5, 12, 1),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:caption-attachment',
    );
    final dmMessage = _messageWithConversation(
      ChatMessage(
        localId: 'dm-caption-attachment',
        remoteId: 'dm-caption-attachment',
        threadId: dmConversation.effectiveConversationId,
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
      ),
      dmConversation,
    );
    final groupMessage = _messageWithConversation(
      ChatMessage(
        localId: 'group-caption-attachment',
        remoteId: 'group-caption-attachment',
        threadId: groupConversation.effectiveConversationId,
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
      ),
      groupConversation,
    );
    final dmMessagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[dmConversation.effectiveConversationId] =
          <ChatMessage>[dmMessage];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: dmConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(dmMessagingService),
        ],
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

    final groupMessagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[groupConversation.effectiveConversationId] =
          <ChatMessage>[groupMessage];
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: groupConversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(groupMessagingService),
        ],
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
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:selectable-attachment',
      displayName: 'Tester',
      lastMessagePreview: '附件说明',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[
            _messageWithConversation(
              ChatMessage(
                localId: 'selectable-attachment',
                remoteId: 'selectable-attachment',
                threadId: conversation.effectiveConversationId,
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
              conversation,
            ),
          ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(find.text('附件说明'), findsOneWidget);
    expect(find.text('copyable-report.pdf'), findsOneWidget);
  });

  testWidgets('查看附件会下载后用本机应用打开文件', (tester) async {
    final gateway = FakeAwikiGateway();
    final opener = _RecordingAttachmentOpenService();
    final picker = FakeAttachmentPickerService()
      ..nextSavedPath = '/tmp/native-open-report.txt';
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:native-open-attachment',
      displayName: 'Tester',
      lastMessagePreview: '[附件] report.txt',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final message = _messageWithConversation(
      ChatMessage(
        localId: 'native-open-attachment',
        remoteId: 'native-open-attachment',
        threadId: conversation.effectiveConversationId,
        senderDid: conversation.targetDid!,
        receiverDid: session.did,
        content: '',
        createdAt: DateTime(2026, 4, 5, 12, 1),
        isMine: false,
        sendState: MessageSendState.sent,
        originalType: 'application/anp-attachment-manifest+json',
        attachment: const ChatAttachment(
          attachmentId: 'att-native-open',
          filename: 'report.txt',
          mimeType: 'text/plain',
          sizeBytes: 5,
        ),
      ),
      conversation,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[message];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          attachmentPickerServiceProvider.overrideWithValue(picker),
          attachmentOpenServiceProvider.overrideWithValue(opener),
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    final openAttachment = find.byKey(
      const Key('chat-open-attachment:native-open-attachment'),
    );
    expect(openAttachment, findsOneWidget);
    await tester.tap(openAttachment);
    await tester.pumpAndSettle();

    expect(picker.saveCalls, 0);
    expect(opener.openedPaths, hasLength(1));
    expect(opener.openedPaths.single, startsWith('/tmp/awiki-test-cache/'));
    expect(opener.openedPaths.single, contains('/native-open-attachment/'));
    expect(opener.openedPaths.single, contains('/att-native-open/'));
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
      conversationId: 'dm:did:test:peer',
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
    final message = _messageWithConversation(
      ChatMessage(
        localId: 'attachment-markdown-caption',
        remoteId: 'attachment-markdown-caption',
        threadId: conversation.effectiveConversationId,
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
      conversation,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[message];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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
    expect(body.selectable, isFalse);
    expect(find.text(filename), findsOneWidget);
  });

  testWidgets('Message Agent 回收卡片展示状态和草稿确认，不显示 raw JSON', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final conversation = ConversationSummary(
      conversationId: 'dm:did:human:bob',
      threadId: 'direct:did:human:bob',
      displayName: 'Bob',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 6, 19, 10, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:human:bob',
    );
    final message = _messageWithConversation(
      ChatMessage(
        localId: 'local_msg_1',
        remoteId: 'msg_1',
        threadId: conversation.effectiveConversationId,
        senderDid: 'did:human:bob',
        receiverDid: session.did,
        content: 'hello',
        createdAt: DateTime(2026, 6, 19, 10, 0),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversation,
    );
    final controlMessage = _messageWithConversation(
      ChatMessage(
        localId: 'control-json',
        remoteId: 'control-json',
        threadId: conversation.effectiveConversationId,
        senderDid: 'did:agent:daemon',
        receiverDid: session.did,
        content: '{"schema":"awiki.message.sync.v1"}',
        originalType: 'application/json',
        payloadJson: '{"schema":"awiki.message.sync.v1"}',
        createdAt: DateTime(2026, 6, 19, 10, 1),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversation,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[message, controlMessage];
    gateway.conversations = <ConversationSummary>[conversation];

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
                  agentDid: 'did:agent:daemon',
                  kind: AgentKind.daemon,
                  displayName: 'Message Daemon',
                  activeState: 'active',
                  latest: AgentLatestStatus(status: 'ready'),
                ),
                AgentSummary(
                  agentDid: 'did:agent:runtime',
                  kind: AgentKind.runtime,
                  daemonAgentDid: 'did:agent:daemon',
                  runtime: 'hermes',
                  displayName: 'Hermes Message Agent',
                  activeState: 'active',
                  latest: AgentLatestStatus(status: 'ready'),
                ),
              ],
            );
            return controller;
          }),
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .openConversation(conversation);
    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('{"schema":"awiki.message.sync.v1"}'), findsNothing);

    container
        .read(chatThreadsProvider.notifier)
        .applyMessageAgentControlPayload(<String, Object?>{
          'schema': 'awiki.message.sync.v1',
          'sync_type': 'runtime_final',
          'runtime_agent_did': 'did:agent:runtime',
          'run_id': 'run_1',
          'source_message_id': 'msg_1',
          'source_conversation_id': conversation.effectiveConversationId,
          'state': 'finished',
          'has_text': true,
          'retention_class': 'hash_only',
        });
    container
        .read(chatThreadsProvider.notifier)
        .applyMessageAgentControlPayload(<String, Object?>{
          'schema': 'awiki.app.action.v1',
          'action_id': 'act_draft',
          'action': 'message.create_draft',
          'state': 'requires_confirmation',
          'runtime_agent_did': 'did:agent:runtime',
          'run_id': 'run_1',
          'source_message_id': 'msg_1',
          'conversation_id': conversation.effectiveConversationId,
          'requires_confirmation': true,
          'args': <String, Object?>{'draft_text': '收到，我会处理。'},
        });
    await tester.pumpAndSettle();

    expect(find.text('消息 Agent 已完成处理'), findsOneWidget);
    expect(find.text('已生成处理结果'), findsOneWidget);
    expect(find.text('消息 Agent 生成了草稿'), findsOneWidget);
    expect(find.text('收到，我会处理。'), findsOneWidget);
    expect(find.text('使用草稿'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);

    await tester.tap(find.text('使用草稿'));
    await tester.pumpAndSettle();

    final input = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(input.controller?.text, '收到，我会处理。');
    expect(gateway.lastSentPayloadPeerDid, 'did:agent:daemon');
    expect(gateway.lastSentPayload?['state'], appActionStateSucceeded);
    expect(find.text('草稿已放入输入框'), findsOneWidget);
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
      conversationId: 'dm:did:agent:deleted-runtime',
      threadId: 'dm:deleted-agent',
      displayName: '旧智能体',
      lastMessagePreview: '旧回复',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:deleted-runtime',
      peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
    );
    final message = _messageWithConversation(
      ChatMessage(
        localId: 'deleted-agent-history',
        remoteId: 'deleted-agent-history',
        threadId: conversation.effectiveConversationId,
        senderDid: conversation.targetDid!,
        receiverDid: session.did,
        content: '历史消息仍可查看',
        createdAt: DateTime(2026, 4, 5, 12, 1),
        isMine: false,
        sendState: MessageSendState.sent,
      ),
      conversation,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[message];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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
      conversationId: 'dm:did:test:peer',
      threadId: 'dm:attachment-only',
      displayName: 'Tester',
      lastMessagePreview: '[附件] raw.pdf',
      lastMessageAt: DateTime(2026, 4, 5, 12, 0),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
    );
    final message = _messageWithConversation(
      ChatMessage(
        localId: 'attachment-only',
        remoteId: 'attachment-only',
        threadId: conversation.effectiveConversationId,
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
      ),
      conversation,
    );
    final messagingService = FakeMessagingService(gateway)
      ..conversationTimelineById[conversation.effectiveConversationId] =
          <ChatMessage>[message];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: CupertinoPageScaffold(
          child: ChatView(conversation: conversation, embedded: false),
        ),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
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

ChatMessage _messageWithConversation(
  ChatMessage message,
  ConversationSummary conversation,
) {
  return ChatMessage(
    localId: message.localId,
    remoteId: message.remoteId,
    conversationId: conversation.effectiveConversationId,
    threadId: conversation.effectiveConversationId,
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
    attachment: message.attachment,
    payloadJson: message.payloadJson,
    mentions: message.mentions,
  );
}

FakeMessagingService _messagingServiceWithConversationMessages(
  FakeAwikiGateway gateway,
  ConversationSummary conversation,
  List<ChatMessage> messages,
) {
  return FakeMessagingService(gateway)
    ..conversationTimelineById[conversation.effectiveConversationId] = messages
        .map((message) => _messageWithConversation(message, conversation))
        .toList(growable: false);
}

ChatMessage _latestProjectedConversationMessage(
  FakeMessagingService messagingService,
  ConversationSummary conversation,
) {
  final messages =
      messagingService.conversationTimelineById[conversation
          .effectiveConversationId] ??
      const <ChatMessage>[];
  if (messages.isEmpty) {
    throw StateError(
      'No projected messages for ${conversation.effectiveConversationId}',
    );
  }
  return messages.last;
}

bool _textSpanHasStyledMention(InlineSpan span, String mentionText) {
  if (span is! TextSpan) {
    return false;
  }
  final style = span.style;
  if (span.text == mentionText &&
      style?.fontWeight == FontWeight.w700 &&
      style?.color != null &&
      style?.backgroundColor != null) {
    return true;
  }
  return span.children?.any(
        (child) => _textSpanHasStyledMention(child, mentionText),
      ) ??
      false;
}
