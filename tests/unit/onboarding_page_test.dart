import 'dart:async';

import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/repositories/awiki_account_gateway.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('macOS 桌面登录页使用参考图左右分栏布局', (tester) async {
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:123',
          credentialName: 'default',
          displayName: 'Alice',
          handle: 'alice',
          jwtToken: 'token-123',
        ),
      ];
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

    expect(find.text('AWiki'), findsOneWidget);
    expect(find.text('身份凭证'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsOneWidget);
    expect(find.text('安全可靠'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('无本地凭证时默认进入登录或注册 tab', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('发送验证码'), findsNothing);
    expect(find.text('验证码'), findsNothing);
    expect(find.text('导入身份凭证'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    expect(container.read(onboardingProvider).entryMode, 'register');
  });

  testWidgets('无本地凭证时仍可手动切换到切换身份 tab', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('切换身份'));
    await tester.pumpAndSettle();

    expect(find.text('导入身份凭证'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    expect(container.read(onboardingProvider).entryMode, 'login');
  });

  testWidgets('有本地凭证时默认进入切换身份 tab', (tester) async {
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:123',
          credentialName: 'default',
          displayName: 'Alice',
          handle: 'alice',
          jwtToken: 'token-123',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    expect(container.read(onboardingProvider).entryMode, 'login');
  });

  testWidgets('退出登录后等待本地凭证刷新再默认进入切换身份 tab', (tester) async {
    final logoutCompleter = Completer<void>();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    final gateway = FakeAwikiGateway()..logoutCompleter = logoutCompleter;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();
    gateway.localCredentials = const <SessionIdentity>[session];

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final logoutFuture = container.read(appRuntimeProvider.notifier).logout();
    await tester.pump();

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(container.read(onboardingProvider).entryMode, 'register');

    logoutCompleter.complete();
    await logoutFuture;
    await tester.pumpAndSettle();

    expect(gateway.logoutCalls, 1);
    expect(container.read(onboardingProvider).entryMode, 'login');
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsOneWidget);
  });

  testWidgets('退出并删除当前凭证后等待本地凭证刷新再默认进入登录或注册 tab', (tester) async {
    final deleteCompleter = Completer<void>();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[session]
      ..deleteLocalCredentialCompleter = deleteCompleter;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final deleteFuture = container
        .read(appRuntimeProvider.notifier)
        .deleteCurrentCredential();
    await tester.pump();
    await tester.pump();

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(container.read(onboardingProvider).entryMode, 'register');

    deleteCompleter.complete();
    await deleteFuture;
    await tester.pumpAndSettle();

    expect(gateway.deleteLocalCredentialCalls, 1);
    expect(container.read(onboardingProvider).entryMode, 'register');
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('发送验证码'), findsNothing);
    expect(find.text('验证码'), findsNothing);
    expect(find.text('导入身份凭证'), findsNothing);
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

    await tester.tap(find.text('登录或注册'));
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

  testWidgets('入口 tab 按登录或注册、切换身份的顺序展示', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    final registerRect = tester.getRect(find.text('登录或注册'));
    final switchRect = tester.getRect(find.text('切换身份'));

    expect(registerRect.left, lessThan(switchRect.left));
  });

  testWidgets('登录和切换身份页面不再展示底部快捷跳转', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    expect(find.textContaining('还没有账号'), findsNothing);
    expect(find.textContaining('已有账号'), findsNothing);
    expect(find.text('去登录或注册'), findsNothing);
    expect(find.text('去登录'), findsNothing);

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();

    expect(find.textContaining('还没有账号'), findsNothing);
    expect(find.textContaining('已有账号'), findsNothing);
    expect(find.text('去登录或注册'), findsNothing);
    expect(find.text('去登录'), findsNothing);
  });

  testWidgets('切换身份 tab 展示导入身份凭证并提示暂未实现', (tester) async {
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:123',
          credentialName: 'default',
          displayName: 'Alice',
          handle: 'alice',
          jwtToken: 'token-123',
        ),
      ];

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(find.text('导入身份凭证'), findsOneWidget);

    await tester.tap(find.text('导入身份凭证'));
    await tester.pump();

    expect(gateway.importCalls, 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.danger, isFalse);
    expect(feedback?.message.id, 'featureNotImplemented');
  });

  testWidgets('切换身份 tab 点击已保存凭证卡片空白区域也能登录', (tester) async {
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

  testWidgets('macOS 窄窗口下入口 tab 保持单行并切到紧凑卡片布局', (tester) async {
    final gateway = FakeAwikiGateway();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(820, 780));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('AWiki'), findsNothing);

    final registerRect = tester.getRect(find.text('登录或注册'));
    final switchRect = tester.getRect(find.text('切换身份'));
    final tabsRect = tester.getRect(
      find.byKey(const Key('onboarding-mac-entry-tabs')),
    );

    expect(registerRect.height, lessThan(24));
    expect(switchRect.height, lessThan(24));
    expect(registerRect.left, greaterThanOrEqualTo(tabsRect.left));
    expect(switchRect.right, lessThanOrEqualTo(tabsRect.right));

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('登录或注册表单使用紧凑 tab 和右对齐动作按钮', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    final listRect = tester.getRect(find.byType(ListView).first);
    final entryTabsRect = tester.getRect(
      find.byKey(const Key('onboarding-entry-tabs')),
    );
    final authTabsRect = tester.getRect(
      find.byKey(const Key('onboarding-auth-mode-tabs')),
    );
    final nextRect = tester.getRect(
      find.ancestor(
        of: find.text('下一步'),
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.width == double.infinity,
        ),
      ),
    );

    expect(entryTabsRect.width, lessThan(listRect.width));
    expect(authTabsRect.width, lessThan(listRect.width));
    expect(nextRect.width, lessThan(listRect.width * 0.5));
    expect(nextRect.right, moreOrLessEquals(listRect.right, epsilon: 1));
  });

  testWidgets('邮箱注册发送激活邮件后进入重新发送倒计时', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).first, 'a@b.com');
    await tester.tap(find.text('发送激活邮件'));
    await tester.pump();

    expect(gateway.sendEmailVerificationCalls, 1);
    expect(find.textContaining('重新发送（'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.message.id, 'activationEmailSent');
    expect(feedback?.danger, isFalse);
  });

  testWidgets('手机号第一步不显示验证码控件且下一步不请求验证码', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(CupertinoTextField).first,
      '13800138000',
    );
    expect(find.text('发送验证码'), findsNothing);
    expect(find.text('验证码'), findsNothing);

    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    final state = container.read(onboardingProvider);
    expect(state.registerStep, 2);
    expect(gateway.sendOtpCalls, 0);
    expect(find.textContaining('重新发送（'), findsNothing);
  });

  testWidgets('邮箱验证成功后检查按钮变成下一步', (tester) async {
    final gateway = FakeAwikiGateway()..emailVerificationResult = true;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
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

  testWidgets('进入 handle 步骤时用户名输入框没有默认值', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      '13800138000',
    );
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();

    final handleField = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField).first,
    );
    expect(handleField.controller?.text, isEmpty);
  });

  testWidgets('手机号提交时未注册 handle 走注册路径', (tester) async {
    final gateway = FakeAwikiGateway()
      ..handleRegistrationStatus = HandleRegistrationStatus.notRegistered;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      '13800138000',
    );
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.lookupHandleRegistrationCalls, 1);
    expect(gateway.registerHandleCalls, 1);
    expect(gateway.recoverHandleCalls, 0);
    expect(gateway.lastRegisteredPhone, '13800138000');
    expect(gateway.lastRegisteredOtp, '123456');
    expect(gateway.lastRegisteredNickName, 'alice');
    expect(gateway.lastRegisteredProfileMarkdown, '# alice\n\n');
  });

  testWidgets('手机号提交时已注册 handle 走恢复路径', (tester) async {
    final gateway = FakeAwikiGateway()
      ..handleRegistrationStatus = HandleRegistrationStatus.registered;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      '13800138000',
    );
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.lookupHandleRegistrationCalls, 1);
    expect(gateway.recoverHandleCalls, 1);
    expect(gateway.registerHandleCalls, 0);
    expect(gateway.lastRecoveredPhone, '13800138000');
    expect(gateway.lastRecoveredOtp, '123456');
  });

  testWidgets('邮箱提交遇到已注册 handle 时提示用手机号恢复', (tester) async {
    final gateway = FakeAwikiGateway()
      ..emailVerificationResult = true
      ..handleRegistrationStatus = HandleRegistrationStatus.registered;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'a@b.com');
    await tester.tap(find.text('我已激活，检查状态'));
    await tester.pump();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.tap(find.text('完成注册'));
    await tester.pump();

    expect(gateway.lookupHandleRegistrationCalls, 1);
    expect(gateway.registerHandleWithEmailCalls, 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.message.id, 'emailLoginUnsupportedForRegisteredHandle');
    expect(feedback?.danger, isTrue);
  });

  testWidgets('邮箱提交时未注册 handle 默认用 handle 作为昵称', (tester) async {
    final gateway = FakeAwikiGateway()
      ..emailVerificationResult = true
      ..handleRegistrationStatus = HandleRegistrationStatus.notRegistered;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'a@b.com');
    await tester.tap(find.text('我已激活，检查状态'));
    await tester.pump();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.tap(find.text('完成注册'));
    await tester.pumpAndSettle();

    expect(gateway.lookupHandleRegistrationCalls, 1);
    expect(gateway.registerHandleWithEmailCalls, 1);
    expect(gateway.lastEmailRegisteredNickName, 'alice');
    expect(gateway.lastEmailRegisteredProfileMarkdown, '# alice\n\n');
  });
}
