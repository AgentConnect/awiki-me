import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../application/models/app_session.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/repositories/awiki_account_gateway.dart';
import '../../l10n/app_message.dart';
import '../app_shell/providers/app_runtime_provider.dart';

class OnboardingState {
  const OnboardingState({
    this.entryMode = 'register',
    this.authMode = 'phone',
    this.registerStep = 1,
    this.emailVerified = false,
    this.otpResendCountdown = 0,
    this.emailResendCountdown = 0,
    this.isBusy = false,
  });

  final String entryMode;
  final String authMode;
  final int registerStep;
  final bool emailVerified;
  final int otpResendCountdown;
  final int emailResendCountdown;
  final bool isBusy;

  bool get isOtpResendCoolingDown => otpResendCountdown > 0;
  bool get isEmailResendCoolingDown => emailResendCountdown > 0;

  OnboardingState copyWith({
    String? entryMode,
    String? authMode,
    int? registerStep,
    bool? emailVerified,
    int? otpResendCountdown,
    int? emailResendCountdown,
    bool? isBusy,
  }) {
    return OnboardingState(
      entryMode: entryMode ?? this.entryMode,
      authMode: authMode ?? this.authMode,
      registerStep: registerStep ?? this.registerStep,
      emailVerified: emailVerified ?? this.emailVerified,
      otpResendCountdown: otpResendCountdown ?? this.otpResendCountdown,
      emailResendCountdown: emailResendCountdown ?? this.emailResendCountdown,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(this.ref) : super(const OnboardingState());

  final Ref ref;
  static const String phoneAuthBypassOtp = '123456';
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const int _otpResendCooldownSeconds = 60;
  static const int _emailResendCooldownSeconds = 60;
  Timer? _otpResendTimer;
  Timer? _emailResendTimer;

  @override
  void dispose() {
    _otpResendTimer?.cancel();
    _emailResendTimer?.cancel();
    super.dispose();
  }

  void setEntryMode(String value) {
    _setEntryMode(value);
  }

  void setEntryModeFromLocalCredentials(List<SessionIdentity> credentials) {
    final nextMode = credentials.isEmpty ? 'register' : 'login';
    if (state.entryMode == nextMode) {
      return;
    }
    _setEntryMode(nextMode);
  }

  void _setEntryMode(String value) {
    state = state.copyWith(
      entryMode: value,
      registerStep: value == 'login' ? 1 : state.registerStep,
      emailVerified: value == 'login' ? false : state.emailVerified,
      otpResendCountdown: value == 'login' ? 0 : state.otpResendCountdown,
      emailResendCountdown: value == 'login' ? 0 : state.emailResendCountdown,
    );
    if (value == 'login') {
      _cancelOtpResendCountdown();
      _cancelEmailResendCountdown();
    }
  }

  void setAuthMode(String value) {
    state = state.copyWith(
      authMode: value,
      emailVerified: false,
      otpResendCountdown: 0,
      emailResendCountdown: 0,
    );
    _cancelOtpResendCountdown();
    _cancelEmailResendCountdown();
  }

  void setRegisterStep(int step) {
    state = state.copyWith(registerStep: step);
  }

  Future<void> requestOtp(String phone) async {
    var success = false;
    await _runBusy(() async {
      await ref.read(onboardingSupportServiceProvider).sendOtp(phone: phone);
      success = true;
    });
    if (success) {
      _startOtpResendCountdown();
      ref.read(uiFeedbackProvider.notifier).showInfo(AppMessage.otpSent());
    }
  }

  Future<void> requestEmailActivation(String email) async {
    var success = false;
    await _runBusy(() async {
      await ref
          .read(onboardingSupportServiceProvider)
          .sendEmailVerification(email: email);
      success = true;
    });
    if (success) {
      _startEmailResendCountdown();
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.activationEmailSent());
    }
  }

  Future<bool> checkEmailActivation(String email) async {
    var verified = false;
    await _runBusy(() async {
      verified = await ref
          .read(onboardingSupportServiceProvider)
          .checkEmailVerified(email: email);
      if (!verified) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.emailNotActivatedClickLink());
      }
    });
    state = state.copyWith(emailVerified: verified);
    return verified;
  }

  Future<void> registerWithPhone({
    required String phone,
    required String otp,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    await _runBusy(() async {
      final session = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithPhone(
            phone: phone,
            otp: otp,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
          );
      await ref
          .read(appRuntimeProvider.notifier)
          .activateSession(_legacySessionFromAppSession(session));
    });
  }

  Future<void> loginOrRegisterWithPhone({
    required String phone,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    await _runBusy(() async {
      final support = ref.read(onboardingSupportServiceProvider);
      final onboarding = ref.read(onboardingServiceProvider);
      final status = await support.lookupHandleRegistration(handle: handle);
      final session = switch (status) {
        HandleRegistrationStatus.registered => throw StateError(
          'handle_already_registered_import_credential',
        ),
        HandleRegistrationStatus.notRegistered =>
          await onboarding.registerHandleWithPhone(
            phone: phone,
            otp: phoneAuthBypassOtp,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
          ),
      };
      await ref
          .read(appRuntimeProvider.notifier)
          .activateSession(_legacySessionFromAppSession(session));
    });
  }

  Future<void> loginExistingWithOtp({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    await _runBusy(() async {
      final session = await ref
          .read(onboardingServiceProvider)
          .recoverHandle(phone: phone, otp: otp, handle: handle);
      await ref
          .read(appRuntimeProvider.notifier)
          .activateSession(_legacySessionFromAppSession(session));
    });
  }

  Future<void> registerWithEmail({
    required String email,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    await _runBusy(() async {
      final support = ref.read(onboardingSupportServiceProvider);
      final status = await support.lookupHandleRegistration(handle: handle);
      if (status == HandleRegistrationStatus.registered) {
        throw StateError('email_login_unsupported_for_registered_handle');
      }
      final verified = await support.checkEmailVerified(email: email);
      if (!verified) {
        throw StateError('email_not_activated');
      }
      final session = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithEmail(
            email: email,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
          );
      await ref
          .read(appRuntimeProvider.notifier)
          .activateSession(_legacySessionFromAppSession(session));
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    state = state.copyWith(isBusy: true);
    try {
      await action().timeout(_requestTimeout);
    } on TimeoutException {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  void _startEmailResendCountdown() {
    _emailResendTimer?.cancel();
    state = state.copyWith(emailResendCountdown: _emailResendCooldownSeconds);
    _emailResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = state.emailResendCountdown - 1;
      if (next <= 0) {
        timer.cancel();
        state = state.copyWith(emailResendCountdown: 0);
        return;
      }
      state = state.copyWith(emailResendCountdown: next);
    });
  }

  void _startOtpResendCountdown() {
    _otpResendTimer?.cancel();
    state = state.copyWith(otpResendCountdown: _otpResendCooldownSeconds);
    _otpResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = state.otpResendCountdown - 1;
      if (next <= 0) {
        timer.cancel();
        state = state.copyWith(otpResendCountdown: 0);
        return;
      }
      state = state.copyWith(otpResendCountdown: next);
    });
  }

  void _cancelEmailResendCountdown() {
    _emailResendTimer?.cancel();
    _emailResendTimer = null;
  }

  void _cancelOtpResendCountdown() {
    _otpResendTimer?.cancel();
    _otpResendTimer = null;
  }
}

SessionIdentity _legacySessionFromAppSession(AppSession session) {
  return session.toLegacySessionIdentity();
}

final onboardingProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>(
      (ref) => OnboardingController(ref),
    );
