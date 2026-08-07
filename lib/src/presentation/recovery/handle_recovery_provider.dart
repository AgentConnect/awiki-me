// [INPUT]: Recovery UI intents plus the Core-owned operation service.
// [OUTPUT]: Secret-free V4.0 Recovery UI state.
// [POS]: Presentation controller; it never persists an operation locator or phase.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/handle_recovery_service.dart';
import '../../application/ports/handle_recovery_core_port.dart';
import '../../domain/entities/handle_recovery.dart';
import '../shared/sms_otp_cooldown_provider.dart';

final handleRecoveryCorePortProvider = Provider<HandleRecoveryCorePort>(
  (ref) => throw UnimplementedError(
    'handleRecoveryCorePortProvider must be overridden by the Core adapter',
  ),
);

final handleRecoveryServiceProvider = Provider<HandleRecoveryService>(
  (ref) => HandleRecoveryService(
    core: ref.watch(handleRecoveryCorePortProvider),
    userPresence: ref.watch(userPresencePortProvider),
  ),
);

enum HandleRecoveryUiAction { terminal, exactResume, userAction, localBlocked }

enum HandleRecoveryUiError {
  riskConfirmationRequired,
  notPrepared,
  userPresenceRequired,
  transitionMismatch,
  transitionChainUnsupported,
  remoteStateChanged,
  resultAbsent,
  outcomeUnknown,
  localStateUnavailable,
  keyUnavailable,
  migrationUnsupported,
  blocked,
  rateLimited,
  failed,
}

extension HandleRecoveryUiErrorDetails on HandleRecoveryUiError {
  HandleRecoveryFailureCode? get code => switch (this) {
    HandleRecoveryUiError.notPrepared => HandleRecoveryFailureCode.notPrepared,
    HandleRecoveryUiError.userPresenceRequired =>
      HandleRecoveryFailureCode.userPresenceRequired,
    HandleRecoveryUiError.transitionMismatch =>
      HandleRecoveryFailureCode.transitionMismatch,
    HandleRecoveryUiError.transitionChainUnsupported =>
      HandleRecoveryFailureCode.transitionChainUnsupported,
    HandleRecoveryUiError.remoteStateChanged =>
      HandleRecoveryFailureCode.remoteStateChanged,
    HandleRecoveryUiError.resultAbsent =>
      HandleRecoveryFailureCode.resultAbsent,
    HandleRecoveryUiError.outcomeUnknown =>
      HandleRecoveryFailureCode.outcomeUnknown,
    HandleRecoveryUiError.localStateUnavailable =>
      HandleRecoveryFailureCode.localStateUnavailable,
    HandleRecoveryUiError.keyUnavailable =>
      HandleRecoveryFailureCode.localKeyUnavailable,
    HandleRecoveryUiError.migrationUnsupported =>
      HandleRecoveryFailureCode.localMigrationUnsupported,
    HandleRecoveryUiError.blocked => HandleRecoveryFailureCode.blocked,
    HandleRecoveryUiError.riskConfirmationRequired ||
    HandleRecoveryUiError.rateLimited ||
    HandleRecoveryUiError.failed => null,
  };

  HandleRecoveryUiAction get action => switch (this) {
    HandleRecoveryUiError.notPrepared ||
    HandleRecoveryUiError.transitionMismatch ||
    HandleRecoveryUiError.transitionChainUnsupported ||
    HandleRecoveryUiError.remoteStateChanged ||
    HandleRecoveryUiError.migrationUnsupported =>
      HandleRecoveryUiAction.terminal,
    HandleRecoveryUiError.resultAbsent ||
    HandleRecoveryUiError.outcomeUnknown => HandleRecoveryUiAction.exactResume,
    HandleRecoveryUiError.riskConfirmationRequired ||
    HandleRecoveryUiError.userPresenceRequired ||
    HandleRecoveryUiError.keyUnavailable ||
    HandleRecoveryUiError.rateLimited => HandleRecoveryUiAction.userAction,
    HandleRecoveryUiError.localStateUnavailable ||
    HandleRecoveryUiError.blocked ||
    HandleRecoveryUiError.failed => HandleRecoveryUiAction.localBlocked,
  };

  String get safeCode => code?.name ?? name;
}

HandleRecoveryUiError handleRecoveryUiErrorFrom(Object error) {
  if (error is HandleRecoveryOtpRateLimited) {
    return HandleRecoveryUiError.rateLimited;
  }
  if (error is! HandleRecoveryFailure) return HandleRecoveryUiError.failed;
  return switch (error.code) {
    HandleRecoveryFailureCode.notPrepared => HandleRecoveryUiError.notPrepared,
    HandleRecoveryFailureCode.userPresenceRequired =>
      HandleRecoveryUiError.userPresenceRequired,
    HandleRecoveryFailureCode.transitionMismatch =>
      HandleRecoveryUiError.transitionMismatch,
    HandleRecoveryFailureCode.transitionChainUnsupported =>
      HandleRecoveryUiError.transitionChainUnsupported,
    HandleRecoveryFailureCode.remoteStateChanged =>
      HandleRecoveryUiError.remoteStateChanged,
    HandleRecoveryFailureCode.resultAbsent =>
      HandleRecoveryUiError.resultAbsent,
    HandleRecoveryFailureCode.outcomeUnknown =>
      HandleRecoveryUiError.outcomeUnknown,
    HandleRecoveryFailureCode.localStateUnavailable =>
      HandleRecoveryUiError.localStateUnavailable,
    HandleRecoveryFailureCode.localKeyUnavailable =>
      HandleRecoveryUiError.keyUnavailable,
    HandleRecoveryFailureCode.localMigrationUnsupported =>
      HandleRecoveryUiError.migrationUnsupported,
    HandleRecoveryFailureCode.factorRetryRequired =>
      HandleRecoveryUiError.failed,
    HandleRecoveryFailureCode.localTransitionPending =>
      HandleRecoveryUiError.outcomeUnknown,
    HandleRecoveryFailureCode.unknownEpoch =>
      HandleRecoveryUiError.localStateUnavailable,
    HandleRecoveryFailureCode.blocked => HandleRecoveryUiError.blocked,
  };
}

class HandleRecoveryState {
  const HandleRecoveryState({
    this.riskConfirmed = false,
    this.isBusy = false,
    this.otpPhone,
    this.owner,
    this.progress,
    this.error,
  });

  final bool riskConfirmed;
  final bool isBusy;
  final String? otpPhone;
  final HandleRecoveryOwner? owner;
  final HandleRecoveryProgress? progress;
  final HandleRecoveryUiError? error;

  bool get canRequestOtp {
    final current = progress;
    return current == null ||
        current.phase == HandleRecoveryProgressPhase.otpRequested ||
        (current.lifecycleClass ==
                HandleRecoveryLifecycleClass.remoteUnresolved &&
            current.commitAttempted &&
            current.keyState == HandleRecoveryKeyState.available);
  }

  bool get otpRequested =>
      otpPhone != null && progress != null && canRequestOtp;

  String? get otpOperationId => progress?.operationId;
  String? get otpHandle => owner?.handle ?? progress?.handle;
  String? get localIdentityId => owner?.localIdentityId;

  HandleRecoveryState copyWith({
    bool? riskConfirmed,
    bool? isBusy,
    String? otpPhone,
    HandleRecoveryOwner? owner,
    HandleRecoveryProgress? progress,
    HandleRecoveryUiError? error,
    bool clearError = false,
    bool clearPhone = false,
    bool clearOperation = false,
  }) {
    return HandleRecoveryState(
      riskConfirmed: riskConfirmed ?? this.riskConfirmed,
      isBusy: isBusy ?? this.isBusy,
      otpPhone: clearPhone ? null : (otpPhone ?? this.otpPhone),
      owner: clearOperation ? null : (owner ?? this.owner),
      progress: clearOperation ? null : (progress ?? this.progress),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HandleRecoveryController extends StateNotifier<HandleRecoveryState> {
  HandleRecoveryController(this._service, this._otpCooldown)
    : super(const HandleRecoveryState());

  final HandleRecoveryService _service;
  final SmsOtpCooldownController _otpCooldown;

  void setRiskConfirmed(bool value) {
    state = state.copyWith(riskConfirmed: value, clearError: true);
  }

  Future<void> requestOtp({
    required HandleRecoveryIdentityScope scope,
    required String handle,
    required String phone,
  }) async {
    if (!await _otpCooldown.beginSend()) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final receipt = await _service.requestOtp(
        scope: scope,
        handle: handle,
        phone: phone,
        expectedOperationId: state.progress?.operationId,
      );
      await _otpCooldown.completeAcceptedAt(receipt.retryAt);
      if (mounted) {
        state = state.copyWith(
          owner: HandleRecoveryOwner(
            localIdentityId: receipt.operation.ownerIdentityId,
            handle: receipt.operation.handle,
          ),
          progress: receipt.operation,
          otpPhone: phone.trim(),
        );
      }
    } catch (error) {
      if (error is HandleRecoveryOtpRateLimited) {
        await _otpCooldown.completeRateLimitedAt(error.retryAt);
      }
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      _otpCooldown.completeFailed();
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> prepare({required String phone, required String otp}) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final operationId = state.progress?.operationId;
      if (operationId == null || state.otpPhone != phone.trim()) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.transitionMismatch,
        );
      }
      final progress = await _service.prepare(
        operationId: operationId,
        phone: phone,
        otp: otp,
      );
      if (mounted) state = state.copyWith(progress: progress);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> activate({required String presenceReason}) async {
    final progress = state.progress;
    if (progress == null) return;
    if (!state.riskConfirmed) {
      state = state.copyWith(
        error: HandleRecoveryUiError.riskConfirmationRequired,
      );
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final next = await _service.activate(
        operationId: progress.operationId,
        presenceReason: presenceReason,
      );
      if (mounted) state = state.copyWith(progress: next);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> resume() async {
    final progress = state.progress;
    if (progress == null) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final next = await _service.resume(progress.operationId);
      if (mounted) state = state.copyWith(progress: next);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> restoreForOwner({
    required HandleRecoveryIdentityScope scope,
    required String handle,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final restored = await _service.restoreForOwner(
        scope: scope,
        handle: handle,
      );
      if (!mounted) return;
      if (restored == null) {
        state = const HandleRecoveryState();
      } else {
        state = state.copyWith(
          owner: HandleRecoveryOwner(
            localIdentityId: restored.ownerIdentityId,
            handle: restored.handle,
          ),
          progress: restored,
        );
      }
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> discardPreAttempt() async {
    final progress = state.progress;
    if (progress == null || !progress.canDiscard || state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _service.discardPreAttempt(progress.operationId);
      if (mounted) {
        state = HandleRecoveryState(riskConfirmed: state.riskConfirmed);
      }
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> quarantineKeyUnavailable({
    required String presenceReason,
  }) async {
    final progress = state.progress;
    if (progress == null ||
        (progress.keyState != HandleRecoveryKeyState.permanentlyUnavailable &&
            state.error != HandleRecoveryUiError.keyUnavailable) ||
        state.isBusy) {
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final next = await _service.quarantineKeyUnavailable(
        operationId: progress.operationId,
        presenceReason: presenceReason,
      );
      if (mounted) state = state.copyWith(progress: next);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  void startAfterQuarantine() {
    if (state.progress?.lifecycleClass !=
        HandleRecoveryLifecycleClass.quarantinedKeyUnavailable) {
      return;
    }
    state = HandleRecoveryState(riskConfirmed: state.riskConfirmed);
  }
}

final handleRecoveryProvider =
    StateNotifierProvider<HandleRecoveryController, HandleRecoveryState>(
      (ref) => HandleRecoveryController(
        ref.watch(handleRecoveryServiceProvider),
        ref.watch(smsOtpCooldownProvider.notifier),
      ),
    );
