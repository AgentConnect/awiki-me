import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../application/models/app_session.dart';
import '../../application/models/onboarding_server_info.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/repositories/awiki_account_gateway.dart';
import '../../l10n/app_message.dart';
import '../app_shell/providers/app_runtime_provider.dart';

const Object _unset = Object();

enum OnboardingServerInfoStatus { loading, ready, failed }

class OnboardingState {
  const OnboardingState({
    this.entryMode = 'register',
    this.authMode = 'phone',
    this.registerStep = 1,
    this.emailVerified = false,
    this.otpResendCountdown = 0,
    this.emailResendCountdown = 0,
    this.isBusy = false,
    this.serverInfoStatus = OnboardingServerInfoStatus.loading,
    this.serverInfo,
    this.serverInfoError,
  });

  final String entryMode;
  final String authMode;
  final int registerStep;
  final bool emailVerified;
  final int otpResendCountdown;
  final int emailResendCountdown;
  final bool isBusy;
  final OnboardingServerInfoStatus serverInfoStatus;
  final OnboardingServerInfo? serverInfo;
  final String? serverInfoError;

  bool get isOtpResendCoolingDown => otpResendCountdown > 0;
  bool get isEmailResendCoolingDown => emailResendCountdown > 0;
  bool get isServerInfoLoading =>
      serverInfoStatus == OnboardingServerInfoStatus.loading;
  bool get isServerInfoReady =>
      serverInfoStatus == OnboardingServerInfoStatus.ready;
  bool get isServerInfoFailed =>
      serverInfoStatus == OnboardingServerInfoStatus.failed;
  bool get hasRegistrationMethods => registrationMethods.isNotEmpty;

  List<OnboardingIdentityMethod> get registrationMethods {
    return serverInfo?.registrationMethods ??
        const <OnboardingIdentityMethod>[];
  }

  OnboardingIdentityMethodId? get selectedMethodId {
    return OnboardingIdentityMethodId.parse(authMode);
  }

  OnboardingIdentityMethod? get selectedRegistrationMethod {
    final id = selectedMethodId;
    if (id == null) {
      return null;
    }
    return serverInfo?.registrationMethod(id);
  }

  bool get supportsEmailRegistration {
    return serverInfo?.supportsEmailActivationRegistration ?? false;
  }

  bool get supportsPhoneOtpRegistration {
    return serverInfo?.supportsPhoneOtpRegistration ?? false;
  }

  bool get supportsPhoneNoVerificationRegistration {
    return serverInfo?.supportsPhoneNoVerificationRegistration ?? false;
  }

  bool get supportsPhoneOtpRecovery {
    return serverInfo?.supportsPhoneOtpRecovery ?? false;
  }

  bool get usesNoVerificationRegistration {
    final method = selectedRegistrationMethod;
    return method != null &&
        method.verification.type == OnboardingVerificationType.none &&
        !method.verification.required;
  }

  OnboardingState copyWith({
    String? entryMode,
    String? authMode,
    int? registerStep,
    bool? emailVerified,
    int? otpResendCountdown,
    int? emailResendCountdown,
    bool? isBusy,
    OnboardingServerInfoStatus? serverInfoStatus,
    Object? serverInfo = _unset,
    Object? serverInfoError = _unset,
  }) {
    return OnboardingState(
      entryMode: entryMode ?? this.entryMode,
      authMode: authMode ?? this.authMode,
      registerStep: registerStep ?? this.registerStep,
      emailVerified: emailVerified ?? this.emailVerified,
      otpResendCountdown: otpResendCountdown ?? this.otpResendCountdown,
      emailResendCountdown: emailResendCountdown ?? this.emailResendCountdown,
      isBusy: isBusy ?? this.isBusy,
      serverInfoStatus: serverInfoStatus ?? this.serverInfoStatus,
      serverInfo: identical(serverInfo, _unset)
          ? this.serverInfo
          : serverInfo as OnboardingServerInfo?,
      serverInfoError: identical(serverInfoError, _unset)
          ? this.serverInfoError
          : serverInfoError as String?,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(this.ref) : super(const OnboardingState());

  final Ref ref;
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
    final method = _registrationMethodForAuthMode(value);
    if (state.isServerInfoReady && method == null) {
      return;
    }
    state = state.copyWith(
      authMode: value,
      registerStep: 1,
      emailVerified: false,
      otpResendCountdown: 0,
      emailResendCountdown: 0,
    );
    _cancelOtpResendCountdown();
    _cancelEmailResendCountdown();
  }

  void setRegisterStep(int step) {
    if (state.usesNoVerificationRegistration && step != 1) {
      return;
    }
    state = state.copyWith(registerStep: step);
  }

  Future<void> loadServerInfo({bool force = false}) async {
    if (!force &&
        (state.isServerInfoReady ||
            state.isServerInfoLoading && state.serverInfo != null)) {
      return;
    }
    state = state.copyWith(
      serverInfoStatus: OnboardingServerInfoStatus.loading,
      serverInfoError: null,
    );
    try {
      final info = await ref
          .read(onboardingSupportServiceProvider)
          .loadServerInfo()
          .timeout(_requestTimeout);
      _applyServerInfo(info);
    } on TimeoutException {
      state = state.copyWith(
        serverInfoStatus: OnboardingServerInfoStatus.failed,
        serverInfoError: 'request_timeout_retry',
      );
    } catch (error) {
      state = state.copyWith(
        serverInfoStatus: OnboardingServerInfoStatus.failed,
        serverInfoError: error.toString(),
      );
    }
  }

  Future<void> requestOtp(String phone) async {
    if (!state.supportsPhoneOtpRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
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

  Future<void> requestEmailActivation({
    required String email,
    required String handle,
  }) async {
    if (!state.supportsEmailRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
    var success = false;
    await _runBusy(() async {
      final support = ref.read(onboardingSupportServiceProvider);
      final status = await support.lookupHandleRegistration(handle: handle);
      if (status == HandleRegistrationStatus.registered) {
        throw StateError('email_login_unsupported_for_registered_handle');
      }
      await support.sendEmailVerification(email: email, handle: handle);
      success = true;
    });
    if (success) {
      _startEmailResendCountdown();
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.activationEmailSent());
    }
  }

  Future<bool> checkEmailActivation({
    required String email,
    required String handle,
  }) async {
    if (!state.supportsEmailRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return false;
    }
    var verified = false;
    await _runBusy(() async {
      verified = await ref
          .read(onboardingSupportServiceProvider)
          .checkEmailVerified(email: email, handle: handle);
      if (!verified) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.emailNotActivatedClickLink());
      }
    });
    state = state.copyWith(emailVerified: verified);
    return verified;
  }

  void resetEmailActivation() {
    if (!state.emailVerified && state.emailResendCountdown == 0) {
      return;
    }
    _cancelEmailResendCountdown();
    state = state.copyWith(emailVerified: false, emailResendCountdown: 0);
  }

  Future<void> registerWithPhone({
    required String phone,
    required String otp,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    if (!state.supportsPhoneOtpRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
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
    required String otp,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    if (!state.supportsPhoneOtpRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
    await _runBusy(() async {
      final support = ref.read(onboardingSupportServiceProvider);
      final onboarding = ref.read(onboardingServiceProvider);
      final status = await support.lookupHandleRegistration(handle: handle);
      final session = switch (status) {
        HandleRegistrationStatus.registered =>
          state.supportsPhoneOtpRecovery
              ? await onboarding.recoverHandle(
                  phone: phone,
                  otp: otp,
                  handle: handle,
                )
              : throw StateError('handle_recovery_unsupported'),
        HandleRegistrationStatus.notRegistered =>
          await onboarding.registerHandleWithPhone(
            phone: phone,
            otp: otp,
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
    if (!state.supportsPhoneOtpRecovery) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
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
    if (!state.supportsEmailRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
    await _runBusy(() async {
      final support = ref.read(onboardingSupportServiceProvider);
      final status = await support.lookupHandleRegistration(handle: handle);
      if (status == HandleRegistrationStatus.registered) {
        throw StateError('email_login_unsupported_for_registered_handle');
      }
      final verified = await support.checkEmailVerified(
        email: email,
        handle: handle,
      );
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

  Future<void> registerWithoutContactVerification({
    required String phone,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    if (!state.supportsPhoneNoVerificationRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
    await _runBusy(() async {
      final support = ref.read(onboardingSupportServiceProvider);
      final status = await support.lookupHandleRegistration(handle: handle);
      if (status == HandleRegistrationStatus.registered) {
        throw StateError('handle_already_registered_import_credential');
      }
      final session = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithoutContactVerification(
            phone: phone,
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

  void _applyServerInfo(OnboardingServerInfo info) {
    final nextAuthMode = _nextAuthMode(info);
    final method = nextAuthMode == null
        ? null
        : info.registrationMethod(
            OnboardingIdentityMethodId.parse(nextAuthMode)!,
          );
    final authChanged = nextAuthMode != null && nextAuthMode != state.authMode;
    if (authChanged || method == null) {
      _cancelOtpResendCountdown();
      _cancelEmailResendCountdown();
    }
    state = state.copyWith(
      authMode: nextAuthMode ?? state.authMode,
      registerStep: method?.verification.type == OnboardingVerificationType.none
          ? 1
          : state.registerStep,
      emailVerified: authChanged ? false : state.emailVerified,
      otpResendCountdown: authChanged || method == null
          ? 0
          : state.otpResendCountdown,
      emailResendCountdown: authChanged || method == null
          ? 0
          : state.emailResendCountdown,
      serverInfoStatus: OnboardingServerInfoStatus.ready,
      serverInfo: info,
      serverInfoError: null,
    );
  }

  String? _nextAuthMode(OnboardingServerInfo info) {
    final currentId = OnboardingIdentityMethodId.parse(state.authMode);
    if (currentId != null && info.registrationMethod(currentId) != null) {
      return currentId.wireName;
    }
    return info.defaultRegistrationMethod?.id.wireName;
  }

  OnboardingIdentityMethod? _registrationMethodForAuthMode(String authMode) {
    final id = OnboardingIdentityMethodId.parse(authMode);
    if (id == null) {
      return null;
    }
    return state.serverInfo?.registrationMethod(id);
  }
}

SessionIdentity _legacySessionFromAppSession(AppSession session) {
  return session.toLegacySessionIdentity();
}

final onboardingProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>(
      (ref) => OnboardingController(ref),
    );
