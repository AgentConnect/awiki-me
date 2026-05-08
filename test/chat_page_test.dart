import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
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

    expect(gateway.lastSentThreadId, 'dm:1');
    expect(gateway.lastSentContent, 'hello');
    expect(find.text('hello'), findsOneWidget);
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
    expect(gateway.lastSentThreadId, 'dm:failed');
    expect(gateway.lastSentContent, 'hello');
  });
}
