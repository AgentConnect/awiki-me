import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../application/models/app_session.dart';
import '../../application/models/onboarding_server_info.dart';
import '../../application/ports/identity_core_port.dart';
import '../../application/ports/legacy_identity_upgrade_port.dart';
import '../../domain/entities/session_identity.dart';
import '../../l10n/app_message.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../devices/devices_provider.dart';

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
    this.legacyUpgradeStatus = const LegacyIdentityUpgradeStatus.idle(),
    this.otpTargetFullHandle,
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
  final LegacyIdentityUpgradeStatus legacyUpgradeStatus;
  final String? otpTargetFullHandle;
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
  bool get isLegacyUpgradeRunning =>
      legacyUpgradeStatus.phase == LegacyIdentityUpgradePhase.running;
  bool get isLegacyUpgradeRetryRequired =>
      legacyUpgradeStatus.phase == LegacyIdentityUpgradePhase.retryRequired;
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
    LegacyIdentityUpgradeStatus? legacyUpgradeStatus,
    Object? otpTargetFullHandle = _unset,
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
      legacyUpgradeStatus: legacyUpgradeStatus ?? this.legacyUpgradeStatus,
      otpTargetFullHandle: identical(otpTargetFullHandle, _unset)
          ? this.otpTargetFullHandle
          : otpTargetFullHandle as String?,
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

  Future<void> requestOtp({
    required String phone,
    required String handle,
    required String handleDomain,
  }) async {
    if (!state.supportsPhoneOtpRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return;
    }
    String? fullHandle;
    var success = false;
    await _runBusy(() async {
      final normalizedHandle = _normalizeHandleForOtp(handle);
      final domain = _normalizeHandleDomain(handleDomain);
      fullHandle = '$normalizedHandle.$domain';
      await ref
          .read(onboardingSupportServiceProvider)
          .sendRegistrationOtp(
            phone: phone,
            handle: normalizedHandle,
            domain: domain,
            fullHandle: fullHandle!,
          );
      success = true;
    });
    if (success) {
      state = state.copyWith(otpTargetFullHandle: fullHandle!);
      _startOtpResendCountdown();
      ref.read(uiFeedbackProvider.notifier).showInfo(AppMessage.otpSent());
    }
  }

  void resetPhoneOtpTarget() {
    if (state.otpResendCountdown == 0 && state.otpTargetFullHandle == null) {
      return;
    }
    _cancelOtpResendCountdown();
    state = state.copyWith(otpResendCountdown: 0, otpTargetFullHandle: null);
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

  Future<IdentityRegistrationStatus?> registerWithPhone({
    required String phone,
    required String otp,
    required String handle,
    required String handleDomain,
    required String nickName,
    required String profileMarkdown,
  }) async {
    if (!state.supportsPhoneOtpRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return null;
    }
    final domain = _normalizeHandleDomain(handleDomain);
    final normalizedHandle = handle.trim().toLowerCase();
    if (state.otpTargetFullHandle != '$normalizedHandle.$domain') {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.operationFailedRetry());
      return null;
    }
    return _runBusy(() async {
      final result = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithPhone(
            phone: phone,
            otp: otp,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
          );
      return _activateRegistrationResult(result);
    });
  }

  Future<IdentityRegistrationStatus?> registerWithEmail({
    required String email,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    if (!state.supportsEmailRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return null;
    }
    return _runBusy(() async {
      final support = ref.read(onboardingSupportServiceProvider);
      final verified = await support.checkEmailVerified(
        email: email,
        handle: handle,
      );
      if (!verified) {
        throw StateError('email_not_activated');
      }
      final result = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithEmail(
            email: email,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
          );
      return _activateRegistrationResult(result);
    });
  }

  Future<IdentityRegistrationStatus?> registerWithoutContactVerification({
    required String phone,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    if (!state.supportsPhoneNoVerificationRegistration) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.registrationMethodUnavailable());
      return null;
    }
    return _runBusy(() async {
      final result = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithoutContactVerification(
            phone: phone,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
          );
      return _activateRegistrationResult(result);
    });
  }

  Future<IdentityRegistrationStatus> _activateRegistrationResult(
    IdentityRegistrationResult result,
  ) async {
    if (result.status == IdentityRegistrationStatus.joinRequired) {
      final progress = result.joinProgress;
      if (progress == null) {
        throw StateError(
          'Join-required registration did not include Join progress.',
        );
      }
      ref.read(devicesProvider.notifier).resume(progress);
      return IdentityRegistrationStatus.joinRequired;
    }
    final session = result.identity;
    if (session == null) {
      throw StateError('Registered result did not include an identity.');
    }
    await ref
        .read(appRuntimeProvider.notifier)
        .activateSession(_legacySessionFromAppSession(session));
    return IdentityRegistrationStatus.registered;
  }

  Future<void> loginWithLocalCredential(String identityIdOrAlias) {
    return _resumeLegacyUpgradeAndLogin(
      identityIdOrAlias,
      inspectBeforeUpgrade: true,
    );
  }

  Future<void> retryLegacyUpgrade() async {
    final identityId = state.legacyUpgradeStatus.identityId;
    if (identityId == null || identityId.isEmpty) {
      return;
    }
    await _resumeLegacyUpgradeAndLogin(identityId, inspectBeforeUpgrade: false);
  }

  Future<void> _resumeLegacyUpgradeAndLogin(
    String identityIdOrAlias, {
    required bool inspectBeforeUpgrade,
  }) async {
    if (state.isLegacyUpgradeRunning) {
      return;
    }
    state = state.copyWith(
      legacyUpgradeStatus: const LegacyIdentityUpgradeStatus.running(),
    );
    try {
      var status = inspectBeforeUpgrade
          ? await ref
                .read(onboardingServiceProvider)
                .legacyUpgradeStatus(identityIdOrAlias)
                .timeout(_requestTimeout)
          : const LegacyIdentityUpgradeStatus.idle();
      if (status.phase == LegacyIdentityUpgradePhase.idle ||
          status.phase == LegacyIdentityUpgradePhase.running) {
        status = await ref
            .read(onboardingServiceProvider)
            .upgradeLegacyIdentity(identityIdOrAlias)
            .timeout(_requestTimeout);
      }
      switch (status.phase) {
        case LegacyIdentityUpgradePhase.completed:
          state = state.copyWith(legacyUpgradeStatus: status);
          await ref
              .read(appRuntimeProvider.notifier)
              .loginWithLocalCredential(identityIdOrAlias);
        case LegacyIdentityUpgradePhase.retryRequired:
          state = state.copyWith(legacyUpgradeStatus: status);
        case LegacyIdentityUpgradePhase.idle:
        case LegacyIdentityUpgradePhase.running:
          state = state.copyWith(
            legacyUpgradeStatus: LegacyIdentityUpgradeStatus.retryRequired(
              identityId: identityIdOrAlias,
            ),
          );
      }
    } on Object {
      state = state.copyWith(
        legacyUpgradeStatus: LegacyIdentityUpgradeStatus.retryRequired(
          identityId: identityIdOrAlias,
        ),
      );
    }
  }

  Future<T?> _runBusy<T>(Future<T> Function() action) async {
    state = state.copyWith(isBusy: true);
    try {
      return await action().timeout(_requestTimeout);
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
    return null;
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
      otpTargetFullHandle: authChanged || method == null
          ? null
          : state.otpTargetFullHandle,
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

String _normalizeHandleForOtp(String handle) {
  final raw = handle.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9-]{2,32}$').hasMatch(raw)) {
    throw ArgumentError('handle_invalid_pattern');
  }
  return raw;
}

String _normalizeHandleDomain(String domain) {
  final normalized = domain.trim().toLowerCase().replaceFirst(
    RegExp(r'\.$'),
    '',
  );
  if (normalized.isEmpty || !normalized.contains('.')) {
    throw ArgumentError('did_domain_invalid');
  }
  return normalized;
}

SessionIdentity _legacySessionFromAppSession(AppSession session) {
  return session.toLegacySessionIdentity();
}

final onboardingProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>(
      (ref) => OnboardingController(ref),
    );
