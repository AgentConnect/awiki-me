import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_list_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    expect(find.text('安全协作中'), findsOneWidget);

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
    expect(find.text('Me'), findsOneWidget);
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

    await tester.tap(find.text('配置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);

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
