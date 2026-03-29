import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/profile/profile_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('个人资料页点击编辑后可提交昵称简介和标签', (tester) async {
    final controller = RecordingAppController(
      gateway: FakeAwikiGateway(),
      realtimeGateway: FakeRealtimeGateway(),
      notificationFacade: FakeNotificationFacade(),
      e2eeFacade: FakeE2eeFacade(),
    );
    controller.profile = const UserProfile(
      did: 'did:test:123',
      nickName: 'Alice',
      bio: 'Old bio',
      tags: <String>['old', 'tag'],
      profileMarkdown: '# Alice',
      handle: 'alice',
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: ProfilePage(
          controller: controller,
          onOpenSettings: () async {},
          onOpenQuickActions: () async {},
          homepageMarkdownLoader: (_) async => null,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();

    expect(find.text('编辑个人资料'), findsOneWidget);

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'Alice New');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'New bio');
    await tester.enterText(find.byType(CupertinoTextField).at(2), 'ai, agent');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(controller.updateProfileCalls, 1);
    final patch = controller.lastProfilePatch;
    expect(patch, isNotNull);
    expect(patch!.nickName, 'Alice New');
    expect(patch.bio, 'New bio');
    expect(patch.tags, <String>['ai', 'agent']);
  });

  testWidgets('个人资料页优先渲染拉取到的 markdown 和 tags', (tester) async {
    final controller = RecordingAppController(
      gateway: FakeAwikiGateway(),
      realtimeGateway: FakeRealtimeGateway(),
      notificationFacade: FakeNotificationFacade(),
      e2eeFacade: FakeE2eeFacade(),
    );
    controller.profile = const UserProfile(
      did: 'did:test:456',
      nickName: 'Bob',
      bio: 'Bio',
      tags: <String>['ai', 'agent'],
      profileMarkdown: '# Local title',
      handle: 'bob',
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: ProfilePage(
          controller: controller,
          onOpenSettings: () async {},
          onOpenQuickActions: () async {},
          homepageMarkdownLoader: (_) async => '# Remote title\n\nRemote body',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Remote title'), findsOneWidget);
    expect(find.text('Remote body'), findsOneWidget);
    expect(find.text('ai'), findsOneWidget);
    expect(find.text('agent'), findsOneWidget);
  });
}
