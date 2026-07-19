enum HandleRecoverySide { requester, oldAdmin }

enum HandleRecoveryPhase { cooling, ready, cancelled, expired, consumed }

class HandleRecoveryProgress {
  const HandleRecoveryProgress({
    required this.recoverySessionId,
    required this.handle,
    required this.handleDomain,
    required this.oldDid,
    required this.side,
    required this.phase,
    required this.coolingUntil,
    required this.expiresAt,
    this.canCancelFromThisDevice = false,
    this.newDid,
    this.localActivationPending = false,
  });

  final String recoverySessionId;

  /// Exact lower-case Handle local part used by the same-domain Recovery API.
  final String handle;
  final String handleDomain;
  final String oldDid;
  final HandleRecoverySide side;
  final HandleRecoveryPhase phase;
  final DateTime coolingUntil;
  final DateTime expiresAt;

  /// True only for an old identity's currently valid, ready admin device.
  final bool canCancelFromThisDevice;
  final String? newDid;

  /// Local Core still has to activate the already-created replacement identity.
  /// This is never a signal that remote finalize may run again.
  final bool localActivationPending;

  String get canonicalHandle => '$handle.$handleDomain';

  bool get isTerminal =>
      phase == HandleRecoveryPhase.cancelled ||
      phase == HandleRecoveryPhase.expired ||
      phase == HandleRecoveryPhase.consumed;

  bool get canFinalize =>
      side == HandleRecoverySide.requester &&
      phase == HandleRecoveryPhase.ready;

  bool get canCancel =>
      side == HandleRecoverySide.oldAdmin &&
      canCancelFromThisDevice &&
      (phase == HandleRecoveryPhase.cooling ||
          phase == HandleRecoveryPhase.ready);
}
