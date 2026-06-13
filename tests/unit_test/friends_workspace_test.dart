import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/conversation_list/conversation_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/friends/friends_workspace_page.dart';
import 'package:awiki_me/src/presentation/group/group_list_page.dart';
import 'package:awiki_me/src/presentation/group/group_provider.dart';
import 'package:awiki_me/src/presentation/shared/responsive_layout.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

void main() {
  testWidgets('桌面宽度下联系人页保持左右分栏布局', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));

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
  });

  testWidgets('联系人页分区展示群组、我关注的和关注我的预览', (tester) async {
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
    expect(find.text('我关注的'), findsOneWidget);
    expect(find.text('关注我的'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Carol'), findsOneWidget);
    expect(find.text('Dora'), findsNothing);
    expect(find.text('Erin'), findsOneWidget);
    expect(find.text('Frank'), findsOneWidget);
    expect(find.text('查看全部'), findsNWidgets(2));
  });

  testWidgets('点击我关注的联系人会打开被点击对象的直聊', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    const session = SessionIdentity(
      did: 'did:test:me',
      handle: 'me',
      displayName: 'Me',
      credentialName: 'default',
    );
    final gateway = FakeAwikiGateway()
      ..conversations = <ConversationSummary>[
        ConversationSummary(
          threadId: 'dm:did:test:alice:did:test:me',
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
        home: const FriendsPage(),
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

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendsPage)),
    );
    final selected = container.read(selectedConversationProvider);
    expect(selected?.targetDid, 'did:test:alice');
    expect(selected?.displayName, 'Alice');
    expect(
      container
          .read(conversationListProvider)
          .conversations
          .firstWhere((item) => item.threadId == selected?.threadId)
          .targetDid,
      'did:test:alice',
    );
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

      await tester.tap(find.text('查看全部'));
      await tester.pumpAndSettle();

      expect(find.byType(RelationshipListPage), findsOneWidget);
      expect(find.text('取消关注'), findsOneWidget);

      await tester.tap(find.text('取消关注'));
      await tester.pump();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);

      await tester.tap(find.text('取消关注').last);
      await tester.pump();

      expect(gateway.lastUnfollowedDidOrHandle, 'did:test:alice');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await tester.binding.setSurfaceSize(null);
    }
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
