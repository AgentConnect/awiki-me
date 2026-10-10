import 'dart:async';
import 'dart:ui' as ui;

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:awiki_me/src/presentation/onboarding/registration_entry_provider.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:awiki_me/src/core/app_error_classifier.dart';
import 'package:awiki_me/src/core/app_transport_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class InviteSupport extends FakeOnboardingSupportService {
  InviteSupport(super.gateway);
  int checks = 0;
  String? lastInvite;
  String? lastEmail;
  bool? lastCheckInvite;
  String decision = 'register';
  bool fail = false;
  Object? failure;
  String? boundPhone;
  Completer<void>? checkGate;
  Completer<void>? otpGate;
  int otpRequests = 0;

  @override
  Future<RegistrationOtpSendReceipt> sendRegistrationOtp({
    required String phone,
    required String handle,
    required String domain,
    required String fullHandle,
  }) async {
    otpRequests++;
    await otpGate?.future;
    return super.sendRegistrationOtp(
      phone: phone,
      handle: handle,
      domain: domain,
      fullHandle: fullHandle,
    );
  }

  @override
  Future<RegistrationCheck> checkRegistration({
    required String handle,
    required String domain,
    String? inviteCode,
    String? phone,
    String? email,
    bool checkInvite = false,
  }) async {
    checks++;
    await checkGate?.future;
    if (failure != null) throw failure!;
    if (fail) throw StateError('network');
    lastInvite = inviteCode;
    lastEmail = email;
    lastCheckInvite = checkInvite;
    final required = decision == 'register' && handle.length <= 4;
    final valid =
        inviteCode == 'ABC123' &&
        (boundPhone == null ||
            (phone == null && email == null) ||
            phone == boundPhone);
    return RegistrationCheck(
      fullHandle: '$handle.$domain',
      decision: decision,
      inviteRequired: required,
      inviteStatus: !required
          ? 'not_required'
          : !checkInvite
          ? 'required'
          : valid
          ? 'valid'
          : 'invalid',
      reason: checkInvite && required && !valid ? 'invite_invalid' : null,
    );
  }
}

// The unified onboarding form uses its own outlined field, so fields are
// located by their stable semantics identifier rather than widget type.
Finder field(String id) => find.descendant(
  of: find.byWidgetPredicate(
    (w) =>
        (w is AppTextField && w.semanticsIdentifier == id) ||
        (w is Semantics && w.properties.identifier == id),
  ),
  matching: find.byType(CupertinoTextField),
);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 1200), const Size(1100, 900)]) {
    testWidgets('browsing identities preserves an issued OTP at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeAwikiGateway();
      final support = InviteSupport(gateway);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const OnboardingPage(),
          gateway: gateway,
          providerOverrides: [
            onboardingSupportServiceProvider.overrideWithValue(support),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('e2e-handle-input'), 'alice');
      await tester.enterText(field('e2e-phone-input'), '13800138000');
      await tapVisible(tester, find.text('发送验证码'));
      await tester.enterText(field('e2e-otp-input'), '123456');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      final issued = container.read(onboardingProvider);
      expect(issued.canSubmitPhoneOtp, isTrue);
      await tapVisible(tester, find.text('切换身份'));
      expect(container.read(onboardingProvider).entryMode, 'login');
      await tapVisible(tester, find.text('登录或注册'));
      final restored = container.read(onboardingProvider);
      expect(restored.otpTargetFullHandle, issued.otpTargetFullHandle);
      expect(restored.otpTargetPhone, issued.otpTargetPhone);
      expect(restored.canSubmitPhoneOtp, isTrue);
      expect(
        tester
            .widget<CupertinoTextField>(field('e2e-otp-input'))
            .controller!
            .text,
        '123456',
      );
      await tapVisible(tester, find.text('登录/注册'));
      expect(gateway.registerHandleCalls, 1);
      expect(gateway.sendOtpCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 1200), const Size(1100, 900)]) {
    testWidgets('browsing identities preserves email activation at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeAwikiGateway()..emailVerificationResult = true;
      await tester.pumpWidget(
        buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('auth-mode-email')));
      await tester.enterText(field('e2e-handle-input'), 'alice');
      await tester.enterText(field('e2e-email-input'), 'fixture@example.com');
      await tapVisible(tester, find.text('发送激活邮件'));
      await tapVisible(tester, find.text('我已激活，检查状态'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      expect(container.read(onboardingProvider).emailVerified, isTrue);
      expect(
        container.read(onboardingProvider).emailResendCountdown,
        greaterThan(0),
      );
      await tapVisible(tester, find.text('切换身份'));
      await tapVisible(tester, find.text('登录或注册'));
      expect(container.read(onboardingProvider).emailVerified, isTrue);
      expect(
        container.read(onboardingProvider).emailResendCountdown,
        greaterThan(0),
      );
      expect(
        tester
            .widget<CupertinoTextField>(field('e2e-email-input'))
            .controller!
            .text,
        'fixture@example.com',
      );
      expect(gateway.checkEmailVerifiedCalls, 1);
      await tapVisible(tester, find.text('完成注册'));
      expect(gateway.registerHandleWithEmailCalls, 1);
      // Submission performs the existing authoritative verification recheck.
      expect(gateway.checkEmailVerifiedCalls, 2);
      expect(gateway.sendEmailVerificationCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(390, 900), const Size(1100, 900)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'focused invite input remains readable in $brightness at $size',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final gateway = FakeAwikiGateway();
          final support = InviteSupport(gateway);
          final theme = AwikiMeTheme.forPlatform(
            TargetPlatform.macOS,
            brightness: brightness,
          );
          await tester.pumpWidget(
            buildLocalizedTestApp(
              home: Theme(
                data: theme.materialTheme,
                child: const RepaintBoundary(
                  key: Key('invite-capture'),
                  child: OnboardingPage(),
                ),
              ),
              gateway: gateway,
              providerOverrides: [
                onboardingSupportServiceProvider.overrideWithValue(support),
              ],
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(field('e2e-handle-input'), 'abcd');
          await tester.enterText(field('e2e-phone-input'), '13800138000');
          await tapVisible(tester, find.text('发送验证码'));
          final invite = field('e2e-invite-input');
          await tester.ensureVisible(invite);
          await tester.pumpAndSettle();
          final beforeFocus = tester.getRect(invite);
          await tester.enterText(invite, 'ABC123');
          await tester.pumpAndSettle();
          expect(tester.getRect(invite), beforeFocus);
          final input = tester.widget<CupertinoTextField>(invite);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('invite-capture')),
          );
          final rect = tester.getRect(invite);
          final point = boundary.globalToLocal(
            Offset(rect.right - 8, rect.center.dy),
          );
          final fill = await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            try {
              final pixels = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              final offset =
                  (point.dy.floor() * image.width + point.dx.floor()) * 4;
              return Color.fromARGB(
                pixels!.getUint8(offset + 3),
                pixels.getUint8(offset),
                pixels.getUint8(offset + 1),
                pixels.getUint8(offset + 2),
              );
            } finally {
              image.dispose();
            }
          });
          final luminances = [
            input.style!.color!.computeLuminance(),
            fill!.computeLuminance(),
          ]..sort();
          expect(
            (luminances.last + .05) / (luminances.first + .05),
            greaterThanOrEqualTo(4.5),
          );
          expect(input.controller!.text, 'ABC123');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final size in <Size>[const Size(390, 1200), const Size(1100, 900)]) {
    for (final outcome in ['precheck_failure', 'send_failure', 'success']) {
      testWidgets('send-code loading stays inside control at $size: $outcome', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final gateway = FakeAwikiGateway()
          ..failNextSendOtp = outcome == 'send_failure';
        final support = InviteSupport(gateway)
          ..checkGate = Completer<void>()
          ..otpGate = Completer<void>()
          ..fail = outcome == 'precheck_failure';
        await tester.pumpWidget(
          buildLocalizedTestApp(
            home: const OnboardingPage(),
            gateway: gateway,
            providerOverrides: [
              onboardingSupportServiceProvider.overrideWithValue(support),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(field('e2e-handle-input'), 'fixture');
        await tester.enterText(field('e2e-phone-input'), '13800138000');
        final button = find.byWidgetPredicate(
          (w) =>
              w is AppPressable &&
              w.semanticsIdentifier == 'e2e-send-otp-button',
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final originalRect = tester.getRect(button);
        final send = tester.widget<AppPressable>(button).onTap!;
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        void expectLoading() {
          final spinner = find.byKey(const Key('onboarding-send-otp-loading'));
          expect(spinner, findsOneWidget);
          expect(
            find.descendant(of: button, matching: spinner),
            findsOneWidget,
          );
          expect(tester.getRect(button), originalRect);
          expect(
            originalRect.contains(tester.getRect(spinner).topLeft),
            isTrue,
          );
          expect(
            originalRect.contains(tester.getRect(spinner).bottomRight),
            isTrue,
          );
          expect(tester.widget<AppPressable>(button).enabled, isFalse);
          expect(tester.widget<AppPressable>(button).onTap, isNull);
          expect(
            find.descendant(
              of: find.byKey(const Key('registration-entry-form')),
              matching: find.byType(CupertinoActivityIndicator),
            ),
            findsNothing,
          );
        }

        expectLoading();
        expect(support.checks, 1);
        expect(support.otpRequests, 0);
        send();
        await tester.tap(button);
        await tester.pump();
        expect(support.checks, 1);
        support.checkGate!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        if (outcome != 'precheck_failure') {
          expectLoading();
          expect(support.otpRequests, 1);
          send();
          await tester.tap(button);
          await tester.pump();
          expect(support.otpRequests, 1);
        }
        support.otpGate!.complete();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('onboarding-send-otp-loading')),
          findsNothing,
        );
        if (outcome == 'success') {
          expect(gateway.sendOtpCalls, 1);
          expect(find.textContaining('重新发送'), findsOneWidget);
          expect(tester.widget<AppPressable>(button).enabled, isFalse);
        } else {
          expect(tester.widget<AppPressable>(button).enabled, isTrue);
          expect(gateway.sendOtpCalls, outcome == 'precheck_failure' ? 0 : 1);
          support.checkGate = Completer<void>();
          await tester.tap(button);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expectLoading();
          expect(support.checks, 2);
          support.fail = true;
          support.checkGate!.complete();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('onboarding-send-otp-loading')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in <Size>[const Size(390, 1200), const Size(1100, 900)]) {
    for (final failPrecheck in <bool>[true, false]) {
      testWidgets(
        'submit loading stays inside button at $size through '
        '${failPrecheck ? 'failed precheck' : 'precheck and failed registration'}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final registrationGate = Completer<void>();
          final gateway = FakeAwikiGateway()
            ..onboardingPhoneRegistrationCompleter = registrationGate
            ..nextOnboardingPhoneRegistrationError = StateError('network');
          final support = InviteSupport(gateway);
          await tester.pumpWidget(
            buildLocalizedTestApp(
              home: const OnboardingPage(),
              gateway: gateway,
              providerOverrides: [
                onboardingSupportServiceProvider.overrideWithValue(support),
              ],
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(field('e2e-handle-input'), 'fixture');
          await tester.enterText(field('e2e-phone-input'), '13800138000');
          await tapVisible(tester, find.text('发送验证码'));
          await tester.enterText(field('e2e-otp-input'), '123456');
          final button = find.byKey(
            const Key('onboarding-mac-phone-submit-action'),
          );
          final pressable = find.descendant(
            of: button,
            matching: find.byType(AppPressable),
          );
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final originalRect = tester.getRect(button);
          final submit = tester.widget<AppPressable>(pressable).onTap!;
          support.checkGate = Completer<void>();
          support.fail = failPrecheck;
          await tester.tap(button);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));

          void expectLoading() {
            final spinner = find.byKey(const Key('onboarding-submit-loading'));
            expect(spinner, findsOneWidget);
            expect(
              find.descendant(of: button, matching: spinner),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: find.byKey(const Key('registration-entry-form')),
                matching: find.byType(CupertinoActivityIndicator),
              ),
              findsNothing,
            );
            expect(tester.getRect(button), originalRect);
            expect(
              originalRect.contains(tester.getRect(spinner).topLeft),
              isTrue,
            );
            expect(
              originalRect.contains(tester.getRect(spinner).bottomRight),
              isTrue,
            );
            expect(tester.widget<AppPressable>(pressable).enabled, isFalse);
            expect(tester.widget<AppPressable>(pressable).onTap, isNull);
            expect(find.text('登录/注册'), findsOneWidget);
          }

          expectLoading();
          expect(support.checks, 2);
          expect(gateway.onboardingPhoneRegistrationCalls, 0);
          // Also protect two callbacks fired before the first frame disables
          // the control, rather than relying only on disabled hit testing.
          submit();
          await tester.tap(button);
          await tester.pump();
          expect(support.checks, 2);

          support.checkGate!.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          if (!failPrecheck) {
            expectLoading();
            expect(gateway.onboardingPhoneRegistrationCalls, 1);
            submit();
            await tester.pump();
            expect(gateway.onboardingPhoneRegistrationCalls, 1);
          }
          registrationGate.complete();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('onboarding-submit-loading')),
            findsNothing,
          );
          expect(tester.widget<AppPressable>(pressable).enabled, isTrue);
          expect(field('e2e-handle-input'), findsOneWidget);
          expect(
            tester
                .widget<CupertinoTextField>(field('e2e-handle-input'))
                .controller!
                .text,
            'fixture',
          );
          if (failPrecheck) {
            expect(
              find.byKey(const Key('registration-entry-error')),
              findsOneWidget,
            );
            expect(gateway.onboardingPhoneRegistrationCalls, 0);
          } else {
            expect(gateway.onboardingPhoneRegistrationCalls, 1);
          }
          // A completed failed attempt must release the submission guard.
          support.checkGate = Completer<void>();
          await tester.tap(button);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(
            find.byKey(const Key('onboarding-submit-loading')),
            findsOneWidget,
          );
          expect(support.checks, 3);
          support.fail = true;
          support.checkGate!.complete();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('onboarding-submit-loading')),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('TLS guidance retains form input and opens redacted details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final gateway = FakeAwikiGateway();
    final support = InviteSupport(gateway)
      ..failure = const AppStructuredError(
        code: tlsHandshakeFailureCode,
        cause: AppTransportDiagnostic(
          code: tlsHandshakeFailureCode,
          host: 'example.com',
          appVersion: 'test',
          caVersion: 'test',
        ),
      );
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        gateway: gateway,
        providerOverrides: [
          onboardingSupportServiceProvider.overrideWithValue(support),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(field('e2e-handle-input'), 'fixture');
    await tester.enterText(field('e2e-phone-input'), '13800138000');
    await tapVisible(tester, find.text('发送验证码'));
    expect(find.text('无法建立安全连接。请检查系统日期和时间，或联系支持人员。'), findsOneWidget);
    expect(
      tester
          .widget<CupertinoTextField>(field('e2e-handle-input'))
          .controller!
          .text,
      'fixture',
    );
    expect(gateway.sendOtpCalls, 0);
    await tapVisible(tester, find.text('详情'));
    expect(find.textContaining('host=example.com'), findsOneWidget);
    expect(find.text('复制详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OTP sends with blank invite', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final gateway = FakeAwikiGateway();
    final support = InviteSupport(gateway);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        gateway: gateway,
        providerOverrides: [
          onboardingSupportServiceProvider.overrideWithValue(support),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(field('e2e-handle-input'), findsOneWidget);
    expect(field('e2e-phone-input'), findsOneWidget);
    expect(field('e2e-otp-input'), findsOneWidget);
    expect(find.text('发送验证码'), findsOneWidget);
    expect(find.text('下一步'), findsNothing);
    expect(field('e2e-invite-input'), findsNothing);

    await tester.enterText(field('e2e-handle-input'), 'abcd');
    await tester.enterText(field('e2e-phone-input'), '13800138000');
    await tapVisible(tester, find.text('发送验证码'));
    expect(support.checks, 1);
    expect(field('e2e-invite-input'), findsOneWidget);
    expect(find.text('注册位数小于5位的handle需要使用邀请码'), findsOneWidget);
    expect(field('e2e-phone-input'), findsOneWidget);
    expect(field('e2e-otp-input'), findsOneWidget);
    expect(gateway.sendOtpCalls, 1);
    await tester.enterText(field('e2e-otp-input'), '123456');
    await tapVisible(tester, find.text('登录/注册'));
    expect(gateway.registerHandleCalls, 0);
    expect(find.text('此账号注册需要邀请码，请填写后继续。'), findsOneWidget);

    await tester.enterText(field('e2e-invite-input'), 'WRONG1');
    await tapVisible(tester, find.text('登录/注册'));
    expect(field('e2e-invite-input'), findsOneWidget);
    expect(support.lastInvite, isNull);
    expect(support.lastCheckInvite, isFalse);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      ).read(registrationEntryProvider).inviteCode,
      'WRONG1',
    );
    expect(gateway.registerHandleCalls, 1);
    expect(gateway.lastRegisteredInviteCode, 'WRONG1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('email activation sends without invite', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final gateway = FakeAwikiGateway();
    final support = InviteSupport(gateway);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        gateway: gateway,
        providerOverrides: [
          onboardingSupportServiceProvider.overrideWithValue(support),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('auth-mode-email')));
    await tester.enterText(field('e2e-handle-input'), 'abcd');
    await tester.enterText(field('e2e-email-input'), 'fixture@example.com');
    await tapVisible(tester, find.text('发送激活邮件'));
    expect(field('e2e-invite-input'), findsOneWidget);
    expect(gateway.sendEmailVerificationCalls, 1);

    await tester.enterText(field('e2e-invite-input'), 'WRONG1');
    expect(gateway.sendEmailVerificationCalls, 1);
    expect(support.lastEmail, 'fixture@example.com');
    expect(support.lastInvite, isNull);
    expect(support.lastCheckInvite, isFalse);
    expect(field('e2e-invite-input'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop invite hint aligns with the invite label', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final gateway = FakeAwikiGateway();
    final support = InviteSupport(gateway);
    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const OnboardingPage(),
        gateway: gateway,
        providerOverrides: [
          onboardingSupportServiceProvider.overrideWithValue(support),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final handleField = find.descendant(
      of: find.bySemanticsIdentifier('e2e-handle-input'),
      matching: find.byType(CupertinoTextField),
    );
    final phoneField = find.descendant(
      of: find.bySemanticsIdentifier('e2e-phone-input'),
      matching: find.byType(CupertinoTextField),
    );
    await tester.enterText(handleField, 'abcd');
    await tester.enterText(phoneField, '13800138000');
    await tapVisible(tester, find.text('发送验证码'));

    final inviteLabel = find.text('邀请码').first;
    final hint = find.text('注册位数小于5位的handle需要使用邀请码');
    expect(find.bySemanticsIdentifier('e2e-invite-input'), findsOneWidget);
    expect(hint, findsOneWidget);
    expect(
      tester.getTopLeft(hint).dx,
      greaterThan(tester.getTopLeft(inviteLabel).dx),
    );
    expect(
      (tester.getTopLeft(hint).dy - tester.getTopLeft(inviteLabel).dy).abs(),
      lessThan(4),
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'five-character new handle requests OTP without an invite field',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final gateway = FakeAwikiGateway();
      final support = InviteSupport(gateway);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const OnboardingPage(),
          gateway: gateway,
          providerOverrides: [
            onboardingSupportServiceProvider.overrideWithValue(support),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('e2e-handle-input'), 'abcde');
      await tester.enterText(field('e2e-phone-input'), '13800138000');
      await tapVisible(tester, find.text('发送验证码'));

      expect(field('e2e-invite-input'), findsNothing);
      expect(gateway.sendOtpCalls, 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      expect(
        container.read(registrationEntryProvider).step,
        RegistrationEntryStep.verification,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registration status failure blocks OTP and an existing account proceeds without invite',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final gateway = FakeAwikiGateway();
      final support = InviteSupport(gateway)..fail = true;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const OnboardingPage(),
          gateway: gateway,
          providerOverrides: [
            onboardingSupportServiceProvider.overrideWithValue(support),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('e2e-handle-input'), 'abc');
      await tester.enterText(field('e2e-phone-input'), '13800138000');
      await tapVisible(tester, find.text('发送验证码'));
      expect(find.textContaining('暂时无法检查账号'), findsOneWidget);
      expect(gateway.sendOtpCalls, 0);
      expect(field('e2e-invite-input'), findsNothing);
      expect(support.checks, 1);
      support.fail = false;
      support.decision = 'existing';
      await tapVisible(tester, find.text('发送验证码'));
      expect(gateway.sendOtpCalls, 1);
      expect(field('e2e-invite-input'), findsNothing);
    },
  );
  testWidgets(
    'existing account OTP keeps the form without an account notice or early recovery',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final gateway = FakeAwikiGateway();
      final support = InviteSupport(gateway)..decision = 'existing';
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: const OnboardingPage(),
          gateway: gateway,
          providerOverrides: [
            onboardingSupportServiceProvider.overrideWithValue(support),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(field('e2e-handle-input'), 'abc');
      await tester.enterText(field('e2e-phone-input'), '13800138000');
      await tapVisible(tester, find.text('发送验证码'));
      final recovery = find.byWidgetPredicate(
        (w) =>
            w is AppSecondaryButton &&
            w.semanticsIdentifier == 'e2e-existing-recovery',
      );
      expect(recovery, findsNothing);
      expect(find.textContaining('已有账号'), findsNothing);
      expect(find.text('恢复 Handle'), findsNothing);
      expect(find.byType(HandleRecoveryPage), findsNothing);
      expect(field('e2e-otp-input'), findsOneWidget);
      expect(find.text('登录/注册'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      expect(
        container.read(registrationEntryProvider).check?.isExisting,
        isTrue,
      );
      expect(gateway.sendOtpCalls, 1);
      expect(gateway.registerHandleCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
