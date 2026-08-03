// [INPUT]: Secret-free Handle Recovery projections from the application/Core boundary.
// [OUTPUT]: Host-neutral identity scope, coarse progress, impact, and stable errors.
// [POS]: App domain projection only; it never owns grants, keys, or the Core state machine.

import 'device_management.dart';

class HandleRecoveryIdentityScope {
  const HandleRecoveryIdentityScope({required this.localIdentityId});

  /// Exact local identity ID. Recovery never guesses the default identity.
  final String localIdentityId;
}

enum HandleRecoveryProgressPhase {
  prepared,
  remoteCommitPending,
  remoteCommitted,
  identityTransitionPending,
  identitySwitched,
  completed,
  blocked,
}

enum HandleRecoveryFailureCode {
  notPrepared,
  userPresenceRequired,
  transitionMismatch,
  transitionChainUnsupported,
  remoteStateChanged,
  outcomeUnknown,
  localStateUnavailable,
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
    required this.handle,
    required this.operationId,
    required this.accepted,
  });

  final String handle;
  final String operationId;
  final bool accepted;
}

enum HandleRecoveryTransitionSourceKind { initiator, joinedDevice }

/// Secret-free Core-authorized projection used only to durably fence the App
/// ProductLocalStore Registry epoch before a new session may sync.
class HandleRecoveryRegistryEpochReset {
  const HandleRecoveryRegistryEpochReset({
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

  /// Recovery commit operation ID for initiators; ordinary Join session ID for
  /// joined devices. This is an opaque non-secret reference.
  final String sourceId;
}

class HandleRecoveryProgress {
  const HandleRecoveryProgress({
    required this.recoveryId,
    required this.handle,
    required this.phase,
    required this.impact,
    this.registryEpochReset,
    this.failureCode,
    this.retryable = false,
  });

  /// Opaque, non-secret reference. It is not a grant or a Vault reference.
  final String recoveryId;
  final String handle;
  final HandleRecoveryProgressPhase phase;
  final HandleRecoveryImpact impact;
  final HandleRecoveryRegistryEpochReset? registryEpochReset;
  final HandleRecoveryFailureCode? failureCode;
  final bool retryable;

  bool get isCompleted => phase == HandleRecoveryProgressPhase.completed;

  bool get canResume =>
      phase != HandleRecoveryProgressPhase.prepared &&
      phase != HandleRecoveryProgressPhase.completed &&
      (phase != HandleRecoveryProgressPhase.blocked || retryable);
}

class HandleRecoveryAuthorizedJoinProgress {
  const HandleRecoveryAuthorizedJoinProgress({
    required this.join,
    this.registryEpochReset,
  });

  final DeviceJoinProgress join;
  final HandleRecoveryRegistryEpochReset? registryEpochReset;
}
