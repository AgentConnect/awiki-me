import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/group_collection_page.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/ports/group_core_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/skill_group_membership_capability.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_identity.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/identity_type.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_top_bar.dart';
import 'package:awiki_me/src/presentation/shared/avatar_badge.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _RecoveryGroupController extends GroupController {
  _RecoveryGroupController(super.ref, GroupRebindRecoverySummary summary) {
    state = GroupState(recoverySummary: summary);
  }
}

class _DelayedPublicProfileService implements ProfileApplicationService {
  final Completer<UserProfile> profile = Completer<UserProfile>();
  int loadCalls = 0;

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    loadCalls += 1;
    return profile.future;
  }

  @override
  Future<UserProfile> loadMyProfile() {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

class _DelayedCreateGroupService extends FakeGroupApplicationService {
  _DelayedCreateGroupService(super.gateway);

  final Completer<void> started = Completer<void>();
  final Completer<GroupSummary> result = Completer<GroupSummary>();

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) {
    started.complete();
    return result.future;
  }
}

class _AdmissionDeniedGroupService extends FakeGroupApplicationService {
  _AdmissionDeniedGroupService(super.gateway);

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) {
    throw const GroupMemberAdmissionException(
      GroupMemberAdmissionDenialReason.agentNotGroupInvitable,
    );
  }
}

class _DelayedRefreshGroupService extends FakeGroupApplicationService {
  _DelayedRefreshGroupService(super.gateway);

  final Completer<void> getStarted = Completer<void>();
  final Completer<GroupSummary> getResult = Completer<GroupSummary>();
  int listMembersCalls = 0;

  @override
  Future<GroupSummary> getGroup(String groupDid) {
    getStarted.complete();
    return getResult.future;
  }

  @override
  Future<GroupCollectionPage<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) {
    listMembersCalls += 1;
    return Future<GroupCollectionPage<GroupMemberSummary>>.value(
      const GroupCollectionPage<GroupMemberSummary>(
        items: <GroupMemberSummary>[],
        hasMore: false,
      ),
    );
  }
}

class _DelayedMemberMutationGroupService extends FakeGroupApplicationService {
  _DelayedMemberMutationGroupService(super.gateway);

  final Completer<void> addStarted = Completer<void>();
  final Completer<GroupSummary> addResult = Completer<GroupSummary>();
  final Completer<void> removeStarted = Completer<void>();
  final Completer<GroupSummary> removeResult = Completer<GroupSummary>();
  int listMembersCalls = 0;

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) {
    addStarted.complete();
    return addResult.future;
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberRef,
  }) {
    removeStarted.complete();
    return removeResult.future;
  }

  @override
  Future<GroupCollectionPage<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) {
    listMembersCalls += 1;
    return Future<GroupCollectionPage<GroupMemberSummary>>.value(
      const GroupCollectionPage<GroupMemberSummary>(
        items: <GroupMemberSummary>[],
        hasMore: false,
      ),
    );
  }
}

class _QueuedGroupMemberService extends FakeGroupApplicationService {
  _QueuedGroupMemberService(super.gateway, this.results);

  final List<Completer<List<GroupMemberSummary>>> results;
  int listMembersCalls = 0;

  @override
  Future<GroupCollectionPage<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) async {
    final result = results[listMembersCalls];
    listMembersCalls += 1;
    return GroupCollectionPage<GroupMemberSummary>(
      items: await result.future,
      hasMore: false,
      pageGroupDid: groupDid,
      groupStateVersion: '1',
    );
  }
}

Matcher get throwsSessionEpochChanged => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'session_epoch_changed',
  ),
);

void main() {
  const session = SessionIdentity(
    did: 'did:wba:awiki.ai:me:e1_key',
    credentialName: 'me.json',
    displayName: 'Me',
    handle: 'me',
    jwtToken: 'token',
  );
  const replacementSession = SessionIdentity(
    did: 'did:wba:awiki.ai:new-owner:e1_key',
    credentialName: 'new-owner.json',
    displayName: 'New owner',
    handle: 'new-owner',
    jwtToken: 'new-token',
  );

  testWidgets('群列表顶部操作使用统一主题图标和提示', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const GroupListPage(embedded: true),
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final expectedColor = tester
        .element(find.byType(GroupListPage))
        .awikiTheme
        .secondaryText;
    const actions = <(String, String, IconData)>[
      ('group-list-refresh-button', '刷新', CupertinoIcons.refresh),
      ('group-list-create-button', '创建群聊', CupertinoIcons.person_2),
      ('group-list-join-button', '加入群聊', CupertinoIcons.plus),
    ];
    double? iconSize;
    for (final action in actions) {
      final button = find.byKey(Key(action.$1));
      expect(button, findsOneWidget);
      expect(
        tester.widget<TopBarActionButton>(button).semanticsLabel,
        action.$2,
      );

      final tooltip = tester.widget<Tooltip>(
        find.descendant(of: button, matching: find.byType(Tooltip)),
      );
      expect(tooltip.message, action.$2);

      final icon = tester.widget<Icon>(
        find.descendant(of: button, matching: find.byType(Icon)),
      );
      expect(icon.icon, action.$3);
      expect(icon.color, expectedColor);
      iconSize ??= icon.size;
      expect(icon.size, iconSize);
    }
    expect(iconSize, isNotNull);
  });

  testWidgets('群列表标题在移动窄屏下完整显示', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const GroupListPage(), session: session),
    );
    await tester.pumpAndSettle();

    final title = find.text('群聊列表');
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).textAlign, TextAlign.left);
    final backButton = find.byType(TopBarActionButton).first;
    expect(
      tester.getTopLeft(title).dx,
      closeTo(tester.getTopRight(backButton).dx, 0.01),
    );
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('群列表标题在桌面窄详情栏中完整显示', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(900, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const Align(
          alignment: Alignment.centerRight,
          child: SizedBox(width: 360, child: GroupListPage(embedded: true)),
        ),
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final title = find.text('群聊列表');
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).textAlign, TextAlign.center);
    expect(
      tester.getCenter(title).dx,
      closeTo(tester.getCenter(find.byType(AwikiMeTopBar)).dx, 0.01),
    );
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
  });

  testWidgets('群列表英文标题使用 Group', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const GroupListPage(),
        locale: const Locale('en'),
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Group chats'), findsNothing);
    final titleParagraph = tester.renderObject<RenderParagraph>(
      find.text('Group'),
    );
    expect(tester.widget<Text>(find.text('Group')).textAlign, TextAlign.left);
    expect(
      titleParagraph.didExceedMaxLines,
      isFalse,
      reason:
          'title slot=${titleParagraph.size.width}, '
          'text=${titleParagraph.getMaxIntrinsicWidth(double.infinity)}',
    );
  });

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

      await tester.tap(find.byKey(const Key('group-list-join-button')));
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

    await tester.tap(find.byKey(const Key('group-list-join-button')));
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
        session: session,
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
    container.read(sessionProvider.notifier).setSession(session);

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

  test('旧身份群成员 Profile 慢请求不会写入新身份投影', () async {
    const groupDid = 'did:wba:awiki.ai:group:e1_group';
    const memberDid = 'did:wba:awiki.ai:user:lzc:e1_member';
    final profiles = _DelayedPublicProfileService();
    addTearDown(() {
      if (!profiles.profile.isCompleted) {
        profiles.profile.complete(
          const UserProfile(
            did: memberDid,
            nickName: 'Old member',
            bio: '',
            tags: <String>[],
            profileMarkdown: '',
          ),
        );
      }
    });
    final gateway = FakeAwikiGateway()
      ..groupMembersByGroupId = const <String, List<GroupMemberSummary>>{
        groupDid: <GroupMemberSummary>[
          GroupMemberSummary(
            userId: memberDid,
            did: memberDid,
            handle: 'lzc',
            role: 'member',
            peerPersonaId: 'persona-old-member',
          ),
        ],
      };
    final container = ProviderContainer(
      overrides: <Override>[
        ...fakeApplicationServiceOverrides(gateway),
        profileApplicationServiceProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).setSession(session);

    final load = container
        .read(groupProvider.notifier)
        .loadGroupMembers(groupDid);
    await pumpEventQueue();
    expect(profiles.loadCalls, 1);
    final loadFailure = expectLater(load, throwsSessionEpochChanged);

    container.read(sessionProvider.notifier).setSession(replacementSession);
    container.read(groupProvider.notifier).clear();
    container.read(peerDisplayProfileProvider.notifier).clear();
    profiles.profile.complete(
      const UserProfile(
        did: memberDid,
        nickName: 'Old member',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
      ),
    );
    await loadFailure;

    final peerState = container.read(peerDisplayProfileProvider);
    expect(peerState.ownerDid, isNull);
    expect(peerState.profilesByPersonaId, isEmpty);
    expect(container.read(groupProvider).membersByGroup, isEmpty);
  });

  test('旧身份建群结果不会写入新身份群列表', () async {
    final gateway = FakeAwikiGateway();
    final groups = _DelayedCreateGroupService(gateway);
    final container = ProviderContainer(
      overrides: <Override>[
        ...fakeApplicationServiceOverrides(gateway),
        groupApplicationServiceProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).setSession(session);
    final controller = container.read(groupProvider.notifier);

    final create = controller.createGroup(
      name: 'Old owner group',
      slug: 'old-owner-group',
      description: '',
      goal: '',
      rules: '',
    );
    await groups.started.future;
    final createFailure = expectLater(create, throwsSessionEpochChanged);
    container.read(sessionProvider.notifier).setSession(replacementSession);
    controller.clear();
    groups.result.complete(
      const GroupSummary(
        conversationId: 'group:old-owner',
        groupId: 'did:wba:awiki.ai:group:old-owner',
        name: 'Old owner group',
        description: '',
        memberCount: 1,
        lastMessageAt: null,
      ),
    );

    await createFailure;
    expect(container.read(groupProvider).groups, isEmpty);
  });

  test('旧身份群详情慢请求不会继续加载成员或发布群状态', () async {
    const groupDid = 'did:wba:awiki.ai:group:old-owner';
    final gateway = FakeAwikiGateway();
    final groups = _DelayedRefreshGroupService(gateway);
    final container = ProviderContainer(
      overrides: <Override>[
        ...fakeApplicationServiceOverrides(gateway),
        groupApplicationServiceProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).setSession(session);
    final controller = container.read(groupProvider.notifier);

    final refresh = controller.refreshGroup(groupDid);
    await groups.getStarted.future;
    final refreshFailure = expectLater(refresh, throwsSessionEpochChanged);
    container.read(sessionProvider.notifier).setSession(replacementSession);
    groups.getResult.complete(
      const GroupSummary(
        conversationId: 'group:old-owner',
        groupId: groupDid,
        name: 'Old owner group',
        description: '',
        memberCount: 1,
        lastMessageAt: null,
      ),
    );

    await refreshFailure;
    expect(groups.listMembersCalls, 0);
    expect(container.read(groupProvider).groups, isEmpty);
    expect(container.read(groupProvider).membersByGroup, isEmpty);
  });

  test('旧身份添加成员的迟到结果不会刷新成员或返回群实体', () async {
    const groupDid = 'did:wba:awiki.ai:group:old-owner';
    final gateway = FakeAwikiGateway();
    final groups = _DelayedMemberMutationGroupService(gateway);
    final container = ProviderContainer(
      overrides: <Override>[
        ...fakeApplicationServiceOverrides(gateway),
        groupApplicationServiceProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).setSession(session);

    final add = container
        .read(groupProvider.notifier)
        .addGroupMember(groupId: groupDid, memberRef: 'bob.awiki.ai');
    await groups.addStarted.future;
    final addFailure = expectLater(add, throwsSessionEpochChanged);
    container.read(sessionProvider.notifier).setSession(replacementSession);
    groups.addResult.complete(
      const GroupSummary(
        conversationId: 'group:old-owner',
        groupId: groupDid,
        name: 'Old owner group',
        description: '',
        memberCount: 2,
        lastMessageAt: null,
      ),
    );

    await addFailure;
    expect(groups.listMembersCalls, 0);
    expect(container.read(groupProvider).groups, isEmpty);
    expect(container.read(groupProvider).membersByGroup, isEmpty);
  });

  test('旧身份移除成员的迟到结果不会刷新成员或返回群实体', () async {
    const groupDid = 'did:wba:awiki.ai:group:old-owner';
    final gateway = FakeAwikiGateway();
    final groups = _DelayedMemberMutationGroupService(gateway);
    final container = ProviderContainer(
      overrides: <Override>[
        ...fakeApplicationServiceOverrides(gateway),
        groupApplicationServiceProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).setSession(session);

    final remove = container
        .read(groupProvider.notifier)
        .removeGroupMember(groupId: groupDid, memberRef: 'bob.awiki.ai');
    await groups.removeStarted.future;
    final removeFailure = expectLater(remove, throwsSessionEpochChanged);
    container.read(sessionProvider.notifier).setSession(replacementSession);
    groups.removeResult.complete(
      const GroupSummary(
        conversationId: 'group:old-owner',
        groupId: groupDid,
        name: 'Old owner group',
        description: '',
        memberCount: 1,
        lastMessageAt: null,
      ),
    );

    await removeFailure;
    expect(groups.listMembersCalls, 0);
    expect(container.read(groupProvider).groups, isEmpty);
    expect(container.read(groupProvider).membersByGroup, isEmpty);
  });

  test('相同群的成员初始加载按 session epoch 独立且只发布新身份结果', () async {
    const groupDid = 'did:wba:awiki.ai:group:shared';
    const oldMember = GroupMemberSummary(
      userId: 'did:wba:awiki.ai:user:old-member',
      did: 'did:wba:awiki.ai:user:old-member',
      handle: 'old-member.awiki.ai',
      role: 'member',
    );
    const newMember = GroupMemberSummary(
      userId: 'did:wba:awiki.ai:user:new-member',
      did: 'did:wba:awiki.ai:user:new-member',
      handle: 'new-member.awiki.ai',
      role: 'member',
    );
    final oldResult = Completer<List<GroupMemberSummary>>();
    final newResult = Completer<List<GroupMemberSummary>>();
    final gateway = FakeAwikiGateway();
    final groups = _QueuedGroupMemberService(
      gateway,
      <Completer<List<GroupMemberSummary>>>[oldResult, newResult],
    );
    final container = ProviderContainer(
      overrides: <Override>[
        ...fakeApplicationServiceOverrides(gateway),
        groupApplicationServiceProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).setSession(session);
    final controller = container.read(groupProvider.notifier);

    final oldLoad = controller.ensureGroupMembersLoaded(groupDid);
    expect(groups.listMembersCalls, 1);
    final oldLoadFailure = expectLater(oldLoad, throwsSessionEpochChanged);
    container.read(sessionProvider.notifier).setSession(replacementSession);

    final newLoad = controller.ensureGroupMembersLoaded(groupDid);
    expect(identical(newLoad, oldLoad), isFalse);
    expect(groups.listMembersCalls, 2);
    newResult.complete(const <GroupMemberSummary>[newMember]);
    expect(await newLoad, const <GroupMemberSummary>[newMember]);

    oldResult.complete(const <GroupMemberSummary>[oldMember]);
    await oldLoadFailure;
    expect(
      container.read(groupProvider).membersByGroup[groupDid],
      const <GroupMemberSummary>[newMember],
    );
  });

  test('没有 active session epoch 时群操作在调用服务前失败', () async {
    final gateway = FakeAwikiGateway();
    final groups = _DelayedCreateGroupService(gateway);
    groups.result.complete(
      const GroupSummary(
        conversationId: 'group:should-not-exist',
        groupId: 'did:wba:awiki.ai:group:should-not-exist',
        name: 'Should not exist',
        description: '',
        memberCount: 1,
        lastMessageAt: null,
      ),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        ...fakeApplicationServiceOverrides(gateway),
        groupApplicationServiceProvider.overrideWithValue(groups),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(groupProvider.notifier)
          .createGroup(
            name: 'Should not exist',
            slug: 'should-not-exist',
            description: '',
            goal: '',
            rules: '',
          ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'No active awiki session. Please sign in first.',
        ),
      ),
    );
    expect(groups.started.isCompleted, isFalse);
    expect(container.read(groupProvider).groups, isEmpty);
    expect(container.read(groupProvider).membersByGroup, isEmpty);
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
    expect(
      find.byKey(
        const Key('group-member-title:did:wba:awiki.ai:user:lzc:e1_member'),
      ),
      findsOneWidget,
    );
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
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupDetailPage)),
    );
    expect(
      container.read(peerDisplayProfileProvider).forDid(memberDid)?.displayName,
      'Bob',
    );

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

    final candidateList = find.descendant(
      of: find.byKey(const Key('group-invite-candidate-list')),
      matching: find.byType(Scrollable),
    );
    expect(find.text('关注联系人'), findsOneWidget);
    expect(find.text('测试智能体'), findsOneWidget);
    expect(find.text('不应该出现的群聊'), findsNothing);
    expect(find.text('不应该出现的 Daemon'), findsNothing);
    expect(find.text('用户'), findsWidgets);
    expect(find.text('Runtime Agent'), findsOneWidget);
    expect(find.text('已在群中'), findsOneWidget);
    expect(
      tester.getSize(
        find.byKey(const Key('group-invite-selection-mark')).first,
      ),
      const Size.square(18),
    );

    expect(
      find.text('最近联系人'),
      findsNothing,
      reason: 'a historical conversation title must not override its Handle',
    );
    await tester.scrollUntilVisible(
      find.text('recent'),
      100,
      scrollable: candidateList,
    );
    expect(find.text('recent'), findsOneWidget);

    final followerCandidate = find.byKey(
      const Key('group-invite-candidate:$followerDid'),
    );
    await tester.ensureVisible(followerCandidate);
    await tester.pumpAndSettle();
    await tester.tap(followerCandidate);
    await tester.pumpAndSettle();
    final agentCandidate = find.byKey(
      const Key('group-invite-candidate:$agentDid'),
    );
    await tester.ensureVisible(agentCandidate);
    await tester.pumpAndSettle();
    await tester.tap(agentCandidate);
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

  testWidgets('Skill Agent 关闭时保留候选展示但不可选择', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:skill-disabled:e1_group';
    const skillDid = 'did:wba:awiki.ai:agent:skill:test:e1_agent';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..serverInfo = skillOnboardingTestServerInfo(
        skillGroupMembershipEnabled: false,
      )
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: skillDid,
          displayName: 'Skill Assistant',
          relationship: 'following',
          handle: 'skill-assistant.awiki.ai',
        ),
      ]
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
          name: 'Skill policy group',
          description: '',
          memberCount: 1,
          lastMessageAt: DateTime(2026, 8, 10),
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

    final candidate = find.byKey(const Key('group-invite-candidate:$skillDid'));
    expect(candidate, findsOneWidget);
    expect(
      find.descendant(of: candidate, matching: find.text('Skill Agent')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: candidate,
        matching: find.text('Skill Agent 暂不支持加入群聊'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Skill Assistant'));
    await tester.pumpAndSettle();
    final confirm = tester.widget<AppPrimaryButton>(
      find.byKey(const Key('identity-add-group-member-button')),
    );
    expect(confirm.onPressed, isNull);
    expect(gateway.lastAddedGroupId, isNull);
  });

  testWidgets('Skill Agent 开关和协议能力均满足时可以邀请', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:skill-enabled:e1_group';
    const skillDid = 'did:wba:awiki.ai:agent:skill:current:e1_agent';
    const skillHandle = 'skill-current.awiki.ai';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..serverInfo = skillOnboardingTestServerInfo(
        skillGroupMembershipEnabled: true,
      )
      ..publicProfilesByQuery = const <String, UserProfile>{
        skillHandle: UserProfile(
          did: skillDid,
          displayName: 'Current Skill',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          fullHandle: skillHandle,
          subjectType: 'agent',
          agentKind: IdentityAgentKind.skill,
          agentCapabilities: <String>{skillGroupMembershipRequiredCapability},
        ),
      }
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
          name: 'Skill enabled group',
          description: '',
          memberCount: 1,
          lastMessageAt: DateTime(2026, 8, 10),
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
      skillHandle,
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();

    expect(find.text('Skill Agent'), findsOneWidget);
    await tester.tap(find.text('Current Skill'));
    await tester.pumpAndSettle();
    expect(find.text('确认添加 (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('identity-add-group-member-button')));
    await tester.pumpAndSettle();

    expect(gateway.lastAddedGroupId, groupDid);
    expect(gateway.lastAddedMemberRef, skillHandle);
  });

  testWidgets('服务端竞态拒绝 Skill Agent 时显示稳定友好文案', (tester) async {
    const groupDid = 'did:wba:awiki.ai:group:skill-race:e1_group';
    const skillDid = 'did:wba:awiki.ai:agent:skill:race:e1_agent';
    const skillHandle = 'skill-race.awiki.ai';
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..serverInfo = skillOnboardingTestServerInfo(
        skillGroupMembershipEnabled: true,
      )
      ..publicProfilesByQuery = const <String, UserProfile>{
        skillHandle: UserProfile(
          did: skillDid,
          displayName: 'Racing Skill',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          fullHandle: skillHandle,
          subjectType: 'agent',
          agentKind: IdentityAgentKind.skill,
          agentCapabilities: <String>{skillGroupMembershipRequiredCapability},
        ),
      }
      ..groups = <GroupSummary>[
        GroupSummary(
          groupId: groupDid,
          conversationId: 'group:$groupDid',
          name: 'Skill race group',
          description: '',
          memberCount: 1,
          lastMessageAt: DateTime(2026, 8, 10),
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
          ),
        ],
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: GroupDetailPage(initialGroup: gateway.groups.first),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          groupApplicationServiceProvider.overrideWithValue(
            _AdmissionDeniedGroupService(gateway),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-detail-add-member-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('identity-lookup-input')),
      skillHandle,
    );
    await tester.tap(find.byKey(const Key('identity-lookup-search-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Racing Skill'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('identity-add-group-member-button')));
    await tester.pumpAndSettle();

    expect(find.text('Racing Skill: Skill Agent 暂不支持加入群聊'), findsOneWidget);
    expect(find.textContaining('service_error'), findsNothing);
  });

  testWidgets('添加群成员候选复用会话的 Persona 昵称和头像投影', (tester) async {
    const groupDid = 'did:wba:awiki.info:group:profile-consistency:e1_group';
    const peerDid = 'did:wba:awiki.info:user:zhuocheng:e1_peer';
    const peerPersonaId = 'persona:zhuocheng';
    const avatarUri = 'https://awiki.info/avatar/zhuocheng.png';
    final group = GroupSummary(
      groupId: groupDid,
      conversationId: 'group:$groupDid',
      name: '资料一致性群',
      description: '',
      memberCount: 1,
      lastMessageAt: DateTime(2026, 7, 17, 17, 14),
      myRole: 'owner',
    );
    final gateway = FakeAwikiGateway()
      ..loginResult = session
      ..groups = <GroupSummary>[group]
      ..conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: 'dm:peer-scope:zhuocheng',
          conversationId: 'dm:peer-scope:zhuocheng',
          displayName: 'zhuocheng',
          lastMessagePreview: 'hello',
          lastMessageAt: DateTime(2026, 7, 17, 17, 13),
          unreadCount: 0,
          isGroup: false,
          targetDid: peerDid,
          targetPeer: 'zhuocheng.awiki.info',
          peerPersonaId: peerPersonaId,
        ),
      ]
      ..groupMembersByGroupId = <String, List<GroupMemberSummary>>{
        groupDid: <GroupMemberSummary>[
          GroupMemberSummary(
            userId: session.did,
            did: session.did,
            handle: session.handle ?? session.did,
            role: 'owner',
          ),
        ],
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: GroupDetailPage(initialGroup: group),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GroupDetailPage)),
      listen: false,
    );
    container
        .read(peerDisplayProfileProvider.notifier)
        .updateFromRemote(
          ownerDid: session.did,
          peerPersonaId: peerPersonaId,
          profile: const UserProfile(
            did: peerDid,
            displayName: '卓诚',
            bio: '',
            tags: <String>[],
            profileMarkdown: '',
            fullHandle: 'zhuocheng.awiki.info',
            avatarUri: avatarUri,
          ),
        );
    await tester.pump();

    await tester.tap(find.byKey(const Key('group-detail-add-member-button')));
    await tester.pumpAndSettle();

    final candidate = find.byKey(const Key('group-invite-candidate:$peerDid'));
    expect(candidate, findsOneWidget);
    expect(
      find.descendant(of: candidate, matching: find.text('卓诚')),
      findsOneWidget,
    );
    final avatar = tester.widget<AvatarBadge>(
      find.descendant(of: candidate, matching: find.byType(AvatarBadge)),
    );
    expect(avatar.seed, '卓诚');
    expect(avatar.avatarUri, avatarUri);
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
    expect(find.text('Bob: 添加失败，请稍后重试'), findsOneWidget);
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

    expect(find.text('bob'), findsOneWidget);
    expect(find.text('@bob.awiki.ai'), findsOneWidget);

    final removeButton = find.bySemanticsLabel('移除成员').last;
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(find.text('移除成员'), findsNWidgets(2));
    expect(
      find.text('移除 bob (@bob.awiki.ai) 后，对方将不能继续在这个群里发送消息。'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('group-remove-member-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(gateway.lastRemovedGroupId, groupDid);
    expect(gateway.lastRemovedMemberRef, 'bob.awiki.ai');
    expect(find.text('bob'), findsNothing);
    expect(find.text('@bob.awiki.ai'), findsNothing);
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
