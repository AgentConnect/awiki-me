import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
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

    expect(find.text('CGW Agent'), findsOneWidget);
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
    expect(conversation.conversationId, 'dm:did:test:peer');
    expect(conversation.threadId, 'dm:did:test:peer');
    expect(conversation.threadId.startsWith('dm:pending:'), isFalse);
    final messaging = container.read(messagingServiceProvider);
    expect(messaging, isA<FakeMessagingService>());
    final fakeMessaging = messaging as FakeMessagingService;
    expect(fakeMessaging.conversationTimelineCalls, greaterThan(0));
    expect(fakeMessaging.lastConversationTimelineId, 'dm:did:test:peer');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
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
