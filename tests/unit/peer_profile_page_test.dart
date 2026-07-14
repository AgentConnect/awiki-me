import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_profile_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('私聊资料页以 handle 为主并紧凑显示 DID，复制保留全值', (tester) async {
    const longDid =
        'did:awiki:user:cgw-agent-lab:e1_abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789';
    const profile = UserProfile(
      did: longDid,
      nickName: 'CGW Agent',
      bio: '融资协作 Agent',
      tags: <String>['Agent'],
      profileMarkdown: '',
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
    expect(find.text('https://zhuocheng.anpclaw.com'), findsOneWidget);
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

    final selected = selectedConversationSummary(container);
    expect(selected?.conversationId, 'dm:peer-scope:v1:alice');
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
