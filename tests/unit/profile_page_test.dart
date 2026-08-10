import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/compact_nested_navigator_back_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show JSONMessageCodec;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

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
  testWidgets('窄屏我的页面使用暖灰内容底和白色顶栏', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = UserProfile(
      did: 'did:test:compact-profile-surface',
      nickName: 'Compact Alice',
      bio: '',
      tags: <String>[],
      handle: 'compact-alice',
      profileMarkdown: '',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfilePage(),
        gateway: FakeAwikiGateway()..myProfile = profile,
        profile: profile,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<CupertinoPageScaffold>(
      find.byType(CupertinoPageScaffold),
    );
    final tabSurface = tester.widget<ColoredBox>(
      find.byKey(const Key('shell-tab-page-surface')),
    );
    final compactHeader = tester.widget<DecoratedBox>(
      find.byKey(const Key('profile-compact-header')),
    );
    final headerDecoration = compactHeader.decoration as BoxDecoration;
    expect(scaffold.backgroundColor, AwikiMeColors.surface);
    expect(tabSurface.color, AwikiMeColors.background);
    expect(headerDecoration.color, AwikiMeColors.surface);
    expect(headerDecoration.border, isNull);
    final compactTitle = tester.widget<Text>(find.text('我'));
    expect(compactTitle.style?.fontSize, 16);
    expect(compactTitle.style?.fontWeight, FontWeight.w400);
    expect(compactTitle.style?.height, 1.25);
    expect(
      tester.getRect(find.byKey(const Key('profile-compact-header'))),
      const Rect.fromLTWH(0, 0, 390, 64),
    );
    expect(
      tester.getRect(find.byKey(const Key('profile-compact-summary'))).top,
      64,
    );
    expect(find.byKey(const Key('awiki-me-brand-mark')), findsNothing);
  });

  testWidgets('窄屏我的页面使用横向昵称简介标签资料头且移除身份卡', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = UserProfile(
      did: 'did:wba:agent-connect.cn:user:newhandle2:e1_profile_key',
      nickName: 'New User',
      bio: '连接人与 Agent，保持简单而高效',
      tags: <String>['开发者', 'AI 协作'],
      handle: 'newhandle2',
      fullHandle: 'newhandle2.agent-connect.cn',
      profileMarkdown: '# Historical identity body',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfilePage(),
        gateway: FakeAwikiGateway()..myProfile = profile,
        profile: profile,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(const Key('profile-display-name'))).data,
      'New User',
    );
    expect(find.text('连接人与 Agent，保持简单而高效'), findsOneWidget);
    expect(find.text('开发者'), findsOneWidget);
    expect(find.text('AI 协作'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('profile-avatar'))),
      const Size.square(72),
    );
    expect(find.text('编辑个人资料'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('profile-edit-button'))).height,
      greaterThanOrEqualTo(104),
    );
    expect(find.byKey(const Key('profile-edit-chevron')), findsOneWidget);
    expect(find.byKey(const Key('profile-statistics-divider')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('profile-compact-summary'))).left,
      0,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('profile-compact-summary')))
          .decoration,
      isNull,
    );
    expect(
      tester
          .widget<Container>(find.byKey(const Key('profile-compact-summary')))
          .color,
      AwikiMeColors.surface,
    );
    expect(
      tester.getRect(find.byKey(const Key('profile-navigation-group'))).top -
          tester
              .getRect(find.byKey(const Key('profile-compact-summary')))
              .bottom,
      8,
    );
    expect(find.byKey(const Key('profile-handle-value')), findsNothing);
    expect(find.text('身份卡'), findsNothing);
    expect(
      find.byKey(const Key('profile-identity-document-row')),
      findsNothing,
    );
    expect(find.byKey(const Key('profile-did-row')), findsOneWidget);
    expect(find.byKey(const Key('profile-homepage-row')), findsOneWidget);
    expect(find.byKey(const Key('profile-settings-row')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('profile-settings-row'))).top -
          tester.getRect(find.byKey(const Key('profile-homepage-row'))).bottom,
      8,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('个人资料页点击编辑后可提交昵称简介和标签', (tester) async {
    final gateway = FakeAwikiGateway();
    const profile = UserProfile(
      did: 'did:test:123',
      nickName: 'Alice',
      bio: 'Old bio',
      tags: <String>['old', 'tag'],
      profileMarkdown: '# Alice',
      handle: 'alice',
    );
    gateway.myProfile = profile;
    gateway.updatedProfile = profile.copyWith();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ProfilePage(homepageMarkdownLoader: (_) async => null),
        gateway: gateway,
        profile: profile,
      ),
    );

    await tester.tap(find.byIcon(CupertinoIcons.pencil));
    await tester.pumpAndSettle();

    expect(find.text('编辑个人资料'), findsWidgets);

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'Alice New');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'New bio');
    await tester.enterText(find.byType(CupertinoTextField).at(2), 'ai, agent');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final patch = gateway.lastProfilePatch;
    expect(patch, isNotNull);
    expect(patch!.nickName, 'Alice New');
    expect(patch.bio, 'New bio');
    expect(patch.tags, <String>['ai', 'agent']);
  });

  testWidgets('窄屏个人资料编辑使用独立页面并在保存后返回', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeAwikiGateway();
    const profile = UserProfile(
      did: 'did:test:compact-edit-profile',
      nickName: 'Alice',
      bio: 'Old bio',
      tags: <String>['old', 'tag'],
      profileMarkdown: '# Alice',
      handle: 'alice',
    );
    gateway.myProfile = profile;
    gateway.updatedProfile = profile.copyWith();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ProfilePage(homepageMarkdownLoader: (_) async => null),
        gateway: gateway,
        profile: profile,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profile-edit-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-edit-page')), findsOneWidget);
    expect(find.byKey(const Key('profile-edit-dialog')), findsNothing);
    expect(find.text('编辑个人资料'), findsOneWidget);
    expect(find.text('头像'), findsOneWidget);
    expect(find.text('最多 5 个标签'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('profile-edit-tag-chip-old')),
          )
          .height,
      40,
    );
    expect(
      tester
          .getSize(
            find.byKey(const ValueKey<String>('profile-edit-remove-tag-old')),
          )
          .height,
      44,
    );
    expect(
      tester.getRect(find.text('昵称')).center.dy,
      closeTo(
        tester
            .getRect(
              find.byKey(const ValueKey<String>('profile-edit-field-昵称')),
            )
            .center
            .dy,
        0.1,
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('profile-edit-add-tag-visual'))),
      const Size(64, 40),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('profile-edit-add-tag-button')))
          .height,
      44,
    );

    await _simulateSystemBack(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-edit-page')), findsNothing);
    expect(find.byKey(const Key('profile-edit-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-edit-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('profile-edit-field-昵称')),
      'Alice New',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('profile-edit-field-个人简介')),
      'New bio',
    );

    for (final tag in <String>['old', 'tag']) {
      final remove = find.byKey(
        ValueKey<String>('profile-edit-remove-tag-$tag'),
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pump();
    }

    for (final tag in <String>['ai', 'agent', 'flutter', 'mobile', 'design']) {
      final add = find.byKey(const Key('profile-edit-add-tag-button'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pump();
      final input = find.byKey(const Key('profile-edit-tag-input'));
      expect(input, findsOneWidget);
      await tester.enterText(input, tag);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(
        find.byKey(ValueKey<String>('profile-edit-tag-chip-$tag')),
        findsOneWidget,
      );
    }

    final disabledAdd = tester.widget<CupertinoButton>(
      find.byKey(const Key('profile-edit-add-tag-button')),
    );
    expect(disabledAdd.onPressed, isNull);

    final save = find.byKey(const Key('profile-edit-save-button'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-edit-page')), findsNothing);
    final patch = gateway.lastProfilePatch;
    expect(patch, isNotNull);
    expect(patch!.nickName, 'Alice New');
    expect(patch.bio, 'New bio');
    expect(patch.tags, <String>['ai', 'agent', 'flutter', 'mobile', 'design']);
  });

  testWidgets('个人资料页显示粉丝和关注数量', (tester) async {
    const profile = UserProfile(
      did: 'did:test:789',
      nickName: 'Elena',
      bio: 'Bio',
      tags: <String>[],
      handle: 'elena',
      profileMarkdown: '# Elena',
    );
    final gateway = FakeAwikiGateway()
      ..myProfile = profile
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:follower-1',
          displayName: 'Follower 1',
          relationship: 'follower',
        ),
        RelationshipSummary(
          did: 'did:test:follower-2',
          displayName: 'Follower 2',
          relationship: 'follower',
        ),
      ]
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:following-1',
          displayName: 'Following 1',
          relationship: 'following',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ProfilePage(homepageMarkdownLoader: (_) async => null),
        gateway: gateway,
        profile: profile,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('2'), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('关注'), findsOneWidget);
  });

  testWidgets('我页关注和粉丝统计打开对应列表并返回我页', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = UserProfile(
      did: 'did:test:profile-relationships',
      nickName: 'Profile Relationships',
      bio: '',
      tags: <String>[],
      handle: 'profile-relationships',
      profileMarkdown: '',
    );
    const session = SessionIdentity(
      did: 'did:test:profile-relationships',
      credentialName: 'profile-relationships',
      handle: 'profile-relationships',
      displayName: 'Profile Relationships',
    );
    final gateway = FakeAwikiGateway()
      ..myProfile = profile
      ..following = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:following-profile',
          displayName: 'Following Profile',
          relationship: 'following',
        ),
      ]
      ..followers = const <RelationshipSummary>[
        RelationshipSummary(
          did: 'did:test:follower-profile',
          displayName: 'Follower Profile',
          relationship: 'follower',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
        profile: profile,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('compact-nav-profile')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('profile-following-stat-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-followers-stat-button')),
      findsOneWidget,
    );

    for (final entry
        in <
          ({
            Key buttonKey,
            FriendsRelationshipListType type,
            String title,
            String contact,
          })
        >[
          (
            buttonKey: const Key('profile-following-stat-button'),
            type: FriendsRelationshipListType.following,
            title: '我关注的',
            contact: 'Following Profile',
          ),
          (
            buttonKey: const Key('profile-followers-stat-button'),
            type: FriendsRelationshipListType.followers,
            title: '关注我的',
            contact: 'Follower Profile',
          ),
        ]) {
      for (var round = 0; round < 3; round += 1) {
        await tester.tap(find.byKey(entry.buttonKey));
        // Exercise the first page reconciliation frame, before a nested
        // NavigationNotification-driven handler could rebuild.
        await tester.pump();

        expect(
          find.byType(RelationshipListPage),
          findsOneWidget,
          reason: '${entry.type} round $round',
        );
        expect(
          tester
              .widget<RelationshipListPage>(find.byType(RelationshipListPage))
              .type,
          entry.type,
          reason: 'round $round',
        );
        final backScope = tester.widget<CompactNestedNavigatorBackScope>(
          find.byKey(const Key('profile-compact-back-scope')),
        );
        expect(backScope.active, isTrue, reason: 'round $round');
        expect(backScope.hasNestedRoute, isTrue, reason: 'round $round');
        expect(
          find.byKey(const Key('compact-bottom-navigation')),
          findsNothing,
        );

        if (round == 0) {
          await tester.pumpAndSettle();
          final title = tester.widget<Text>(find.text(entry.title));
          expect(title.style?.fontSize, 16);
          expect(title.style?.fontWeight, FontWeight.w400);
          expect(find.text(entry.contact), findsOneWidget);
        }

        if (round == 2) {
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('relationship-list-back-button')),
          );
        } else {
          await _simulateSystemBack(tester);
        }
        await tester.pumpAndSettle();

        expect(find.byType(RelationshipListPage), findsNothing);
        expect(find.byKey(entry.buttonKey), findsOneWidget);
        expect(
          find.byKey(const Key('compact-bottom-navigation')),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('窄屏长 handle 与展开 DID 不溢出并保留完整值', (tester) async {
    const profile = UserProfile(
      did:
          'did:wba:very-long-tenant.example:user:alice:e1_abcdefghijklmnopqrstuvwxyz0123456789',
      nickName: 'Alice With A Secondary Display Name',
      bio: '',
      tags: <String>[],
      handle: 'alice',
      fullHandle: 'alice.very-long-tenant.example',
      profileMarkdown: '',
    );
    final gateway = FakeAwikiGateway()..myProfile = profile;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ProfilePage(homepageMarkdownLoader: (_) async => null),
        gateway: gateway,
        profile: profile,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('profile-did-value')), findsNothing);

    await tester.tap(find.byKey(const Key('profile-did-row')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final didText = tester.widget<Text>(
      find.byKey(const Key('profile-did-value')),
    );
    expect(didText.data, profile.did);
    expect(didText.data, endsWith('yz0123456789'));
    expect(didText.maxLines, 4);
    expect(didText.softWrap, isTrue);
    expect(didText.overflow, TextOverflow.ellipsis);
    final didParagraph = tester.renderObject<RenderParagraph>(
      find.byKey(const Key('profile-did-value')),
    );
    expect(didParagraph.didExceedMaxLines, isFalse);
    final displayNameText = tester.widget<Text>(
      find.byKey(const Key('profile-display-name')),
    );
    expect(displayNameText.maxLines, 1);
    expect(displayNameText.data, 'Alice With A Secondary Display Name');
    expect(find.byKey(const Key('profile-handle-value')), findsNothing);
    expect(find.byKey(const Key('profile-copy-did-button')), findsOneWidget);
  });
}
