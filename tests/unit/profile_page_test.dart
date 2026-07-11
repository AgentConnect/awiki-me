import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/presentation/profile/profile_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
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
    expect(find.text('暂无 profile'), findsOneWidget);
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

  testWidgets('个人资料页以完整 handle 为主并只保留一个 DID 复制入口', (tester) async {
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

  testWidgets('窄屏长 handle 与 DID 不溢出并保留尾指纹', (tester) async {
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
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(360, 720));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: ProfilePage(homepageMarkdownLoader: (_) async => null),
        gateway: gateway,
        profile: profile,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final didText = tester.widget<Text>(
      find.byKey(const Key('profile-did-value')),
    );
    expect(didText.data, contains('…'));
    expect(didText.data, endsWith('yz0123456789'));
    expect(didText.maxLines, 2);
    expect(find.byKey(const Key('profile-copy-did-button')), findsOneWidget);
  });
}
