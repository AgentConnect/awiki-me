import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_list_page.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_workspace_page.dart';
import 'package:flutter/cupertino.dart';
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

  testWidgets('手机宽度下点击会话进入独立聊天页', (tester) async {
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[conversation]
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': history,
      };
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationListPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(
              ref,
              gateway.conversations,
            ),
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
      ..dmHistoryByPeerDid = <String, List<ChatMessage>>{
        'did:peer': history,
      };
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1024, 768));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ConversationWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          conversationListProvider.overrideWith(
            (ref) => _StaticConversationListController(
              ref,
              gateway.conversations,
            ),
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
