import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../application/app_session_service.dart';
import '../../application/models/onboarding_server_info.dart';
import '../../application/onboarding_support_service.dart';
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
    this.emailVerified = false,
    this.otpResendCountdown = 0,
    this.emailResendCountdown = 0,
    this.isBusy = false,
    this.legacyUpgradeStatus = const LegacyIdentityUpgradeStatus.idle(),
    this.otpTargetFullHandle,
    this.otpTargetPhone,
    this.otpCooldownPhone,
    this.otpRetryAt,
    this.serverInfoStatus = OnboardingServerInfoStatus.loading,
    this.serverInfo,
    this.serverInfoError,
  });

  final String entryMode;
  final String authMode;
  final bool emailVerified;
  final int otpResendCountdown;
  final int emailResendCountdown;
  final bool isBusy;
  final LegacyIdentityUpgradeStatus legacyUpgradeStatus;
  final String? otpTargetFullHandle;
  final String? otpTargetPhone;
  final String? otpCooldownPhone;
  final DateTime? otpRetryAt;
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
    bool? emailVerified,
    int? otpResendCountdown,
    int? emailResendCountdown,
    bool? isBusy,
    LegacyIdentityUpgradeStatus? legacyUpgradeStatus,
    Object? otpTargetFullHandle = _unset,
    Object? otpTargetPhone = _unset,
    Object? otpCooldownPhone = _unset,
    Object? otpRetryAt = _unset,
    OnboardingServerInfoStatus? serverInfoStatus,
    Object? serverInfo = _unset,
    Object? serverInfoError = _unset,
  }) {
    return OnboardingState(
      entryMode: entryMode ?? this.entryMode,
      authMode: authMode ?? this.authMode,
      emailVerified: emailVerified ?? this.emailVerified,
      otpResendCountdown: otpResendCountdown ?? this.otpResendCountdown,
      emailResendCountdown: emailResendCountdown ?? this.emailResendCountdown,
      isBusy: isBusy ?? this.isBusy,
      legacyUpgradeStatus: legacyUpgradeStatus ?? this.legacyUpgradeStatus,
      otpTargetFullHandle: identical(otpTargetFullHandle, _unset)
          ? this.otpTargetFullHandle
          : otpTargetFullHandle as String?,
      otpTargetPhone: identical(otpTargetPhone, _unset)
          ? this.otpTargetPhone
          : otpTargetPhone as String?,
      otpCooldownPhone: identical(otpCooldownPhone, _unset)
          ? this.otpCooldownPhone
          : otpCooldownPhone as String?,
      otpRetryAt: identical(otpRetryAt, _unset)
          ? this.otpRetryAt
          : otpRetryAt as DateTime?,
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
  OnboardingController(
    this.ref, {
    Duration requestTimeout = const Duration(seconds: 20),
  }) : _requestTimeout = requestTimeout,
       super(const OnboardingState());

  final Ref ref;
  final Duration _requestTimeout;
  late final AppSessionService _sessionService = ref.read(
    appSessionServiceProvider,
  );
  static const int _emailResendCooldownSeconds = 60;
  Timer? _otpResendTimer;
  Timer? _emailResendTimer;
  final Map<String, DateTime> _otpRetryAtByPhone = <String, DateTime>{};
  int _busyGeneration = 0;
  AppSessionTransition? _activeSessionTransition;

  @override
  void dispose() {
    final transition = _activeSessionTransition;
    if (transition != null) {
      unawaited(_cancelOrAbortSessionTransition(transition));
      _activeSessionTransition = null;
    }
    _busyGeneration += 1;
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
      emailVerified: value == 'login' ? false : state.emailVerified,
      otpResendCountdown: value == 'login' ? 0 : state.otpResendCountdown,
      otpTargetFullHandle: value == 'login' ? null : state.otpTargetFullHandle,
      otpTargetPhone: value == 'login' ? null : state.otpTargetPhone,
      otpCooldownPhone: value == 'login' ? null : state.otpCooldownPhone,
      otpRetryAt: value == 'login' ? null : state.otpRetryAt,
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
      emailVerified: false,
      otpResendCountdown: 0,
      otpTargetFullHandle: null,
      otpTargetPhone: null,
      otpCooldownPhone: null,
      otpRetryAt: null,
      emailResendCountdown: 0,
    );
    _cancelOtpResendCountdown();
    _cancelEmailResendCountdown();
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
    RegistrationOtpSendReceipt? receipt;
    final normalizedPhone = _normalizePhoneForOtpCooldown(phone);
    var success = false;
    await _runBusy(() async {
      final normalizedHandle = _normalizeHandleForOtp(handle);
      final domain = _normalizeHandleDomain(handleDomain);
      fullHandle = '$normalizedHandle.$domain';
      try {
        receipt = await ref
            .read(onboardingSupportServiceProvider)
            .sendRegistrationOtp(
              phone: phone,
              handle: normalizedHandle,
              domain: domain,
              fullHandle: fullHandle!,
            );
      } on RegistrationOtpRateLimited catch (error) {
        if (normalizedPhone != null) {
          _recordOtpRetryBoundary(normalizedPhone, error.retryAt);
        }
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.otpRateLimited(error.retryAfterSeconds));
        return;
      }
      success = true;
    });
    if (success && receipt != null && normalizedPhone != null) {
      state = state.copyWith(
        otpTargetFullHandle: fullHandle!,
        otpTargetPhone: normalizedPhone,
      );
      _recordOtpRetryBoundary(normalizedPhone, receipt!.retryAt);
      ref.read(uiFeedbackProvider.notifier).showInfo(AppMessage.otpSent());
    }
  }

  void resetPhoneOtpTarget() {
    if (state.otpTargetFullHandle == null && state.otpTargetPhone == null) {
      return;
    }
    state = state.copyWith(otpTargetFullHandle: null, otpTargetPhone: null);
  }

  void updateOtpPhone(String phone) {
    final normalizedPhone = _normalizePhoneForOtpCooldown(phone);
    final phoneChanged = normalizedPhone != state.otpCooldownPhone;
    if (!phoneChanged && state.otpTargetPhone == normalizedPhone) {
      return;
    }
    state = state.copyWith(otpTargetFullHandle: null, otpTargetPhone: null);
    if (!phoneChanged) {
      return;
    }
    _showOtpRetryBoundaryForPhone(normalizedPhone);
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
    final normalizedPhone = _normalizePhoneForOtpCooldown(phone);
    if (normalizedPhone == null ||
        state.otpTargetPhone != normalizedPhone ||
        state.otpTargetFullHandle != '$normalizedHandle.$domain') {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.operationFailedRetry());
      return null;
    }
    final transition = _sessionService.beginSessionTransition();
    return _runBusy(() async {
      final result = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithPhone(
            phone: phone,
            otp: otp,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
            transition: transition,
          );
      return _activateRegistrationResult(result, transition);
    }, sessionTransition: transition);
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
    final transition = _sessionService.beginSessionTransition();
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
            transition: transition,
          );
      return _activateRegistrationResult(result, transition);
    }, sessionTransition: transition);
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
    final transition = _sessionService.beginSessionTransition();
    return _runBusy(() async {
      final result = await ref
          .read(onboardingServiceProvider)
          .registerHandleWithoutContactVerification(
            phone: phone,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
            transition: transition,
          );
      return _activateRegistrationResult(result, transition);
    }, sessionTransition: transition);
  }

  Future<IdentityRegistrationStatus> _activateRegistrationResult(
    IdentityRegistrationResult result,
    AppSessionTransition transition,
  ) async {
    if (result.status == IdentityRegistrationStatus.joinRequired) {
      if (!_sessionService.isLatestSessionTransition(transition)) {
        throw const AppSessionTransitionSuperseded();
      }
      final progress = result.joinProgress;
      if (progress == null) {
        throw StateError(
          'Join-required registration did not include Join progress.',
        );
      }
      ref.read(devicesProvider.notifier).resumeNewDevice(progress);
      return IdentityRegistrationStatus.joinRequired;
    }
    final session = result.identity;
    if (session == null) {
      throw StateError('Registered result did not include an identity.');
    }
    if (!_sessionService.isSessionTransitionCurrent(transition)) {
      throw const AppSessionTransitionSuperseded();
    }
    await ref
        .read(appRuntimeProvider.notifier)
        .activateCommittedSession(session, expectedTransition: transition);
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
          : const LegacyIdentityUpgradeStatus.idle();
      if (status.phase == LegacyIdentityUpgradePhase.idle ||
          status.phase == LegacyIdentityUpgradePhase.running) {
        status = await ref
            .read(onboardingServiceProvider)
            .upgradeLegacyIdentity(identityIdOrAlias);
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
              failureCode: status.failureCode ?? 'legacy_upgrade_failed',
            ),
          );
      }
    } on Object {
      state = state.copyWith(
        legacyUpgradeStatus: LegacyIdentityUpgradeStatus.retryRequired(
          identityId: identityIdOrAlias,
          failureCode: 'legacy_upgrade_failed',
        ),
      );
    }
  }

  Future<T?> _runBusy<T>(
    Future<T> Function() action, {
    AppSessionTransition? sessionTransition,
  }) async {
    final generation = ++_busyGeneration;
    if (sessionTransition != null) {
      _activeSessionTransition = sessionTransition;
    }
    state = state.copyWith(isBusy: true);
    try {
      return await action().timeout(_requestTimeout);
    } on TimeoutException {
      await _cancelOrAbortSessionTransition(sessionTransition);
      if (generation != _busyGeneration) {
        return null;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
    } on AppSessionTransitionSuperseded {
      await _cancelOrAbortSessionTransition(sessionTransition);
      return null;
    } catch (error) {
      await _cancelOrAbortSessionTransition(sessionTransition);
      if (generation != _busyGeneration) {
        return null;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      if (identical(_activeSessionTransition, sessionTransition)) {
        _activeSessionTransition = null;
      }
      if (generation == _busyGeneration) {
        state = state.copyWith(isBusy: false);
      }
    }
    return null;
  }

  Future<void> _cancelOrAbortSessionTransition(
    AppSessionTransition? transition,
  ) async {
    if (transition == null) {
      return;
    }
    _sessionService.cancelPendingSessionTransition(transition);
    final lease = await _sessionService.currentSessionLease();
    if (lease != null && identical(lease.transition, transition)) {
      await _sessionService.abortSessionIfCurrent(lease);
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

  void _recordOtpRetryBoundary(String phone, DateTime retryAt) {
    final authoritative = retryAt.toUtc();
    _otpRetryAtByPhone[phone] = authoritative;
    _showOtpRetryBoundaryForPhone(phone);
  }

  void _showOtpRetryBoundaryForPhone(String? phone) {
    _otpResendTimer?.cancel();
    if (phone == null) {
      state = state.copyWith(
        otpResendCountdown: 0,
        otpCooldownPhone: null,
        otpRetryAt: null,
      );
      return;
    }
    final retryAt = _otpRetryAtByPhone[phone];
    final remaining = _otpSecondsRemaining(retryAt);
    if (retryAt == null || remaining == 0) {
      _otpRetryAtByPhone.remove(phone);
      state = state.copyWith(
        otpResendCountdown: 0,
        otpCooldownPhone: phone,
        otpRetryAt: null,
      );
      return;
    }
    state = state.copyWith(
      otpResendCountdown: remaining,
      otpCooldownPhone: phone,
      otpRetryAt: retryAt,
    );
    _otpResendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.otpCooldownPhone != phone || state.otpRetryAt != retryAt) {
        timer.cancel();
        return;
      }
      final next = _otpSecondsRemaining(retryAt);
      if (next == 0) {
        timer.cancel();
        _otpRetryAtByPhone.remove(phone);
        state = state.copyWith(otpResendCountdown: 0, otpRetryAt: null);
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
      emailVerified: authChanged ? false : state.emailVerified,
      otpResendCountdown: authChanged || method == null
          ? 0
          : state.otpResendCountdown,
      otpTargetFullHandle: authChanged || method == null
          ? null
          : state.otpTargetFullHandle,
      otpTargetPhone: authChanged || method == null
          ? null
          : state.otpTargetPhone,
      otpCooldownPhone: authChanged || method == null
          ? null
          : state.otpCooldownPhone,
      otpRetryAt: authChanged || method == null ? null : state.otpRetryAt,
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

int _otpSecondsRemaining(DateTime? retryAt) {
  if (retryAt == null) {
    return 0;
  }
  final milliseconds = retryAt
      .toUtc()
      .difference(DateTime.now().toUtc())
      .inMilliseconds;
  if (milliseconds <= 0) {
    return 0;
  }
  return (milliseconds / Duration.millisecondsPerSecond).ceil();
}

String? _normalizePhoneForOtpCooldown(String phone) {
  final raw = phone.trim();
  if (RegExp(r'^1[3-9]\d{9}$').hasMatch(raw)) {
    return '+86$raw';
  }
  if (RegExp(r'^\+\d{7,17}$').hasMatch(raw)) {
    return raw;
  }
  return null;
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

final onboardingProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>(
      (ref) => OnboardingController(ref),
    );
