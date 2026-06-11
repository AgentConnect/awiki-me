import 'dart:async';

import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/group/create_group_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

    final didFinder = find.byKey(const Key('group-detail-did-value'));
    expect(didFinder, findsOneWidget);
    final didText = tester.widget<Text>(didFinder);
    expect(didText.data, groupDid);
    expect(didText.maxLines, isNull);
    expect(
      find.byKey(const Key('group-detail-copy-did-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('group-detail-copy-did-button')));
    await tester.pump();

    expect(clipboardText, groupDid);
    expect(find.text('DID 已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.textContaining('Join-code'), findsNothing);
    expect(find.textContaining('join-code'), findsNothing);
  });

  testWidgets('群详情可以添加成员并刷新成员列表', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberRef = 'did:wba:awiki.ai:user:bob:e1_member';
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
            role: 'owner-role-hidden',
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

    expect(find.text('成员'), findsOneWidget);
    expect(
      find.byKey(const Key('group-detail-add-member-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('group-detail-refresh-members-button')),
      findsOneWidget,
    );
    expect(find.text('me'), findsOneWidget);
    expect(find.text('owner-role-hidden'), findsNothing);

    await tester.tap(find.byKey(const Key('group-detail-add-member-button')));
    await tester.pumpAndSettle();

    expect(find.text('成员 handle 或 DID'), findsOneWidget);
    expect(find.text('支持普通用户和智能体，输入 handle 或 DID 后会直接加入群聊。'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField).last, memberRef);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(gateway.lastAddedGroupId, groupDid);
    expect(gateway.lastAddedMemberRef, memberRef);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text(memberRef), findsNothing);
    expect(find.text('2 人'), findsOneWidget);
  });

  testWidgets('群详情可以移除成员并刷新成员列表', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          name: '融资协作群',
          description: '',
          memberCount: 2,
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
          const GroupMemberSummary(
            userId: memberDid,
            did: memberDid,
            handle: 'bob.awiki.ai',
            role: 'member',
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

    expect(find.text('bob.awiki.ai'), findsOneWidget);

    final removeButton = find.bySemanticsLabel('移除成员').last;
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(find.text('移除成员'), findsOneWidget);
    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();

    expect(gateway.lastRemovedGroupId, groupDid);
    expect(gateway.lastRemovedMemberRef, memberDid);
    expect(find.text('bob.awiki.ai'), findsNothing);
    expect(find.text('1 人'), findsOneWidget);
  });

  testWidgets('群详情成员刷新按钮显示 loading 并只刷新成员列表', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    final memberRefresh = Completer<void>();
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
        groupDid: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:wba:awiki.ai:user:alice:e1_member',
            did: 'did:wba:awiki.ai:user:alice:e1_member',
            handle: 'did:wba:awiki.ai:user:alice:e1_member',
            role: 'owner-role-hidden',
            profileUrl: null,
          ),
        ],
      };
    addTearDown(() {
      if (!memberRefresh.isCompleted) {
        memberRefresh.complete();
      }
    });

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: GroupDetailPage(initialGroup: gateway.groups.first),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('owner'), findsOneWidget);
    expect(find.text('owner-role-hidden'), findsNothing);
    expect(find.text('did:wba:awiki.ai:user:alice:e1_member'), findsNothing);

    gateway
      ..listGroupMembersCompleter = memberRefresh
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupDid: const <GroupMemberSummary>[
          GroupMemberSummary(
            userId: 'did:wba:awiki.ai:user:carol:e1_member',
            did: 'did:wba:awiki.ai:user:carol:e1_member',
            handle: '',
            role: 'member-role-hidden',
            profileUrl: null,
          ),
        ],
      };

    await tester.tap(
      find.byKey(const Key('group-detail-refresh-members-button')),
    );
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('group-detail-refresh-members-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsOneWidget,
    );

    memberRefresh.complete();
    await tester.pumpAndSettle();

    expect(gateway.listConversationsCalls, 0);
    expect(find.text('carol'), findsOneWidget);
    expect(find.text('did:wba:awiki.ai:user:carol:e1_member'), findsNothing);
    expect(find.text('member-role-hidden'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('group-detail-refresh-members-button')),
        matching: find.byType(CupertinoActivityIndicator),
      ),
      findsNothing,
    );
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
