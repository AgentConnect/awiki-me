// [INPUT]: Secret-free Handle Recovery projections from the application/Core boundary.
// [OUTPUT]: Stable owner, Core operation projections, epoch receipts, and stable errors.
// [POS]: App domain projection only; Core owns every durable operation and secret.

import 'device_management.dart';

class HandleRecoveryIdentityScope {
  const HandleRecoveryIdentityScope({required this.localIdentityId});

  /// Exact local identity ID. Recovery never guesses the default identity.
  final String localIdentityId;
}

/// Stable selector used to enumerate Core-owned Recovery operations.
///
/// The App does not turn this into a local locator. Core remains authoritative
/// for the operation ID, phase, commit-attempt flag, and key state.
class HandleRecoveryOwner {
  const HandleRecoveryOwner({
    required this.localIdentityId,
    required this.handle,
  });

  final String localIdentityId;
  final String handle;
}

enum HandleRecoveryProgressPhase {
  otpRequested,
  prepared,
  remoteCommitPending,
  remoteCommitted,
  identityTransitionPending,
  identitySwitched,
  completed,
  blocked,
}

enum HandleRecoveryLifecycleClass {
  preCommit,
  remoteUnresolved,
  remoteCommitted,
  localTransitionPending,
  applied,
  discardedPreAttempt,
  quarantinedKeyUnavailable,
  supersededByStateChange,
  failedTerminal,
}

enum HandleRecoveryKeyState {
  available,
  temporarilyLocked,
  permanentlyUnavailable,
  destroyedPreAttempt,
}

/// V4.0 exposes only the minimum pre-commit migration decision. Transparent
/// N-k history adoption and the full fresh/archive UX remain V4.1 work.
enum HandleRecoveryLocalMigration {
  supported,
  freshStartRequired,
  preCommitUnsupported,
}

enum HandleRecoveryFailureCode {
  factorRetryRequired,
  notPrepared,
  userPresenceRequired,
  transitionMismatch,
  transitionChainUnsupported,
  remoteStateChanged,
  resultAbsent,
  outcomeUnknown,
  localStateUnavailable,
  localKeyUnavailable,
  localTransitionPending,
  localMigrationUnsupported,
  unknownEpoch,
  blocked,
}

class HandleRecoveryFailure implements Exception {
  const HandleRecoveryFailure(this.code, {this.retryable = false});

  final HandleRecoveryFailureCode code;
  final bool retryable;

  @override
  String toString() => 'HandleRecoveryFailure(${code.name})';
}

class HandleRecoveryImpact {
  const HandleRecoveryImpact({
    required this.localOrdinaryDataWillMigrate,
    required this.otherDevicesMustRejoin,
    this.unsupportedE2eeGroupCount = 0,
    this.unsupportedDidOnlyGroupCount = 0,
  });

  final bool localOrdinaryDataWillMigrate;
  final bool otherDevicesMustRejoin;
  final int unsupportedE2eeGroupCount;
  final int unsupportedDidOnlyGroupCount;

  bool get hasUnsupportedE2eeGroups => unsupportedE2eeGroupCount > 0;
  bool get hasUnsupportedDidOnlyGroups => unsupportedDidOnlyGroupCount > 0;
}

class HandleRecoveryOtpResult {
  const HandleRecoveryOtpResult({
    required this.operation,
    required this.accepted,
    required this.retryAfterSeconds,
    required this.retryAt,
  });

  final HandleRecoveryProgress operation;
  final bool accepted;
  final int retryAfterSeconds;
  final DateTime retryAt;

  String get handle => operation.handle;
  String get operationId => operation.operationId;
}

enum HandleRecoveryTransitionSourceKind { initiator, joinedDevice }

/// Secret-free Core-authorized projection used only to durably fence the App
/// ProductLocalStore Registry epoch before a new session may sync.
class HandleRecoveryRegistryEpochReset {
  const HandleRecoveryRegistryEpochReset({
    required this.receiptSchemaVersion,
    required this.accountUserId,
    required this.ownerIdentityId,
    required this.handle,
    required this.previousDid,
    required this.currentDid,
    required this.bindingGeneration,
    required this.currentDeviceId,
    required this.deviceAuthGeneration,
    required this.registryVersion,
    required this.stateRootFingerprint,
    required this.appliedAt,
    required this.metadataJson,
    required this.sourceKind,
    required this.sourceId,
  });

  final String receiptSchemaVersion;
  final String accountUserId;
  final String ownerIdentityId;
  final String handle;
  final String previousDid;
  final String currentDid;
  final String bindingGeneration;
  final String currentDeviceId;
  final int deviceAuthGeneration;
  final int registryVersion;
  final String stateRootFingerprint;
  final DateTime appliedAt;
  final String metadataJson;
  final HandleRecoveryTransitionSourceKind sourceKind;

  /// Recovery operation ID for initiators; ordinary Join session ID for
  /// joined devices. This is an opaque non-secret reference.
  final String sourceId;
}

/// Exact, secret-free projection of one Core-owned Recovery operation.
class HandleRecoveryProgress {
  const HandleRecoveryProgress({
    required this.operationId,
    required this.ownerIdentityId,
    required this.accountUserId,
    required this.handle,
    required this.lifecycleClass,
    required this.impact,
    required this.commitAttempted,
    required this.keyState,
    required this.resultAbsent,
    required this.readyToCommit,
    required this.localMigration,
    required this.discardAllowed,
    required this.stateRootFingerprint,
    required this.createdAt,
    required this.updatedAt,
    this.intentHash,
    this.supersededByOperationId,
    this.lastErrorCode,
    this.registryEpochReset,
    this.failureCode,
    this.retryable = false,
  }) : assert(!discardAllowed || !commitAttempted);

  final String operationId;
  final String ownerIdentityId;
  final String? accountUserId;
  final String handle;
  final HandleRecoveryLifecycleClass lifecycleClass;
  final HandleRecoveryImpact impact;

  /// Durable Core fact. The App must never infer this from a UI phase.
  final bool commitAttempted;
  final HandleRecoveryKeyState keyState;
  final bool resultAbsent;
  final bool readyToCommit;
  final HandleRecoveryLocalMigration localMigration;

  /// Core-authoritative pre-attempt discard capability.
  final bool discardAllowed;
  final String? intentHash;
  final String? stateRootFingerprint;
  final String? supersededByOperationId;
  final String? lastErrorCode;
  final DateTime createdAt;
  final DateTime updatedAt;
  final HandleRecoveryRegistryEpochReset? registryEpochReset;
  final HandleRecoveryFailureCode? failureCode;
  final bool retryable;

  HandleRecoveryProgressPhase get phase => switch (lifecycleClass) {
    HandleRecoveryLifecycleClass.preCommit =>
      readyToCommit
          ? HandleRecoveryProgressPhase.prepared
          : HandleRecoveryProgressPhase.otpRequested,
    HandleRecoveryLifecycleClass.remoteUnresolved =>
      HandleRecoveryProgressPhase.remoteCommitPending,
    HandleRecoveryLifecycleClass.remoteCommitted =>
      HandleRecoveryProgressPhase.remoteCommitted,
    HandleRecoveryLifecycleClass.localTransitionPending =>
      HandleRecoveryProgressPhase.identityTransitionPending,
    HandleRecoveryLifecycleClass.applied =>
      HandleRecoveryProgressPhase.completed,
    HandleRecoveryLifecycleClass.discardedPreAttempt ||
    HandleRecoveryLifecycleClass.quarantinedKeyUnavailable ||
    HandleRecoveryLifecycleClass.supersededByStateChange ||
    HandleRecoveryLifecycleClass.failedTerminal =>
      HandleRecoveryProgressPhase.blocked,
  };

  bool get isCompleted =>
      lifecycleClass == HandleRecoveryLifecycleClass.applied;

  bool get isActionable =>
      lifecycleClass == HandleRecoveryLifecycleClass.preCommit ||
      lifecycleClass == HandleRecoveryLifecycleClass.remoteUnresolved ||
      lifecycleClass == HandleRecoveryLifecycleClass.remoteCommitted ||
      lifecycleClass == HandleRecoveryLifecycleClass.localTransitionPending;

  bool get canDiscard => discardAllowed && !commitAttempted;

  bool get isStillConfirming =>
      resultAbsent ||
      lifecycleClass == HandleRecoveryLifecycleClass.remoteUnresolved;

  bool get canActivate =>
      lifecycleClass == HandleRecoveryLifecycleClass.preCommit &&
      readyToCommit &&
      localMigration != HandleRecoveryLocalMigration.preCommitUnsupported &&
      keyState == HandleRecoveryKeyState.available;

  bool get canResume =>
      commitAttempted &&
      !isCompleted &&
      keyState == HandleRecoveryKeyState.available &&
      isActionable;
}

class HandleRecoveryAuthorizedJoinProgress {
  const HandleRecoveryAuthorizedJoinProgress({
    required this.join,
    this.joinTransitionReference,
  });

  final DeviceJoinProgress join;
  final HandleRecoveryJoinTransitionReference? joinTransitionReference;
}

/// Compatibility projection used only to recognize a Recovery-authorized
/// Join. It deliberately contains only the fields exposed by the legacy Join
/// DTO and is never accepted as a V4 account-epoch receipt.
class HandleRecoveryJoinTransitionReference {
  const HandleRecoveryJoinTransitionReference({
    required this.accountUserId,
    required this.ownerIdentityId,
    required this.handle,
    required this.previousDid,
    required this.currentDid,
    required this.bindingGeneration,
    required this.sourceKind,
    required this.sourceId,
  });

  final String accountUserId;
  final String ownerIdentityId;
  final String handle;
  final String previousDid;
  final String currentDid;
  final String bindingGeneration;
  final HandleRecoveryTransitionSourceKind sourceKind;
  final String sourceId;
}
