// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_agent_identity.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/agents/agent_status_indicator.dart';
import 'package:awiki_me/src/presentation/agents/agent_visual_status.dart';
import 'package:awiki_me/src/presentation/agents/agents_page.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_list_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_workspace_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:awiki_me/src/presentation/shared/adaptive_overlays.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/app_dialog.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_semantic_icon.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/display_scale.dart';
import 'package:awiki_me/src/presentation/shared/responsive_layout.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
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

  void replaceConversations(List<ConversationSummary> conversations) {
    state = ConversationListState(conversations: conversations);
    final selected = ref.read(selectedConversationProvider);
    if (selected == null) {
      return;
    }
    for (final conversation in conversations) {
      if (conversation.conversationId == selected) {
        return;
      }
    }
    ref.read(selectedConversationProvider.notifier).clearSelection();
  }

  void showLoadError() {
    state = ConversationListState(
      loadState: ConversationListLoadState.error,
      errorCode: 'conversation_load_failed',
    );
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> refreshFastLocal() async {}

  @override
  Future<void> restoreConversation(ConversationSummary conversation) async {}
}

class _BlockingRestoreConversationListController
    extends _StaticConversationListController {
  _BlockingRestoreConversationListController(
    super.ref,
    super.items, {
    required this.restoreStarted,
    required this.restoreCompleter,
  });

  final Completer<void> restoreStarted;
  final Completer<void> restoreCompleter;

  @override
  Future<ConversationSummary> commitConversationId(
    String conversationId, {
    SessionEpoch? expectedEpoch,
  }) {
    if (!restoreStarted.isCompleted) {
      restoreStarted.complete();
    }
    return restoreCompleter.future.then((_) {
      return state.conversations.singleWhere(
        (conversation) => conversation.conversationId == conversationId,
      );
    });
  }
}

class _RecordingDeleteConversationListController
    extends _StaticConversationListController {
  _RecordingDeleteConversationListController(super.ref, super.items);

  ConversationSummary? deletedConversation;

  @override
  Future<void> deleteFromRecents(ConversationSummary conversation) async {
    deletedConversation = conversation;
    state = ConversationListState(
      conversations: state.conversations
          .where((item) => item.conversationId != conversation.conversationId)
          .toList(growable: false),
    );
  }
}

const _groupWorkspaceSession = SessionIdentity(
  did: 'did:test:owner',
  credentialName: 'group-workspace',
  handle: 'owner.awiki',
  displayName: 'Owner',
);

void main() {
  testWidgets('会话行头像和昵称复用 Persona Profile 投影', (tester) async {
    const ownerDid = 'did:wba:awiki.info:user:me:e1_current';
    const peerDid = 'did:wba:awiki.info:user:zhuocheng:e1_peer';
    const peerPersonaId = 'persona:zhuocheng';
    const avatarUri = 'https://awiki.info/avatar/zhuocheng.png';
    final conversation = ConversationSummary(
      threadId: 'dm:peer-scope:zhuocheng',
      conversationId: 'dm:peer-scope:zhuocheng',
      displayName: 'zhuocheng',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 7, 17, 17, 13),
      unreadCount: 0,
      isGroup: false,
      targetDid: peerDid,
      targetPeer: 'zhuocheng.awiki.info',
      peerPersonaId: peerPersonaId,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(macStyle: true),
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListPage)),
      listen: false,
    );
    container
        .read(peerDisplayProfileProvider.notifier)
        .updateFromRemote(
          ownerDid: ownerDid,
          peerPersonaId: peerPersonaId,
          profile: const UserProfile(
            did: peerDid,
            displayName: '卓诚',
            bio: '',
            tags: <String>[],
            profileMarkdown: '',
            fullHandle: 'zhuocheng.awiki.info',
            avatarUri: avatarUri,
          ),
        );
    await tester.pump();

    final row = find.byKey(
      const Key('conversation-row:dm:peer-scope:zhuocheng'),
    );
    expect(find.descendant(of: row, matching: find.text('卓诚')), findsOneWidget);
    final avatar = tester.widget<AvatarBadge>(
      find.descendant(of: row, matching: find.byType(AvatarBadge)),
    );
    expect(avatar.seed, '卓诚');
    expect(avatar.avatarUri, avatarUri);
  });

  final conversation = ConversationSummary(
    threadId: 'dm:did:me:did:peer',
    conversationId: 'dm:did:me:did:peer',
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

  testWidgets('会话加载失败不会伪装成真实空列表', (tester) async {
    late _StaticConversationListController controller;
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: FakeAwikiGateway(),
        providerOverrides: <Override>[
          conversationListProvider.overrideWith((ref) {
            controller = _StaticConversationListController(
              ref,
              const <ConversationSummary>[],
            );
            return controller;
          }),
        ],
      ),
    );
    controller.showLoadError();
    await tester.pump();

    expect(
      find.byKey(const Key('conversation-list-load-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('conversation-list-load-retry')),
      findsOneWidget,
    );
    expect(find.text('暂无会话'), findsNothing);
  });

  testWidgets('最近会话显示未读 @ 我提示', (tester) async {
    final mentionConversation = ConversationSummary(
      threadId: 'group:did:group:mentions',
      conversationId: 'group:did:group:mentions',
      displayName: '项目群',
      lastMessagePreview: '@Marcus 请看这里',
      lastMessageAt: DateTime(2026, 3, 28, 10, 30),
      unreadCount: 2,
      unreadMentionCount: 1,
      firstUnreadMentionMessageId: 'msg-mention-1',
      isGroup: true,
      groupId: 'did:group:mentions',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[mentionConversation];
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

    expect(find.text('项目群'), findsOneWidget);
    final unreadBadge = find.byKey(const Key('conversation-row-unread-badge'));
    expect(unreadBadge, findsOneWidget);
    expect(
      find.descendant(of: unreadBadge, matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.text('未读 2'), findsNothing);
    expect(find.text('@我'), findsOneWidget);
  });

  testWidgets('群资料仅在展示层解析且不改写 Core 会话投影', (tester) async {
    const groupDid = 'did:wba:awiki.info:groups:canonical';
    const conversationId = 'group:did:wba:awiki.info:groups:canonical';
    final groupConversation = ConversationSummary(
      threadId: 'legacy-group-thread',
      conversationId: conversationId,
      displayName: groupDid,
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 14, 10),
      unreadCount: 0,
      isGroup: true,
      groupId: groupDid,
      canonicalGroupDid: groupDid,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(
              ref,
              <ConversationSummary>[groupConversation],
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationListPage)),
    );

    container
        .read(groupProvider.notifier)
        .upsertGroup(
          GroupSummary(
            conversationId: conversationId,
            groupId: groupDid,
            displayName: 'Canonical Group',
            description: '',
            memberCount: 2,
            lastMessageAt: DateTime(2026, 7, 14, 10),
          ),
        );
    await tester.pump();

    expect(find.text('Canonical Group'), findsOneWidget);
    expect(
      container.read(conversationListProvider).conversations.single.displayName,
      groupDid,
    );
  });

  testWidgets('macOS 宽度下聊天头部不显示身份卡或会话信息入口', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1600, 960);
    tester.view.devicePixelRatio = 1;

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

    expect(find.byKey(const Key('conversation-search-field')), findsOneWidget);
    expect(
      find.byKey(const Key('conversation-quick-actions-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('start-conversation-button')), findsNothing);
    expect(find.byType(ChatView), findsNothing);

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('安全协作中'), findsOneWidget);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.text('群聊信息'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('桌面消息快捷操作使用锚定菜单和设计稿图标', (tester) async {
    final gateway = FakeAwikiGateway()..conversations = <ConversationSummary>[];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 820);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(const Key('conversation-quick-actions-button'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.byType(AppDropMenu), findsNothing);
    final firstItem = find.byKey(const Key('quick-action-start-conversation'));
    expect(firstItem, findsOneWidget);
    final triggerRect = tester.getRect(trigger);
    final firstItemRect = tester.getRect(firstItem);
    expect(firstItemRect.top, greaterThan(triggerRect.bottom));
    expect(firstItemRect.left, lessThan(triggerRect.left));
    expect(tester.getSemantics(firstItem).role, SemanticsRole.menuItem);

    const expectedIcons = <(String, IconData)>[
      ('quick-action-start-conversation', CupertinoIcons.chat_bubble),
      ('quick-action-create-group', CupertinoIcons.person_2),
      ('quick-action-join-group', CupertinoIcons.plus),
      ('quick-action-follow-contact', CupertinoIcons.person_add),
    ];
    for (final entry in expectedIcons) {
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(Key(entry.$1)),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, entry.$2);
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(firstItem, findsNothing);

    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(firstItem, findsOneWidget);
    await tester.tapAt(const Offset(1000, 700));
    await tester.pumpAndSettle();
    expect(firstItem, findsNothing);
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('移动消息搜索使用白色表层且快捷操作锚定右上角', (tester) async {
    final gateway = FakeAwikiGateway()..conversations = <ConversationSummary>[];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      MediaQuery.sizeOf(tester.element(find.byType(ConversationListPage))),
      const Size(393, 852),
    );

    final searchSurface = tester.widget<DecoratedBox>(
      find.byKey(const Key('compact-conversation-search-surface')),
    );
    final searchDecoration = searchSurface.decoration as BoxDecoration;
    expect(searchDecoration.color, AwikiMeColors.surface);
    expect(searchDecoration.border, isNull);
    final searchField = tester.widget<CupertinoSearchTextField>(
      find.byKey(const Key('conversation-search-field')),
    );
    expect(
      (searchField.decoration as BoxDecoration).color,
      AwikiMeColors.subtleSurface,
    );
    final pageSurface = tester.widget<ColoredBox>(
      find.byKey(const Key('shell-tab-page-surface')),
    );
    expect(pageSurface.color, AwikiMeColors.surface);
    final compactHeader = find.byKey(const Key('shell-compact-header'));
    expect(tester.getRect(compactHeader), const Rect.fromLTWH(0, 0, 393, 64));
    final title = tester.widget<Text>(
      find.descendant(of: compactHeader, matching: find.text('消息')),
    );
    expect(title.style?.fontSize, 16);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(title.style?.height, 1.25);
    expect(find.byKey(const Key('awiki-me-brand-mark')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('shell-quick-actions-button')),
        matching: find.byIcon(CupertinoIcons.add_circled),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('compact-conversation-inline-empty-state')),
      findsOneWidget,
    );
    expect(find.byType(EmptyStateCard), findsNothing);

    final trigger = find.byKey(const Key('shell-quick-actions-button'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.byType(AppDropMenu), findsNothing);
    expect(find.byType(CompactActionSheet, skipOffstage: false), findsNothing);
    final menu = find.byKey(const Key('compact-quick-actions-menu'));
    final pointer = find.byKey(const Key('compact-quick-actions-pointer'));
    expect(menu, findsOneWidget);
    expect(pointer, findsOneWidget);
    final menuRect = tester.getRect(menu);
    final triggerRect = tester.getRect(trigger);
    expect(menuRect.right, 385);
    expect(menuRect.width, 196);
    expect(menuRect.height, 208);
    expect(menuRect.top, greaterThan(triggerRect.bottom));
    expect(tester.getSize(pointer), const Size(20, 10));
    const expectedIcons = <(String, IconData)>[
      ('quick-action-start-conversation', CupertinoIcons.chat_bubble),
      ('quick-action-create-group', CupertinoIcons.person_2),
      ('quick-action-join-group', CupertinoIcons.plus),
      ('quick-action-follow-contact', CupertinoIcons.person_add),
    ];
    for (final entry in expectedIcons) {
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(Key(entry.$1)),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.icon, entry.$2);
      expect(icon.color, AwikiMePalette.actionBlue);
      expect(tester.getSize(find.byKey(Key(entry.$1))).height, 52);
    }

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('窄屏消息分隔线从文字列开始', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final conversation = ConversationSummary(
      threadId: 'dm:separator',
      conversationId: 'dm:separator',
      displayName: 'Separator',
      lastMessagePreview: 'Preview',
      lastMessageAt: DateTime(2026, 8, 1),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:separator',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation];

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

    final separator = tester.getRect(
      find.byKey(const Key('conversation-row-separator:dm:separator')),
    );
    expect(separator.left, 80);
    expect(separator.right, 390);
    expect(separator.height, 1);
  });

  testWidgets('macOS 最近会话点击不等待恢复最近列表完成', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
    final restoreStarted = Completer<void>();
    final restoreCompleter = Completer<void>();
    addTearDown(() {
      if (!restoreCompleter.isCompleted) {
        restoreCompleter.complete();
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
            (ref) => _BlockingRestoreConversationListController(
              ref,
              gateway.conversations,
              restoreStarted: restoreStarted,
              restoreCompleter: restoreCompleter,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);

    await tester.tap(find.text('Marcus Chen'));
    await tester.pump();

    expect(restoreStarted.isCompleted, isTrue);
    expect(find.byType(ChatView), findsOneWidget);

    restoreCompleter.complete();
    await tester.pump();

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话切换时仅新会话选中且底色不交叉动画', (tester) async {
    final secondConversation = ConversationSummary(
      threadId: 'dm:did:me:did:second-peer',
      conversationId: 'dm:did:me:did:second-peer',
      displayName: 'Ada Lovelace',
      lastMessagePreview: 'A second conversation.',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:second-peer',
    );
    final thirdConversation = ConversationSummary(
      threadId: 'dm:did:me:did:third-peer',
      conversationId: 'dm:did:me:did:third-peer',
      displayName: 'Grace Hopper',
      lastMessagePreview: 'A third conversation.',
      lastMessageAt: DateTime(2026, 3, 28, 10, 26),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:third-peer',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        conversation,
        secondConversation,
        thirdConversation,
      ]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': history,
        'did:second-peer': const <ChatMessage>[],
        'did:third-peer': const <ChatMessage>[],
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );

    await tester.tap(find.text('Marcus Chen'));
    await tester.pumpAndSettle();
    expect(
      container.read(selectedConversationProvider),
      conversation.conversationId,
    );

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pump();

    expect(
      container.read(selectedConversationProvider),
      secondConversation.conversationId,
    );
    final conversationTiles = tester.widgetList<AppPressableTile>(
      find.descendant(
        of: find.byKey(const Key('mac-conversation-list-pane')),
        matching: find.byType(AppPressableTile),
      ),
    );
    expect(conversationTiles, isNotEmpty);
    final selectedTile = conversationTiles.singleWhere((tile) => tile.selected);
    final unselectedTiles = conversationTiles.where((tile) => !tile.selected);
    expect(conversationTiles.every((tile) => !tile.animateSelection), isTrue);
    expect(
      conversationTiles.every((tile) => tile.duration == AwikiMeMotion.instant),
      isTrue,
    );
    expect(
      conversationTiles.every(
        (tile) => tile.interactionExitDuration == Duration.zero,
      ),
      isTrue,
    );
    expect(selectedTile.hoverColor, CupertinoColors.transparent);
    expect(selectedTile.hoverBoxShadow, isEmpty);
    expect(selectedTile.selectedBoxShadow, AwikiMeShadows.selectedListItem);
    expect(
      unselectedTiles.every((tile) => tile.hoverColor == AwikiMeColors.surface),
      isTrue,
    );
    expect(
      conversationTiles.every(
        (tile) => tile.pressedColor == AwikiMeColors.subtleSurface,
      ),
      isTrue,
    );
    expect(
      unselectedTiles.every(
        (tile) => tile.hoverBoxShadow == AwikiMeShadows.hoveredListItem,
      ),
      isTrue,
    );

    Finder interactionLayer(String conversationId) => find.descendant(
      of: find.byKey(Key('conversation-row:$conversationId')),
      matching: find.byType(AnimatedOpacity),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Marcus Chen')));
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(find.text('Grace Hopper')));
    await tester.pump();

    expect(
      tester
          .widget<AnimatedOpacity>(
            interactionLayer(conversation.conversationId),
          )
          .duration,
      Duration.zero,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            interactionLayer(thirdConversation.conversationId),
          )
          .duration,
      AwikiMeMotion.instant,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Runtime Agent 会话在非 Mac 聊天页显示收件箱入口并打开全屏页', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      handle: 'me',
      displayName: 'Me',
      jwtToken: 'token',
    );
    final runtimeConversation = ConversationSummary(
      threadId: 'dm:did:me:did:agent:runtime',
      conversationId: 'dm:did:me:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[runtimeConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      }
      ..publicProfilesByQuery = const <String, UserProfile>{
        'did:agent:runtime': UserProfile(
          did: 'did:agent:runtime',
          nickName: 'Hermes',
          bio: 'Runtime Agent',
          tags: <String>['agent'],
          profileMarkdown: 'Hermes profile',
        ),
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ChatPage(conversation: runtimeConversation),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.bySemanticsLabel('Agent 收件箱'), findsNothing);
    await tester.tap(find.byKey(const Key('chat-information-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat-information-peer-row')));
    await tester.pumpAndSettle();

    expect(find.text('智能体信息'), findsOneWidget);
    await tester.tap(find.text('Agent 收件箱'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Agent 收件箱'), findsOneWidget);
    expect(find.text('Hermes'), findsWidgets);
    expect(control.lastInboxDaemonDid, 'did:agent:daemon');
    expect(control.lastInboxRuntimeDid, 'did:agent:runtime');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话只给真实智能体显示 AI 标记且无会话信息入口', (tester) async {
    final humanConversation = ConversationSummary(
      conversationId: 'dm:did:test:human',
      threadId: 'dm:human',
      displayName: '普通用户',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 3, 28, 10, 24),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:human',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:test:agent',
      threadId: 'dm:agent',
      displayName: '远端智能体',
      lastMessagePreview: 'ready',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:agent',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        humanConversation,
        agentConversation,
      ]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:test:human': <ChatMessage>[],
        'did:test:agent': <ChatMessage>[],
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
          peerIdentityServiceProvider.overrideWithValue(
            FakePeerIdentityService(
              identities: const <String, PeerAgentIdentity>{
                'did:test:agent': PeerAgentIdentity.agent(
                  agentKind: PeerAgentKind.runtime,
                ),
              },
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI'), findsOneWidget);

    await tester.tap(find.text('普通用户'));
    await tester.pumpAndSettle();
    expect(find.text('用户'), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    await tester.tap(find.text('远端智能体'));
    await tester.pumpAndSettle();
    expect(find.text('智能体'), findsWidgets);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('macOS 最近会话为正在处理的本地智能体显示状态圆点', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
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
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = AgentsState(agents: control.agents);
            return controller;
          }),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final initialDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(initialDot.status.kind, AgentVisualStatusKind.ready);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: agentConversation,
          content: '请处理',
          expectedAgentReplyDid: 'did:agent:runtime',
        );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('最近会话会主动加载本地智能体状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
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
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          peerIdentityServiceProvider.overrideWithValue(
            FakePeerIdentityService(
              identities: const <String, PeerAgentIdentity>{
                'did:agent:runtime': PeerAgentIdentity.agent(
                  agentKind: PeerAgentKind.runtime,
                ),
              },
            ),
          ),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final dot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(dot.status.kind, AgentVisualStatusKind.ready);
    expect(control.lastRefreshedDaemonDid, 'did:agent:daemon');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话同步显示群聊触发的本地智能体处理中状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      conversationId: 'dm:did:agent:runtime',
      threadId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final groupConversation = ConversationSummary(
      conversationId: 'group:did:group:agent-room',
      threadId: 'group:did:group:agent-room',
      displayName: 'Agent 群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10, 1),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:group:agent-room',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        agentConversation,
        groupConversation,
      ]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      }
      ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
        'did:group:agent-room': <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:agent:runtime',
            did: 'did:agent:runtime',
            handle: 'hermes',
            role: 'member',
            displayName: 'Hermes',
            subjectType: GroupMemberSubjectType.agent,
          ),
        ],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
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
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = AgentsState(agents: control.agents);
            return controller;
          }),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final initialDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(initialDot.status.kind, AgentVisualStatusKind.ready);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    await container
        .read(chatThreadsProvider.notifier)
        .sendMessage(
          conversation: groupConversation,
          content: '@hermes 请处理',
          mentions: const <ChatMentionDraft>[
            ChatMentionDraft(
              localId: 'men_agent',
              surface: '@hermes',
              start: 0,
              end: 7,
              target: ChatMentionTargetDraft.member(
                kind: ChatMentionTargetKind.agent,
                did: 'did:agent:runtime',
                handle: 'hermes',
                displayName: 'Hermes',
              ),
            ),
          ],
        );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);
    final pendingTurn = container
        .read(chatThreadsProvider)[groupConversation.threadId]!
        .agentPendingTurns
        .single;

    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'run',
        'conversation_id': groupConversation.threadId,
        'task_id': 'task_group_mention',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_group_mention',
            'message_id': 'task_group_mention',
            'source_message_id': pendingTurn.remoteMessageId,
            'mention_id': 'men_agent',
            'runtime_agent_did': 'did:agent:runtime',
            'conversation_id': groupConversation.threadId,
            'status': 'failed',
            'updated_at': DateTime(2026, 6, 4, 10, 2).toIso8601String(),
            'last_error_code': 'agent_invocation_denied',
          },
        ],
      },
    );
    await tester.pump(const Duration(milliseconds: 50));

    final settledDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(settledDot.status.kind, AgentVisualStatusKind.ready);
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话用 Controller activity 显示本地智能体处理中状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      threadId: 'dm:did:agent:runtime',
      conversationId: 'dm:did:agent:runtime',
      displayName: 'Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:runtime': <ChatMessage>[],
      };
    final control = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:agent:daemon',
          kind: AgentKind.daemon,
          displayName: '代理 1',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: 'did:agent:runtime',
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:agent:daemon',
          runtime: 'hermes',
          displayName: 'Hermes',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];
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
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(control),
          agentsProvider.overrideWith((ref) {
            final controller = AgentsController(ref);
            controller.state = AgentsState(agents: control.agents);
            return controller;
          }),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final initialDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(initialDot.status.kind, AgentVisualStatusKind.ready);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    container.read(agentsProvider.notifier).applyControlPayload(
      <String, Object?>{
        'schema': AgentControlPayloads.statusSchema,
        'status_scope': 'runtime_activity',
        'daemon_agent_did': 'did:agent:daemon',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_external_activity',
            'runtime_agent_did': 'did:agent:runtime',
            'requester_did': 'did:human:bob',
            'trigger_kind': 'external_direct',
            'status': 'running',
            'updated_at': DateTime(2026, 6, 4, 10, 2).toIso8601String(),
          },
        ],
      },
    );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);
    final thread = container.read(
      chatThreadProvider(agentConversation.threadId),
    );
    expect(thread.agentPendingTurns, isEmpty);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话用运行状态显示远端智能体处理中状态', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final agentConversation = ConversationSummary(
      threadId: 'dm:did:agent:remote-runtime',
      conversationId: 'dm:did:agent:remote-runtime',
      displayName: 'Remote Hermes',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 6, 4, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:agent:remote-runtime',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[agentConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:agent:remote-runtime': <ChatMessage>[],
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
        session: session,
        providerOverrides: <Override>[
          peerIdentityServiceProvider.overrideWithValue(
            FakePeerIdentityService(
              identities: const <String, PeerAgentIdentity>{
                'did:agent:remote-runtime': PeerAgentIdentity.agent(
                  agentKind: PeerAgentKind.runtime,
                ),
              },
            ),
          ),
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AgentStatusDot), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    container.read(chatThreadsProvider.notifier).applyAgentRunStatusPayload(
      <String, Object?>{
        'schema': 'awiki.agent.status.v1',
        'status_scope': 'run',
        'conversation_id': 'direct:did:human:me',
        'task_id': 'task_external_direct',
        'runs': <Object?>[
          <String, Object?>{
            'run_id': 'run_external_direct',
            'message_id': 'task_external_direct',
            'source_message_id': 'msg_external_direct',
            'runtime_agent_did': 'did:agent:remote-runtime',
            'conversation_id': 'direct:did:human:me',
            'status': 'running',
          },
        ],
      },
    );
    await tester.pump(const Duration(milliseconds: 50));

    final processingDot = tester.widget<AgentStatusDot>(
      find.byType(AgentStatusDot).first,
    );
    expect(processingDot.status.kind, AgentVisualStatusKind.processing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 最近会话保留已删除智能体并显示状态', (tester) async {
    final deletedConversation = ConversationSummary(
      threadId: 'dm:deleted-agent',
      conversationId: 'dm:deleted-agent',
      displayName: '旧智能体',
      lastMessagePreview: '旧回复',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:deleted-agent',
      peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[deletedConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:test:deleted-agent': <ChatMessage>[],
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

    expect(find.text('旧智能体'), findsOneWidget);
    expect(find.text('智能体已删除'), findsOneWidget);

    await tester.tap(find.text('旧智能体'));
    await tester.pumpAndSettle();

    expect(find.text('智能体已删除，无法继续发送消息'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('手机最近会话保留已删除状态且聊天页使用发送禁用提示', (tester) async {
    final deletedConversation = ConversationSummary(
      threadId: 'dm:deleted-agent-mobile',
      conversationId: 'dm:deleted-agent-mobile',
      displayName: '旧智能体',
      lastMessagePreview: '旧回复',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:deleted-agent-mobile',
      peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[deletedConversation]
      ..dmHistoryByPeerDid = const <String, List<ChatMessage>>{
        'did:test:deleted-agent-mobile': <ChatMessage>[],
      };
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

    expect(find.text('旧智能体'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('智能体已删除'), findsOneWidget);

    await tester.tap(find.text('旧智能体'));
    await tester.pumpAndSettle();

    expect(find.text('智能体已删除'), findsNothing);
    expect(find.text('智能体已删除，无法继续发送消息'), findsOneWidget);
  });

  testWidgets('macOS 聊天头部移除身份卡按钮但头像仍可打开用户信息弹窗', (tester) async {
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
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    await tester.tap(find.text('Marcus Chen').last);
    await tester.pumpAndSettle();

    expect(find.text('用户信息'), findsOneWidget);
    expect(find.text('负责融资协作。'), findsOneWidget);
    expect(find.text('@marcus'), findsOneWidget);
    expect(find.byKey(const Key('peer-info-dialog-did-value')), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('关闭信息弹窗'));
    await tester.pumpAndSettle();
    expect(find.text('用户信息'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('macOS 群聊头像打开统一信息弹窗且头部不显示入口', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:owner',
      credentialName: 'owner.json',
      displayName: 'Owner',
      handle: 'owner.awiki',
    );
    const groupId = 'did:test:group:funding';
    final group = GroupSummary(
      groupId: groupId,
      conversationId: 'group:$groupId',
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
      membershipStatus: 'active',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      conversationId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupId: const <GroupMemberSummary>[
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
    final messagingService = FakeMessagingService(gateway);
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
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
          messagingServiceProvider.overrideWithValue(messagingService),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('融资协作群').first);
    await tester.pumpAndSettle();
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('群聊信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.byType(GroupDetailPage), findsNothing);

    await tester.tap(find.text('融资协作群').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('群聊信息'), findsWidgets);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('2 人'), findsOneWidget);
    expect(find.text('owner'), findsWidgets);
    expect(
      find.byKey(const Key('group-info-dialog-did-value')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('group-info-dialog-refresh-members-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('group-info-dialog-add-member-button')),
      findsOneWidget,
    );
    expect(find.text('owner.awiki'), findsOneWidget);
    expect(find.text('member.awiki'), findsOneWidget);
    expect(find.textContaining('did:test:owner'), findsNothing);
    expect(find.textContaining('did:test:member'), findsNothing);
    expect(find.byType(GroupDetailPage), findsNothing);

    await tester.tap(find.bySemanticsLabel('关闭信息弹窗'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);

    const memberHandle = 'bob.awiki.ai';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    gateway.publicProfilesByQuery = const <String, UserProfile>{
      memberHandle: UserProfile(
        did: memberDid,
        nickName: 'Bob',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: memberHandle,
        fullHandle: memberHandle,
      ),
    };
    await tester.tap(
      find.byKey(const Key('group-info-dialog-add-member-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加群成员'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      memberHandle,
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-add-group-member-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastAddedGroupId, group.groupId);
    expect(gateway.lastAddedMemberRef, memberHandle);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text(memberDid), findsNothing);
    expect(find.text('3 人'), findsOneWidget);
    expect(messagingService.lastConversationTimelineId, 'group:funding');

    final removeMemberButton = find.bySemanticsLabel('移除成员').last;
    await tester.scrollUntilVisible(
      removeMemberButton,
      180,
      scrollable: find.descendant(
        of: find.byKey(const Key('group-info-dialog-scroll-view')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(removeMemberButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除成员').last);
    await tester.pumpAndSettle();

    expect(gateway.lastRemovedGroupId, group.groupId);
    expect(gateway.lastRemovedMemberRef, memberHandle);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('2 人'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊头部添加成员弹窗不等待远端成员刷新', (tester) async {
    const groupId = 'did:test:group:instant-invite';
    final group = GroupSummary(
      groupId: groupId,
      conversationId: 'group:$groupId',
      name: '即时邀请群',
      description: '',
      memberCount: 1,
      lastMessageAt: DateTime(2026, 7, 13, 18),
      myRole: 'owner',
      membershipStatus: 'active',
    );
    final conversation = ConversationSummary(
      threadId: 'group:instant-invite',
      conversationId: 'group:instant-invite',
      displayName: '即时邀请群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 13, 18),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final memberRefresh = Completer<void>();
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupId: const <GroupMemberSummary>[
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
        session: _groupWorkspaceSession,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('即时邀请群').first);
    await tester.pumpAndSettle();
    final headerAddMember = find.byKey(
      const Key('chat-header-add-group-member-button'),
    );
    expect(headerAddMember, findsOneWidget);
    final renderedHeaderButton = find.descendant(
      of: headerAddMember,
      matching: find.byType(AppIconButton),
    );
    final headerButton = tester.widget<AppIconButton>(renderedHeaderButton);
    final headerResponsive = tester.element(headerAddMember).awikiResponsive;
    final headerIcon = tester.widget<Icon>(
      find.descendant(
        of: headerAddMember,
        matching: find.byIcon(CupertinoIcons.person_add),
      ),
    );
    expect(headerButton.backgroundColor, AwikiMePalette.content);
    expect(headerButton.borderColor, AwikiMePalette.hairline);
    expect(headerButton.size, closeTo(headerResponsive.scaled(34), 0.01));
    expect(
      headerButton.borderRadius,
      BorderRadius.circular(headerResponsive.radius(8)),
    );
    expect(headerIcon.color, AwikiMePalette.mutedNeutral);

    gateway.listGroupMembersCompleter = memberRefresh;
    await tester.tap(headerAddMember);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(memberRefresh.isCompleted, isFalse);
    expect(find.text('添加群成员'), findsOneWidget);

    memberRefresh.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await tester.tap(
      find.descendant(
        of: find.byType(AddGroupMemberDialog),
        matching: find.byIcon(CupertinoIcons.xmark),
      ),
    );
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊信息保留完整群权限避免按钮抖动', (tester) async {
    const groupId = 'did:test:group:funding';
    final fullGroup = GroupSummary(
      groupId: groupId,
      conversationId: 'group:$groupId',
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
      membershipStatus: 'active',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      conversationId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[fullGroup]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupId: const <GroupMemberSummary>[
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
        session: _groupWorkspaceSession,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('group-info-dialog-add-member-button')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('移除成员'), findsWidgets);

    gateway.groups = <GroupSummary>[
      GroupSummary(
        groupId: groupId,
        conversationId: 'group:$groupId',
        name: groupId,
        description: '',
        memberCount: 0,
        lastMessageAt: DateTime(2026, 3, 28, 10, 26),
      ),
    ];
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    await container.read(groupProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('群聊信息'), findsWidgets);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('owner'), findsWidgets);
    expect(
      find.byKey(const Key('group-info-dialog-add-member-button')),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('移除成员').last);
    await tester.pumpAndSettle();

    expect(find.text('移除成员'), findsNWidgets(2));

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 右侧栏空间不足时聊天头部仍不显示信息入口', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{'did:peer': history};
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

    await tester.tap(find.text('Marcus Chen').first);
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsNothing);
    expect(find.text('会话信息'), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 右侧栏空间不足时群聊头像打开统一信息弹窗', (tester) async {
    const groupId = 'did:test:group:funding';
    final group = GroupSummary(
      groupId: groupId,
      conversationId: 'group:$groupId',
      name: '融资协作群',
      description: '同步融资材料和里程碑',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      myRole: 'owner',
      membershipStatus: 'active',
    );
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      conversationId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: groupId,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[groupConversation]
      ..groups = <GroupSummary>[group]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupId: const <GroupMemberSummary>[
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
        session: _groupWorkspaceSession,
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
    expect(find.byKey(const Key('mac-inline-side-panel')), findsNothing);
    expect(find.text('群聊信息'), findsNothing);
    expect(find.byKey(const Key('chat-identity-card-button')), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byKey(const Key('mac-inline-side-panel')), findsNothing);
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);
    expect(find.text('群聊信息'), findsWidgets);
    expect(find.text('同步融资材料和里程碑'), findsOneWidget);
    expect(find.text('owner.awiki'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('关闭信息弹窗'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('同步融资材料和里程碑'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊成员刷新不受群详情空响应影响', (tester) async {
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      conversationId: 'group:funding',
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
          conversationId: 'group:${groupConversation.groupId!}',
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
        session: _groupWorkspaceSession,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

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

    await tester.tap(
      find.byKey(const Key('group-info-dialog-refresh-members-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(feedback, isNull);
    expect(find.text('late-member.awiki'), findsOneWidget);
    expect(find.textContaining('did:test:late-member'), findsNothing);
    expect(find.text('late-role-hidden'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 群聊成员刷新期间显示按钮级 loading', (tester) async {
    final groupConversation = ConversationSummary(
      threadId: 'group:funding',
      conversationId: 'group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'hello group',
      lastMessageAt: DateTime(2026, 3, 28, 10, 25),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group:funding',
    );
    final group = GroupSummary(
      groupId: groupConversation.groupId!,
      conversationId: 'group:${groupConversation.groupId!}',
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
        session: _groupWorkspaceSession,
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
    await tester.tap(find.byKey(const Key('chat-peer-info-avatar-button')));
    await tester.pumpAndSettle();

    gateway.listGroupMembersCompleter = memberRefresh;
    await tester.tap(
      find.byKey(const Key('group-info-dialog-refresh-members-button')),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('group-info-dialog-refresh-members-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsOneWidget,
    );

    memberRefresh.complete();
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('group-info-dialog-refresh-members-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 会话信息头部按钮已移除', (tester) async {
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
    expect(find.text('会话信息'), findsNothing);
    expect(
      find.byKey(const Key('chat-conversation-info-button')),
      findsNothing,
    );
    expect(find.byKey(const Key('mac-side-panel')), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('Windows 宽屏复用桌面主导航和会话工作区', (tester) async {
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
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.binding.setSurfaceSize(const Size(1280, 800));

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

    expect(find.byKey(const Key('mac-desktop-rail-slot')), findsOneWidget);
    expect(find.byKey(const Key('conversation-search-field')), findsOneWidget);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.byKey(const Key('mac-conversation-list-pane')), findsOneWidget);

    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务视图即将接入'), findsOneWidget);

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
    expect(find.byKey(const Key('conversation-search-field')), findsOneWidget);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('Agents'), findsNothing);
    expect(find.byKey(const Key('mac-messages-unread-badge')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('mac-messages-unread-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    final conversationRow = find.byKey(
      Key('conversation-row:${conversation.conversationId}'),
    );
    expect(conversationRow, findsOneWidget);
    final unreadBadge = find.descendant(
      of: conversationRow,
      matching: find.byKey(const Key('conversation-row-unread-badge')),
    );
    expect(unreadBadge, findsOneWidget);
    expect(
      find.descendant(of: unreadBadge, matching: find.text('3')),
      findsOneWidget,
    );
    await tester.tap(find.text('任务'));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务视图即将接入'), findsOneWidget);

    await tester.tap(find.text('工作台'));
    await tester.pumpAndSettle();
    expect(find.textContaining('工作台模块即将接入'), findsOneWidget);

    await tester.tap(find.text('消息'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation-search-field')), findsOneWidget);
    expect(conversationRow, findsOneWidget);

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    expect(find.text('联系人'), findsWidgets);

    await tester.tap(find.byKey(const Key('mac-me-rail-avatar')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('desktop-current-identity-dialog')),
      findsOneWidget,
    );
    expect(find.text('我'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-current-identity-close')));
    await tester.pumpAndSettle();

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
    expect(settingsPaneSize.width, closeTo(272, 0.1));
    expect(settingsPaneSize.width, lessThan(1280 - 64));

    await tester.tap(find.text('消息'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation-search-field')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 会话切到联系人后新消息保持未读', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    final initialAt = DateTime(2026, 7, 29, 10);
    final initial = ConversationSummary(
      threadId: 'dm:peer-scope:v1:tab-hidden',
      conversationId: 'dm:peer-scope:v1:tab-hidden',
      displayName: 'Marcus Chen',
      lastMessagePreview: 'sent before switching tabs',
      lastMessageAt: initialAt,
      unreadCount: 0,
      isGroup: false,
      targetDid: 'did:test:peer',
      lastMessageSnapshot: ChatMessage(
        localId: 'message-before-tab-switch',
        remoteId: 'message-before-tab-switch',
        threadId: 'dm:peer-scope:v1:tab-hidden',
        senderDid: session.did,
        content: 'sent before switching tabs',
        createdAt: initialAt,
        isMine: true,
        serverSequence: 1,
        sendState: MessageSendState.sent,
      ),
    );
    final incomingAt = initialAt.add(const Duration(seconds: 1));
    final incoming = initial.copyWith(
      lastMessagePreview: 'received while contacts are visible',
      lastMessageAt: incomingAt,
      unreadCount: 1,
      lastMessageSnapshot: ChatMessage(
        localId: 'message-after-tab-switch',
        remoteId: 'message-after-tab-switch',
        threadId: initial.threadId,
        senderDid: 'did:test:peer',
        content: 'received while contacts are visible',
        createdAt: incomingAt,
        isMine: false,
        serverSequence: 2,
        sendState: MessageSendState.sent,
      ),
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[initial]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:test:peer': <ChatMessage>[initial.lastMessageSnapshot!],
      };
    late _StaticConversationListController controller;
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
          conversationListProvider.overrideWith((ref) {
            controller = _StaticConversationListController(
              ref,
              gateway.conversations,
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(Key('conversation-row:${initial.conversationId}')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatView), findsOneWidget);

    await tester.tap(find.byKey(const Key('desktop-rail-contacts')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatView), findsNothing);
    expect(find.byType(FriendsWorkspacePage), findsOneWidget);
    expect(
      find.byKey(const Key('friends-expanded-list-header')),
      findsOneWidget,
    );

    controller.upsertConversation(incoming);
    await tester.pumpAndSettle();

    expect(controller.state.unreadCount, 1);
    expect(
      find.descendant(
        of: find.byKey(const Key('mac-messages-unread-badge')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('消息'));
    await tester.pumpAndSettle();
    final row = find.byKey(Key('conversation-row:${initial.conversationId}'));
    expect(
      find.descendant(
        of: row,
        matching: find.text('received while contacts are visible'),
      ),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航智能体标签跟随语言', (tester) async {
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

    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('Agents'), findsNothing);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        locale: const Locale('en'),
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

    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('智能体'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主导航统一使用轻量语义图标', (tester) async {
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

    final rail = find.byKey(const Key('mac-desktop-rail-slot'));
    AwikiMeSemanticIcon railIcon(AwikiMeIconRole role) {
      return tester.widget<AwikiMeSemanticIcon>(
        find.descendant(
          of: rail,
          matching: find.byWidgetPredicate(
            (widget) => widget is AwikiMeSemanticIcon && widget.role == role,
          ),
        ),
      );
    }

    expect(railIcon(AwikiMeIconRole.messages).selected, isTrue);
    expect(
      railIcon(AwikiMeIconRole.messages).color,
      AwikiMePalette.brandAccent,
    );
    for (final role in <AwikiMeIconRole>[
      AwikiMeIconRole.agents,
      AwikiMeIconRole.contacts,
      AwikiMeIconRole.tasks,
      AwikiMeIconRole.workbench,
      AwikiMeIconRole.settings,
    ]) {
      expect(railIcon(role).selected, isFalse);
      expect(railIcon(role).color, AwikiMePalette.mutedNeutral);
    }
    expect(
      tester.getSize(find.byKey(const Key('desktop-rail-messages'))).width,
      closeTo(54 * AwikiDisplayScale.layoutBaseline, 0.01),
    );
    expect(
      railIcon(AwikiMeIconRole.messages).size,
      closeTo(18 * AwikiDisplayScale.layoutBaseline, 0.01),
    );
    expect(
      tester.getCenter(find.byKey(const Key('mac-me-rail-avatar'))).dy,
      lessThan(
        tester.getCenter(find.byKey(const Key('desktop-rail-messages'))).dy,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const Key('desktop-rail-settings'))).dy,
      greaterThan(
        tester.getCenter(find.byKey(const Key('desktop-rail-workbench'))).dy,
      ),
    );

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();

    expect(railIcon(AwikiMeIconRole.messages).selected, isFalse);
    expect(railIcon(AwikiMeIconRole.contacts).selected, isTrue);
    expect(
      railIcon(AwikiMeIconRole.contacts).color,
      AwikiMePalette.brandAccent,
    );

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
      closeTo(64 * AwikiDisplayScale.effective(1.12), 0.1),
    );
    expect(
      tester.getSize(find.byKey(const Key('mac-conversation-list-pane'))).width,
      closeTo(272 * AwikiDisplayScale.effective(1.12), 0.1),
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
      conversationId: 'dm:read',
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
        conversationId: 'dm:read',
        displayName: 'Read Chat',
        lastMessagePreview: 'read',
        lastMessageAt: DateTime(2026, 3, 28, 10, 24),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:read',
      ),
      ConversationSummary(
        threadId: 'dm:unread',
        conversationId: 'dm:unread',
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
    expect(
      find.descendant(
        of: find.byKey(const Key('mac-messages-unread-badge')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 主窗口按可用尺寸切换布局且不溢出', (tester) async {
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
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;

    for (final size in <Size>[
      const Size(360, 780),
      const Size(393, 852),
      const Size(720, 600),
      const Size(960, 640),
      const Size(1280, 800),
      const Size(1440, 900),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      tester.view.physicalSize = size;
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

      expect(MediaQuery.sizeOf(tester.element(find.byType(AppShell))), size);
      final expectsExpanded = size.width >= 720 && size.height >= 600;
      expect(
        find.byKey(const Key('mac-desktop-rail-slot')),
        expectsExpanded ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const Key('conversation-quick-actions-button')),
        expectsExpanded ? findsOneWidget : findsNothing,
      );
      if (!expectsExpanded) {
        expect(find.text('消息'), findsWidgets);
      }
      await tester.tap(find.text('Marcus Chen').first);
      await tester.pumpAndSettle();
      expect(find.byType(ChatView), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('会话详情跨 compact 和 expanded 断点保持选中项与输入草稿', (tester) async {
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
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);

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

    await tester.tap(
      find.byKey(Key('conversation-row:${conversation.conversationId}')),
    );
    await tester.pumpAndSettle();
    final chatInput = find.descendant(
      of: find.byType(ChatView),
      matching: find.byType(CupertinoTextField),
    );
    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('智能体'), findsNothing);
    await tester.enterText(chatInput, '跨断点草稿');
    await tester.pump();

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mac-desktop-rail-slot')), findsOneWidget);
    expect(find.byType(ChatView), findsOneWidget);
    expect(
      tester.widget<CupertinoTextField>(chatInput).controller!.text,
      '跨断点草稿',
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mac-desktop-rail-slot')), findsNothing);
    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('智能体'), findsNothing);
    expect(
      tester.widget<CupertinoTextField>(chatInput).controller!.text,
      '跨断点草稿',
    );

    await tester.tap(find.byKey(const Key('chat-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);
    expect(find.text('智能体'), findsOneWidget);
    expect(
      find.byKey(Key('conversation-row:${conversation.conversationId}')),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Android 系统返回从 compact 私聊回到消息列表', (tester) async {
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
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);

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

    final row = find.byKey(
      Key('conversation-row:${conversation.conversationId}'),
    );
    await tester.tap(row);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );

    expect(find.byType(ChatView), findsOneWidget);
    expect(
      container.read(selectedConversationProvider),
      conversation.conversationId,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(ChatView), findsNothing);
    expect(row, findsOneWidget);
    expect(container.read(selectedConversationProvider), isNull);
    expect(find.byKey(const Key('compact-bottom-navigation')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Android 从我的信息返回消息列表后保留我页根路由', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'me.json',
      displayName: 'Mia',
      handle: 'mia',
      jwtToken: 'token',
    );
    const profile = UserProfile(
      did: 'did:test:me',
      displayName: 'Mia',
      bio: 'Product lead',
      tags: <String>[],
      profileMarkdown: '',
      fullHandle: 'mia.awiki.ai',
    );
    final ownMessage = ChatMessage(
      localId: 'own-message-profile-return',
      remoteId: 'own-message-profile-return',
      conversationId: conversation.conversationId,
      threadId: conversation.threadId,
      senderDid: session.did,
      senderName: session.displayName,
      receiverDid: conversation.targetDid,
      content: 'hello from me',
      createdAt: conversation.lastMessageAt,
      isMine: true,
      sendState: MessageSendState.sent,
    );
    final gateway = FakeAwikiGateway()
      ..myProfile = profile
      ..conversations = <ConversationSummary>[conversation]
      ..localDmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[ownMessage],
      }
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': <ChatMessage>[ownMessage],
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);

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

    await tester.tap(find.byKey(const Key('compact-nav-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-compact-summary')), findsOneWidget);

    await tester.tap(find.byKey(const Key('compact-nav-messages')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('conversation-row:${conversation.conversationId}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('chat-message-avatar:own-message-profile-return:mine'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的信息'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('我的信息'), findsNothing);
    expect(find.byType(ChatView), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatView), findsNothing);
    expect(
      find.byKey(Key('conversation-row:${conversation.conversationId}')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('compact-nav-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-compact-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);

    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('Android 系统返回逐层关闭用户信息和聊天信息页', (tester) async {
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
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);

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

    await tester.tap(
      find.byKey(Key('conversation-row:${conversation.conversationId}')),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    await tester.tap(find.byKey(const Key('chat-information-button')));
    await tester.pumpAndSettle();
    expect(find.text('聊天信息'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat-information-peer-row')));
    await tester.pumpAndSettle();
    expect(find.text('用户信息'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('用户信息'), findsNothing);
    expect(find.text('聊天信息'), findsOneWidget);
    expect(
      container.read(selectedConversationProvider),
      conversation.conversationId,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('聊天信息'), findsNothing);
    expect(find.byType(ChatView), findsOneWidget);
    expect(
      container.read(selectedConversationProvider),
      conversation.conversationId,
    );

    debugDefaultTargetPlatformOverride = null;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
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
        conversationId: 'group:funding',
        displayName: '融资协作群',
        lastMessagePreview: '明早同步 deck',
        lastMessageAt: DateTime(2026, 3, 28, 10, 25),
        unreadCount: 0,
        isGroup: true,
        groupId: 'did:test:group:funding',
      ),
      ConversationSummary(
        threadId: 'dm:did:me:did:ops',
        conversationId: 'dm:did:me:did:ops',
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
    expect(
      tester.getSize(find.byKey(const Key('conversation-search-field'))).height,
      closeTo(32 * AwikiDisplayScale.layoutBaseline, 0.01),
    );
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

  testWidgets('手机宽度下最近会话搜索支持标题和最近消息预览', (tester) async {
    final conversations = <ConversationSummary>[
      conversation,
      ConversationSummary(
        threadId: 'group:funding',
        conversationId: 'group:funding',
        displayName: '融资协作群',
        lastMessagePreview: '明早同步 deck',
        lastMessageAt: DateTime(2026, 3, 28, 10, 25),
        unreadCount: 0,
        isGroup: true,
        groupId: 'did:test:group:funding',
      ),
      ConversationSummary(
        threadId: 'dm:did:me:did:ops',
        conversationId: 'dm:did:me:did:ops',
        displayName: 'Ops Bot',
        lastMessagePreview: 'server alert recovered',
        lastMessageAt: DateTime(2026, 3, 28, 10, 26),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:ops',
      ),
    ];
    final gateway = FakeAwikiGateway()..conversations = conversations;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(ref, conversations),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('conversation-search-field')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('conversation-search-field'))).height,
      closeTo(52 * AwikiDisplayScale.layoutBaseline, 0.01),
    );
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
  });

  testWidgets('手机四入口与桌面身份 Dialog 在跨断点时保持有效状态', (tester) async {
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

    expect(find.text('消息'), findsWidgets);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('联系人'), findsOneWidget);
    expect(find.text('我'), findsOneWidget);
    expect(find.byKey(const Key('compact-bottom-navigation')), findsOneWidget);
    expect(find.text('Agents'), findsNothing);
    final shellBackground = tester.widget<DecoratedBox>(
      find.byKey(const Key('app-shell-page-background')),
    );
    expect(
      (shellBackground.decoration as BoxDecoration).color,
      AwikiMeColors.surface,
    );
    final navRow = find
        .descendant(
          of: find.byKey(const Key('compact-bottom-navigation')),
          matching: find.byType(Row),
        )
        .first;
    expect(
      find.byKey(const Key('mobile-messages-unread-badge')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mobile-messages-unread-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    final tabKeys = <Key>[
      const Key('compact-nav-messages'),
      const Key('compact-nav-agents'),
      const Key('compact-nav-contacts'),
      const Key('compact-nav-profile'),
    ];
    final tabRects = tabKeys.map((key) => tester.getRect(find.byKey(key)));
    final firstTabWidth = tabRects.first.width;
    for (final rect in tabRects) {
      expect(rect.width, closeTo(firstTabWidth, 0.1));
      expect(rect.height, greaterThanOrEqualTo(44));
    }
    final iconSlotSizes = tabKeys.map(
      (key) => tester.getSize(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(AwikiMeSemanticIcon),
        ),
      ),
    );
    for (final size in iconSlotSizes) {
      expect(size, const Size.square(22 * AwikiDisplayScale.layoutBaseline));
    }
    final bottomNavHeight = tester.getSize(navRow).height;
    expect(bottomNavHeight, closeTo(62, 0.1));
    final navRowCenterY = tester.getCenter(navRow).dy;
    final messageLabelCenterY = tester.getCenter(find.text('消息').last).dy;
    expect(messageLabelCenterY, lessThan(navRowCenterY + 22));
    final navRowRect = tester.getRect(navRow);
    final mobileBadgeRect = tester.getRect(
      find.byKey(const Key('mobile-messages-unread-badge')),
    );
    expect(mobileBadgeRect.top, greaterThanOrEqualTo(navRowRect.top));
    expect(mobileBadgeRect.right, lessThanOrEqualTo(navRowRect.right));

    final navLabels = find
        .descendant(of: navRow, matching: find.byType(Text))
        .evaluate()
        .map((element) => (element.widget as Text).data)
        .whereType<String>()
        .where((label) => <String>{'消息', '智能体', '联系人', '我'}.contains(label))
        .toList();
    expect(navLabels, ['消息', '联系人', '智能体', '我']);

    await tester.tap(find.text('智能体'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentsWorkspacePage), findsOneWidget);
    expect(find.text('智能体'), findsWidgets);

    await tester.tap(find.text('联系人'));
    await tester.pumpAndSettle();
    expect(find.text('联系人'), findsWidgets);

    await tester.tap(find.byKey(const Key('compact-nav-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-compact-summary')), findsOneWidget);
    expect(find.byKey(const Key('profile-back-button')), findsNothing);
    expect(find.byKey(const Key('compact-bottom-navigation')), findsOneWidget);
    expect(
      find.byKey(const Key('mobile-messages-unread-badge')),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('desktop-current-identity-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('profile-sidebar-summary')), findsNothing);
    expect(find.byKey(const Key('mac-conversation-list-pane')), findsOneWidget);

    await tester.tap(find.byKey(const Key('desktop-current-identity-close')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compact-bottom-navigation')), findsOneWidget);
    expect(find.byKey(const Key('profile-compact-summary')), findsNothing);
    expect(
      find.byKey(const Key('mobile-messages-unread-badge')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('mobile-messages-unread-badge')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('compact-nav-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-settings-row')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-profile-row')), findsOneWidget);
    expect(find.byKey(const Key('compact-bottom-navigation')), findsNothing);
    await tester.tap(find.byKey(const Key('settings-back-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compact-bottom-navigation')), findsOneWidget);
    expect(find.text('消息'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机主导航英文环境显示 Agents', (tester) async {
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
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        locale: const Locale('en'),
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

    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);
    expect(find.text('智能体'), findsNothing);

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentsWorkspacePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机消息列表在头像展示未读并在标题行展示时间', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final richConversation = ConversationSummary(
      threadId: 'dm:mobile-right-meta',
      conversationId: 'dm:mobile-right-meta',
      displayName: 'Mobile Runtime Agent',
      lastMessagePreview: '这是一段很长的最近消息预览，用来验证右侧时间、状态和未读数量不会被遮挡。',
      lastMessageAt: DateTime(2026, 12, 31, 23, 59),
      unreadCount: 120,
      isGroup: false,
      targetDid: 'did:wba:anpclaw.com:agent:runtime:mobile:e1_agent',
      targetPeer: 'mobile-agent.anpclaw.com',
      avatarSeed: 'Mobile Runtime Agent',
    );
    final agent = AgentSummary(
      agentDid: richConversation.targetDid!,
      kind: AgentKind.runtime,
      daemonAgentDid: 'did:test:daemon',
      runtime: 'hermes',
      handle: 'mobile-agent',
      displayName: 'Mobile Runtime Agent',
      activeState: 'active',
      latest: const AgentLatestStatus(
        status: 'needs_config',
        needsConfig: true,
      ),
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[richConversation];
    final control = FakeAgentControlService()..agents = <AgentSummary>[agent];
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) =>
                _StaticConversationListController(ref, gateway.conversations),
          ),
          agentControlServiceProvider.overrideWithValue(control),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mobile Runtime Agent'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('未读 120'), findsNothing);
    expect(find.byType(AgentStatusDot), findsOneWidget);
    final rowRect = tester.getRect(
      find.ancestor(
        of: find.text('Mobile Runtime Agent'),
        matching: find.byType(AppPressableTile),
      ),
    );
    final metaRect = tester.getRect(
      find.byKey(const Key('conversation-row-right-meta')),
    );
    expect(rowRect.height, closeTo(74 * AwikiDisplayScale.layoutBaseline, 0.1));
    final unreadBadge = find.byKey(const Key('conversation-row-unread-badge'));
    expect(unreadBadge, findsOneWidget);
    final unreadBadgeRect = tester.getRect(unreadBadge);
    final timeRect = tester.getRect(find.text('12-31'));
    expect(metaRect.right, lessThanOrEqualTo(rowRect.right));
    expect(timeRect.right, lessThanOrEqualTo(rowRect.right - 2));
    expect(unreadBadgeRect.left, greaterThanOrEqualTo(rowRect.left));
    expect(unreadBadgeRect.right, lessThanOrEqualTo(rowRect.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机会话左滑显示删除操作并使用紧凑确认框', (tester) async {
    const session = SessionIdentity(
      did: 'did:human:me',
      credentialName: 'me.json',
      displayName: 'Me',
      handle: 'me',
    );
    final target = ConversationSummary(
      threadId: 'dm:swipe-delete',
      conversationId: 'dm:swipe-delete',
      displayName: 'Swipe Target',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 8, 3, 14, 20),
      unreadCount: 1,
      isGroup: false,
      targetDid: 'did:test:swipe-target',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[target];
    late _RecordingDeleteConversationListController controller;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith((ref) {
            controller = _RecordingDeleteConversationListController(
              ref,
              gateway.conversations,
            );
            return controller;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(Key('conversation-row:${target.conversationId}'));
    await tester.drag(row, const Offset(-120, 0));
    await tester.pumpAndSettle();

    final deleteAction = find.byKey(
      Key('conversation-row-delete:${target.conversationId}'),
    );
    expect(deleteAction, findsOneWidget);
    final rowSurface = find.descendant(
      of: row,
      matching: find.byType(AppPressableTile),
    );
    expect(
      tester.getTopLeft(rowSurface).dx,
      lessThan(tester.getTopLeft(row).dx),
    );

    await tester.tap(deleteAction);
    await tester.pumpAndSettle();

    final dialog = find.byType(AppConfirmationDialog);
    expect(dialog, findsOneWidget);
    expect(deleteAction, findsNothing);
    expect(find.text('删除会话'), findsOneWidget);
    expect(find.text('从最近列表移除该会话'), findsOneWidget);
    expect(find.text('同时清空历史消息'), findsOneWidget);
    expect(find.text('单会话历史清理待 Core 支持'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoCheckbox>(find.byType(CupertinoCheckbox))
          .onChanged,
      isNull,
    );
    expect(controller.deletedConversation, isNull);

    await tester.tap(find.descendant(of: dialog, matching: find.text('删除')));
    await tester.pumpAndSettle();

    expect(
      controller.deletedConversation?.conversationId,
      target.conversationId,
    );
    expect(row, findsNothing);
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

  testWidgets('macOS 双栏刷新后按 exact conversation ID 保持选中会话', (tester) async {
    const agentDid = 'did:wba:awiki.ai:agent:runtime:test';
    const agentHandle = 'test-agent.awiki.ai';
    final controllerConversation = ConversationSummary(
      conversationId: 'dm:peer-scope:v1:controller',
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
      conversationId: 'dm:peer-scope:v1:runtime',
      threadId: 'dm:peer-scope:v1:runtime',
      displayName: 'Runtime Agent',
      lastMessagePreview: 'runtime preview',
      lastMessageAt: DateTime(2026, 7, 3, 7, 10),
      unreadCount: 0,
      isGroup: false,
      targetDid: agentDid,
      targetPeer: agentHandle,
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        runtimeConversation,
        controllerConversation,
      ]
      ..localDmHistoryByPeerDid = const <String, List<ChatMessage>>{};
    late _StaticConversationListController listController;
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
          conversationListProvider.overrideWith((ref) {
            listController = _StaticConversationListController(
              ref,
              gateway.conversations,
            );
            return listController;
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Controller'));
    await tester.pumpAndSettle();

    ChatView chatView() => tester.widget<ChatView>(find.byType(ChatView));
    expect(chatView().conversation.threadId, controllerConversation.threadId);

    listController.replaceConversations(<ConversationSummary>[
      runtimeConversation.copyWith(
        lastMessagePreview: 'runtime refreshed',
        lastMessageAt: DateTime(2026, 7, 3, 7, 12),
      ),
      controllerConversation.copyWith(
        displayName: 'Controller Refreshed',
        lastMessagePreview: 'controller refreshed',
        lastMessageAt: DateTime(2026, 7, 3, 7, 11),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(chatView().conversation.threadId, controllerConversation.threadId);
    expect(chatView().conversation.displayName, 'Controller Refreshed');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });
}
