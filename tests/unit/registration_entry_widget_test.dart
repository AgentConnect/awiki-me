import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/onboarding_support_service.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

class InviteSupport extends FakeOnboardingSupportService {
  InviteSupport(super.gateway);
  int checks = 0;
  String? lastInvite;
  String? lastEmail;
  String decision = 'register';
  bool fail = false;

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
    final required = decision == 'register';
    return RegistrationCheck(
      fullHandle: '$handle.$domain',
      decision: decision,
      inviteRequired: required,
      inviteStatus: !required
          ? 'not_required'
          : !checkInvite
          ? 'required'
          : inviteCode == 'fixture-valid'
          ? 'valid'
          : 'invalid',
      reason: checkInvite && required && inviteCode != 'fixture-valid'
          ? 'invite_invalid'
          : null,
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
  for (final desktop in [false, true]) {
    for (final email in [false, true]) {
      testWidgets(
        '${desktop ? "desktop" : "mobile"}: account then mandatory invite then ${email ? 'email' : 'OTP'}',
        (tester) async {
          debugDefaultTargetPlatformOverride = desktop
              ? TargetPlatform.macOS
              : TargetPlatform.android;
          tester.view.physicalSize = desktop
              ? const Size(1200, 1000)
              : const Size(390, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final gateway = FakeAwikiGateway()..emailVerificationResult = true;
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
          expect(find.text('发送验证码'), findsNothing);
          await tester.enterText(field('e2e-handle-input'), 'abc');
          await tapVisible(tester, find.text('下一步'));
          expect(field('e2e-invite-input'), findsOneWidget);
          expect(find.text('发送验证码'), findsNothing);
          await tapVisible(tester, find.text('下一步'));
          expect(
            find.byKey(const Key('registration-entry-error')),
            findsOneWidget,
          );
          expect(gateway.sendOtpCalls, 0);
          await tester.enterText(field('e2e-invite-input'), 'wrong');
          await tapVisible(tester, find.text('下一步'));
          // Desktop retains its existing outlined fields; semantics select the
          // nested Cupertino field independently of the shared/mobile component.
          if (email) {
            await tapVisible(tester, find.byKey(const Key('auth-mode-email')));
          }
          final fields = find.byType(CupertinoTextField);
          await tester.enterText(
            email && !desktop
                ? field('e2e-email-input')
                : fields.at(email ? 1 : 0),
            email ? 'fixture@example.com' : '13800138000',
          );
          final sendLabel = email ? '发送激活邮件' : '发送验证码';
          await tapVisible(tester, find.text(sendLabel));
          expect(gateway.sendOtpCalls, 0);
          expect(gateway.sendEmailVerificationCalls, 0);
          expect(find.textContaining('邀请码无效'), findsOneWidget);
          await tapVisible(tester, find.text('返回修改账号或邀请码'));
          await tapVisible(tester, find.text('下一步'));
          await tester.enterText(field('e2e-invite-input'), 'fixture-valid');
          await tapVisible(tester, find.text('下一步'));
          await tapVisible(tester, find.text(sendLabel));
          expect(support.lastInvite, 'fixture-valid');
          if (email) {
            expect(gateway.sendEmailVerificationCalls, 1);
            expect(support.lastEmail, 'fixture@example.com');
            expect(gateway.sendOtpCalls, 0);
            await tapVisible(tester, find.text('我已激活，检查状态'));
            await tapVisible(tester, find.text('完成注册'));
            expect(gateway.registerHandleWithEmailCalls, 1);
          } else {
            expect(gateway.sendOtpCalls, 1);
            await tester.enterText(
              find.byType(CupertinoTextField).at(2),
              '123456',
            );
            await tapVisible(tester, find.text('登录/注册'));
            expect(gateway.registerHandleCalls, 1);
          }
          expect(gateway.lastRegisteredInviteCode, 'fixture-valid');
          expect(tester.takeException(), isNull);
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  testWidgets(
    'existing short account can verify without invitation during discovery failure',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
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
      await tapVisible(tester, find.text('下一步'));
      expect(find.textContaining('暂时无法检查账号'), findsOneWidget);
      await tapVisible(tester, find.text('已有账号，继续登录'));
      await tester.enterText(
        find.byType(CupertinoTextField).at(0),
        '13800138000',
      );
      await tapVisible(tester, find.text('发送验证码'));
      expect(gateway.sendOtpCalls, 1);
      expect(field('e2e-invite-input'), findsNothing);
      expect(support.checks, 1);
    },
  );
}
