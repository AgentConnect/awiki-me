// Secret-free projections. Core owns every durable operation and key.
enum PinRecoveryKind { enable, recover }

enum PinRecoveryPhase {
  awaitingPin,
  authorizing,
  registering,
  verifyingBackup,
  recoveringKey,
  awaitingDeviceConfirmation,
  committing,
  commitUnknown,
  localActivationPending,
  activeSecurePending,
  cleanupPending,
  completed,
  failed,
  cancelled,
}

enum PinRecoveryAction {
  verifyPhone,
  submitPin,
  confirmDevice,
  resume,
  cancel,
  retryLocalActivation,
  inspect,
}

enum PinRecoverySecureReadiness {
  notStarted,
  prekeysPending,
  securePending,
  ready,
}

class PinRecoveryTarget {
  const PinRecoveryTarget({
    required this.targetId,
    required this.fullHandle,
    required this.did,
    required this.bindingGeneration,
    required this.canEnable,
    required this.canRecover,
    this.activeEpoch,
    this.unavailableReason,
  });
  final String targetId, fullHandle, did, bindingGeneration;
  final String? activeEpoch, unavailableReason;
  final bool canEnable, canRecover;
}

class PinPhoneChallenge {
  const PinPhoneChallenge({
    required this.handle,
    required this.maskedPhone,
    required this.resendAfterSeconds,
  });
  final String handle, maskedPhone;
  final int resendAfterSeconds;
}

class PinRealmProgress {
  const PinRealmProgress({
    required this.realmId,
    required this.phase,
    this.errorCode,
  });
  final String realmId, phase;
  final String? errorCode;
}

class PinRecoveryProgress {
  const PinRecoveryProgress({
    required this.operationId,
    required this.kind,
    required this.phase,
    required this.allowedActions,
    required this.target,
    required this.attemptsUsed,
    required this.attemptsLimit,
    required this.needsPhoneVerification,
    required this.secureReadiness,
    required this.cleanupRemaining,
    this.recoveredIdentityId,
    this.newDeviceId,
    this.deviceLabel,
    this.errorCode,
    this.nodeProgress = const [],
  });
  final List<PinRealmProgress> nodeProgress;
  final String operationId;
  final PinRecoveryKind kind;
  final PinRecoveryPhase phase;
  final List<PinRecoveryAction> allowedActions;
  final PinRecoveryTarget target;
  final int attemptsUsed, attemptsLimit, cleanupRemaining;
  final bool needsPhoneVerification;
  final PinRecoverySecureReadiness secureReadiness;
  final String? recoveredIdentityId, newDeviceId, deviceLabel, errorCode;
  bool allows(PinRecoveryAction action) => allowedActions.contains(action);
  bool get isProtected =>
      kind == PinRecoveryKind.enable && phase == PinRecoveryPhase.completed;
  bool get canEnter =>
      kind == PinRecoveryKind.recover &&
      recoveredIdentityId != null &&
      (phase == PinRecoveryPhase.completed ||
          phase == PinRecoveryPhase.activeSecurePending);
}

class PinRecoveryFailure implements Exception {
  const PinRecoveryFailure(this.code);
  final String code;
  @override
  String toString() => 'PinRecoveryFailure';
}

enum PinBackupState { unknown, notEnabled, pending, active }

class PinBackupStatus {
  const PinBackupStatus({
    required this.did,
    required this.state,
    this.fullHandle,
    this.bindingGeneration,
    this.activeEpoch,
    this.errorCode,
  });
  final String did;
  final PinBackupState state;
  final String? fullHandle, bindingGeneration, activeEpoch, errorCode;
}
