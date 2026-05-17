import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('macOS 桌面登录页使用参考图左右分栏布局', (tester) async {
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1440, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('AWiki'), findsOneWidget);
    expect(find.text('身份凭证'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsOneWidget);
    expect(find.text('安全可靠'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 桌面注册页保留邮箱注册动作', (tester) async {
    final gateway = FakeAwikiGateway();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1440, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).first, 'a@b.com');
    await tester.tap(find.text('发送激活邮件'));
    await tester.pump();

    expect(gateway.sendEmailVerificationCalls, 1);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('登录 tab 展示导入身份凭证并触发导入动作', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    expect(find.text('导入身份凭证'), findsOneWidget);

    await tester.tap(find.text('导入身份凭证'));
    await tester.pump();

    expect(gateway.importCalls, 1);
  });

  testWidgets('登录 tab 点击已保存凭证卡片空白区域也能登录', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    gateway.localCredentials = const <SessionIdentity>[session];
    gateway.loginResult = session;
    gateway.myProfile = const UserProfile(
      did: 'did:test:123',
      nickName: 'Alice',
      bio: '',
      profileMarkdown: '',
      tags: <String>[],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    final tileRect = tester.getRect(find.text('Alice').first);
    await tester.tapAt(Offset(tileRect.left + 20, tileRect.center.dy));
    await tester.pumpAndSettle();

    expect(gateway.loginCalls, 1);
    expect(gateway.lastLoginCredentialName, 'default');
  });

  testWidgets('桌面宽度下登录页使用居中窄列布局', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    final listRect = tester.getRect(find.byType(ListView).first);
    expect(listRect.width, lessThanOrEqualTo(420));
  });

  testWidgets('邮箱注册发送激活邮件后进入重新发送倒计时', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).first, 'a@b.com');
    await tester.tap(find.text('发送激活邮件'));
    await tester.pump();

    expect(gateway.sendEmailVerificationCalls, 1);
    expect(find.textContaining('重新发送（'), findsOneWidget);
  });

  testWidgets('邮箱验证成功后检查按钮变成下一步', (tester) async {
    final gateway = FakeAwikiGateway()..emailVerificationResult = true;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).first, 'a@b.com');
    await tester.tap(find.text('我已激活，检查状态'));
    await tester.pump();

    expect(gateway.checkEmailVerifiedCalls, 1);
    expect(find.text('下一步'), findsOneWidget);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    expect(container.read(onboardingProvider).registerStep, 2);
  });
}
