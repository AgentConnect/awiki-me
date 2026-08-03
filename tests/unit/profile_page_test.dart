import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/friends/friends_page.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_page.dart';
import 'package:awiki_me/src/presentation/profile/profile_workspace_page.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/compact_nested_navigator_back_scope.dart';
import 'package:awiki_me/src/presentation/shared/identity_profile_surface.dart';
import 'package:awiki_me/src/presentation/shared/responsive_layout.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart'
    show JSONMessageCodec, MethodCall, MethodChannel, SystemChannels;
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
    expect(compactTitle.style?.fontWeight, FontWeight.w600);
    expect(compactTitle.style?.height, 1.25);
    expect(
      tester.getRect(find.byKey(const Key('profile-compact-header'))),
      const Rect.fromLTWH(0, 0, 390, 64),
    );
    expect(find.byKey(const Key('awiki-me-brand-mark')), findsNothing);
  });

  testWidgets('窄屏资料入口默认折叠并保持 DID 主页身份卡单开', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = UserProfile(
      did: 'did:wba:agent-connect.cn:user:newhandle2:e1_profile_key',
      nickName: 'newhandle2.agent-connect.cn',
      bio: '',
      tags: <String>['identity'],
      handle: 'newhandle2',
      fullHandle: 'newhandle2.agent-connect.cn',
      profileMarkdown: '# Identity document\n\nIndependent profile body',
    );
    String? clipboardText;
    String? launchedUrl;
    const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');
    tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final data = call.arguments as Map<Object?, Object?>;
          clipboardText = data['text'] as String?;
        }
        return null;
      })
      ..setMockMethodCallHandler(launcherChannel, (MethodCall call) async {
        if (call.method == 'launch') {
          final data = call.arguments as Map<Object?, Object?>;
          launchedUrl = data['url'] as String?;
          return true;
        }
        return null;
      });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(SystemChannels.platform, null)
        ..setMockMethodCallHandler(launcherChannel, null);
    });

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfilePage(),
        gateway: FakeAwikiGateway()..myProfile = profile,
        profile: profile,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    final headerRect = tester.getRect(
      find.byKey(const Key('profile-compact-header')),
    );
    final avatarRect = tester.getRect(find.byKey(const Key('profile-avatar')));
    final statsRect = tester.getRect(
      find.byKey(const Key('profile-statistics')),
    );
    final navigationGroup = find.byKey(const Key('profile-navigation-group'));
    final navigationRect = tester.getRect(navigationGroup);
    final didRow = find.byKey(const Key('profile-did-row'));
    final homepageRow = find.byKey(const Key('profile-homepage-row'));
    final identityRect = tester.getRect(
      find.byKey(const Key('profile-identity-document-row')),
    );
    final settingsRect = tester.getRect(
      find.byKey(const Key('profile-settings-row')),
    );

    expect(headerRect, const Rect.fromLTWH(0, 0, 390, 64));
    expect(avatarRect.left, closeTo(143, 0.1));
    expect(avatarRect.top, closeTo(104, 0.1));
    expect(avatarRect.size, const Size.square(104));
    final handle = tester.widget<Text>(
      find.byKey(const Key('profile-handle-value')),
    );
    expect(handle.data, 'newhandle2.agent-connect.cn');
    expect(handle.maxLines, 1);
    expect(handle.softWrap, isFalse);
    expect(
      tester.getSize(find.byKey(const Key('profile-edit-button'))),
      const Size.square(44),
    );
    expect(statsRect, const Rect.fromLTWH(16, 292, 358, 30));
    final statisticsDivider = tester.getRect(
      find.byKey(const Key('profile-statistics-divider')),
    );
    expect(statisticsDivider, const Rect.fromLTWH(194.5, 292, 1, 30));
    expect(find.byKey(const Key('profile-metadata-card')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('profile-navigation-top-divider'))),
      const Rect.fromLTWH(0, 354, 390, 1),
    );
    expect(navigationRect, const Rect.fromLTWH(0, 354, 390, 212));
    expect(tester.getRect(didRow), const Rect.fromLTWH(0, 355, 390, 52));
    expect(
      tester.getRect(find.byKey(const Key('profile-did-icon-target'))),
      const Rect.fromLTWH(16, 359, 44, 44),
    );
    expect(
      tester.getRect(find.byKey(const Key('profile-did-divider'))),
      const Rect.fromLTWH(0, 407, 390, 1),
    );
    expect(tester.getRect(homepageRow), const Rect.fromLTWH(0, 408, 390, 52));
    expect(
      tester.getRect(find.byKey(const Key('profile-homepage-divider'))),
      const Rect.fromLTWH(0, 460, 390, 1),
    );
    expect(identityRect, const Rect.fromLTWH(0, 461, 390, 52));
    expect(
      tester.getRect(find.byKey(const Key('profile-navigation-divider'))),
      const Rect.fromLTWH(0, 513, 390, 1),
    );
    expect(settingsRect, const Rect.fromLTWH(0, 514, 390, 52));
    expect(
      tester.getSize(find.byKey(const Key('profile-did-icon-target'))),
      const Size.square(44),
    );
    expect(
      tester.getSize(find.byKey(const Key('profile-homepage-icon-target'))),
      const Size.square(44),
    );
    expect(
      tester.getRect(
        find.byKey(const Key('profile-identity-document-icon-target')),
      ),
      const Rect.fromLTWH(16, 465, 44, 44),
    );
    expect(
      tester.getRect(
        find.byKey(const Key('profile-identity-document-icon-box')),
      ),
      const Rect.fromLTWH(27, 476, 22, 22),
    );
    for (final title in <String>['DID', '主页', '身份卡', '设置']) {
      final text = tester.widget<Text>(find.text(title));
      expect(text.style?.fontSize, 16);
      expect(text.style?.fontWeight, FontWeight.w600);
      expect(text.style?.height, 1.25);
    }
    expect(find.byKey(const Key('profile-did-value')), findsNothing);
    expect(find.byKey(const Key('profile-homepage-value')), findsNothing);
    expect(find.byKey(const Key('profile-identity-document')), findsNothing);
    expect(
      tester
          .widget<Semantics>(
            find.descendant(of: didRow, matching: find.byType(Semantics)).first,
          )
          .properties
          .expanded,
      isFalse,
    );

    await tester.tap(didRow);
    await tester.pump();

    expect(
      tester.getRect(navigationGroup),
      const Rect.fromLTWH(0, 354, 390, 296),
    );
    expect(
      tester.getRect(find.byKey(const Key('profile-did-details'))),
      const Rect.fromLTWH(0, 407, 390, 84),
    );
    final didValue = tester.widget<Text>(
      find.byKey(const Key('profile-did-value')),
    );
    expect(didValue.data, profile.did);
    expect(didValue.maxLines, 4);
    expect(didValue.overflow, TextOverflow.ellipsis);
    expect(
      tester.getSize(find.byKey(const Key('profile-copy-did-button'))),
      const Size.square(44),
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('profile-did-arrow'))).icon,
      CupertinoIcons.chevron_down,
    );
    expect(
      tester
          .widget<Semantics>(
            find.descendant(of: didRow, matching: find.byType(Semantics)).first,
          )
          .properties
          .expanded,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('profile-copy-did-button')));
    await tester.pump();
    expect(clipboardText, profile.did);
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(homepageRow);
    await tester.pump();

    expect(
      tester.getRect(navigationGroup),
      const Rect.fromLTWH(0, 354, 390, 276),
    );
    expect(find.byKey(const Key('profile-did-details')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('profile-homepage-details'))),
      const Rect.fromLTWH(0, 460, 390, 64),
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-homepage-value'))).data,
      'https://newhandle2.agent-connect.cn',
    );
    expect(
      tester.getSize(find.byKey(const Key('profile-homepage-action-target'))),
      const Size.square(44),
    );
    await tester.tap(find.byKey(const Key('profile-homepage-action-target')));
    await tester.pump();
    expect(launchedUrl, 'https://newhandle2.agent-connect.cn');

    await tester.tap(find.byKey(const Key('profile-identity-document-row')));
    await tester.pump();

    expect(find.byKey(const Key('profile-homepage-details')), findsNothing);
    expect(
      tester.getRect(navigationGroup),
      const Rect.fromLTWH(0, 354, 390, 212),
    );
    expect(find.byKey(const Key('profile-identity-document')), findsOneWidget);
    expect(find.byType(IdentityDocumentContent), findsOneWidget);
    expect(find.text('Independent profile body'), findsOneWidget);
    expect(
      tester
          .widget<Icon>(
            find.byKey(const Key('profile-identity-document-arrow')),
          )
          .icon,
      CupertinoIcons.chevron_down,
    );

    await tester.tap(find.byKey(const Key('profile-identity-document-row')));
    await tester.pump();

    expect(find.byKey(const Key('profile-identity-document')), findsNothing);
    expect(
      tester.getRect(navigationGroup),
      const Rect.fromLTWH(0, 354, 390, 212),
    );
  });

  testWidgets('窄屏仅含身份元数据时展开显示空态并可再次收起', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = UserProfile(
      did: 'did:wba:agent-connect.cn:user:empty:e1_profile_key',
      nickName: 'Empty Alice',
      bio: '',
      tags: <String>[],
      handle: 'empty',
      fullHandle: 'empty.agent-connect.cn',
      profileMarkdown: '''
我的短号(handle)：empty.agent-connect.cn
DID: did:wba:agent-connect.cn:user:empty:e1_profile_key
''',
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

    final group = find.byKey(const Key('profile-navigation-group'));
    final identity = find.byKey(const Key('profile-identity-document-row'));
    final settings = find.byKey(const Key('profile-settings-row'));
    final arrow = find.byKey(const Key('profile-identity-document-arrow'));

    expect(tester.getRect(group), const Rect.fromLTWH(0, 354, 390, 212));
    expect(tester.widget<Icon>(arrow).icon, CupertinoIcons.chevron_right);
    expect(find.byKey(const Key('profile-identity-document')), findsNothing);

    await tester.tap(find.byKey(const Key('profile-did-row')));
    await tester.pump();
    expect(find.byKey(const Key('profile-did-details')), findsOneWidget);

    await tester.tap(identity);
    await tester.pump();

    final emptyState = find.byKey(const Key('profile-identity-empty-state'));
    expect(find.byKey(const Key('profile-did-details')), findsNothing);
    expect(tester.getRect(group), const Rect.fromLTWH(0, 354, 390, 240));
    expect(tester.getRect(emptyState), const Rect.fromLTWH(0, 513, 390, 28));
    final emptyText = tester.widget<Text>(
      find.byKey(const Key('profile-identity-empty-state-text')),
    );
    expect(emptyText.data, '暂无资料');
    expect(emptyText.style?.fontSize, 13);
    expect(emptyText.style?.fontWeight, FontWeight.w400);
    expect(emptyText.style?.height, closeTo(18 / 13, 0.001));
    expect(emptyText.style?.color, AwikiMeColors.secondaryText);
    expect(find.byKey(const Key('profile-did-value')), findsNothing);
    expect(find.byKey(const Key('profile-homepage-value')), findsNothing);
    expect(tester.widget<Icon>(arrow).icon, CupertinoIcons.chevron_down);
    expect(tester.getRect(settings), const Rect.fromLTWH(0, 542, 390, 52));
    expect(find.byKey(const Key('profile-identity-document')), findsNothing);

    await tester.tap(identity);
    await tester.pump();

    expect(tester.getRect(group), const Rect.fromLTWH(0, 354, 390, 212));
    expect(tester.widget<Icon>(arrow).icon, CupertinoIcons.chevron_right);
    expect(tester.getRect(settings), const Rect.fromLTWH(0, 514, 390, 52));
  });

  testWidgets('窄屏主页缺失时省略主页手风琴并保持几何', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const profile = UserProfile(
      did: 'did:test:no-homepage',
      nickName: 'No Homepage',
      bio: '',
      tags: <String>[],
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

    final group = find.byKey(const Key('profile-navigation-group'));
    expect(find.byKey(const Key('profile-homepage-row')), findsNothing);
    expect(tester.getRect(group), const Rect.fromLTWH(0, 354, 390, 159));
    expect(
      tester.getRect(find.byKey(const Key('profile-did-row'))),
      const Rect.fromLTWH(0, 355, 390, 52),
    );
    expect(
      tester.getRect(find.byKey(const Key('profile-identity-document-row'))),
      const Rect.fromLTWH(0, 408, 390, 52),
    );
    expect(
      tester.getRect(find.byKey(const Key('profile-settings-row'))),
      const Rect.fromLTWH(0, 461, 390, 52),
    );

    await tester.tap(find.byKey(const Key('profile-did-row')));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getRect(group), const Rect.fromLTWH(0, 354, 390, 243));
    expect(
      tester.getRect(find.byKey(const Key('profile-did-details'))),
      const Rect.fromLTWH(0, 407, 390, 84),
    );
  });

  testWidgets('桌面我的页面使用 272px 摘要栏和完整资料详情', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    const profile = UserProfile(
      did: 'did:test:workspace-profile',
      nickName: 'Alice',
      bio: 'Workspace bio',
      tags: <String>['awiki'],
      handle: 'alice',
      profileMarkdown: '# Alice\n\nWorkspace profile body',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfileWorkspacePage(),
        gateway: FakeAwikiGateway()..myProfile = profile,
        profile: profile,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    final pane = tester.widget<AwikiPaneLayout>(find.byType(AwikiPaneLayout));
    expect(pane.listPaneWidth, 272);
    expect(find.byKey(const Key('profile-sidebar-summary')), findsOneWidget);
    expect(find.text('Workspace profile body'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.pencil), findsOneWidget);
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

    await _simulateSystemBack(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-edit-page')), findsNothing);
    expect(find.byKey(const Key('profile-edit-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-edit-button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'Alice New');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'New bio');
    await tester.enterText(
      find.byType(CupertinoTextField).at(2),
      'ai, agent, flutter, mobile, design, ignored',
    );

    await tester.tap(find.byKey(const Key('profile-edit-save-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-edit-page')), findsNothing);
    final patch = gateway.lastProfilePatch;
    expect(patch, isNotNull);
    expect(patch!.nickName, 'Alice New');
    expect(patch.bio, 'New bio');
    expect(patch.tags, <String>['ai', 'agent', 'flutter', 'mobile', 'design']);
  });

  testWidgets('个人资料页优先渲染拉取到的 markdown 和 tags', (tester) async {
    const profile = UserProfile(
      did: 'did:wba:anpclaw.com:bob:e1_456',
      nickName: 'Bob',
      bio: 'Bio',
      tags: <String>['ai', 'agent'],
      profileMarkdown: '# Local title',
      handle: 'bob',
    );
    final gateway = FakeAwikiGateway()..myProfile = profile;
    String? requestedHomepageUrl;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfilePage(),
        gateway: gateway,
        profile: profile,
        homepageMarkdownLoader: (url) async {
          requestedHomepageUrl = url;
          return '# Remote title\n\nRemote body';
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(requestedHomepageUrl, 'https://bob.anpclaw.com');
    expect(find.text('Remote title'), findsNothing);
    expect(find.text('Remote body'), findsOneWidget);
    expect(find.text('ai'), findsOneWidget);
    expect(find.text('agent'), findsOneWidget);
  });

  testWidgets('个人资料页在主页 markdown 成功返回空正文时显示空状态', (tester) async {
    const profile = UserProfile(
      did: 'did:test:visible-profile',
      nickName: 'Alice',
      bio: 'Bio',
      tags: <String>[],
      profileMarkdown: '# Alice\n\n# 如何与我通信\n\nKeep this copy',
      handle: 'alice',
    );
    final gateway = FakeAwikiGateway()..myProfile = profile;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfilePage(),
        gateway: gateway,
        profile: profile,
        homepageMarkdownLoader: (_) async => '# Alice\n\n',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Keep this copy'), findsNothing);
    expect(find.text('暂无资料'), findsOneWidget);
  });

  testWidgets('个人资料页不会用主页 HTML 覆盖已有正文', (tester) async {
    const profile = UserProfile(
      did: 'did:test:html-profile',
      nickName: 'Alice',
      bio: 'Bio',
      tags: <String>[],
      profileMarkdown: '# Alice\n\n# 如何与我通信\n\nKeep this copy',
      handle: 'alice',
    );
    final gateway = FakeAwikiGateway()..myProfile = profile;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfilePage(),
        gateway: gateway,
        profile: profile,
        homepageMarkdownLoader: (_) async =>
            '<!doctype html><html><body></body></html>',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Keep this copy'), findsOneWidget);
  });

  testWidgets('个人资料页主页加载失败时保留本地 profile 正文', (tester) async {
    const profile = UserProfile(
      did: 'did:test:homepage-error',
      nickName: 'Alice',
      bio: 'Bio',
      tags: <String>['local'],
      profileMarkdown: '# Alice\n\nLocal fallback body',
      handle: 'alice',
    );
    final gateway = FakeAwikiGateway()..myProfile = profile;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const ProfilePage(),
        gateway: gateway,
        profile: profile,
        homepageMarkdownLoader: (_) async => throw StateError('homepage down'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Local fallback body'), findsOneWidget);
    expect(find.text('local'), findsOneWidget);
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
          expect(title.style?.fontWeight, FontWeight.w600);
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

  testWidgets('个人资料页按显示名称、完整 handle、DID 排列身份信息', (tester) async {
    const profile = UserProfile(
      did: 'did:wba:anpclaw.com:user:elena:e1_full_identity_key',
      nickName: 'Elena',
      bio: 'Bio',
      tags: <String>['copyable'],
      handle: 'elena',
      fullHandle: 'elena.anpclaw.com',
      profileMarkdown: '# Elena\n\nCopyable body',
    );
    final gateway = FakeAwikiGateway()..myProfile = profile;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ProfilePage(homepageMarkdownLoader: (_) async => null),
        gateway: gateway,
        profile: profile,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(IdentityProfileHeader), findsOneWidget);
    expect(find.byType(IdentityProfileBadge), findsNothing);
    expect(find.byType(IdentityDocumentContent), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-handle-value'))).data,
      '@elena.anpclaw.com',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-display-name'))).data,
      'Elena',
    );
    final didText = tester.widget<Text>(
      find.byKey(const Key('profile-did-value')),
    );
    expect(didText.data, startsWith('did:wba:anpclaw.com:user:elena:e1_'));
    expect(find.byKey(const Key('profile-copy-did-button')), findsOneWidget);
    expect(find.text('Copyable body'), findsOneWidget);
    expect(find.text('copyable'), findsOneWidget);
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
    final handleText = tester.widget<Text>(
      find.byKey(const Key('profile-handle-value')),
    );
    expect(handleText.maxLines, 1);
    expect(handleText.softWrap, isFalse);
    expect(handleText.data, isNot(contains('\n')));
    expect(find.byKey(const Key('profile-copy-did-button')), findsOneWidget);
  });
}
