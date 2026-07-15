import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/shared/identity_flow.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  const session = SessionIdentity(
    did: 'did:test:me',
    credentialName: 'me.json',
    displayName: 'Me',
    handle: 'me',
    jwtToken: 'token',
  );

  const peerProfile = UserProfile(
    did: 'did:test:peer',
    nickName: 'CGW Agent',
    bio: '融资协作 Agent',
    tags: <String>['Agent'],
    profileMarkdown: '',
    handle: 'cgw.awiki.ai',
  );

  testWidgets('通过 handle 发起新消息后打开空单聊', (tester) async {
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = <String, UserProfile>{
        'cgw.awiki.ai': peerProfile,
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'cgw.awiki.ai': 'dm:peer-scope:v1:canonical-peer',
      };
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 820));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('start-conversation-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      '@cgw.awiki.ai',
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('identity-preview-handle-value')))
          .data,
      '@cgw.awiki.ai',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('identity-preview-display-name')))
          .data,
      'CGW Agent',
    );
    await tester.tap(find.byKey(const Key('identity-start-chat-button')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('CGW Agent'), findsWidgets);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConversationWorkspacePage)),
    );
    final conversation = tester
        .widget<ChatView>(find.byType(ChatView))
        .conversation;
    expect(conversation.conversationId, 'dm:peer-scope:v1:canonical-peer');
    expect(conversation.threadId, 'dm:peer-scope:v1:canonical-peer');
    expect(conversation.threadId.startsWith('dm:pending:'), isFalse);
    final messaging = container.read(messagingServiceProvider);
    expect(messaging, isA<FakeMessagingService>());
    final fakeMessaging = messaging as FakeMessagingService;
    expect(fakeMessaging.conversationTimelineCalls, greaterThan(0));
    expect(
      fakeMessaging.lastConversationTimelineId,
      'dm:peer-scope:v1:canonical-peer',
    );
    await container.read(conversationListProvider.notifier).refresh();
    await tester.pump();
    final recentConversations = container
        .read(conversationListProvider)
        .conversations;
    expect(recentConversations, hasLength(1));
    expect(recentConversations.single.targetDid, peerProfile.did);
    expect(recentConversations.single.lastMessagePreview, isEmpty);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('联系人裸 handle 入口通过 DID 解析后只打开 canonical 单聊', (tester) async {
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:peer',
          displayName: 'CGW Agent',
          relationship: 'following',
          handle: 'cgw',
        ),
      ]
      ..publicProfilesByQuery = <String, UserProfile>{
        'did:test:peer': peerProfile,
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'did:test:peer': 'dm:peer-scope:v1:canonical-peer',
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendsPage)),
    );
    await container.read(friendsProvider.notifier).refresh();
    await tester.pumpAndSettle();

    final contactRow = find.byKey(const Key('contact-row:did:test:peer'));
    expect(contactRow, findsOneWidget);
    await tester.tap(contactRow);
    await tester.pumpAndSettle();

    final opened = selectedConversationSummary(container);
    expect(opened, isNotNull);
    expect(opened!.conversationId, 'dm:peer-scope:v1:canonical-peer');
    expect(opened.threadId, 'dm:peer-scope:v1:canonical-peer');
    expect(opened.targetDid, 'did:test:peer');
    expect(opened.targetPeer, 'cgw.awiki.ai');
    final rows = container.read(conversationListProvider).conversations;
    expect(rows, hasLength(1));
    expect(rows.single.conversationId, opened.conversationId);
  });

  testWidgets('handle-backed 解析缺少 canonical ID 时 fail closed', (tester) async {
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:peer',
          displayName: 'CGW Agent',
          relationship: 'following',
          handle: 'cgw.awiki.ai',
        ),
      ]
      ..publicProfilesByQuery = <String, UserProfile>{
        'cgw.awiki.ai': peerProfile,
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendsPage)),
    );
    await container.read(friendsProvider.notifier).refresh();
    await tester.pumpAndSettle();

    final contactRow = find.byKey(const Key('contact-row:did:test:peer'));
    expect(contactRow, findsOneWidget);
    await tester.tap(contactRow);
    await tester.pumpAndSettle();

    expect(find.byType(ChatView), findsNothing);
    expect(container.read(conversationListProvider).conversations, isEmpty);
    expect(container.read(selectedConversationProvider), isNull);
  });

  testWidgets('纯 DID identity 返回 legacy conversation ID 时 fail closed', (
    tester,
  ) async {
    const pureDidProfile = UserProfile(
      did: 'did:test:pure-peer',
      displayName: 'Pure DID Peer',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
    );
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:pure-peer',
          displayName: 'Pure DID Peer',
          relationship: 'following',
        ),
      ]
      ..publicProfilesByQuery = const <String, UserProfile>{
        'did:test:pure-peer': pureDidProfile,
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'did:test:pure-peer': 'dm:did:test:pure-peer',
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendsPage)),
    );
    await container.read(friendsProvider.notifier).refresh();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contact-row:did:test:pure-peer')));
    await tester.pumpAndSettle();

    expect(container.read(selectedConversationProvider), isNull);
    expect(container.read(conversationListProvider).conversations, isEmpty);
  });

  testWidgets('最近会话更多操作菜单使用更多操作标题', (tester) async {
    final gateway = FakeAwikiGateway();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 820));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('conversation-quick-actions-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多操作'), findsOneWidget);
    expect(find.text('快捷操作'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('关注联系人先解析身份再关注该身份', (tester) async {
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = <String, UserProfile>{
        'cgw.awiki.ai': peerProfile,
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const _IdentityFlowHarness(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注联系人'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      'cgw.awiki.ai',
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('identity-add-contact-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-add-contact-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastFollowedDidOrHandle, 'did:test:peer');
    expect(gateway.following.single.did, 'did:test:peer');
  });

  testWidgets('联系人页快捷操作关注联系人会打开解析流并关注', (tester) async {
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = <String, UserProfile>{
        'cgw.awiki.ai': peerProfile,
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is TopBarActionButton && widget.semanticsLabel == '更多操作',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('关注联系人'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      'cgw.awiki.ai',
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-add-contact-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastFollowedDidOrHandle, 'did:test:peer');
    expect(gateway.following.single.did, 'did:test:peer');
  });
}

class _IdentityFlowHarness extends ConsumerWidget {
  const _IdentityFlowHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      child: Center(
        child: SizedBox(
          width: 240,
          child: AppPrimaryButton(
            label: '关注联系人',
            onPressed: () => showFollowIdentityDialog(context, ref),
          ),
        ),
      ),
    );
  }
}
