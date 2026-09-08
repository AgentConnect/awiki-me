import '../../domain/entities/handle_recovery.dart';
import '../../application/ports/handle_recovery_core_port.dart';

enum HandleRecoveryBusyAction {
  none,
  reading,
  sendingOtp,
  verifying,
  authenticating,
  recovering,
  entering,
}

enum HandleRecoveryViewStage {
  reading,
  verification,
  confirmation,
  continuation,
  completed,
  blocked,
}

enum HandleRecoveryUiAction { terminal, exactResume, userAction, localBlocked }

enum HandleRecoveryUiError {
  factorRetryRequired,
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
    HandleRecoveryUiError.factorRetryRequired =>
      HandleRecoveryFailureCode.factorRetryRequired,
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
    HandleRecoveryUiError.factorRetryRequired ||
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
      HandleRecoveryUiError.factorRetryRequired,
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
    this.lookupFailed = false,
    this.isBusy = false,
    this.action = HandleRecoveryBusyAction.none,
    this.sessionActivationFailed = false,
    this.sessionActivated = false,
    this.otpPhone,
    this.owner,
    this.progress,
    this.error,
  });

  final bool riskConfirmed;
  final bool lookupFailed;
  final bool isBusy;
  final HandleRecoveryBusyAction action;
  final bool sessionActivationFailed;
  final bool sessionActivated;
  final String? otpPhone;
  final HandleRecoveryOwner? owner;
  final HandleRecoveryProgress? progress;
  final HandleRecoveryUiError? error;

  HandleRecoveryUiError? get effectiveError =>
      error ??
      (progress?.failureCode == null
          ? null
          : handleRecoveryUiErrorFrom(
              HandleRecoveryFailure(progress!.failureCode!),
            ));

  bool get isTerminal =>
      effectiveError?.action == HandleRecoveryUiAction.terminal ||
      effectiveError == HandleRecoveryUiError.localStateUnavailable ||
      effectiveError == HandleRecoveryUiError.blocked ||
      (progress != null && !progress!.isActionable && !progress!.isCompleted);

  bool get needsFactorRefresh =>
      effectiveError == HandleRecoveryUiError.factorRetryRequired ||
      progress?.failureCode == HandleRecoveryFailureCode.factorRetryRequired;

  bool get canRequestOtp {
    if (lookupFailed || isTerminal) return false;
    final current = progress;
    if (current == null) return true;
    if (current.keyState != HandleRecoveryKeyState.available) return false;
    return (current.lifecycleClass == HandleRecoveryLifecycleClass.preCommit &&
            (!current.readyToCommit || needsFactorRefresh)) ||
        (current.lifecycleClass ==
                HandleRecoveryLifecycleClass.remoteUnresolved &&
            current.commitAttempted &&
            needsFactorRefresh);
  }

  bool get canActivate =>
      !lookupFailed &&
      !isTerminal &&
      !needsFactorRefresh &&
      (progress?.canActivate ?? false);
  bool get canResume =>
      !lookupFailed &&
      !isTerminal &&
      !needsFactorRefresh &&
      (progress?.canResume ?? false);

  HandleRecoveryViewStage get viewStage {
    if (action == HandleRecoveryBusyAction.reading) {
      return HandleRecoveryViewStage.reading;
    }
    if (lookupFailed ||
        isTerminal ||
        progress?.keyState == HandleRecoveryKeyState.temporarilyLocked ||
        progress?.keyState == HandleRecoveryKeyState.permanentlyUnavailable ||
        effectiveError == HandleRecoveryUiError.keyUnavailable) {
      return HandleRecoveryViewStage.blocked;
    }
    if (progress?.isCompleted ?? false) {
      return HandleRecoveryViewStage.completed;
    }
    if (canRequestOtp) return HandleRecoveryViewStage.verification;
    if (canActivate) return HandleRecoveryViewStage.confirmation;
    return HandleRecoveryViewStage.continuation;
  }

  bool get otpRequested =>
      otpPhone != null && progress != null && canRequestOtp;

  String? get otpOperationId => progress?.operationId;
  String? get otpHandle => owner?.handle ?? progress?.handle;
  String? get localIdentityId => owner?.localIdentityId;

  HandleRecoveryState copyWith({
    bool? riskConfirmed,
    bool? isBusy,
    HandleRecoveryBusyAction? action,
    bool? sessionActivationFailed,
    bool? sessionActivated,
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
      lookupFailed: lookupFailed,
      isBusy: isBusy ?? this.isBusy,
      action: action ?? this.action,
      sessionActivationFailed:
          sessionActivationFailed ?? this.sessionActivationFailed,
      sessionActivated: sessionActivated ?? this.sessionActivated,
      otpPhone: clearPhone ? null : (otpPhone ?? this.otpPhone),
      owner: clearOperation ? null : (owner ?? this.owner),
      progress: clearOperation ? null : (progress ?? this.progress),
      error: clearError ? null : (error ?? this.error),
    );
  }
}
