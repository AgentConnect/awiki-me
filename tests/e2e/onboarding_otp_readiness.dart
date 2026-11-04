import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';

/// A resend boundary can be visible before its bound OTP target is published.
bool onboardingOtpReceiptReady({
  required OnboardingState onboarding,
  required bool coolingDown,
  required String expectedFullHandle,
  required String expectedPhone,
}) =>
    coolingDown &&
    !onboarding.isBusy &&
    onboarding.canSubmitPhoneOtp &&
    onboarding.otpTargetFullHandle == expectedFullHandle &&
    onboarding.otpTargetPhone == expectedPhone;
