import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/group/create_group_page.dart';
import 'package:flutter/cupertino.dart';
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

  testWidgets('创建群成功后直接进入群聊', (tester) async {
    final gateway = FakeAwikiGateway()..loginResult = session;
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CreateGroupPage(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).first, '融资协作群');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.lastCreatedGroupName, '融资协作群');
    expect(find.byType(ChatView), findsOneWidget);
    expect(find.text('融资协作群'), findsWidgets);
  });

  testWidgets('群聊输入框发送 group 文本消息', (tester) async {
    final gateway = FakeAwikiGateway()..loginResult = session;
    final conversation = ConversationSummary(
      threadId: 'group:group-1',
      displayName: '融资协作群',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 5, 17, 10, 0),
      unreadCount: 0,
      isGroup: true,
      groupId: 'group-1',
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

    await tester.enterText(find.byType(CupertinoTextField), 'hello group');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(gateway.lastSentThreadId, 'group:group-1');
    expect(gateway.lastSentGroupId, 'group-1');
    expect(gateway.lastSentPeerDid, isNull);
    expect(gateway.lastSentContent, 'hello group');
  });
}
