import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/registration_entry_provider.dart';
import 'package:awiki_me/src/presentation/recovery/handle_recovery_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class InviteSupport extends FakeOnboardingSupportService {
  InviteSupport(super.gateway);
  int checks = 0;
  String? lastInvite;
  String? lastEmail;
  String decision = 'register';
  bool fail = false;
  String? boundPhone;

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
    if (fail) throw StateError('network');
    lastInvite = inviteCode;
    lastEmail = email;
    final required = decision == 'register' && handle.length <= 4;
    final valid =
        inviteCode == 'fixture-valid' &&
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

Finder field(String id) => find.descendant(
  of: find.byWidgetPredicate(
    (w) => w is AppTextField && w.semanticsIdentifier == id,
  ),
  matching: find.byType(CupertinoTextField),
);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fixed login/register form checks invite on OTP request', (
    tester,
  ) async {
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
    expect(gateway.sendOtpCalls, 0);

    await tester.enterText(field('e2e-invite-input'), 'wrong');
    await tapVisible(tester, find.text('发送验证码'));
    expect(gateway.sendOtpCalls, 0);
    expect(find.text('邀请码无效、已过期或已用完，请检查后重试。'), findsOneWidget);

    await tester.enterText(field('e2e-invite-input'), 'fixture-valid');
    await tapVisible(tester, find.text('发送验证码'));
    expect(gateway.sendOtpCalls, 1);
    expect(support.lastInvite, 'fixture-valid');
    expect(tester.takeException(), isNull);
  });

  testWidgets('email activation waits for a valid short-handle invite', (
    tester,
  ) async {
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
    expect(gateway.sendEmailVerificationCalls, 0);

    await tester.enterText(field('e2e-invite-input'), 'wrong');
    await tapVisible(tester, find.text('发送激活邮件'));
    expect(gateway.sendEmailVerificationCalls, 0);
    expect(find.text('邀请码无效、已过期或已用完，请检查后重试。'), findsOneWidget);

    await tester.enterText(field('e2e-invite-input'), 'fixture-valid');
    await tapVisible(tester, find.text('发送激活邮件'));
    expect(gateway.sendEmailVerificationCalls, 1);
    expect(support.lastEmail, 'fixture@example.com');
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
    'existing account keeps recovery available inside the fixed form',
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
      await tapVisible(tester, recovery);
      expect(find.byType(HandleRecoveryPage), findsOneWidget);
      expect(gateway.sendOtpCalls, 1);
      expect(gateway.registerHandleCalls, 0);
    },
  );
}
