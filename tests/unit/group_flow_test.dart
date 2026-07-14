import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_identity.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _RecoveryGroupController extends GroupController {
  _RecoveryGroupController(super.ref, GroupRebindRecoverySummary summary) {
    state = GroupState(recoverySummary: summary);
  }
}

void main() {
  const session = SessionIdentity(
    did: 'did:wba:awiki.ai:me:e1_key',
    credentialName: 'me.json',
    displayName: 'Me',
    handle: 'me',
    jwtToken: 'token',
  );

  testWidgets('macOS 创建群弹窗只填写名称并直接进入群聊', (tester) async {
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

      await tester.tap(find.byKey(const Key('group-list-create-button')));
      await tester.pumpAndSettle();

      expect(find.text('创建群聊'), findsOneWidget);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('短链接'), findsNothing);
      expect(find.text('介绍'), findsNothing);
      expect(find.text('目标'), findsNothing);
      expect(find.text('规则'), findsNothing);
      expect(find.text('提示'), findsNothing);
      expect(find.text('入群身份'), findsNothing);
      expect(
        find.byKey(const Key('group-identity-mode-control')),
        findsNothing,
      );
      expect(find.byKey(const Key('create-group-name-input')), findsOneWidget);
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const Key('create-group-name-input')),
            )
            .selectionEnabled,
        isTrue,
      );

      await tester.enterText(
        find.byKey(const Key('create-group-name-input')),
        '融资协作群',
      );
      await tester.tap(find.byKey(const Key('create-group-submit-button')));
      await tester.pumpAndSettle();

      expect(gateway.lastCreatedGroupName, '融资协作群');
      expect(gateway.lastCreatedGroupDescription, isEmpty);
      expect(gateway.lastCreatedGroupGoal, isEmpty);
      expect(gateway.lastCreatedGroupRules, isEmpty);
      expect(gateway.lastCreatedGroupPrompt, isEmpty);
      expect(gateway.lastGroupIdentityMode, GroupIdentityMode.handle);
      expect(gateway.lastGroupIdentityHandle, 'me.awiki.ai');
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
      expect(find.text('入群身份'), findsNothing);
      expect(
        find.byKey(const Key('group-identity-mode-control')),
        findsNothing,
      );

      const groupDid = 'did:wba:awiki.ai:group:e1_group';
      await tester.enterText(find.byType(CupertinoTextField).last, groupDid);
      await tester.tap(find.text('加入'));
      await tester.pumpAndSettle();

      expect(gateway.lastJoinedGroupDid, groupDid);
      expect(gateway.lastGroupIdentityMode, GroupIdentityMode.handle);
      expect(gateway.lastGroupIdentityHandle, 'me.awiki.ai');
      expect(find.byType(ChatView), findsOneWidget);
      expect(find.text('Joined $groupDid'), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('无 Handle 时建群不会静默降级为 DID-only', (tester) async {
    const didOnlySession = SessionIdentity(
      did: 'did:web:identity.example.com:users:a-very-long-identity-value',
      credentialName: 'did-only.json',
      displayName: 'DID only',
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()..loginResult = didOnlySession;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const GroupListPage(),
        gateway: gateway,
        session: didOnlySession,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group-list-create-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-identity-mode-control')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const Key('create-group-name-input')),
      'DID 群',
    );
    await tester.tap(find.byKey(const Key('create-group-submit-button')));
    await tester.pumpAndSettle();
    expect(gateway.lastGroupIdentityMode, isNull);
    expect(gateway.lastGroupIdentityHandle, isNull);
    expect(find.byType(ChatView), findsNothing);
  });

  testWidgets('窄屏建群隐藏身份选择且不遮挡操作', (tester) async {
    const longHandle =
        'alice-with-a-very-long-persona-name.identity-provider.example.com';
    const longHandleSession = SessionIdentity(
      did: 'did:web:identity-provider.example.com:alice',
      credentialName: 'alice.json',
      displayName: 'Alice',
      handle: longHandle,
      jwtToken: 'token',
    );
    final gateway = FakeAwikiGateway()..loginResult = longHandleSession;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const GroupListPage(),
        gateway: gateway,
        session: longHandleSession,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group-list-create-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group-identity-mode-control')), findsNothing);
    expect(find.byKey(const Key('create-group-submit-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('群列表区分 recovery 的 P4 pending 与 P6 blocked', (tester) async {
    const summary = GroupRebindRecoverySummary(
      processed: 2,
      completed: 0,
      pending: 1,
      blocked: 1,
      sendPausedGroupDids: <String>['did:example:group'],
      items: <GroupRebindRecoveryItem>[
        GroupRebindRecoveryItem(
          groupDid: 'did:example:group',
          layer: 'p4',
          phase: 'awaiting_p6',
          blocked: false,
        ),
        GroupRebindRecoveryItem(
          groupDid: 'did:example:group',
          layer: 'p6',
          phase: 'blocked',
          blocked: true,
        ),
      ],
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const GroupListPage(),
        providerOverrides: <Override>[
          groupProvider.overrideWith(
            (ref) => _RecoveryGroupController(ref, summary),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('group-recovery-status-band')), findsOneWidget);
    expect(find.text('did:example:group'), findsNWidgets(2));
    expect(find.text('成员关系'), findsOneWidget);
    expect(find.text('群加密'), findsOneWidget);
    expect(find.text('等待中'), findsOneWidget);
    expect(find.text('已阻塞'), findsOneWidget);
  });

  testWidgets('通过 Group DID 加入群失败时停留列表并提示错误', (tester) async {
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..failNextJoinGroup = true;

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

    await tester.enterText(
      find.byType(CupertinoTextField).last,
      'did:wba:awiki.ai:group:e1_group',
    );
    await tester.tap(find.text('加入'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupListPage), findsOneWidget);
    expect(find.byType(ChatView), findsNothing);
    expect(gateway.lastJoinedGroupDid, isNull);
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
            conversationId: 'group:$groupDid',
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

  test('群成员加载会用公开 Profile Display Name 补全展示名', () async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberDid = 'did:wba:awiki.ai:user:lzc:e1_member';
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        memberDid: UserProfile(
          did: memberDid,
          nickName: '李智诚',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'lzc',
          fullHandle: 'lzc.awiki.ai',
          avatarUri: 'https://example.test/lzc.png',
        ),
      }
      ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
        groupDid: <GroupMemberSummary>[
          GroupMemberSummary(
            userId: memberDid,
            did: memberDid,
            handle: 'lzc',
            role: 'member',
          ),
        ],
      };
    final container = ProviderContainer(
      overrides: fakeApplicationServiceOverrides(gateway),
    );
    addTearDown(container.dispose);

    final members = await container
        .read(groupProvider.notifier)
        .loadGroupMembers(groupDid);

    expect(members.single.displayName, '李智诚');
    expect(members.single.handle, 'lzc');
    expect(members.single.avatarUri, 'https://example.test/lzc.png');
    expect(
      container.read(groupMembersProvider(groupDid)).single.displayName,
      '李智诚',
    );
  });

  testWidgets('群成员行优先展示 Display Name 而不是 handle', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const CupertinoPageScaffold(
          child: Center(
            child: GroupMemberRow(
              item: GroupMemberSummary(
                userId: 'did:wba:awiki.ai:user:lzc:e1_member',
                did: 'did:wba:awiki.ai:user:lzc:e1_member',
                handle: 'lzc',
                role: 'member',
                displayName: '李智诚',
              ),
              onRemove: null,
            ),
          ),
        ),
      ),
    );

    expect(find.text('李智诚'), findsOneWidget);
    expect(find.text('lzc'), findsNothing);
    expect(find.text('@lzc'), findsOneWidget);
    expect(
      find.textContaining('did:wba:awiki.ai:user:lzc:e1_member'),
      findsNothing,
    );
  });

  testWidgets('群详情可以添加成员并刷新成员列表', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberHandle = 'bob.awiki.ai';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..publicProfilesByQuery = const <String, UserProfile>{
        memberHandle: UserProfile(
          did: memberDid,
          nickName: 'Bob',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: memberHandle,
          fullHandle: memberHandle,
        ),
      }
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
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

    expect(find.text('群成员'), findsOneWidget);
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

    expect(find.text('添加群成员'), findsOneWidget);
    expect(find.text('搜索本地身份，或输入 handle / DID 匹配新身份。'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      '@$memberHandle',
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('@$memberHandle'), findsWidgets);
    expect(find.text('用户'), findsWidgets);
    expect(find.text('匹配结果'), findsOneWidget);
    expect(gateway.lastAddedGroupId, isNull);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-add-group-member-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastAddedGroupId, groupDid);
    expect(gateway.lastAddedMemberRef, memberHandle);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text(memberDid), findsNothing);
    expect(find.text('2 人'), findsOneWidget);
  });

  testWidgets('群详情添加成员弹窗展示本地身份并支持多选确认', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const followerDid = 'did:wba:awiki.ai:user:follower:e1_member';
    const recentDid = 'did:wba:awiki.ai:user:recent:e1_member';
    const agentDid = 'did:wba:awiki.ai:agent:runtime:test:e1_agent';
    const existingDid = 'did:wba:awiki.ai:user:existing:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: followerDid,
          displayName: '关注联系人',
          relationship: 'following',
          handle: 'followed.awiki.ai',
        ),
        RelationshipSummary(
          did: existingDid,
          displayName: '已在群中联系人',
          relationship: 'following',
          handle: 'existing.awiki.ai',
        ),
      ]
      ..conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: 'dm:recent',
          conversationId: 'dm:recent',
          displayName: '最近联系人',
          lastMessagePreview: 'hello',
          lastMessageAt: DateTime(2026, 5, 17, 11),
          unreadCount: 0,
          isGroup: false,
          targetDid: recentDid,
          targetPeer: 'recent.awiki.ai',
        ),
        ConversationSummary(
          threadId: 'group:not-candidate',
          conversationId: 'group:not-candidate',
          displayName: '不应该出现的群聊',
          lastMessagePreview: 'group',
          lastMessageAt: DateTime(2026, 5, 17, 12),
          unreadCount: 0,
          isGroup: true,
          groupId: 'did:wba:awiki.ai:groups:not_candidate:e1_group',
        ),
      ]
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
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
            userId: existingDid,
            did: existingDid,
            handle: 'existing.awiki.ai',
            role: 'member',
            profileUrl: null,
          ),
        ],
      };
    final agentControl = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: 'did:wba:awiki.ai:agent:daemon:test:e1_daemon',
          kind: AgentKind.daemon,
          displayName: '不应该出现的 Daemon',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
        AgentSummary(
          agentDid: agentDid,
          kind: AgentKind.runtime,
          daemonAgentDid: 'did:wba:awiki.ai:agent:daemon:test:e1_daemon',
          runtime: 'hermes',
          handle: 'agent-test.awiki.ai',
          displayName: '测试智能体',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: GroupDetailPage(initialGroup: gateway.groups.first),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(agentControl),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group-detail-add-member-button')));
    await tester.pumpAndSettle();

    expect(find.text('关注联系人'), findsOneWidget);
    expect(find.text('最近联系人'), findsOneWidget);
    expect(find.text('测试智能体'), findsOneWidget);
    expect(find.text('不应该出现的群聊'), findsNothing);
    expect(find.text('不应该出现的 Daemon'), findsNothing);
    expect(find.text('用户'), findsWidgets);
    expect(find.text('智能体'), findsOneWidget);
    expect(find.text('已在群中'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const Key('group-invite-selection-mark')).first,
      ),
      const Size.square(18),
    );

    await tester.tap(find.text('关注联系人'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试智能体'));
    await tester.pumpAndSettle();
    expect(find.text('确认添加 (2)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('identity-add-group-member-button')));
    await tester.pumpAndSettle();

    expect(gateway.groupMembersByGroupId[groupDid]!.map((item) => item.did), [
      session.did,
      existingDid,
      'followed.awiki.ai',
      'agent-test.awiki.ai',
    ]);
    expect(find.text('4 人'), findsOneWidget);
  });

  testWidgets('群详情邀请候选排除已删除智能体的所有本地来源', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:deleted_agent_filter';
    const deletedAgentDid = 'did:wba:awiki.ai:agent:runtime:deleted:e1_deleted';
    const humanDid = 'did:wba:awiki.ai:user:active:e1_active';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: deletedAgentDid,
          displayName: '已删除智能体候选',
          relationship: 'following',
          handle: 'deleted-agent.awiki.ai',
        ),
        RelationshipSummary(
          did: humanDid,
          displayName: '正常联系人',
          relationship: 'following',
          handle: 'active-user.awiki.ai',
        ),
      ]
      ..conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: 'dm:deleted-agent',
          conversationId: 'dm:deleted-agent',
          displayName: '已删除智能体候选',
          lastMessagePreview: 'history',
          lastMessageAt: DateTime(2026, 7, 13),
          unreadCount: 0,
          isGroup: false,
          targetDid: deletedAgentDid,
          targetPeer: 'deleted-agent.awiki.ai',
          peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
        ),
      ]
      ..publicProfilesByQuery = const <String, UserProfile>{
        'deleted-agent.awiki.ai': UserProfile(
          did: deletedAgentDid,
          nickName: '已删除智能体候选',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'deleted-agent.awiki.ai',
          fullHandle: 'deleted-agent.awiki.ai',
          subjectType: 'agent',
        ),
      }
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
          name: '生命周期测试群',
          description: '',
          memberCount: 1,
          lastMessageAt: DateTime(2026, 7, 13),
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
    final agentControl = FakeAgentControlService()
      ..agents = const <AgentSummary>[
        AgentSummary(
          agentDid: deletedAgentDid,
          kind: AgentKind.runtime,
          handle: 'deleted-agent.awiki.ai',
          displayName: '已删除智能体候选',
          activeState: 'archived',
          latest: AgentLatestStatus(status: 'archived'),
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: GroupDetailPage(initialGroup: gateway.groups.first),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          agentControlServiceProvider.overrideWithValue(agentControl),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group-detail-add-member-button')));
    await tester.pumpAndSettle();

    expect(find.text('正常联系人'), findsOneWidget);
    expect(find.text('已删除智能体候选'), findsNothing);
    expect(find.text('@deleted-agent.awiki.ai'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      'deleted-agent.awiki.ai',
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();

    expect(find.text('该身份已被删除或当前不可邀请。'), findsOneWidget);
    expect(find.text('已删除智能体候选'), findsNothing);
  });

  testWidgets('群详情添加成员搜索框支持一键清空', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const followerDid = 'did:wba:awiki.ai:user:follower:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: followerDid,
          displayName: '关注联系人',
          relationship: 'following',
          handle: 'followed.awiki.ai',
        ),
      ]
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
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

    await tester.tap(find.byKey(const Key('group-detail-add-member-button')));
    await tester.pumpAndSettle();
    expect(find.text('关注联系人'), findsOneWidget);
    expect(find.byKey(const Key('identity-lookup-clear-button')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      'none',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('identity-lookup-clear-button')),
      findsOneWidget,
    );
    expect(find.text('关注联系人'), findsNothing);

    await tester.tap(find.byKey(const Key('identity-lookup-clear-button')));
    await tester.pumpAndSettle();
    final input = tester.widget<CupertinoTextField>(
      find.byKey(const Key('identity-lookup-input')),
    );
    expect(input.controller?.text, isEmpty);
    expect(find.byKey(const Key('identity-lookup-clear-button')), findsNothing);
    expect(find.text('关注联系人'), findsOneWidget);
  });

  testWidgets('群详情添加成员失败时保留对话框并提示错误', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberHandle = 'bob.awiki.ai';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..failNextAddGroupMember = true
      ..publicProfilesByQuery = const <String, UserProfile>{
        memberHandle: UserProfile(
          did: memberDid,
          nickName: 'Bob',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: memberHandle,
          fullHandle: memberHandle,
        ),
      }
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
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

    await tester.tap(find.byKey(const Key('group-detail-add-member-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      memberHandle,
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-add-group-member-button')));
    await tester.pumpAndSettle();

    expect(find.text('添加群成员'), findsOneWidget);
    expect(find.textContaining('add member failed'), findsOneWidget);
    expect(gateway.lastAddedGroupId, isNull);
  });

  testWidgets('群详情可以移除成员并刷新成员列表', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
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

    expect(find.text('移除成员'), findsNWidgets(2));
    expect(find.text('移除 bob.awiki.ai 后，对方将不能继续在这个群里发送消息。'), findsOneWidget);
    await tester.tap(find.byType(CupertinoDialogAction).last);
    await tester.pumpAndSettle();

    expect(gateway.lastRemovedGroupId, groupDid);
    expect(gateway.lastRemovedMemberRef, 'bob.awiki.ai');
    expect(find.text('bob.awiki.ai'), findsNothing);
    expect(find.text('1 人'), findsOneWidget);
  });

  testWidgets('群详情普通成员仍显示管理按钮但保持禁用', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberDid = 'did:wba:awiki.ai:user:bob:e1_member';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
          name: '融资协作群',
          description: '',
          memberCount: 2,
          lastMessageAt: DateTime(2026, 5, 17, 10),
          myRole: 'member',
        ),
      ]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupDid: <GroupMemberSummary>[
          GroupMemberSummary(
            userId: session.did,
            did: session.did,
            handle: session.handle ?? session.did,
            role: 'member',
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

    final addButton = find.byKey(const Key('group-detail-add-member-button'));
    expect(addButton, findsOneWidget);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.text('添加群成员'), findsNothing);

    final removeButton = find.bySemanticsLabel('移除成员').last;
    expect(removeButton, findsOneWidget);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(find.text('移除成员'), findsNothing);
    expect(gateway.lastRemovedGroupId, isNull);
    expect(gateway.lastRemovedMemberRef, isNull);
  });

  testWidgets('群详情成员刷新按钮显示 loading 并只刷新成员列表', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    final memberRefresh = Completer<void>();
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
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
    expect(
      find.textContaining('did:wba:awiki.ai:user:alice:e1_member'),
      findsNothing,
    );

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
    expect(
      find.textContaining('did:wba:awiki.ai:user:carol:e1_member'),
      findsNothing,
    );
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
      conversationId: 'group:group-1',
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
