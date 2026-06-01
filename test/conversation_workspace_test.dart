import 'dart:async';

import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_list_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    List<ConversationSummary> items,
  ) {
    state = ConversationListState(conversations: items);
  }
}

void main() {
  final conversation = ConversationSummary(
    threadId: 'dm:did:me:did:peer',
    displayName: 'Marcus Chen',
    lastMessagePreview: 'Hey! I just saw the updates.',
    lastMessageAt: DateTime(2026, 3, 28, 10, 24),
    unreadCount: 3,
    isGroup: false,
    targetDid: 'did:peer',
  );

  final history = <ChatMessage>[
    ChatMessage(
      localId: '1',
      threadId: 'dm:did:me:did:peer',
      senderDid: 'did:peer',
      senderName: 'Marcus Chen',
      content: 'Hey! I just saw the updates.',
      createdAt: DateTime(2026, 3, 28, 10, 24),
      isMine: false,
      sendState: MessageSendState.sent,
    ),
  ];

  testWidgets('macOS 宽度下使用三栏消息工作区与身份卡', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('最近会话'), findsOneWidget);
    expect(find.byType(ChatView), findsNothing);

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('会话信息'), findsOneWidget);
    expect(find.text('did:peer'), findsOneWidget);
    expect(find.text('安全协作中'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 会话信息完整显示 DID 并支持一键复制', (tester) async {
    const longDid =
        'did:awiki:user:marcus-chen-lab:e1_abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789';
    final longDidConversation = ConversationSummary(
      threadId: 'dm:did:me:$longDid',
      displayName: 'Marcus Chen',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 3, 28, 10, 24),
      unreadCount: 0,
      isGroup: false,
      targetDid: longDid,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[longDidConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{longDid: []};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'Clipboard.setData') {
            final data = methodCall.arguments as Map<Object?, Object?>;
            clipboardText = data['text'] as String?;
          }
          return null;
        });

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    final didFinder = find.byKey(const Key('mac-conversation-did-value'));
    expect(didFinder, findsOneWidget);
    final didText = tester.widget<Text>(didFinder);
    expect(didText.data, longDid);
    expect(didText.maxLines, isNull);
    expect(
      find.byKey(const Key('mac-conversation-copy-did-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('mac-conversation-copy-did-button')));
    await tester.pump();

    expect(clipboardText, longDid);
    expect(find.text('DID 已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 会话状态最近预览多行时圆点对齐首行', (tester) async {
    final previewConversation = ConversationSummary(
      threadId: 'dm:did:me:did:peer',
      displayName: 'Marcus Chen',
      lastMessagePreview: '这是一段比较长的最近消息预览，用来触发右侧会话状态区域里的两行文本布局',
      lastMessageAt: DateTime(2026, 3, 28, 10, 24),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:peer',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[previewConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    final dotRect = tester.getRect(
      find.byKey(const Key('mac-conversation-preview-status-dot')),
    );
    final valueRect = tester.getRect(
      find.byKey(const Key('mac-conversation-preview-status-value')),
    );

    expect(valueRect.height, greaterThan(20));
    expect((dotRect.center.dy - (valueRect.top + 8.1)).abs(), lessThan(1.0));

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 身份卡在右侧栏替换会话信息并支持关闭', (tester) async {
    const peerProfile = UserProfile(
      did: 'did:peer',
      nickName: 'Marcus Chen',
      bio: '融资协作 Agent',
      tags: <String>['Agent'],
      profileMarkdown: '# Marcus\n\n负责融资协作。',
      handle: 'marcus',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history}
      ..publicProfilesByQuery = <String, UserProfile>{'did:peer': peerProfile};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        homepageMarkdownLoader: (_) async => null,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen').first);
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsOneWidget);
    var conversationInfoIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chat-conversation-info-button')),
        matching: find.byIcon(CupertinoIcons.sidebar_right),
      ),
    );
    var identityLabel = tester.widget<Text>(find.text('身份卡'));
    var conversationInfoDecoration =
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(
                          const Key('chat-conversation-info-button'),
                        ),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(conversationInfoDecoration.color, const Color(0xFFE4ECF7));
    expect(conversationInfoIcon.weight, 900);
    expect(identityLabel.style?.fontWeight, FontWeight.w400);
    final conversationInfoWidth = tester
        .getSize(find.byKey(const Key('mac-side-panel')))
        .width;

    await tester.tap(find.text('身份卡'));
    await tester.pumpAndSettle();

    final identityCardWidth = tester
        .getSize(find.byKey(const Key('mac-side-panel')))
        .width;
    expect(identityCardWidth, greaterThan(conversationInfoWidth));
    expect(find.text('Marcus Chen 的身份卡'), findsOneWidget);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('负责融资协作。'), findsOneWidget);
    expect(find.text('@marcus'), findsOneWidget);
    identityLabel = tester.widget<Text>(find.text('身份卡'));
    conversationInfoIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chat-conversation-info-button')),
        matching: find.byIcon(CupertinoIcons.sidebar_right),
      ),
    );
    final identityButtonDecoration =
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(const Key('chat-identity-card-button')),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(identityButtonDecoration.color, const Color(0xFFE4ECF7));
    expect(identityLabel.style?.fontWeight, FontWeight.w600);
    expect(conversationInfoIcon.weight, 500);

    await tester.tap(find.text('身份卡'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('Marcus Chen 的身份卡'), findsNothing);

    await tester.tap(find.byKey(const Key('chat-conversation-info-button')));
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsOneWidget);
    conversationInfoIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('chat-conversation-info-button')),
        matching: find.byIcon(CupertinoIcons.sidebar_right),
      ),
    );
    identityLabel = tester.widget<Text>(find.text('身份卡'));
    conversationInfoDecoration =
        tester
                .widget<Container>(
                  find
                      .descendant(
                        of: find.byKey(
                          const Key('chat-conversation-info-button'),
                        ),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(conversationInfoDecoration.color, const Color(0xFFE4ECF7));
    expect(conversationInfoIcon.weight, 900);
    expect(identityLabel.style?.fontWeight, FontWeight.w400);

    await tester.tap(find.text('身份卡'));
    await tester.pumpAndSettle();
    final beforeResize = tester
        .getSize(find.byKey(const Key('mac-side-panel')))
        .width;
    await tester.drag(
      find.byKey(const Key('mac-side-panel-resize-divider')),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    final afterResize = tester
        .getSize(find.byKey(const Key('mac-side-panel')))
        .width;

    expect(afterResize, greaterThan(beforeResize));

    await tester.tap(find.byKey(const Key('mac-side-panel-close-button')));
    await tester.pumpAndSettle();

    expect(find.text('会话信息'), findsOneWidget);
    expect(find.text('Marcus Chen 的身份卡'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊信息按钮在右侧栏打开群详情而不是全屏跳转', (tester) async {
    final group = GroupSummary(
      groupId: 'did:test:group:funding',
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        group.groupId: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:test:owner',
            did: 'did:test:owner',
            handle: 'owner.awiki',
            role: 'owner',
          ),
          GroupMemberSummary(
            userId: 'did:test:member',
            did: 'did:test:member',
            handle: 'member.awiki',
            role: 'member',
          ),
        ],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsOneWidget);
    expect(find.text('群聊信息'), findsOneWidget);
    expect(find.text('身份卡'), findsNothing);

    await tester.tap(find.text('群聊信息'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mac-side-panel')), findsOneWidget);
    expect(find.text('融资协作群 的群聊信息'), findsOneWidget);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('2 人'), findsOneWidget);
    expect(find.text('owner'), findsWidgets);
    expect(find.byKey(const Key('mac-group-info-did-value')), findsOneWidget);
    expect(
      find.byKey(const Key('mac-group-info-refresh-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('mac-group-info-add-member-button')),
      findsOneWidget,
    );
    expect(find.text('owner.awiki'), findsOneWidget);
    expect(find.text('member.awiki'), findsOneWidget);
    expect(find.text('did:test:owner'), findsNothing);
    expect(find.text('did:test:member'), findsNothing);
    expect(find.byType(GroupDetailPage), findsNothing);

    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    await tester.tap(find.byKey(const Key('mac-group-info-add-member-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).last, memberDid);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(gateway.lastAddedGroupId, group.groupId);
    expect(gateway.lastAddedMemberDid, memberDid);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text(memberDid), findsNothing);
    expect(find.text('3 人'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 右侧栏空间不足时在聊天区打开会话信息和身份卡', (tester) async {
    const peerProfile = UserProfile(
      did: 'did:peer',
      nickName: 'Marcus Chen',
      bio: '融资协作 Agent',
      tags: <String>['Agent'],
      profileMarkdown: '# Marcus\n\n负责融资协作。',
      handle: 'marcus',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history}
      ..publicProfilesByQuery = <String, UserProfile>{'did:peer': peerProfile};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(900, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiDisplayScaleScope(
          scale: 1.12,
          child: ConversationWorkspacePage(),
        ),
        gateway: gateway,
        homepageMarkdownLoader: (_) async => null,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen').first);
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('会话信息'), findsNothing);

    await tester.tap(find.byKey(const Key('chat-conversation-info-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('会话信息'), findsOneWidget);
    expect(find.text('did:peer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mac-compact-panel-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('会话信息'), findsNothing);

    await tester.tap(find.text('身份卡'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('Marcus Chen 的身份卡'), findsOneWidget);
    expect(find.text('负责融资协作。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mac-compact-panel-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('Marcus Chen 的身份卡'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 右侧栏空间不足时在聊天区打开群聊信息', (tester) async {
    final group = GroupSummary(
      groupId: 'did:test:group:funding',
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        group.groupId: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:test:owner',
            did: 'did:test:owner',
            handle: 'owner.awiki',
            role: 'owner',
          ),
        ],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(900, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiDisplayScaleScope(
          scale: 1.12,
          child: ConversationWorkspacePage(),
        ),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('融资协作群 的群聊信息'), findsNothing);

    await tester.tap(find.text('群聊信息'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('融资协作群 的群聊信息'), findsOneWidget);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('owner.awiki'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mac-compact-panel-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('融资协作群 的群聊信息'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊成员刷新不受群详情空响应影响', (tester) async {
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupConversation.groupId!,
          name: '融资协作群',
          description: '同步融资材料和里程碑',
          memberCount: 1,
          lastMessageAt: DateTime(2026, 3, 28, 10, 25),
          myRole: 'owner',
        ),
      ]
      ..getGroupError = StateError(
        'IM Core group response did not include a group.',
      );
    UiFeedbackEvent? feedback;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: Consumer(
          builder: (context, ref, child) {
            feedback = ref.watch(uiFeedbackProvider);
            return const ConversationWorkspacePage();
          },
        ),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('群聊信息'));
    await tester.pumpAndSettle();

    expect(find.text('暂无成员快照，先执行一次刷新群详情与成员。'), findsOneWidget);

    gateway.groupMembersByGroupId = <String, List<GroupMemberSummary>>{
      groupConversation.groupId!: const <GroupMemberSummary>[
        GroupMemberSummary(
          userId: 'did:test:late-member',
          did: 'did:test:late-member',
          handle: 'late-member.awiki',
          role: 'late-role-hidden',
        ),
      ],
    };

    await tester.tap(find.byKey(const Key('mac-group-info-refresh-button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(feedback, isNull);
    expect(find.text('late-member.awiki'), findsOneWidget);
    expect(find.text('did:test:late-member'), findsNothing);
    expect(find.text('late-role-hidden'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊成员刷新期间显示按钮级 loading', (tester) async {
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );
    final group = GroupSummary(
      groupId: groupConversation.groupId!,
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 1,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
    );
    final memberRefresh = Completer<void>();
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        group.groupId: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:test:owner',
            did: 'did:test:owner',
            handle: 'owner.awiki',
            role: 'owner',
          ),
        ],
      };
    addTearDown(() {
      if (!memberRefresh.isCompleted) {
        memberRefresh.complete();
      }
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('群聊信息'));
    await tester.pumpAndSettle();

    gateway.listGroupMembersCompleter = memberRefresh;
    await tester.tap(find.byKey(const Key('mac-group-info-refresh-button')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('mac-group-info-refresh-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsOneWidget,
    );

    memberRefresh.complete();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('mac-group-info-refresh-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 会话信息按钮支持折叠和重新打开右侧栏', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1600, 960));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-conversation-info-button')));
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsNothing);

    await tester.tap(find.byKey(const Key('chat-conversation-info-button')));
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航点击会切换模块并保持图标可点', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    const profile = UserProfile(
      did: 'did:test:me',
      nickName: 'Mia',
      bio: 'Product lead',
      tags: <String>['agent'],
      profileMarkdown: '',
      handle: 'mia',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        profile: profile,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AW'), findsNothing);
    expect(find.text('Me'), findsNothing);
    final railAvatar = find.byKey(const Key('mac-me-rail-avatar'));
    expect(
      find.descendant(of: railAvatar, matching: find.byType(AvatarBadge)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: railAvatar, matching: find.text('M')),
      findsOneWidget,
    );
    expect(find.text('最近会话'), findsOneWidget);

    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务视图即将接入'), findsOneWidget);

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    expect(find.text('朋友'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mac-me-rail-avatar')));
    await tester.pumpAndSettle();
    expect(find.text('我'), findsOneWidget);

    await tester.tap(find.text('设置').first);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.back), findsNothing);
    expect(find.byKey(const Key('mac-desktop-rail-slot')), findsOneWidget);
    final settingsPaneSize = tester.getSize(
      find.byKey(const Key('mac-settings-list-pane')),
    );
    expect(settingsPaneSize.width, closeTo(420, 0.1));
    expect(settingsPaneSize.width, lessThan(1280 - 72));

    await tester.tap(find.text('消息'));
    await tester.pumpAndSettle();
    expect(find.text('最近会话'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航未选中项统一为空心轻量样式', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
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

    final inactiveIcons = <IconData>[
      CupertinoIcons.person_2,
      CupertinoIcons.person,
      CupertinoIcons.checkmark_square,
      CupertinoIcons.square_grid_2x2,
      CupertinoIcons.gear_alt,
    ];
    for (final iconData in inactiveIcons) {
      final icon = tester.widget<Icon>(find.byIcon(iconData));
      expect(icon.color, const Color(0xFF7A879C));
      expect(icon.weight, 400);
    }
    expect(find.byIcon(CupertinoIcons.person_2_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.person_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.checkmark_square_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.square_grid_2x2_fill), findsNothing);
    expect(find.byIcon(CupertinoIcons.gear_alt_fill), findsNothing);

    final activeMessageIcon = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.chat_bubble_2_fill),
    );
    expect(activeMessageIcon.color, const Color(0xFF0B65F8));
    expect(activeMessageIcon.weight, 700);

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();

    final inactiveMessageIcon = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.chat_bubble_2),
    );
    final activeContactsIcon = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.person_fill),
    );
    expect(inactiveMessageIcon.color, const Color(0xFF7A879C));
    expect(inactiveMessageIcon.weight, 400);
    expect(activeContactsIcon.color, const Color(0xFF0B65F8));
    expect(activeContactsIcon.weight, 700);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航头像缺少身份文本时回退到 Me', (tester) async {
    const session = SessionIdentity(
      did: '',
      credentialName: 'empty.json',
      displayName: '',
      jwtToken: 'token',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const AppShell(), session: session),
    );
    await tester.pumpAndSettle();

    final railAvatar = find.byKey(const Key('mac-me-rail-avatar'));
    expect(
      find.descendant(of: railAvatar, matching: find.text('Me')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: railAvatar, matching: find.text('M')),
      findsNothing,
    );
    expect(
      find.descendant(of: railAvatar, matching: find.text('?')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航和消息工作区跟随显示缩放', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiDisplayScaleScope(scale: 1.12, child: AppShell()),
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

    expect(
      tester.getSize(find.byKey(const Key('mac-desktop-rail-slot'))).width,
      greaterThan(72),
    );
    expect(
      tester.getSize(find.byKey(const Key('mac-conversation-list-pane'))).width,
      greaterThan(340),
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航无未读时不显示消息角标', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final readConversation = ConversationSummary(
      threadId: 'dm:read',
      displayName: 'Read Chat',
      lastMessagePreview: 'read',
      lastMessageAt: DateTime(2026, 3, 28, 10, 24),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:read',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    final readOnlyGateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[readConversation];
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: readOnlyGateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(
              ref,
              <ConversationSummary>[readConversation],
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12'), findsNothing);
    expect(find.text('2'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航消息角标显示真实未读数量', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final conversations = <ConversationSummary>[
      ConversationSummary(
        threadId: 'dm:read',
        displayName: 'Read Chat',
        lastMessagePreview: 'read',
        lastMessageAt: DateTime(2026, 3, 28, 10, 24),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:read',
      ),
      ConversationSummary(
        threadId: 'dm:unread',
        displayName: 'Unread Chat',
        lastMessagePreview: 'unread',
        lastMessageAt: DateTime(2026, 3, 28, 10, 25),
        unreadCount: 2,
        isGroup: false,
        targetDid: 'did:unread',
      ),
    ];
    final gateway = FakeAwikiGateway()..conversations = conversations;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(ref, conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('12'), findsNothing);
    expect(find.text('2'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主窗口压缩高度和宽度时不会出现布局溢出', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    const profile = UserProfile(
      did: 'did:test:me',
      nickName: 'Mia',
      bio: 'Product lead',
      tags: <String>['agent'],
      profileMarkdown: '',
      handle: 'mia',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    for (final size in <Size>[
      const Size(1280, 600),
      const Size(960, 560),
      const Size(720, 520),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          gateway: gateway,
          session: session,
          profile: profile,
          providerOverrides: <Override>[
            conversationListProvider.overrideWith(
              (ref) =>
                  _StaticConversationListController(ref, gateway.conversations),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('最近会话'), findsOneWidget);
      await tester.tap(find.text('Marcus Chen').first);
      await tester.pumpAndSettle();
      expect(find.byType(ChatView), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话列表分栏可以拖动调整宽度', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final before = tester
        .getSize(find.byKey(const Key('mac-conversation-list-pane')))
        .width;
    await tester.drag(
      find.byKey(const Key('awiki-pane-divider')),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();
    final after = tester
        .getSize(find.byKey(const Key('mac-conversation-list-pane')))
        .width;

    expect(after, greaterThan(before));

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话搜索支持标题和最近消息预览', (tester) async {
    final conversations = <ConversationSummary>[
      conversation,
      ConversationSummary(
        threadId: 'group:funding',
        displayName: '融资协作群',
        lastMessagePreview: '明早同步 deck',
        lastMessageAt: DateTime(2026, 3, 28, 10, 25),
        unreadCount: 0,
        isGroup: true,
        groupId: 'did:test:group:funding',
      ),
      ConversationSummary(
        threadId: 'dm:did:me:did:ops',
        displayName: 'Ops Bot',
        lastMessagePreview: 'server alert recovered',
        lastMessageAt: DateTime(2026, 3, 28, 10, 26),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:ops',
      ),
    ];
    final gateway = FakeAwikiGateway()..conversations = conversations;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(ref, conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('搜索会话'), findsOneWidget);
    expect(find.text('搜索会话或 Agent'), findsNothing);
    expect(find.text('Marcus Chen'), findsOneWidget);
    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('Ops Bot'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), '融资');
    await tester.pumpAndSettle();
    expect(find.text('Marcus Chen'), findsNothing);
    expect(find.text('融资协作群'), findsOneWidget);
    expect(find.text('Ops Bot'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'recovered');
    await tester.pumpAndSettle();
    expect(find.text('Marcus Chen'), findsNothing);
    expect(find.text('融资协作群'), findsNothing);
    expect(find.text('Ops Bot'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoSearchTextField), 'not-found');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关会话'), findsOneWidget);
    expect(find.text('换个关键词试试'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('手机宽度下点击会话进入独立聊天页', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(ChatView), findsOneWidget);
  });

  testWidgets('手机主导航显示文字标签并保持切换功能', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    const profile = UserProfile(
      did: 'did:test:me',
      nickName: 'Mia',
      bio: 'Product lead',
      tags: <String>['agent'],
      profileMarkdown: '',
      handle: 'mia',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        profile: profile,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('消息'), findsOneWidget);
    expect(find.text('朋友'), findsOneWidget);
    expect(find.text('我'), findsOneWidget);
    final messageTabSize = tester.getSize(find.text('消息'));
    final friendsTabSize = tester.getSize(find.text('朋友'));
    final meTabSize = tester.getSize(find.text('我'));
    expect(messageTabSize.height, greaterThan(0));
    expect(friendsTabSize.height, greaterThan(0));
    expect(meTabSize.height, greaterThan(0));
    final bottomNavHeight = tester
        .getSize(
          find.ancestor(of: find.text('消息'), matching: find.byType(Row)).first,
        )
        .height;
    expect(bottomNavHeight, closeTo(52, 0.1));
    final navRowCenterY = tester
        .getCenter(
          find.ancestor(of: find.text('消息'), matching: find.byType(Row)).first,
        )
        .dy;
    final messageLabelCenterY = tester.getCenter(find.text('消息')).dy;
    expect(messageLabelCenterY, lessThan(navRowCenterY + 22));

    await tester.tap(find.text('朋友'));
    await tester.pumpAndSettle();
    expect(find.text('朋友'), findsWidgets);

    await tester.tap(find.text('我'));
    await tester.pumpAndSettle();
    expect(find.text('Product lead'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pad 宽度下展示双栏并在右侧更新聊天内容', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1024, 768));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsNothing);
    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('Marcus Chen'), findsWidgets);
  });
}
