import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/desktop_startup_presentation_service.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/shared/startup_splash.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

final class _RecordingDesktopStartupPresentationService
    implements DesktopStartupPresentationService {
  int callCount = 0;

  @override
  Future<void> presentReadyContent() async {
    callCount += 1;
  }
}

class _ControlledStartupRuntimeController extends AppRuntimeController {
  _ControlledStartupRuntimeController(
    super.ref, {
    required this.ready,
    this.restoredSession,
    bool initiallyInitialized = false,
  }) {
    if (initiallyInitialized) {
      state = const AppRuntimeState(isInitialized: true);
    }
  }

  final Future<void> ready;
  final SessionIdentity? restoredSession;

  @override
  Future<void> initialize() async {
    if (state.isInitialized) {
      return;
    }
    state = state.copyWith(isBusy: true);
    await ready;
    final session = restoredSession;
    if (session != null) {
      ref.read(sessionProvider.notifier).activateSession(session);
    }
    state = state.copyWith(
      isInitialized: true,
      isBusy: false,
      activatedDid: session?.did,
    );
  }
}

void _setTestViewSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('冷启动恢复会话期间只显示开屏，不提前显示登录页', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));
    final ready = Completer<void>();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: <Override>[
          appRuntimeProvider.overrideWith(
            (ref) =>
                _ControlledStartupRuntimeController(ref, ready: ready.future),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(AwikiMeStartupSplash), findsOneWidget);
    expect(find.byKey(const Key('app-startup-splash')), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);

    ready.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byType(AwikiMeStartupSplash), findsNothing);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面缩到移动端尺寸仍跳过开屏并在恢复后直接进入登录页', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      _setTestViewSize(tester, const Size(390, 844));
      final ready = Completer<void>();
      final presentation = _RecordingDesktopStartupPresentationService();

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          providerOverrides: <Override>[
            appRuntimeProvider.overrideWith(
              (ref) =>
                  _ControlledStartupRuntimeController(ref, ready: ready.future),
            ),
            desktopStartupPresentationServiceProvider.overrideWithValue(
              presentation,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(AwikiMeStartupSplash), findsNothing);
      expect(
        find.byKey(const Key('app-desktop-startup-placeholder')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('startup-splash-brand')), findsNothing);
      expect(find.byKey(const Key('startup-splash-feature-0')), findsNothing);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(presentation.callCount, 0);

      ready.complete();
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('app-desktop-startup-placeholder')),
        findsNothing,
      );
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(presentation.callCount, 1);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('品牌开屏严格限定在 Android 和 iOS', () {
    expect(usesBrandedStartupSplash(TargetPlatform.android), isTrue);
    expect(usesBrandedStartupSplash(TargetPlatform.iOS), isTrue);
    expect(usesBrandedStartupSplash(TargetPlatform.macOS), isFalse);
    expect(usesBrandedStartupSplash(TargetPlatform.windows), isFalse);
    expect(usesBrandedStartupSplash(TargetPlatform.linux), isFalse);
  });

  testWidgets('已保存会话冷启动从开屏直接进入消息工作区', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));
    final ready = Completer<void>();
    const session = SessionIdentity(
      did: 'did:test:alice',
      credentialName: 'alice.json',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token',
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: <Override>[
          appRuntimeProvider.overrideWith(
            (ref) => _ControlledStartupRuntimeController(
              ref,
              ready: ready.future,
              restoredSession: session,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(AwikiMeStartupSplash), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);

    ready.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(AwikiMeStartupSplash), findsNothing);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byKey(const Key('app-shell-page-background')), findsOneWidget);
    expect(find.byKey(const Key('compact-bottom-navigation')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面已保存会话恢复后才呈现消息工作区', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      _setTestViewSize(tester, const Size(390, 844));
      final ready = Completer<void>();
      final presentation = _RecordingDesktopStartupPresentationService();
      const session = SessionIdentity(
        did: 'did:test:desktop-alice',
        credentialName: 'desktop-alice.json',
        displayName: 'Desktop Alice',
        handle: 'desktop-alice',
        jwtToken: 'desktop-token',
      );

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const AppShell(),
          providerOverrides: <Override>[
            appRuntimeProvider.overrideWith(
              (ref) => _ControlledStartupRuntimeController(
                ref,
                ready: ready.future,
                restoredSession: session,
              ),
            ),
            desktopStartupPresentationServiceProvider.overrideWithValue(
              presentation,
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(AwikiMeStartupSplash), findsNothing);
      expect(
        find.byKey(const Key('app-desktop-startup-placeholder')),
        findsOneWidget,
      );
      expect(presentation.callCount, 0);

      ready.complete();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(const Key('app-desktop-startup-placeholder')),
        findsNothing,
      );
      expect(find.byType(OnboardingPage), findsNothing);
      expect(
        find.byKey(const Key('app-shell-page-background')),
        findsOneWidget,
      );
      expect(presentation.callCount, 1);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('运行时已初始化且无会话时立即显示登录页', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        providerOverrides: <Override>[
          appRuntimeProvider.overrideWith(
            (ref) => _ControlledStartupRuntimeController(
              ref,
              ready: Future<void>.value(),
              initiallyInitialized: true,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.byType(AwikiMeStartupSplash), findsNothing);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开屏沿用正式文案、Logo，且没有误导性的交互入口', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const AwikiMeStartupSplash()),
    );
    await tester.pump();

    expect(find.text('AWiki Me'), findsOneWidget);
    expect(find.text('连接你的 Agent 世界'), findsOneWidget);
    expect(find.text('安全协作'), findsOneWidget);
    expect(find.text('智能体随行'), findsOneWidget);
    expect(find.text('人与 Agent 同群'), findsOneWidget);
    expect(
      find.byKey(const Key('startup-splash-feature-icon-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('startup-splash-feature-icon-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('startup-splash-feature-icon-2')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('startup-splash-logo')), findsOneWidget);
    expect(find.byKey(const Key('startup-splash-progress')), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开屏按 390x844 设计目标对齐品牌、三行能力与进度位置', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AwikiMeStartupSplash(),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getRect(find.byKey(const Key('startup-splash-logo'))),
      const Rect.fromLTWH(112, 246, 24, 24),
    );
    expect(
      tester.getRect(find.byKey(const Key('startup-splash-title'))).top,
      318,
    );
    expect(
      tester.getRect(find.byKey(const Key('startup-splash-subtitle'))).top,
      372,
    );
    expect(
      tester.getRect(find.byKey(const Key('startup-splash-feature-0'))).top,
      454,
    );
    expect(
      tester.getRect(find.byKey(const Key('startup-splash-feature-1'))).top,
      510,
    );
    expect(
      tester.getRect(find.byKey(const Key('startup-splash-feature-2'))).top,
      566,
    );
    expect(
      tester.getRect(find.byKey(const Key('startup-splash-progress'))),
      const Rect.fromLTWH(76, 756, 238, 4),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('开屏在横屏、大字体和减少动态效果下仍不溢出', (tester) async {
    _setTestViewSize(tester, const Size(844, 390));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const MediaQuery(
          data: MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(1.3),
          ),
          child: AwikiMeStartupSplash(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AwikiMeStartupSplash), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('英文开屏使用自适应布局且长文案不溢出', (tester) async {
    _setTestViewSize(tester, const Size(390, 844));

    await tester.pumpWidget(
      buildLocalizedTestApp(
        locale: const Locale('en'),
        home: const AwikiMeStartupSplash(),
      ),
    );
    await tester.pump();

    expect(find.text('AWiki Me'), findsOneWidget);
    expect(find.text('Secure collaboration'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
