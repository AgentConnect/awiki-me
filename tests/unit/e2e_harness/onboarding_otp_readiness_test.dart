import 'dart:async';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/sms_otp_cooldown_service.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/shared/sms_otp_cooldown_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/onboarding_otp_readiness.dart';
import '../test_support.dart';

void main() {
  test(
    'resend countdown before persisted OTP target is not submit readiness',
    () async {
      final gateway = FakeAwikiGateway();
      final storage = _DelayedCooldown();
      final container = ProviderContainer(
        overrides: [
          identityCorePortProvider.overrideWithValue(FakeIdentityCorePort()),
          onboardingSupportServiceProvider.overrideWithValue(
            FakeOnboardingSupportService(gateway),
          ),
          smsOtpCooldownServiceProvider.overrideWithValue(storage),
          appSessionServiceProvider.overrideWithValue(
            FakeAppSessionService(gateway),
          ),
        ],
      );
      final controller = container.read(onboardingProvider.notifier);
      await controller.loadServerInfo();
      final request = controller.requestOtp(
        phone: '+8613800138000',
        handle: 'alice',
        handleDomain: 'awiki.ai',
      );
      addTearDown(() async {
        if (!storage.release.isCompleted) storage.release.complete();
        await request;
        container.dispose();
      });
      await storage.started.future;
      bool ready() => onboardingOtpReceiptReady(
        onboarding: container.read(onboardingProvider),
        coolingDown: container.read(smsOtpCooldownProvider).isCoolingDown,
        expectedFullHandle: 'alice.awiki.ai',
        expectedPhone: '+8613800138000',
      );
      expect(container.read(smsOtpCooldownProvider).isCoolingDown, isTrue);
      expect(container.read(onboardingProvider).canSubmitPhoneOtp, isFalse);
      expect(
        ready(),
        isFalse,
        reason: 'countdown can precede the bound OTP target',
      );
      storage.release.complete();
      await request;
      expect(ready(), isTrue);
    },
  );

  test('receipt must match the exact unconsumed target and be idle', () {
    const state = OnboardingState(
      otpTargetFullHandle: 'alice.example.test',
      otpTargetPhone: 'PRIVATE_PHONE',
    );
    bool ready(
      OnboardingState value, {
      String handle = 'alice.example.test',
      String phone = 'PRIVATE_PHONE',
    }) => onboardingOtpReceiptReady(
      onboarding: value,
      coolingDown: true,
      expectedFullHandle: handle,
      expectedPhone: phone,
    );
    expect(ready(state), isTrue);
    expect(ready(state, handle: 'other.example.test'), isFalse);
    expect(ready(state, phone: 'OTHER_PRIVATE_PHONE'), isFalse);
    expect(ready(state.copyWith(isPhoneOtpConsumed: true)), isFalse);
    expect(ready(state.copyWith(isBusy: true)), isFalse);
  });
}

class _DelayedCooldown extends NoopSmsOtpCooldownService {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> saveRetryAt(
    DateTime retryAt, {
    SmsOtpCooldownPurpose purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) async {
    started.complete();
    await release.future;
  }
}
