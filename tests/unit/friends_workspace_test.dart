import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/navigation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_navigation_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_workspace_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_profile_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/compact_nested_navigator_back_scope.dart';
import 'package:awiki_me/src/presentation/shared/responsive_layout.dart';
import 'package:awiki_me/src/presentation/shared/sidebar_workspace.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show JSONMessageCodec;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class _StaticFriendsController extends FriendsController {
  _StaticFriendsController(super.ref, FriendsState initialState) {
    state = initialState;
  }
}

class _StaticGroupController extends GroupController {
  _StaticGroupController(super.ref, GroupState initialState) {
    state = initialState;
  }
}

const _friendsWorkspaceSession = SessionIdentity(
  did: 'did:test:me',
  credentialName: 'friends-workspace',
  handle: 'me.awiki',
  displayName: 'Me',
);

Future<void> _simulateSystemBack(WidgetTester tester) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMessageCodec().encodeMessage(<String, dynamic>{
      'method': 'popRoute',
    }),
    (_) {},
  );
}

void main() {
  testWidgets('桌面联系人概览保持左右分栏并默认留空右侧', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsWorkspacePage(),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:friend-1',
                    displayName: 'Alice',
                    relationship: 'following',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AwikiPaneLayout), findsOneWidget);
    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byType(FriendsWorkspacePage), findsOneWidget);
    expect(find.byType(AwikiWorkspaceEmptyDetail), findsOneWidget);
    expect(find.byType(RelationshipListPage), findsNothing);
    expect(
      find.byKey(const Key('friends-expanded-list-header')),
      findsOneWidget,
    );
    final paneRect = tester.getRect(find.byType(AwikiSidebarWorkspace));
    final titleRect = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('friends-expanded-list-header')),
        matching: find.text('联系人'),
      ),
    );
    final headerContext = tester.element(
      find.byKey(const Key('friends-expanded-list-header')),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('friends-expanded-list-header')))
          .height,
      closeTo(headerContext.awikiResponsive.displayScaled(56), 0.01),
    );
    expect(
      titleRect.left - paneRect.left,
      closeTo(headerContext.awikiResponsive.spacing(14), 1),
    );
  });

  testWidgets('桌面联系人右上角快捷操作使用锚定菜单', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsWorkspacePage(),
        session: _friendsWorkspaceSession,
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(const Key('shell-quick-actions-button'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.byType(AppDropMenu), findsNothing);
    final firstItem = find.byKey(const Key('quick-action-start-conversation'));
    expect(firstItem, findsOneWidget);
    final triggerRect = tester.getRect(trigger);
    final firstItemRect = tester.getRect(firstItem);
    expect(firstItemRect.top, greaterThan(triggerRect.bottom));
    expect(firstItemRect.left, lessThan(triggerRect.left));

    await tester.tapAt(const Offset(1000, 700));
    await tester.pumpAndSettle();
    expect(firstItem, findsNothing);
  });

  testWidgets('桌面概览的两个查看全部只在右侧切换对应列表', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:desktop-following',
          displayName: 'Desktop Following',
          relationship: 'following',
        ),
      ]
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:desktop-follower',
          displayName: 'Desktop Follower',
          relationship: 'follower',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:desktop-following',
                    displayName: 'Desktop Following',
                    relationship: 'following',
                  ),
                ],
                followers: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:desktop-follower',
                    displayName: 'Desktop Follower',
                    relationship: 'follower',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Desktop Following'), findsOneWidget);
    expect(find.text('Desktop Follower'), findsOneWidget);
    expect(find.byType(AwikiWorkspaceEmptyDetail), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-following-view-all')));
    await tester.pumpAndSettle();

    expect(find.byType(AwikiWorkspaceEmptyDetail), findsNothing);
    expect(find.byType(RelationshipListPage), findsOneWidget);
    expect(
      tester
          .widget<RelationshipListPage>(find.byType(RelationshipListPage))
          .type,
      FriendsRelationshipListType.following,
    );

    await tester.tap(find.byKey(const Key('friends-followers-view-all')));
    await tester.pumpAndSettle();

    expect(find.byType(RelationshipListPage), findsOneWidget);
    expect(
      tester
          .widget<RelationshipListPage>(find.byType(RelationshipListPage))
          .type,
      FriendsRelationshipListType.followers,
    );
  });

  testWidgets('窄屏联系人四个 Tab 原位切换分类内容', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:compact-following',
          displayName: 'Compact Following',
          relationship: 'following',
        ),
      ]
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:compact-follower',
          displayName: 'Compact Follower',
          relationship: 'follower',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:compact-following',
                    displayName: 'Compact Following',
                    relationship: 'following',
                  ),
                ],
                followers: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:compact-follower',
                    displayName: 'Compact Follower',
                    relationship: 'follower',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.byKey(const Key('friends-category-tabs')), findsOneWidget);
    for (final entry in <(String, String)>[
      ('all', '全部'),
      ('following', '关注'),
      ('followers', '粉丝'),
      ('groups', '群组'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(Key('friends-category-tab-${entry.$1}')),
          matching: find.text(entry.$2),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Compact Following'), findsOneWidget);
    expect(find.text('Compact Follower'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-category-tab-following')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.text('Compact Following'), findsOneWidget);
    expect(find.text('Compact Follower'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('relationship-action-visual'))),
      const Size(80, 38),
    );

    await tester.tap(find.byKey(const Key('friends-category-tab-followers')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.text('Compact Following'), findsNothing);
    expect(find.text('Compact Follower'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-category-tab-groups')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.byType(GroupListPage), findsNothing);
    expect(find.text('Compact Following'), findsNothing);
    expect(find.text('Compact Follower'), findsNothing);
    expect(find.textContaining('还没有群组'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-category-tab-all')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.text('Compact Following'), findsOneWidget);
    expect(find.text('Compact Follower'), findsOneWidget);
  });

  testWidgets('窄屏全部联系人按 DID 去重且群组 Tab 原位展示列表', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const mutual = RelationshipSummary(
      did: 'did:test:mutual',
      displayName: 'Mutual Contact',
      relationship: 'following',
    );
    const follower = RelationshipSummary(
      did: 'did:test:follower-only',
      displayName: 'Follower Only',
      relationship: 'follower',
    );
    final groups = <GroupSummary>[
      GroupSummary(
        groupId: 'did:test:group:design',
        conversationId: 'group:did:test:group:design',
        name: 'Design Group',
        description: 'UI review',
        memberCount: 4,
        lastMessageAt: DateTime(2026, 8, 2),
      ),
    ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[mutual],
                followers: <RelationshipSummary>[mutual, follower],
              ),
            ),
          ),
          groupProvider.overrideWith(
            (ref) => _StaticGroupController(ref, GroupState(groups: groups)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mutual Contact'), findsOneWidget);
    expect(find.text('Follower Only'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-category-tab-groups')));
    await tester.pumpAndSettle();

    expect(find.byType(GroupListPage), findsNothing);
    expect(
      find.byKey(const Key('friends-group-tab-row:did:test:group:design')),
      findsOneWidget,
    );
    expect(find.text('Design Group'), findsOneWidget);
    expect(find.text('UI review'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoSearchTextField>(
            find.byKey(const Key('friends-search-field')),
          )
          .placeholder,
      '搜索群组',
    );
  });

  testWidgets('群组 Tab 在保留页面隐藏并恢复后仍完整显示', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final groups = <GroupSummary>[
      GroupSummary(
        groupId: 'did:test:group:retained',
        conversationId: 'group:did:test:group:retained',
        name: 'Retained Group',
        description: '',
        memberCount: 2,
        lastMessageAt: DateTime(2026, 8, 2),
      ),
    ];
    var contactsActive = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setHostState = setState;
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Offstage(
                  offstage: !contactsActive,
                  child: TickerMode(
                    enabled: contactsActive,
                    child: const FriendsWorkspacePage(),
                  ),
                ),
                Offstage(
                  offstage: contactsActive,
                  child: const ColoredBox(color: CupertinoColors.white),
                ),
              ],
            );
          },
        ),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(ref, const FriendsState()),
          ),
          groupProvider.overrideWith(
            (ref) => _StaticGroupController(ref, GroupState(groups: groups)),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friends-category-tab-groups')));
    await tester.pumpAndSettle();
    expect(find.text('Retained Group'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('friends-list-surface')),
        matching: find.byType(AnimatedSwitcher),
      ),
      findsNothing,
    );

    setHostState(() => contactsActive = false);
    await tester.pump();
    setHostState(() => contactsActive = true);
    await tester.pumpAndSettle();

    expect(find.text('联系人'), findsOneWidget);
    expect(find.text('搜索群组'), findsOneWidget);
    expect(find.text('Retained Group'), findsOneWidget);
    expect(
      find.byKey(const Key('friends-group-tab-row:did:test:group:retained')),
      findsOneWidget,
    );
  });

  testWidgets('窄屏联系人群组直达会话且系统返回联系人群组 Tab', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final group = GroupSummary(
      groupId: 'did:test:group:contacts-route',
      conversationId: 'group:did:test:group:contacts-route',
      name: 'Contacts Route Group',
      description: '',
      memberCount: 2,
      lastMessageAt: DateTime(2026, 8, 2),
    );
    final gateway = FakeAwikiGateway()..groups = <GroupSummary>[group];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiShellNavigationScope(child: FriendsWorkspacePage()),
        gateway: gateway,
        session: _friendsWorkspaceSession,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(ref, const FriendsState()),
          ),
          groupProvider.overrideWith(
            (ref) => _StaticGroupController(
              ref,
              GroupState(groups: <GroupSummary>[group]),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendsWorkspacePage)),
    );
    container
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.contacts);

    await tester.tap(find.byKey(const Key('friends-category-tab-groups')));
    await tester.pumpAndSettle();
    final groupRow = find.byKey(
      const Key('friends-group-tab-row:did:test:group:contacts-route'),
    );

    for (var round = 0; round < 3; round += 1) {
      await tester.tap(groupRow);
      await tester.pump();

      expect(find.byType(ChatPage), findsOneWidget, reason: 'round $round');
      final backScope = tester.widget<CompactNestedNavigatorBackScope>(
        find.byKey(const Key('friends-compact-back-scope')),
      );
      expect(backScope.active, isTrue, reason: 'round $round');
      expect(backScope.hasNestedRoute, isTrue, reason: 'round $round');
      expect(
        container.read(friendsWorkspaceNavigationProvider).detail,
        FriendsWorkspaceDetail.groupChat,
        reason: 'round $round',
      );
      expect(
        container.read(shellDestinationProvider),
        ShellDestination.contacts,
        reason: 'round $round',
      );
      expect(container.read(selectedConversationProvider), isNull);

      if (round == 0) {
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('chat-information-button')));
        await tester.pumpAndSettle();
        expect(find.text('群聊信息'), findsWidgets);

        await _simulateSystemBack(tester);
        await tester.pumpAndSettle();

        expect(find.text('群聊信息'), findsNothing);
        expect(find.byType(ChatPage), findsOneWidget);
        expect(
          container.read(friendsWorkspaceNavigationProvider).detail,
          FriendsWorkspaceDetail.groupChat,
        );
      }

      await _simulateSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ChatPage), findsNothing, reason: 'round $round');
      expect(find.byType(FriendsPage), findsOneWidget, reason: 'round $round');
      expect(find.text('Contacts Route Group'), findsOneWidget);
      expect(
        container.read(friendsWorkspaceNavigationProvider).detail,
        FriendsWorkspaceDetail.overview,
        reason: 'round $round',
      );
      expect(
        container.read(shellDestinationProvider),
        ShellDestination.contacts,
        reason: 'round $round',
      );
    }
  });

  testWidgets('联系人消息按钮进入聊天后系统返回不会弹空后台联系人导航栈', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const did = 'did:test:contact-message-back';
    const contact = RelationshipSummary(
      did: did,
      displayName: 'Contact Message Back',
      relationship: 'following',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        did: UserProfile(
          did: did,
          displayName: 'Contact Message Back',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
        ),
      }
      ..directoryConversationIdsByQuery = <String, String>{
        did: 'dm:peer-scope:v1:contact-message-back',
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: _friendsWorkspaceSession,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(following: <RelationshipSummary>[contact]),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('compact-nav-contacts')));
    await tester.pumpAndSettle();
    final contactRow = find.byKey(const Key('friends-all-contact:$did'));
    expect(contactRow, findsOneWidget);
    await tester.tap(
      find.descendant(of: contactRow, matching: find.text('消息')),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    expect(find.byType(ChatPage), findsOneWidget);
    expect(container.read(shellDestinationProvider), ShellDestination.messages);

    await _simulateSystemBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsNothing);

    await tester.tap(find.byKey(const Key('compact-nav-contacts')));
    await tester.pumpAndSettle();

    expect(container.read(shellDestinationProvider), ShellDestination.contacts);
    expect(find.byKey(const Key('friends-page-surface')), findsOneWidget);
    expect(find.byKey(const Key('friends-list-surface')), findsOneWidget);
    expect(contactRow, findsOneWidget);
  });

  testWidgets('窄屏粉丝列表资料跨断点保持返回层级', (tester) async {
    const followerDid = 'did:test:responsive-follower';
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:responsive-following',
          displayName: 'Responsive Following',
          relationship: 'following',
        ),
      ]
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: followerDid,
          displayName: 'Responsive Follower',
          relationship: 'follower',
        ),
      ]
      ..publicProfilesByQuery = const <String, UserProfile>{
        followerDid: UserProfile(
          did: followerDid,
          displayName: 'Responsive Follower',
          bio: 'Responsive profile',
          tags: <String>[],
          profileMarkdown: '',
        ),
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsWorkspacePage(),
        gateway: gateway,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:responsive-following',
                    displayName: 'Responsive Following',
                    relationship: 'following',
                  ),
                ],
                followers: <RelationshipSummary>[
                  RelationshipSummary(
                    did: followerDid,
                    displayName: 'Responsive Follower',
                    relationship: 'follower',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Responsive Follower'), findsOneWidget);
    expect(find.text('Responsive Following'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-category-tab-followers')));
    await tester.pumpAndSettle();

    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.text('Responsive Following'), findsNothing);
    await tester.tap(
      find.byKey(const Key('friends-followers-contact:$followerDid')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PeerProfilePage), findsOneWidget);
    expect(find.text('Responsive profile'), findsNothing);
    await tester.tap(find.byKey(const Key('peer-profile-summary-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Responsive profile'), findsOneWidget);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();

    expect(find.byType(AwikiPaneLayout), findsOneWidget);
    expect(find.byType(PeerProfilePage), findsOneWidget);
    expect(find.text('Responsive profile'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();

    expect(find.byType(PeerProfilePage), findsOneWidget);
    await _simulateSystemBack(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PeerProfilePage), findsNothing);
    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.text('Responsive Follower'), findsOneWidget);
    expect(find.text('Responsive Following'), findsNothing);
  });

  testWidgets('联系人页分区展示群组、我关注的和关注我的预览', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:following-1',
                    displayName: 'Alice',
                    relationship: 'following',
                  ),
                  RelationshipSummary(
                    did: 'did:test:following-2',
                    displayName: 'Bob',
                    relationship: 'following',
                  ),
                  RelationshipSummary(
                    did: 'did:test:following-3',
                    displayName: 'Carol',
                    relationship: 'following',
                  ),
                  RelationshipSummary(
                    did: 'did:test:following-4',
                    displayName: 'Dora',
                    relationship: 'following',
                  ),
                ],
                followers: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:follower-1',
                    displayName: 'Erin',
                    relationship: 'follower',
                  ),
                  RelationshipSummary(
                    did: 'did:test:follower-2',
                    displayName: 'Frank',
                    relationship: 'follower',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('群组'), findsOneWidget);
    expect(find.byKey(const Key('friends-groups-row')), findsOneWidget);
    expect(find.text('我关注的'), findsOneWidget);
    expect(find.text('关注我的'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('Dora'), findsNothing);
    expect(find.text('Erin'), findsOneWidget);
    expect(find.text('Frank'), findsOneWidget);
    expect(find.text('查看全部'), findsNWidgets(2));
    expect(find.text('朋友'), findsNothing);
  });

  testWidgets('窄屏联系人一级页使用全宽连续表面', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:compact-contact',
                    displayName: 'Compact Contact',
                    relationship: 'following',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final pageRect = tester.getRect(
      find.byKey(const Key('friends-page-surface')),
    );
    final listRect = tester.getRect(
      find.byKey(const Key('friends-list-surface')),
    );
    expect(pageRect.left, 0);
    expect(pageRect.right, 390);
    expect(listRect.left, pageRect.left);
    expect(listRect.right, pageRect.right);
    expect(listRect.bottom, pageRect.bottom);
    final contactTitle = tester.widget<Text>(find.text('Compact Contact'));
    expect(contactTitle.style?.fontSize, 14);
    expect(contactTitle.style?.fontWeight, FontWeight.w400);
    final listSurface = tester.widget<DecoratedBox>(
      find.byKey(const Key('friends-list-surface')),
    );
    expect(
      (listSurface.decoration as BoxDecoration).color,
      AwikiMeColors.background,
    );
    final categoryTabs = find.byKey(const Key('friends-category-tabs'));
    expect(tester.getRect(categoryTabs), const Rect.fromLTWH(0, 132, 390, 56));
    for (final tab in <String>['all', 'following', 'followers', 'groups']) {
      expect(
        tester.getSize(find.byKey(Key('friends-category-tab-$tab'))),
        const Size(97.5, 55),
      );
    }
    expect(
      tester.getSize(find.byKey(const Key('friends-category-tab-indicator'))),
      const Size(40, 3),
    );
    expect(find.byKey(const Key('friends-groups-row')), findsNothing);
    final compactHeader = find.byKey(const Key('shell-compact-header'));
    expect(tester.getRect(compactHeader), const Rect.fromLTWH(0, 0, 390, 64));
    final title = tester.widget<Text>(
      find.descendant(of: compactHeader, matching: find.text('联系人')),
    );
    expect(title.style?.fontSize, 16);
    expect(title.style?.fontWeight, FontWeight.w400);
    expect(title.style?.height, 1.25);
    expect(find.byKey(const Key('awiki-me-brand-mark')), findsNothing);
    final actionVisual = find.byKey(const Key('relationship-action-visual'));
    expect(tester.getSize(actionVisual.first), const Size(64, 38));
    final actionTarget = find.ancestor(
      of: actionVisual.first,
      matching: find.byType(AppPressable),
    );
    expect(tester.getSize(actionTarget.first), const Size(64, 44));

    final trigger = find.byKey(const Key('shell-quick-actions-button'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();

    expect(find.byType(AppDropMenu), findsNothing);
    final menu = find.byKey(const Key('compact-quick-actions-menu'));
    expect(menu, findsOneWidget);
    final menuRect = tester.getRect(menu);
    expect(menuRect.right, 382);
    expect(menuRect.width, 196);
    expect(menuRect.height, 208);
    expect(menuRect.top, greaterThan(tester.getRect(trigger).bottom));
    expect(
      tester.getSize(find.byKey(const Key('quick-action-start-conversation'))),
      const Size(196, 52),
    );

    await tester.tapAt(const Offset(8, 400));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
  });

  testWidgets('联系人页关注我的预览可直接回关联系人', (tester) async {
    final gateway = FakeAwikiGateway()
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:follower-1',
          displayName: 'Erin',
          relationship: 'follower',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        session: _friendsWorkspaceSession,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                followers: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:follower-1',
                    displayName: 'Erin',
                    relationship: 'follower',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(gateway.lastFollowedDidOrHandle, 'did:test:follower-1');
    expect(gateway.following.single.did, 'did:test:follower-1');
    expect(find.text('Erin'), findsOneWidget);
  });

  testWidgets('回关联系人成功后列表刷新失败也保持乐观关注态', (tester) async {
    final gateway = FakeAwikiGateway()
      ..failListFollowing = true
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:follower-1',
          displayName: 'Erin',
          relationship: 'follower',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        session: _friendsWorkspaceSession,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                followers: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:follower-1',
                    displayName: 'Erin',
                    relationship: 'follower',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('关注'));
    await tester.pumpAndSettle();

    expect(gateway.lastFollowedDidOrHandle, 'did:test:follower-1');
    expect(gateway.following.single.did, 'did:test:follower-1');
    expect(find.text('Erin'), findsOneWidget);
  });

  testWidgets('互相关注联系人只分别显示在我关注的和关注我的', (tester) async {
    const mutual = RelationshipSummary(
      did: 'did:test:mutual',
      displayName: 'Mutual Alice',
      relationship: 'friend',
    );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[mutual],
                followers: <RelationshipSummary>[mutual],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mutual Alice'), findsNWidgets(2));
    expect(find.text('我关注的'), findsOneWidget);
    expect(find.text('关注我的'), findsOneWidget);
    expect(find.text('朋友'), findsNothing);
    expect(find.text('关注'), findsNothing);
  });

  testWidgets('完整关注我的列表保留已经互关的联系人', (tester) async {
    const mutual = RelationshipSummary(
      did: 'did:test:mutual-full-list',
      displayName: 'Mutual Full List',
      relationship: 'friend',
    );
    final gateway = FakeAwikiGateway()
      ..followers = const <RelationshipSummary>[mutual]
      ..following = const <RelationshipSummary>[mutual];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const RelationshipListPage(
          type: FriendsRelationshipListType.followers,
        ),
        gateway: gateway,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                followers: <RelationshipSummary>[mutual],
                following: <RelationshipSummary>[mutual],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mutual Full List'), findsOneWidget);
    expect(find.text('取消关注'), findsOneWidget);
  });

  testWidgets('联系人预览区分加载失败与真实空列表并支持重试', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              FriendsState(followersError: StateError('followers failed')),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有关注任何人。'), findsOneWidget);
    expect(find.text('操作失败，请稍后重试。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('窄屏联系人进入全屏真实资料子页', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    const did = 'did:test:compact-alice';
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        did: UserProfile(
          did: did,
          displayName: 'Compact Alice',
          bio: 'Compact profile',
          tags: <String>[],
          profileMarkdown: '',
        ),
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: did,
                    displayName: 'Compact Alice',
                    relationship: 'following',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contact-row:$did')));
    await tester.pumpAndSettle();

    expect(find.byType(PeerProfilePage), findsOneWidget);
    expect(find.text('Compact profile'), findsOneWidget);
  });

  testWidgets('点击联系人先展示真实资料并可从资料发起直聊', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        'did:test:alice': UserProfile(
          did: 'did:test:alice',
          displayName: 'Alice',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
        ),
      }
      ..directoryConversationIdsByQuery = <String, String>{
        'did:test:alice': 'dm:peer-scope:v1:alice',
      }
      ..conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: 'dm:did:test:alice:did:test:me',
          conversationId: 'dm:did:test:alice:did:test:me',
          displayName: 'Stale Bob',
          lastMessagePreview: 'old',
          lastMessageAt: DateTime(2026, 5, 27, 12),
          unreadCount: 0,
          isGroup: false,
          targetDid: 'did:test:bob',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsWorkspacePage(),
        gateway: gateway,
        session: session,
        profile: const UserProfile(
          did: 'did:test:me',
          nickName: 'Me',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
        ),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: 'did:test:alice',
                    displayName: 'Alice',
                    relationship: 'following',
                  ),
                  RelationshipSummary(
                    did: 'did:test:bob',
                    displayName: 'Bob',
                    relationship: 'following',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('contact-row:did:test:alice')));
    await tester.pumpAndSettle();

    expect(find.byType(PeerProfilePage), findsOneWidget);
    expect(find.text('用户信息'), findsOneWidget);
    await tester.tap(find.byKey(const Key('peer-profile-send-message')));
    await tester.pumpAndSettle();

    final conversation = tester
        .widget<ChatView>(find.byType(ChatView))
        .conversation;
    expect(conversation.targetDid, 'did:test:alice');
    expect(conversation.displayName, 'Alice');
    expect(conversation.conversationId, 'dm:peer-scope:v1:alice');
  });

  testWidgets('窄屏从联系人资料发消息后返回仍保留联系人资料层级', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const did = 'did:test:compact-profile-chat';
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{
        did: UserProfile(
          did: did,
          displayName: 'Compact Profile Chat',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
        ),
      }
      ..directoryConversationIdsByQuery = <String, String>{
        did: 'dm:peer-scope:v1:compact-profile-chat',
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiShellNavigationScope(child: FriendsWorkspacePage()),
        gateway: gateway,
        session: _friendsWorkspaceSession,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: did,
                    displayName: 'Compact Profile Chat',
                    relationship: 'following',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendsWorkspacePage)),
    );
    container
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.contacts);

    await tester.tap(find.byKey(const Key('friends-all-contact:$did')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('peer-profile-send-message')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsOneWidget);
    expect(container.read(shellDestinationProvider), ShellDestination.contacts);

    await _simulateSystemBack(tester);
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsNothing);
    expect(find.byType(PeerProfilePage), findsOneWidget);
    expect(container.read(shellDestinationProvider), ShellDestination.contacts);
  });

  testWidgets('macOS 点击我关注的在右侧展示完整联系人列表并可取消关注', (tester) async {
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:alice',
          displayName: 'Alice',
          relationship: 'following',
        ),
      ];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    try {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const FriendsWorkspacePage(),
          gateway: gateway,
          session: _friendsWorkspaceSession,
          providerOverrides: <Override>[
            friendsProvider.overrideWith(
              (ref) => _StaticFriendsController(
                ref,
                const FriendsState(
                  following: <RelationshipSummary>[
                    RelationshipSummary(
                      did: 'did:test:alice',
                      displayName: 'Alice',
                      relationship: 'following',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AwikiWorkspaceEmptyDetail), findsOneWidget);

      await tester.tap(find.byKey(const Key('friends-following-view-all')));
      await tester.pumpAndSettle();

      expect(find.byType(RelationshipListPage), findsOneWidget);
      expect(
        tester
            .widget<RelationshipListPage>(find.byType(RelationshipListPage))
            .type,
        FriendsRelationshipListType.following,
      );
      expect(find.text('取消关注'), findsOneWidget);

      await tester.tap(find.text('取消关注'));
      await tester.pump();
      expect(find.byKey(const Key('confirm-unfollow-button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-unfollow-button')));
      await tester.pump();

      expect(gateway.lastUnfollowedDidOrHandle, 'did:test:alice');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('Linux 宽屏从完整联系人列表查看资料并打开会话', (tester) async {
    const peerDid = 'did:test:alice';
    final gateway = FakeAwikiGateway()
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: peerDid,
          displayName: 'Alice',
          relationship: 'follower',
        ),
      ]
      ..directoryConversationIdsByQuery = const <String, String>{
        peerDid: 'dm:peer-scope:v1:alice',
      }
      ..publicProfilesByQuery = const <String, UserProfile>{
        peerDid: UserProfile(
          did: peerDid,
          displayName: 'Alice',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
        ),
      };
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AwikiShellNavigationScope(child: FriendsWorkspacePage()),
        gateway: gateway,
        session: const SessionIdentity(
          did: 'did:test:me',
          credentialName: 'default',
          handle: 'me',
          displayName: 'Me',
        ),
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                followers: <RelationshipSummary>[
                  RelationshipSummary(
                    did: peerDid,
                    displayName: 'Alice',
                    relationship: 'follower',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendsWorkspacePage)),
    );

    await tester.tap(find.byKey(const Key('friends-followers-view-all')));
    await tester.pumpAndSettle();
    expect(find.byType(RelationshipListPage), findsOneWidget);

    final fullListRow = find.descendant(
      of: find.byType(RelationshipListPage),
      matching: find.byKey(const Key('contact-row:$peerDid')),
    );
    expect(fullListRow, findsOneWidget);
    await tester.tap(fullListRow);
    await tester.pumpAndSettle();

    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.byType(PeerProfilePage), findsOneWidget);

    await tester.tap(find.byKey(const Key('peer-profile-send-message')));
    await tester.pumpAndSettle();

    expect(
      container.read(selectedConversationProvider),
      'dm:peer-scope:v1:alice',
    );
  });

  testWidgets('查看全部会并发补齐缺失 profile 并显示昵称', (tester) async {
    const peerDid = 'did:test:profile-missing';
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      handle: 'me',
      displayName: 'Me',
    );
    final gateway = FakeAwikiGateway()
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: peerDid,
          displayName: peerDid,
          relationship: 'following',
        ),
      ]
      ..publicProfilesByQuery = const <String, UserProfile>{
        peerDid: UserProfile(
          did: peerDid,
          displayName: '远端昵称',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          fullHandle: 'profile-missing.awiki.ai',
        ),
      };

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const FriendsPage(),
        gateway: gateway,
        session: session,
        providerOverrides: <Override>[
          friendsProvider.overrideWith(
            (ref) => _StaticFriendsController(
              ref,
              const FriendsState(
                following: <RelationshipSummary>[
                  RelationshipSummary(
                    did: peerDid,
                    displayName: peerDid,
                    relationship: 'following',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('friends-following-view-all')));
    await tester.pumpAndSettle();

    expect(find.text('远端昵称'), findsOneWidget);
    expect(gateway.loadPublicProfileQueries, <String>[peerDid]);
  });

  testWidgets('关注列表加载失败时显示错误并支持重试', (tester) async {
    final gateway = FakeAwikiGateway()..failListFollowing = true;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const RelationshipListPage(
          type: FriendsRelationshipListType.following,
        ),
        gateway: gateway,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('following unavailable'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    gateway
      ..failListFollowing = false
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:alice',
          displayName: 'Alice',
          relationship: 'following',
        ),
      ];

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.textContaining('following unavailable'), findsNothing);
  });

  testWidgets('macOS 点击联系人页 Group 入口在右侧展示群聊列表', (tester) async {
    final groups = <GroupSummary>[
      GroupSummary(
        groupId: 'did:test:group:funding',
        conversationId: 'group:did:test:group:funding',
        name: '融资协作群',
        description: '融资材料同步',
        memberCount: 3,
        lastMessageAt: DateTime(2026, 5, 27, 12),
        myRole: 'owner',
      ),
    ];
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    try {
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const FriendsWorkspacePage(),
          providerOverrides: <Override>[
            groupProvider.overrideWith(
              (ref) => _StaticGroupController(ref, GroupState(groups: groups)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupListPage), findsNothing);
      expect(find.text('群聊列表'), findsNothing);

      await tester.tap(find.text('群组').last);
      await tester.pumpAndSettle();

      expect(find.byType(FriendsWorkspacePage), findsOneWidget);
      expect(find.byType(FriendsPage), findsOneWidget);
      expect(find.byType(GroupListPage), findsOneWidget);
      expect(find.text('群聊列表'), findsOneWidget);
      expect(find.text('融资协作群'), findsOneWidget);
      final pageRect = tester.getRect(find.byType(GroupListPage));
      final cardRect = tester.getRect(
        find.byKey(const Key('group-list-card:did:test:group:funding')),
      );
      expect(cardRect.left, greaterThan(pageRect.left + 10));
      expect(cardRect.right, lessThan(pageRect.right - 10));

      final friendsSurface = tester.widget<DecoratedBox>(
        find.byKey(const Key('friends-list-surface')),
      );
      expect(
        (friendsSurface.decoration as BoxDecoration).color,
        AwikiMeColors.surface,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });
}
