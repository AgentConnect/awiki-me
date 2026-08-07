// [INPUT]: Handle-owned Recovery UI intents plus optional local identity hints and App ports.
// [OUTPUT]: Secret-free coarse Recovery UI state.
// [POS]: Presentation controller; OTP is passed transiently and never stored.

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
    local: ref.watch(productLocalStoreProvider),
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
  outcomeUnknown,
  localStateUnavailable,
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
    HandleRecoveryUiError.outcomeUnknown =>
      HandleRecoveryFailureCode.outcomeUnknown,
    HandleRecoveryUiError.localStateUnavailable =>
      HandleRecoveryFailureCode.localStateUnavailable,
    HandleRecoveryUiError.blocked => HandleRecoveryFailureCode.blocked,
    HandleRecoveryUiError.riskConfirmationRequired ||
    HandleRecoveryUiError.rateLimited ||
    HandleRecoveryUiError.failed => null,
  };

  HandleRecoveryUiAction get action => switch (this) {
    HandleRecoveryUiError.notPrepared ||
    HandleRecoveryUiError.transitionMismatch ||
    HandleRecoveryUiError.transitionChainUnsupported =>
      HandleRecoveryUiAction.terminal,
    HandleRecoveryUiError.remoteStateChanged ||
    HandleRecoveryUiError.outcomeUnknown => HandleRecoveryUiAction.exactResume,
    HandleRecoveryUiError.riskConfirmationRequired ||
    HandleRecoveryUiError.userPresenceRequired ||
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
    HandleRecoveryFailureCode.outcomeUnknown =>
      HandleRecoveryUiError.outcomeUnknown,
    HandleRecoveryFailureCode.localStateUnavailable =>
      HandleRecoveryUiError.localStateUnavailable,
    HandleRecoveryFailureCode.blocked => HandleRecoveryUiError.blocked,
  };
}

class HandleRecoveryState {
  const HandleRecoveryState({
    this.otpRequested = false,
    this.riskConfirmed = false,
    this.isBusy = false,
    this.otpOperationId,
    this.otpHandle,
    this.otpPhone,
    this.localIdentityId,
    this.progress,
    this.error,
  });

  final bool otpRequested;
  final bool riskConfirmed;
  final bool isBusy;
  final String? otpOperationId;
  final String? otpHandle;
  final String? otpPhone;
  final String? localIdentityId;
  final HandleRecoveryProgress? progress;
  final HandleRecoveryUiError? error;

  HandleRecoveryState copyWith({
    bool? otpRequested,
    bool? riskConfirmed,
    bool? isBusy,
    String? otpOperationId,
    String? otpHandle,
    String? otpPhone,
    String? localIdentityId,
    HandleRecoveryProgress? progress,
    HandleRecoveryUiError? error,
    bool clearError = false,
  }) {
    return HandleRecoveryState(
      otpRequested: otpRequested ?? this.otpRequested,
      riskConfirmed: riskConfirmed ?? this.riskConfirmed,
      isBusy: isBusy ?? this.isBusy,
      otpOperationId: otpOperationId ?? this.otpOperationId,
      otpHandle: otpHandle ?? this.otpHandle,
      otpPhone: otpPhone ?? this.otpPhone,
      localIdentityId: localIdentityId ?? this.localIdentityId,
      progress: progress ?? this.progress,
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
    HandleRecoveryIdentityScope? scope,
    required String handle,
    required String phone,
  }) async {
    final normalizedHandle = handle.trim().toLowerCase();
    final normalizedPhone = phone.trim();
    final pendingOperationId = state.otpOperationId;
    if (pendingOperationId != null &&
        (state.localIdentityId != scope?.localIdentityId ||
            state.otpHandle != normalizedHandle ||
            (state.otpPhone != null && state.otpPhone != normalizedPhone))) {
      state = state.copyWith(error: HandleRecoveryUiError.transitionMismatch);
      return;
    }
    if (!await _otpCooldown.beginSend()) return;
    late final String operationId;
    try {
      if (pendingOperationId != null) {
        operationId = pendingOperationId;
      } else {
        final operation = await _service.beginOrRestoreOperation(
          scope: scope,
          handle: normalizedHandle,
        );
        operationId = operation.operationId;
      }
    } catch (error) {
      _otpCooldown.completeFailed();
      state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      return;
    }
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      otpOperationId: operationId,
      otpHandle: normalizedHandle,
      otpPhone: normalizedPhone,
      localIdentityId: scope?.localIdentityId,
    );
    try {
      final receipt = await _service.requestOtp(
        handle: normalizedHandle,
        phone: normalizedPhone,
        operationId: operationId,
      );
      await _otpCooldown.completeAcceptedAt(receipt.retryAt);
      if (mounted) {
        state = state.copyWith(
          otpRequested: true,
          otpOperationId: receipt.operationId,
          otpHandle: receipt.handle,
          otpPhone: normalizedPhone,
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

  Future<void> prepare({
    HandleRecoveryIdentityScope? scope,
    required String handle,
    required String phone,
    required String otp,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final operationId = state.otpOperationId;
      if (operationId == null ||
          state.otpHandle != handle.trim().toLowerCase() ||
          state.otpPhone != phone.trim()) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.transitionMismatch,
        );
      }
      final progress = await _service.prepare(
        scope: scope,
        handle: handle,
        phone: phone,
        otp: otp,
        operationId: operationId,
      );
      if (mounted) {
        state = state.copyWith(
          progress: progress,
          localIdentityId: progress.ownerIdentityId,
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
        recoveryId: progress.recoveryId,
        presenceReason: presenceReason,
      );
      if (next.isCompleted && state.localIdentityId != null) {
        await _service.clearLocator(state.localIdentityId!);
      }
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
      final next = await _service.resume(progress.recoveryId);
      if (next.isCompleted && state.localIdentityId != null) {
        await _service.clearLocator(state.localIdentityId!);
      }
      if (mounted) state = state.copyWith(progress: next);
    } catch (error) {
      if (mounted) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (mounted) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> restoreForIdentity(String localIdentityId) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final restored = await _service.restoreForIdentity(localIdentityId);
      if (!mounted) return;
      if (restored == null) {
        state = const HandleRecoveryState();
      } else {
        state = state.copyWith(
          localIdentityId: restored.locator.localIdentityId,
          otpOperationId: restored.locator.operationId,
          otpHandle: restored.locator.fullHandle,
          progress: restored.progress,
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

  Future<void> cancelPendingOtp() async {
    if (state.progress != null || state.isBusy) return;
    final localIdentityId = state.localIdentityId;
    if (localIdentityId != null) {
      await _service.clearLocator(localIdentityId);
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
