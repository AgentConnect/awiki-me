import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/group/create_group_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

  testWidgets('macOS 创建群成功后直接进入群聊', (tester) async {
    final gateway = FakeAwikiGateway()..loginResult = session;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(900, 720));
    try {
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
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('通过 Group DID 加入群后直接进入群聊', (tester) async {
    final gateway = FakeAwikiGateway()..loginResult = session;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(900, 720));
    try {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const GroupListPage(),
          gateway: gateway,
          session: session,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.link));
      await tester.pumpAndSettle();

      const groupDid = 'did:wba:awiki.ai:group:e1_group';
      await tester.enterText(find.byType(CupertinoTextField).last, groupDid);
      await tester.tap(find.text('加入'));
      await tester.pumpAndSettle();

      expect(gateway.lastJoinedGroupDid, groupDid);
      expect(find.byType(ChatView), findsOneWidget);
      expect(find.text('Joined $groupDid'), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('群详情显示 Group DID 且不再显示 join-code 操作', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const GroupDetailPage(
          initialGroup: GroupSummary(
            groupId: groupDid,
            name: '融资协作群',
            description: '',
            memberCount: 2,
            lastMessageAt: null,
            myRole: 'member',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group DID: $groupDid'), findsOneWidget);
    expect(find.textContaining('Join-code'), findsNothing);
    expect(find.textContaining('join-code'), findsNothing);
  });

  testWidgets('群详情可以添加成员并刷新成员列表', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          name: '融资协作群',
          description: '',
          memberCount: 1,
          lastMessageAt: DateTime(2026, 5, 17, 10),
          myRole: 'owner',
        ),
      ]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupDid: <GroupMemberSummary>[
          GroupMemberSummary(
            userId: session.did,
            did: session.did,
            handle: session.handle ?? session.did,
            role: 'owner',
            profileUrl: null,
          ),
        ],
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: GroupDetailPage(initialGroup: gateway.groups.first),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加成员'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).last, memberDid);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(gateway.lastAddedGroupId, groupDid);
    expect(gateway.lastAddedMemberDid, memberDid);
    expect(find.text(memberDid), findsOneWidget);
    expect(find.text('2 人'), findsOneWidget);
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
