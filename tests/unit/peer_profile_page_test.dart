import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_profile_page.dart';
import 'package:awiki_me/src/presentation/shared/identity_profile_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  const testSession = SessionIdentity(
    did: 'did:test:me',
    credentialName: 'me.json',
    displayName: 'Me',
  );

  testWidgets('未关注的公开资料可执行真实关注并更新关系状态', (tester) async {
    const did = 'did:test:peer-to-follow';
    const profile = UserProfile(
      did: did,
      displayName: 'Peer To Follow',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{did: profile};

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        session: testSession,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('peer-profile-identity-hero')), findsOneWidget);
    expect(find.byKey(const Key('peer-profile-action-row')), findsOneWidget);
    expect(find.byType(IdentityDocumentContent), findsOneWidget);
    expect(find.byKey(const Key('peer-profile-follow')), findsOneWidget);
    await tester.tap(find.byKey(const Key('peer-profile-follow')));
    await tester.pumpAndSettle();

    expect(gateway.lastFollowedDidOrHandle, did);
    expect(find.byKey(const Key('peer-profile-follow')), findsNothing);
    expect(find.text('取消关注'), findsOneWidget);
  });

  testWidgets('关注列表已有联系人时资料页显示取消关注而不是重复关注', (tester) async {
    const did = 'did:test:already-following';
    const profile = UserProfile(
      did: did,
      displayName: 'Already Following',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
    );
    const following = RelationshipSummary(
      did: did,
      displayName: 'Already Following',
      relationship: 'following',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{did: profile}
      ..relationshipsByDidOrHandle = <String, RelationshipSummary>{
        did: const RelationshipSummary(
          did: did,
          displayName: 'Already Following',
          relationship: 'follower',
        ),
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        session: testSession,
        homepageMarkdownLoader: (_) async => null,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _SeededFriendsController(
              ref,
              const FriendsState(following: <RelationshipSummary>[following]),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('peer-profile-follow')), findsNothing);
    expect(find.byKey(const Key('peer-profile-unfollow')), findsOneWidget);
    expect(find.text('朋友'), findsOneWidget);

    await tester.tap(find.byKey(const Key('peer-profile-unfollow')));
    await tester.pumpAndSettle();

    expect(gateway.lastUnfollowedDidOrHandle, did);
    expect(find.byKey(const Key('peer-profile-follow')), findsOneWidget);
    expect(find.text('关注了我'), findsOneWidget);
  });

  testWidgets('私聊资料页按名称、handle、DID 排列并复制完整 DID', (tester) async {
    const longDid =
        'did:awiki:user:cgw-agent-lab:e1_abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789';
    const profile = UserProfile(
      did: longDid,
      nickName: 'CGW Agent',
      bio: '融资协作 Agent',
      tags: <String>['Agent'],
      profileMarkdown: '## CGW Agent\n\n融资协作 Agent',
      handle: 'cgw.awiki.ai',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{longDid: profile};
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

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
        home: const PeerProfilePage(did: longDid),
        gateway: gateway,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    final didFinder = find.byKey(const Key('peer-profile-did-value'));
    expect(didFinder, findsOneWidget);
    final didText = tester.widget<Text>(didFinder);
    expect(didText.data, isNot(longDid));
    expect(didText.data, startsWith('did:awiki:user:cgw-agent-lab:e1_'));
    expect(didText.data, contains('…'));
    expect(didText.data, endsWith('yz0123456789'));
    expect(didText.maxLines, 2);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('peer-profile-handle-value')))
          .data,
      '@cgw.awiki.ai',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('peer-profile-display-name')))
          .data,
      'CGW Agent',
    );
    expect(find.text('CGW Agent'), findsOneWidget);
    expect(find.text('@cgw.awiki.ai'), findsOneWidget);
    expect(
      find.byKey(const Key('peer-profile-copy-did-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('peer-profile-copy-did-button')));
    await tester.pump();

    expect(clipboardText, longDid);
    expect(find.text('DID 已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('私聊资料页主页链接优先使用 fullHandle', (tester) async {
    const did = 'did:wba:anpclaw.com:zhuocheng:e1_key';
    const profile = UserProfile(
      did: did,
      nickName: 'zhuocheng',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'zhuocheng',
      fullHandle: 'zhuocheng.anpclaw.com',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{did: profile};
    String? requestedHomepageUrl;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        homepageMarkdownLoader: (url) async {
          requestedHomepageUrl = url;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedHomepageUrl, 'https://zhuocheng.anpclaw.com');
    expect(
      find.descendant(
        of: find.byKey(const Key('peer-profile-details')),
        matching: find.text('zhuocheng.anpclaw.com'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('窄屏第 3 版资料页使用 16px 紧凑按钮并保留 48dp 触控区', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const did =
        'did:wba:agent-connect.cn:user:newhandle1:e1_abcdefghijklmnopqrstuvwxyz0123456789';
    const profile = UserProfile(
      did: did,
      nickName: 'newhandle1.agent-connect.cn',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      fullHandle: 'newhandle1.agent-connect.cn',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{did: profile};

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        session: testSession,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(IdentityProfileCard), findsNothing);
    expect(find.byType(IdentityDocumentCard), findsNothing);
    expect(find.byKey(const Key('peer-profile-details')), findsOneWidget);
    expect(find.text('DID'), findsOneWidget);
    expect(find.text('主页'), findsOneWidget);
    expect(find.text('身份卡'), findsOneWidget);
    expect(find.text('暂无资料'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('peer-profile-display-name')))
          .data,
      'newhandle1',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('peer-profile-handle-value')))
          .data,
      '@newhandle1.agent-connect.cn',
    );

    expect(
      tester.getSize(find.byKey(const Key('peer-profile-avatar'))),
      const Size(60, 60),
    );
    expect(
      tester.getSize(find.byKey(const Key('peer-profile-send-message'))).height,
      48,
    );
    expect(
      tester.getSize(find.byKey(const Key('peer-profile-follow'))).height,
      48,
    );
    expect(
      tester.getSize(find.byKey(const Key('peer-profile-send-message-visual'))),
      const Size(84, 40),
    );
    expect(
      tester.getSize(find.byKey(const Key('peer-profile-relationship-visual'))),
      const Size(80, 40),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('peer-profile-delete-thread-visual')))
          .height,
      40,
    );

    for (final entry in <(Key, String)>[
      (const Key('peer-profile-send-message-visual'), '发消息'),
      (const Key('peer-profile-relationship-visual'), '关注'),
      (const Key('peer-profile-delete-thread-visual'), '删除本地聊天记录'),
    ]) {
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(entry.$1),
          matching: find.text(entry.$2),
        ),
      );
      expect(text.style?.fontSize, 16);
    }

    final sendRect = tester.getRect(
      find.byKey(const Key('peer-profile-send-message-visual')),
    );
    final followRect = tester.getRect(
      find.byKey(const Key('peer-profile-relationship-visual')),
    );
    expect(sendRect.center.dy, followRect.center.dy);
    expect(sendRect.right, lessThan(followRect.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('私聊资料页发消息使用 Core 解析的 canonical ID', (tester) async {
    const did = 'did:wba:awiki.info:alice:e1_key';
    const profile = UserProfile(
      did: did,
      nickName: 'Alice',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'alice',
      fullHandle: 'alice.awiki.info',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        did: profile,
        'alice.awiki.info': profile,
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'alice.awiki.info': 'dm:peer-scope:v1:alice',
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        session: const SessionIdentity(
          did: 'did:test:me',
          credentialName: 'me.json',
          displayName: 'Me',
        ),
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PeerProfilePage)),
    );

    await tester.tap(find.text('发消息'));
    await tester.pumpAndSettle();

    final opened = tester.widget<ChatView>(find.byType(ChatView)).conversation;
    expect(opened.conversationId, 'dm:peer-scope:v1:alice');
    final rows = container.read(conversationListProvider).conversations;
    expect(rows, hasLength(1));
    expect(rows.single.conversationId, 'dm:peer-scope:v1:alice');
  });

  testWidgets('私聊资料页不为未知会话构造 DID conversation id', (tester) async {
    const did = 'did:wba:awiki.info:alice:e1_key';
    const profile = UserProfile(
      did: did,
      nickName: 'Alice',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'alice',
      fullHandle: 'alice.awiki.info',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        did: profile,
        'alice.awiki.info': profile,
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'alice.awiki.info': 'dm:peer-scope:v1:alice',
      };
    final chatThreads = _RecordingChatThreadsControllerPlaceholder();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        session: testSession,
        homepageMarkdownLoader: (_) async => null,
        providerOverrides: <Override>[
          chatThreadsProvider.overrideWith((ref) {
            return _RecordingChatThreadsController(ref, chatThreads);
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除本地聊天记录'));
    await tester.pumpAndSettle();

    expect(chatThreads.deletedConversationIds, isEmpty);
  });

  testWidgets('私聊资料页只删除 Core canonical 会话', (tester) async {
    const did = 'did:wba:awiki.info:alice:e1_key';
    const conversationId = 'dm:peer-scope:v1:alice';
    const profile = UserProfile(
      did: did,
      nickName: 'Alice',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'alice',
      fullHandle: 'alice.awiki.info',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        did: profile,
        'alice.awiki.info': profile,
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'alice.awiki.info': conversationId,
      };
    final chatThreads = _RecordingChatThreadsControllerPlaceholder();
    final conversation = ConversationSummary(
      conversationId: conversationId,
      threadId: 'legacy-wire-thread',
      displayName: 'Alice',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 14),
      unreadCount: 0,
      isGroup: false,
      targetDid: did,
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        session: testSession,
        homepageMarkdownLoader: (_) async => null,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(ref, conversation),
          ),
          chatThreadsProvider.overrideWith((ref) {
            return _RecordingChatThreadsController(ref, chatThreads);
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除本地聊天记录'));
    await tester.pumpAndSettle();

    expect(chatThreads.deletedConversationIds, <String>[conversationId]);
  });
}

class _RecordingChatThreadsControllerPlaceholder {
  final List<String> deletedConversationIds = <String>[];
}

class _SeededFriendsController extends FriendsController {
  _SeededFriendsController(super.ref, FriendsState initialState) {
    state = initialState;
  }
}

class _StaticConversationListController extends ConversationListController {
  _StaticConversationListController(
    super.ref,
    ConversationSummary conversation,
  ) {
    state = ConversationListState(
      conversations: <ConversationSummary>[conversation],
    );
  }
}

class _RecordingChatThreadsController extends ChatThreadsController {
  _RecordingChatThreadsController(super.ref, this.placeholder);

  final _RecordingChatThreadsControllerPlaceholder placeholder;

  @override
  Future<void> deleteConversation(ConversationSummary conversation) async {
    placeholder.deletedConversationIds.add(conversation.conversationId);
  }
}
