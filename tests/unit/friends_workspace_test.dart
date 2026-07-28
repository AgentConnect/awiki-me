import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_workspace_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/profile/peer_profile_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
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

  testWidgets('窄屏联系人从双预览进入固定列表并返回概览', (tester) async {
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

    expect(find.byKey(const Key('friends-groups-row')), findsOneWidget);
    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.text('Compact Following'), findsOneWidget);
    expect(find.text('Compact Follower'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-following-view-all')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsNothing);
    expect(find.byType(RelationshipListPage), findsOneWidget);
    expect(
      tester
          .widget<RelationshipListPage>(find.byType(RelationshipListPage))
          .type,
      FriendsRelationshipListType.following,
    );
    expect(find.text('Compact Following'), findsOneWidget);
    expect(find.text('Compact Follower'), findsNothing);

    await _simulateSystemBack(tester);
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.text('Compact Following'), findsOneWidget);
    expect(find.text('Compact Follower'), findsOneWidget);

    await tester.tap(find.byKey(const Key('friends-followers-view-all')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsNothing);
    expect(find.byType(RelationshipListPage), findsOneWidget);
    expect(
      tester
          .widget<RelationshipListPage>(find.byType(RelationshipListPage))
          .type,
      FriendsRelationshipListType.followers,
    );
    expect(find.text('Compact Following'), findsNothing);
    expect(find.text('Compact Follower'), findsOneWidget);

    await tester.tap(find.byKey(const Key('relationship-list-back-button')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendsPage), findsOneWidget);
    expect(find.text('Compact Following'), findsOneWidget);
    expect(find.text('Compact Follower'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('friends-followers-view-all')));
    await tester.pumpAndSettle();

    expect(find.byType(RelationshipListPage), findsOneWidget);
    expect(
      tester
          .widget<RelationshipListPage>(find.byType(RelationshipListPage))
          .type,
      FriendsRelationshipListType.followers,
    );
    expect(find.text('Responsive Following'), findsNothing);
    await tester.tap(find.byKey(const Key('contact-row:$followerDid')));
    await tester.pumpAndSettle();

    expect(find.byType(PeerProfilePage), findsOneWidget);
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
    expect(find.byType(RelationshipListPage), findsOneWidget);
    expect(
      tester
          .widget<RelationshipListPage>(find.byType(RelationshipListPage))
          .type,
      FriendsRelationshipListType.followers,
    );
    expect(find.text('Responsive Follower'), findsOneWidget);
    expect(find.text('Responsive Following'), findsNothing);

    await _simulateSystemBack(tester);
    await tester.pumpAndSettle();

    expect(find.byType(RelationshipListPage), findsNothing);
    expect(find.text('Responsive Follower'), findsOneWidget);
    expect(find.text('Responsive Following'), findsOneWidget);
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
            (ref) => _StaticFriendsController(ref, const FriendsState()),
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
    final listSurface = tester.widget<DecoratedBox>(
      find.byKey(const Key('friends-list-surface')),
    );
    expect(
      (listSurface.decoration as BoxDecoration).color,
      AwikiMeColors.surface,
    );
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
    expect(find.text('个人资料'), findsOneWidget);
    await tester.tap(find.byKey(const Key('peer-profile-send-message')));
    await tester.pumpAndSettle();

    final conversation = tester
        .widget<ChatView>(find.byType(ChatView))
        .conversation;
    expect(conversation.targetDid, 'did:test:alice');
    expect(conversation.displayName, 'Alice');
    expect(conversation.conversationId, 'dm:peer-scope:v1:alice');
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
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
  });
}
