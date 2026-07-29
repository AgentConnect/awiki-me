import 'dart:async';

import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/app/app_locale.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/onboarding_server_info.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/legacy_identity_upgrade_port.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_join_page.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_feedback.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/shared/tenant_management_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void _setTestViewSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() => _resetTestViewSize(tester));
}

void _resetTestViewSize(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  testWidgets(
    'Legacy upgrade blocks login, shows loading, and retries the same identity id',
    (tester) async {
      const localIdentity = SessionIdentity(
        did: 'did:wba:awiki.ai:alice:e1_legacy',
        credentialName: 'legacy-alias',
        displayName: 'Alice',
        handle: 'alice.awiki.ai',
      );
      final gateway = FakeAwikiGateway()
        ..localCredentials = const <SessionIdentity>[localIdentity]
        ..loginResult = localIdentity;
      final firstUpgrade = Completer<LegacyIdentityUpgradeStatus>();
      final onboarding = _LegacyUpgradeOnboardingService(firstUpgrade);

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const OnboardingPage(),
          gateway: gateway,
          providerOverrides: <Override>[
            onboardingServiceProvider.overrideWithValue(onboarding),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alice'));
      await tester.pump();

      expect(onboarding.statusSelectors, <String>['legacy-alias']);
      expect(onboarding.upgradeSelectors, <String>['legacy-alias']);
      expect(
        find.byKey(const Key('legacy-upgrade-loading-mask')),
        findsOneWidget,
      );
      expect(gateway.loginCalls, 0);

      await tester.pump(const Duration(seconds: 21));
      expect(
        find.byKey(const Key('legacy-upgrade-loading-mask')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('legacy-upgrade-retry-message')),
        findsNothing,
      );

      firstUpgrade.complete(
        const LegacyIdentityUpgradeStatus.retryRequired(
          identityId: 'identity-123',
          failureCode: 'service_error',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('legacy-upgrade-retry-message')),
        findsOneWidget,
      );
      expect(find.text('旧身份升级失败，请重试。'), findsOneWidget);
      expect(find.text('Diagnostic code: service_error'), findsOneWidget);
      expect(find.textContaining('document'), findsNothing);
      expect(find.textContaining('key'), findsNothing);
      expect(find.textContaining('proof'), findsNothing);
      expect(find.textContaining('token'), findsNothing);
      expect(gateway.loginCalls, 0);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(onboarding.upgradeSelectors, <String>[
        'legacy-alias',
        'identity-123',
      ]);
      expect(gateway.loginCalls, 1);
      expect(gateway.lastLoginCredentialName, 'identity-123');
    },
  );

  testWidgets('macOS 桌面登录页使用新稿左右分栏和单层认证入口', (tester) async {
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
      _resetTestViewSize(tester);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    _setTestViewSize(tester, const Size(1440, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding-expanded-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('onboarding-desktop-dot-pattern')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('onboarding-mac-hero-title')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-mac-auth-card')), findsOneWidget);
    expect(
      find.byKey(const Key('onboarding-mac-auth-method-tabs')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('auth-mode-phone')), findsOneWidget);
    expect(find.byKey(const Key('auth-mode-email')), findsOneWidget);
    expect(
      find.byKey(const Key('onboarding-mac-credential-mode')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('onboarding-local-credential-section')),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('+86'), findsOneWidget);
    expect(find.text('安全可靠'), findsOneWidget);
    expect(find.text('高效协作'), findsOneWidget);
    expect(find.text('权限可控'), findsOneWidget);
    expect(find.text('已验证'), findsNothing);
    expect(find.text('用户协议'), findsNothing);
    expect(find.text('隐私政策'), findsNothing);

    final heroRect = tester.getRect(
      find.byKey(const Key('onboarding-mac-hero-title')),
    );
    final cardRect = tester.getRect(
      find.byKey(const Key('onboarding-mac-auth-card')),
    );
    final languageRect = tester.getRect(
      find.byKey(const Key('onboarding-language-switcher-button')),
    );
    final tenantRect = tester.getRect(find.byTooltip('管理租户'));
    expect(heroRect.right, lessThan(cardRect.left));
    expect(cardRect.width, moreOrLessEquals(540, epsilon: 0.1));
    expect(cardRect.height, lessThan(900 * 0.8));
    expect(languageRect.left, lessThan(tenantRect.left));

    debugDefaultTargetPlatformOverride = null;
    _resetTestViewSize(tester);
  });

  testWidgets('Windows 宽屏进入共享桌面 onboarding 而不是移动端 fallback', (tester) async {
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      _resetTestViewSize(tester);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    _setTestViewSize(tester, const Size(1280, 800));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding-expanded-layout')), findsOneWidget);
    expect(
      find.byKey(const Key('onboarding-desktop-dot-pattern')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('onboarding-mac-hero-title')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-mac-auth-card')), findsOneWidget);
    expect(
      find.byKey(const Key('onboarding-mac-auth-method-tabs')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('auth-mode-phone')), findsOneWidget);
    expect(find.byKey(const Key('auth-mode-email')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    _resetTestViewSize(tester);
  });

  testWidgets('Windows 有本地凭证时在认证表单下方展示并可一键登录', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:windows',
      credentialName: 'windows-default',
      displayName: 'Windows Alice',
      handle: 'windows-alice',
      jwtToken: 'token-windows',
    );
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[session]
      ..loginResult = session
      ..myProfile = const UserProfile(
        did: 'did:test:windows',
        nickName: 'Windows Alice',
        bio: '',
        profileMarkdown: '',
        tags: <String>[],
      );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      _resetTestViewSize(tester);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    _setTestViewSize(tester, const Size(1280, 800));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('onboarding-mac-credential-mode')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('onboarding-local-credential-section')),
      findsOneWidget,
    );
    expect(find.text('Windows Alice'), findsOneWidget);

    await tester.tap(find.text('Windows Alice'));
    await tester.pumpAndSettle();

    expect(gateway.loginCalls, 1);
    expect(gateway.lastLoginCredentialName, 'windows-default');

    debugDefaultTargetPlatformOverride = null;
    _resetTestViewSize(tester);
  });

  testWidgets('macOS 单层认证入口只在邮箱和手机号之间切换', (tester) async {
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      _resetTestViewSize(tester);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    _setTestViewSize(tester, const Size(1120, 820));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    expect(container.read(onboardingProvider).authMode, 'phone');

    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();
    expect(container.read(onboardingProvider).authMode, 'email');
    expect(find.text('发送激活邮件'), findsOneWidget);

    expect(
      find.byKey(const Key('onboarding-mac-credential-mode')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('auth-mode-phone')));
    await tester.pumpAndSettle();
    expect(container.read(onboardingProvider).authMode, 'phone');
    expect(find.text('发送验证码'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
    _resetTestViewSize(tester);
  });

  testWidgets('macOS 手机号发码提交同屏 Handle 作为 OTP 目标', (tester) async {
    final support = _RecordingOnboardingSupportService(FakeAwikiGateway());
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.binding.setSurfaceSize(null);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.binding.setSurfaceSize(const Size(1120, 820));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        providerOverrides: <Override>[
          onboardingSupportServiceProvider.overrideWithValue(support),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(CupertinoTextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), '13800138000');
    await tester.enterText(fields.at(1), 'alice-0714');
    await tester.tap(find.text('发送验证码'));
    await tester.pump();

    expect(support.phone, '13800138000');
    expect(support.handle, 'alice-0714');
    expect(support.domain, 'awiki.ai');
    expect(support.fullHandle, 'alice-0714.awiki.ai');

    debugDefaultTargetPlatformOverride = null;
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('macOS 手机号入口下的本机身份卡可直接登录', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[session]
      ..loginResult = session
      ..myProfile = const UserProfile(
        did: 'did:test:123',
        nickName: 'Alice',
        bio: '',
        profileMarkdown: '',
        tags: <String>[],
      );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      _resetTestViewSize(tester);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    _setTestViewSize(tester, const Size(1440, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('onboarding-local-credential-section')),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsOneWidget);

    final tileRect = tester.getRect(find.text('Alice'));
    await tester.tapAt(Offset(tileRect.left + 20, tileRect.center.dy));
    await tester.pumpAndSettle();

    expect(gateway.loginCalls, 1);
    expect(gateway.lastLoginCredentialName, 'default');

    debugDefaultTargetPlatformOverride = null;
    _resetTestViewSize(tester);
  });

  testWidgets('无本地凭证时直接展示手机号和邮箱认证入口', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsNothing);
    expect(find.byKey(const Key('onboarding-entry-tabs')), findsNothing);
    expect(find.byKey(const Key('auth-mode-phone')), findsOneWidget);
    expect(find.byKey(const Key('auth-mode-email')), findsOneWidget);
  });

  testWidgets('移动端没有身份一级 tab 且认证表单始终展示', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding-entry-tabs')), findsNothing);
    expect(find.text('切换身份'), findsNothing);
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsNothing);
    expect(find.text('重新识别本地凭证'), findsNothing);
  });

  testWidgets('桌面有本地凭证时直接展示在认证表单下方', (tester) async {
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
    expect(find.text('导入身份凭证'), findsNothing);
    expect(find.text('重新识别本地凭证'), findsNothing);
    expect(
      find.byKey(const Key('onboarding-local-credential-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('onboarding-mac-credential-mode')),
      findsNothing,
    );
  });

  testWidgets('Android 和 iOS 有本地凭证时在认证表单下方展示身份', (tester) async {
    final gateway = FakeAwikiGateway()
      ..localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:mobile',
          credentialName: 'mobile-default',
          displayName: 'Mobile Alice',
          handle: 'mobile-alice',
          jwtToken: 'token-mobile',
        ),
      ];
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      _resetTestViewSize(tester);
    });
    _setTestViewSize(tester, const Size(390, 844));

    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
      );
      await tester.pumpAndSettle();

      expect(find.text('发送验证码'), findsOneWidget);
      expect(
        find.byKey(const Key('onboarding-local-credential-section')),
        findsOneWidget,
      );
      expect(find.text('Mobile Alice'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('紧凑登录页使用全屏白底且不再包裹阴影卡片', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('onboarding-compact-auth-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('onboarding-compact-brand')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-compact-logo')), findsOneWidget);
    expect(find.byKey(const Key('onboarding-mac-auth-card')), findsNothing);
    expect(find.text('发送验证码'), findsOneWidget);
    final authSurface = tester.widget<Container>(
      find.byKey(const Key('onboarding-compact-auth-card')),
    );
    expect(authSurface.decoration, isNull);
    expect(authSurface.color, AwikiMePalette.content);

    final logoSize = tester.getSize(
      find.byKey(const Key('onboarding-compact-logo')),
    );
    expect(logoSize.width, lessThanOrEqualTo(40));
    expect(logoSize.height, lessThanOrEqualTo(40));
  });

  testWidgets('移动端认证和已有身份在可容纳时整体居中，超高时可滚动', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));

    for (final size in const <Size>[
      Size(360, 780),
      Size(390, 844),
      Size(393, 852),
    ]) {
      tester.view.physicalSize = size;
      for (final credentials in <List<SessionIdentity>>[
        const <SessionIdentity>[],
        const <SessionIdentity>[
          SessionIdentity(
            did: 'did:test:centered-mobile',
            credentialName: 'centered-mobile',
            displayName: 'Centered Mobile Identity',
            handle: 'centered-mobile',
            jwtToken: 'token-centered-mobile',
          ),
        ],
      ]) {
        final gateway = FakeAwikiGateway()..localCredentials = credentials;
        await tester.pumpWidget(
          buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
        );
        await tester.pumpAndSettle();

        final scrollRect = tester.getRect(
          find.byKey(const Key('onboarding-compact-scroll-view')),
        );
        final contentRect = tester.getRect(
          find.byKey(const Key('onboarding-compact-auth-card')),
        );
        if (contentRect.height <= scrollRect.height) {
          expect(
            contentRect.center.dy,
            moreOrLessEquals(scrollRect.center.dy, epsilon: 3),
          );
          expect(contentRect.top, greaterThan(scrollRect.top));
          expect(contentRect.bottom, lessThan(scrollRect.bottom));
        } else {
          expect(contentRect.top, greaterThan(scrollRect.top));
          expect(contentRect.bottom, greaterThan(scrollRect.bottom));
          await tester.drag(
            find.byKey(const Key('onboarding-compact-scroll-view')),
            const Offset(0, -120),
          );
          await tester.pumpAndSettle();
          expect(
            tester
                .getRect(find.byKey(const Key('onboarding-compact-auth-card')))
                .top,
            lessThan(contentRect.top),
          );
        }
        expect(
          find.byKey(const Key('onboarding-local-credential-section')),
          credentials.isEmpty ? findsNothing : findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('移动端键盘弹出后认证主体保持可滚动且底栏不被遮挡', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();

    final scrollView = find.byKey(const Key('onboarding-compact-scroll-view'));
    final footer = find.byKey(const Key('onboarding-compact-footer'));
    final content = find.byKey(const Key('onboarding-compact-auth-card'));
    final contentBefore = tester.getRect(content);

    expect(scrollView, findsOneWidget);
    expect(tester.getRect(footer).bottom, lessThanOrEqualTo(844 - 280));

    await tester.drag(scrollView, const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(tester.getRect(content).top, lessThan(contentBefore.top));
    expect(tester.getRect(footer).bottom, lessThanOrEqualTo(844 - 280));
  });

  testWidgets('退出登录后立即保留认证表单和本地身份入口', (tester) async {
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    final gateway = FakeAwikiGateway();

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
    await container.read(appRuntimeProvider.notifier).logout();
    await tester.pump();
    await tester.pump();

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(AwikiMeLoadingMask), findsNothing);
    expect(container.read(appRuntimeProvider).isBusy, isFalse);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsNothing);
    expect(find.text('重新识别本地凭证'), findsNothing);
    expect(
      find.byKey(const Key('onboarding-local-credential-section')),
      findsOneWidget,
    );
    expect(gateway.logoutCalls, 1);
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
    deleteCompleter.complete();
    await deleteFuture;
    await tester.pumpAndSettle();

    expect(gateway.deleteLocalCredentialCalls, 1);
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.text('导入身份凭证'), findsNothing);
  });

  testWidgets('macOS 桌面注册页保留邮箱注册动作', (tester) async {
    final gateway = FakeAwikiGateway();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      _resetTestViewSize(tester);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    _setTestViewSize(tester, const Size(1440, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'a@b.com');
    await tester.tap(find.text('发送激活邮件'));
    await tester.pump();

    expect(gateway.sendEmailVerificationCalls, 1);
    expect(gateway.lastEmailVerificationHandle, 'alice');

    debugDefaultTargetPlatformOverride = null;
    _resetTestViewSize(tester);
  });

  testWidgets('移动端邮箱激活检查按钮使用整行宽度避免换行', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();

    final actionRect = tester.getRect(
      find.byKey(const Key('onboarding-email-action')),
    );
    expect(find.text('我已激活，检查状态'), findsOneWidget);
    expect(actionRect.width, greaterThan(300));
  });

  testWidgets('移动端一级 tab 直接按手机号、邮箱的顺序展示', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    final phoneRect = tester.getRect(find.byKey(const Key('auth-mode-phone')));
    final emailRect = tester.getRect(find.byKey(const Key('auth-mode-email')));

    expect(find.byKey(const Key('onboarding-entry-tabs')), findsNothing);
    expect(phoneRect.left, lessThan(emailRect.left));
    expect(phoneRect.width, moreOrLessEquals(emailRect.width));
    expect(phoneRect.center.dy, moreOrLessEquals(emailRect.center.dy));
  });

  testWidgets('移动端认证页不展示旧的身份模式快捷跳转', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    expect(find.textContaining('还没有账号'), findsNothing);
    expect(find.textContaining('已有账号'), findsNothing);
    expect(find.text('去登录或注册'), findsNothing);
    expect(find.text('去登录'), findsNothing);
    expect(find.text('切换身份'), findsNothing);
    expect(find.byKey(const Key('onboarding-entry-tabs')), findsNothing);
    expect(find.text('发送验证码'), findsOneWidget);
  });

  testWidgets('登录页右下角展示当前租户入口且不再硬编码 awiki.info', (tester) async {
    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    await _scrollToOnboardingUtilityBar(tester);
    expect(find.byTooltip('管理租户'), findsOneWidget);
    expect(find.text('AWiki'), findsWidgets);
    expect(find.text('Based on awiki.info'), findsNothing);
  });

  testWidgets('登录页可从底部工具栏切换语言', (tester) async {
    final localePreferenceService = FakeLocalePreferenceService();
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        localePreferenceService: localePreferenceService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('auth-mode-phone')), findsOneWidget);

    await _scrollToOnboardingUtilityBar(tester);
    await tester.tap(
      find.byKey(const Key('onboarding-language-switcher-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await _scrollToOnboardingUtilityBar(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    expect(localePreferenceService.saveCalls, 1);
    expect(container.read(appLocaleModeProvider), AppLocaleMode.english);
    expect(find.text('EN'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
  });

  testWidgets('移动端语言和租户入口固定在底部且不随认证内容滚动', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));
    final gateway = FakeAwikiGateway()
      ..localCredentials = List<SessionIdentity>.generate(
        6,
        (index) => SessionIdentity(
          did: 'did:test:mobile-$index',
          credentialName: 'mobile-$index',
          displayName: 'Mobile Identity $index',
          handle: 'mobile-$index',
          jwtToken: 'token-$index',
        ),
      );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    final footer = find.byKey(const Key('onboarding-compact-footer'));
    final firstIdentity = find.text('Mobile Identity 0');
    final footerBefore = tester.getRect(footer);
    final firstIdentityBefore = tester.getRect(firstIdentity);
    final languageRect = tester.getRect(
      find.byKey(const Key('onboarding-language-switcher-button')),
    );
    final tenantRect = tester.getRect(find.byTooltip('管理租户'));

    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pumpAndSettle();

    final footerAfter = tester.getRect(footer);
    final firstIdentityAfter = tester.getRect(firstIdentity);
    expect(footerAfter, footerBefore);
    expect(firstIdentityAfter.top, lessThan(firstIdentityBefore.top));
    expect(languageRect.left, lessThan(tenantRect.left));
    expect(footerAfter.bottom, lessThanOrEqualTo(844));
    expect(footerAfter.bottom, greaterThan(790));
  });

  testWidgets('登录页租户弹窗可添加租户配置且不自动切换', (tester) async {
    late StateSetter refreshTenants;
    final tenantActions = FakeAppTenantActions();
    tenantActions.onChanged = () => refreshTenants(() {});
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          refreshTenants = setState;
          return buildLocalizedTestApp(
            home: const OnboardingPage(),
            providerOverrides: <Override>[
              appTenantRegistryProvider.overrideWithValue(
                tenantActions.registry,
              ),
              activeAppTenantProvider.overrideWithValue(
                tenantActions.registry.activeTenant,
              ),
              appTenantActionsProvider.overrideWithValue(tenantActions),
            ],
          );
        },
      ),
    );
    await tester.pump();

    await _scrollToOnboardingUtilityBar(tester);
    await tester.tap(find.byTooltip('管理租户'));
    await tester.pumpAndSettle();
    expect(find.byType(TenantManagementDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('tenant-management-create-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-name-field')),
        matching: find.byType(CupertinoTextField),
      ),
      '杭州测试',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-backend-field')),
        matching: find.byType(CupertinoTextField),
      ),
      'https://dev.example.com/',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-did-host-field')),
        matching: find.byType(CupertinoTextField),
      ),
      'dev.example.com',
    );
    await tester.tap(find.byKey(const Key('tenant-form-submit-button')));
    await tester.pumpAndSettle();

    expect(tenantActions.createTenantCalls, 1);
    expect(tenantActions.useTenantCalls, 0);
    expect(tenantActions.registry.activeTenant.isPrimaryTenant, isTrue);
    expect(find.text('杭州测试'), findsOneWidget);

    await tester.tap(find.byTooltip('使用').last);
    await tester.pumpAndSettle();

    expect(tenantActions.useTenantCalls, 1);
    expect(tenantActions.registry.activeTenant.name, '杭州测试');
  });

  testWidgets('租户错误提示可选中并展示未知错误详情', (tester) async {
    final tenantActions = FakeAppTenantActions()
      ..nextCreateError = StateError('runtime bootstrap failed');
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        providerOverrides: <Override>[
          appTenantActionsProvider.overrideWithValue(tenantActions),
        ],
      ),
    );
    await tester.pump();

    await _scrollToOnboardingUtilityBar(tester);
    await tester.tap(find.byTooltip('管理租户'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tenant-management-create-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-name-field')),
        matching: find.byType(CupertinoTextField),
      ),
      'Test',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-backend-field')),
        matching: find.byType(CupertinoTextField),
      ),
      'https://anpolis.net',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('tenant-did-host-field')),
        matching: find.byType(CupertinoTextField),
      ),
      'anpolis.net',
    );
    await tester.tap(find.byKey(const Key('tenant-form-submit-button')));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsWidgets);
    expect(find.textContaining('租户操作失败，请稍后重试。'), findsOneWidget);
    expect(find.textContaining('runtime bootstrap failed'), findsOneWidget);
  });

  testWidgets('移动端已有身份显示在认证表单下方且不再展示刷新入口', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));
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

    expect(find.text('导入身份凭证'), findsNothing);
    expect(find.text('重新识别本地凭证'), findsNothing);
    expect(find.text('发送验证码'), findsOneWidget);
    expect(
      find.byKey(const Key('onboarding-local-credential-section')),
      findsOneWidget,
    );
    expect(find.text('Alice'), findsOneWidget);
    expect(gateway.importCalls, 0);
  });

  testWidgets('移动端点击表单下方已保存身份卡片空白区域也能登录', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));
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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('onboarding-local-credential-section')),
      findsOneWidget,
    );
    final identityTile = find.byKey(
      const Key('onboarding-local-credential:default'),
    );
    await tester.ensureVisible(identityTile);
    await tester.pumpAndSettle();
    await tester.tap(identityTile);
    await tester.pumpAndSettle();

    expect(gateway.loginCalls, 1);
    expect(gateway.lastLoginCredentialName, 'default');
  });

  testWidgets('展开宽度下登录页使用品牌与认证双栏布局', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(1280, 900));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    expect(find.byKey(const Key('onboarding-expanded-layout')), findsOneWidget);
    final heroRect = tester.getRect(
      find.byKey(const Key('onboarding-mac-hero-title')),
    );
    final cardRect = tester.getRect(
      find.byKey(const Key('onboarding-mac-auth-card')),
    );
    expect(heroRect.right, lessThan(cardRect.left));
    expect(cardRect.width, lessThanOrEqualTo(540));
  });

  testWidgets('macOS 窄窗口下单层认证入口保持单行并隐藏品牌列', (tester) async {
    final gateway = FakeAwikiGateway();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      _resetTestViewSize(tester);
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    _setTestViewSize(tester, const Size(820, 780));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('onboarding-mac-hero-title')), findsNothing);
    expect(
      find.byKey(const Key('onboarding-desktop-compact-brand')),
      findsOneWidget,
    );

    final phoneRect = tester.getRect(find.byKey(const Key('auth-mode-phone')));
    final emailRect = tester.getRect(find.byKey(const Key('auth-mode-email')));
    final tabsRect = tester.getRect(
      find.byKey(const Key('onboarding-mac-auth-method-tabs')),
    );

    expect(phoneRect.left, greaterThanOrEqualTo(tabsRect.left));
    expect(emailRect.left, greaterThan(phoneRect.left));
    expect(emailRect.right, lessThanOrEqualTo(tabsRect.right));
    expect(phoneRect.center.dy, moreOrLessEquals(emailRect.center.dy));
    expect(
      find.byKey(const Key('onboarding-mac-credential-mode')),
      findsNothing,
    );

    debugDefaultTargetPlatformOverride = null;
    _resetTestViewSize(tester);
  });

  testWidgets('全屏认证表单使用一级认证 tab 和右对齐动作按钮', (tester) async {
    addTearDown(() => _resetTestViewSize(tester));
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage()),
    );
    await tester.pump();

    final cardRect = tester.getRect(
      find.byKey(const Key('onboarding-compact-auth-card')),
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

    expect(find.byKey(const Key('onboarding-entry-tabs')), findsNothing);
    expect(authTabsRect.width, lessThan(cardRect.width));
    expect(nextRect.width, lessThan(cardRect.width * 0.5));
    expect(nextRect.right, lessThan(cardRect.right));
    expect(cardRect.right - nextRect.right, moreOrLessEquals(4, epsilon: 1));
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

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'a@b.com');
    await tester.tap(find.text('发送激活邮件'));
    await tester.pump();

    expect(gateway.sendEmailVerificationCalls, 1);
    expect(gateway.lastEmailVerificationHandle, 'alice');
    expect(find.textContaining('重新发送（'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.message.id, 'activationEmailSent');
    expect(feedback?.danger, isFalse);
  });

  testWidgets('手机号验证码发送成功后进入重新发送倒计时', (tester) async {
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
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'alice');
    await tester.tap(find.text('发送验证码'));
    await tester.pump();

    expect(gateway.sendOtpCalls, 1);
    expect(find.textContaining('重新发送（'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    final state = container.read(onboardingProvider);
    expect(state.otpResendCountdown, 60);
    expect(state.isOtpResendCoolingDown, isTrue);

    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.message.id, 'otpSent');
    expect(feedback?.danger, isFalse);
  });

  testWidgets('手机号验证码发送失败时保持可重试且不进入倒计时', (tester) async {
    final gateway = FakeAwikiGateway()..failNextSendOtp = true;

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
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'alice');
    await tester.tap(find.text('发送验证码'));
    await tester.pump();
    await tester.pump();

    expect(gateway.sendOtpCalls, 1);
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.textContaining('重新发送（'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    final state = container.read(onboardingProvider);
    expect(state.isBusy, isFalse);
    expect(state.otpResendCountdown, 0);
    final feedback = container.read(uiFeedbackProvider);
    expect(feedback?.danger, isTrue);
    expect(feedback?.message.id, 'raw');
    expect(feedback?.message.detail, 'otp gateway unavailable');
  });

  testWidgets('邮箱验证成功后可以直接完成注册', (tester) async {
    final gateway = FakeAwikiGateway()..emailVerificationResult = true;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'a@b.com');
    await tester.tap(find.text('我已激活，检查状态'));
    await tester.pump();

    expect(gateway.checkEmailVerifiedCalls, 1);
    expect(gateway.lastCheckedEmailVerificationHandle, 'alice');
    expect(find.text('完成注册'), findsOneWidget);

    await tester.tap(find.text('完成注册'));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingPage)),
    );
    expect(container.read(onboardingProvider).registerStep, 1);
    expect(gateway.registerHandleWithEmailCalls, 1);
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
    await tester.enterText(find.byType(CupertinoTextField).at(2), '123456');
    await _tapVisible(tester, find.text('下一步'));
    await tester.pumpAndSettle();

    final handleField = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField).first,
    );
    expect(handleField.controller?.text, isEmpty);
  });

  testWidgets('手机号提交直接走注册路径', (tester) async {
    final gateway = FakeAwikiGateway();

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
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'alice');
    await tester.enterText(find.byType(CupertinoTextField).at(2), '123456');
    await _tapVisible(tester, find.text('发送验证码'));
    await tester.pump();
    await _tapVisible(tester, find.text('下一步'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.registerHandleCalls, 1);
    expect(gateway.lastRegisteredNickName, 'alice');
    expect(gateway.lastRegisteredProfileMarkdown, '# alice\n\n');
  });

  testWidgets('手机号注册返回 joinRequired 时进入设备加入页', (tester) async {
    final gateway = FakeAwikiGateway()
      ..registrationStatus = IdentityRegistrationStatus.joinRequired;

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
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'alice');
    await tester.enterText(find.byType(CupertinoTextField).at(2), '123456');
    await _tapVisible(tester, find.text('发送验证码'));
    await tester.pump();
    await _tapVisible(tester, find.text('下一步'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.registerHandleCalls, 0);
    expect(find.byKey(const Key('device-join-page')), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DeviceJoinPage)),
    );
    final join = container.read(devicesProvider).activeJoin;
    expect(join?.joinSessionId, 'registration-join-1');
    expect(join.toString(), isNot(contains('123456')));
    expect(
      container.read(onboardingProvider).toString(),
      isNot(contains('123456')),
    );
  });

  testWidgets('OpenServer 注册页只展示手机号和 handle 并走无验证码注册', (tester) async {
    final gateway = FakeAwikiGateway()
      ..serverInfo = OnboardingServerInfo.openServerDefault(
        didDomain: 'anpolis.net',
      );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(find.text('发送验证码'), findsNothing);
    expect(find.byKey(const Key('auth-mode-email')), findsNothing);
    expect(find.text('当前服务器不需要短信或邮箱验证码，可直接创建新身份。'), findsOneWidget);

    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      '13800138000',
    );
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'alice');
    await tester.ensureVisible(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(gateway.registerHandleWithoutContactVerificationCalls, 1);
    expect(gateway.registerHandleCalls, 0);
  });

  testWidgets('server-info 加载失败时注册区展示重试入口', (tester) async {
    final gateway = FakeAwikiGateway()
      ..serverInfoError = StateError('server-info unavailable');

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pumpAndSettle();

    expect(find.text('无法读取当前服务器支持的登录方式。请检查租户地址后重试。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('发送验证码'), findsNothing);

    gateway.serverInfoError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(gateway.loadServerInfoCalls, greaterThanOrEqualTo(2));
    expect(find.text('发送验证码'), findsOneWidget);
  });

  testWidgets('邮箱提交直接注册并默认用 handle 作为昵称', (tester) async {
    final gateway = FakeAwikiGateway()..emailVerificationResult = true;

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    await tester.tap(find.text('登录或注册'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-mode-email')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField).at(0), 'alice');
    await tester.enterText(find.byType(CupertinoTextField).at(1), 'a@b.com');
    await tester.tap(find.text('我已激活，检查状态'));
    await tester.pump();
    await tester.tap(find.text('完成注册'));
    await tester.pumpAndSettle();

    expect(gateway.lastCheckedEmailVerificationHandle, 'alice');
    expect(gateway.registerHandleWithEmailCalls, 1);
    expect(gateway.lastEmailRegisteredNickName, 'alice');
    expect(gateway.lastEmailRegisteredProfileMarkdown, '# alice\n\n');
  });
}

class _LegacyUpgradeOnboardingService implements OnboardingService {
  _LegacyUpgradeOnboardingService(this.firstUpgrade);

  final Completer<LegacyIdentityUpgradeStatus> firstUpgrade;
  final List<String> statusSelectors = <String>[];
  final List<String> upgradeSelectors = <String>[];

  @override
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  ) async {
    statusSelectors.add(identityIdOrAlias);
    return const LegacyIdentityUpgradeStatus.idle();
  }

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) {
    upgradeSelectors.add(identityIdOrAlias);
    if (upgradeSelectors.length == 1) {
      return firstUpgrade.future;
    }
    return Future<LegacyIdentityUpgradeStatus>.value(
      const LegacyIdentityUpgradeStatus.completed(),
    );
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) {
    throw UnsupportedError('not used');
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) {
    throw UnsupportedError('not used');
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) {
    throw UnsupportedError('not used');
  }
}

class _RecordingOnboardingSupportService extends FakeOnboardingSupportService {
  _RecordingOnboardingSupportService(super.gateway);

  String? phone;
  String? handle;
  String? domain;
  String? fullHandle;

  @override
  Future<void> sendRegistrationOtp({
    required String phone,
    required String handle,
    required String domain,
    required String fullHandle,
  }) async {
    this.phone = phone;
    this.handle = handle;
    this.domain = domain;
    this.fullHandle = fullHandle;
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Future<void> _scrollToOnboardingUtilityBar(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('onboarding-language-switcher-button')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}
