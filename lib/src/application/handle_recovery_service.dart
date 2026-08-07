// [INPUT]: Stable owner, transient OTP input, explicit presence, and Core projections.
// [OUTPUT]: Validated, secret-free Handle Recovery operations for presentation.
// [POS]: Thin application orchestration; Core is the only durable state machine.

import '../domain/entities/device_management.dart';
import '../domain/entities/handle_recovery.dart';
import 'ports/handle_recovery_core_port.dart';
import 'ports/user_presence_port.dart';

class HandleRecoveryService {
  HandleRecoveryService({
    required HandleRecoveryCorePort core,
    required UserPresencePort userPresence,
  }) : _core = core,
       _userPresence = userPresence;

  final HandleRecoveryCorePort _core;
  final UserPresencePort _userPresence;

  HandleRecoveryOwner owner({
    required HandleRecoveryIdentityScope scope,
    required String handle,
  }) => HandleRecoveryOwner(
    localIdentityId: _validatedOwnerReference(scope.localIdentityId),
    handle: _normalizedHandle(handle),
  );

  Future<HandleRecoveryOtpResult> requestOtp({
    required HandleRecoveryIdentityScope scope,
    required String handle,
    required String phone,
    String? expectedOperationId,
  }) async {
    final requestedOwner = owner(scope: scope, handle: handle);
    final result = await _core.requestOtp(
      owner: requestedOwner,
      phone: _normalizedRequired(phone),
    );
    _validateOperation(result.operation, expectedOwner: requestedOwner);
    final expected = expectedOperationId == null
        ? null
        : _validatedOperationId(expectedOperationId);
    final operation = result.operation;
    final initialFactor =
        operation.lifecycleClass == HandleRecoveryLifecycleClass.preCommit &&
        !operation.commitAttempted &&
        operation.keyState == HandleRecoveryKeyState.available &&
        operation.phase == HandleRecoveryProgressPhase.otpRequested;
    final postAttemptFactorRetry =
        expected != null &&
        operation.operationId == expected &&
        operation.lifecycleClass ==
            HandleRecoveryLifecycleClass.remoteUnresolved &&
        operation.commitAttempted &&
        operation.keyState == HandleRecoveryKeyState.available;
    if (!result.accepted ||
        (expected != null && operation.operationId != expected) ||
        (!initialFactor && !postAttemptFactorRetry)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    return result;
  }

  Future<HandleRecoveryProgress> prepare({
    required String operationId,
    required String phone,
    required String otp,
  }) async {
    final normalizedOperationId = _validatedOperationId(operationId);
    final progress = await _core.prepare(
      operationId: normalizedOperationId,
      phone: _normalizedRequired(phone),
      otp: _normalizedRequired(otp),
    );
    _validateOperation(progress, expectedOperationId: normalizedOperationId);
    return progress;
  }

  Future<List<HandleRecoveryProgress>> listOperations({
    required HandleRecoveryIdentityScope scope,
    required String handle,
  }) async {
    final requestedOwner = owner(scope: scope, handle: handle);
    final operations = await _core.listOperations(requestedOwner);
    final seen = <String>{};
    for (final operation in operations) {
      _validateOperation(operation, expectedOwner: requestedOwner);
      if (!seen.add(operation.operationId)) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.transitionMismatch,
        );
      }
    }
    return List<HandleRecoveryProgress>.unmodifiable(operations);
  }

  /// Reopens the Core-selected actionable operation for this stable owner.
  /// List ordering and actionable-slot uniqueness are Core contract details;
  /// the App does not reconstruct ordering from timestamps or phases.
  Future<HandleRecoveryProgress?> restoreForOwner({
    required HandleRecoveryIdentityScope scope,
    required String handle,
  }) async {
    final operations = await listOperations(scope: scope, handle: handle);
    final actionable = operations.where((item) => item.isActionable).toList();
    if (actionable.length > 1) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.localStateUnavailable,
      );
    }
    if (actionable.length == 1) {
      return status(actionable.single.operationId);
    }
    // Reopening the latest applied operation closes the crash window between
    // Core transition and central App activation. Timestamps are Core-owned
    // projections; the App does not persist this selection.
    HandleRecoveryProgress? latestApplied;
    for (final operation in operations) {
      if (operation.lifecycleClass != HandleRecoveryLifecycleClass.applied) {
        continue;
      }
      final current = latestApplied;
      if (current == null ||
          operation.updatedAt.isAfter(current.updatedAt) ||
          (operation.updatedAt.compareTo(current.updatedAt) == 0 &&
              operation.operationId.compareTo(current.operationId) > 0)) {
        latestApplied = operation;
      }
    }
    return latestApplied == null ? null : status(latestApplied.operationId);
  }

  Future<HandleRecoveryProgress> activate({
    required String operationId,
    required String presenceReason,
  }) async {
    final normalizedOperationId = _validatedOperationId(operationId);
    final current = await status(normalizedOperationId);
    if (!current.canActivate) {
      throw HandleRecoveryFailure(
        current.localMigration ==
                HandleRecoveryLocalMigration.preCommitUnsupported
            ? HandleRecoveryFailureCode.localMigrationUnsupported
            : HandleRecoveryFailureCode.notPrepared,
      );
    }
    final confirmed = await _userPresence.confirm(reason: presenceReason);
    if (!confirmed) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.userPresenceRequired,
      );
    }
    final progress = await _core.activate(
      operationId: normalizedOperationId,
      userPresenceConfirmed: true,
    );
    _validateOperation(progress, expectedOperationId: normalizedOperationId);
    return progress;
  }

  Future<HandleRecoveryProgress> resume(String operationId) async {
    final normalizedOperationId = _validatedOperationId(operationId);
    final progress = await _core.reconcile(normalizedOperationId);
    _validateOperation(progress, expectedOperationId: normalizedOperationId);
    return progress;
  }

  Future<HandleRecoveryProgress> status(String operationId) async {
    final normalizedOperationId = _validatedOperationId(operationId);
    final progress = await _core.getStatus(normalizedOperationId);
    _validateOperation(progress, expectedOperationId: normalizedOperationId);
    return progress;
  }

  Future<void> discardPreAttempt(String operationId) async {
    final normalizedOperationId = _validatedOperationId(operationId);
    final current = await status(normalizedOperationId);
    if (!current.canDiscard || current.commitAttempted) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.outcomeUnknown,
      );
    }
    await _core.discardPreAttempt(normalizedOperationId);
  }

  Future<HandleRecoveryProgress> quarantineKeyUnavailable({
    required String operationId,
    required String presenceReason,
  }) async {
    final normalizedOperationId = _validatedOperationId(operationId);
    final confirmed = await _userPresence.confirm(reason: presenceReason);
    if (!confirmed) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.userPresenceRequired,
      );
    }
    final progress = await _core.quarantineKeyUnavailable(
      operationId: normalizedOperationId,
      confirmed: true,
    );
    _validateOperation(progress, expectedOperationId: normalizedOperationId);
    return progress;
  }

  Future<HandleRecoveryRegistryEpochReset?> authorizedEpochReceipt({
    required HandleRecoveryIdentityScope scope,
    required String handle,
  }) async {
    final requestedOwner = owner(scope: scope, handle: handle);
    final receipt = await _core.authorizedEpochReceipt(requestedOwner);
    if (receipt == null) return null;
    if (receipt.ownerIdentityId != requestedOwner.localIdentityId ||
        receipt.handle != requestedOwner.handle) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    return receipt;
  }

  Future<DeviceJoinProgress> activateAuthorizedJoin({
    required HandleRecoveryIdentityScope scope,
    required String phone,
    required String otp,
    required String handle,
    required String did,
    required String operationId,
    int? ttlSeconds,
    required String presenceReason,
  }) async {
    final normalizedHandle = _normalizedHandle(handle);
    final normalizedDid = _validatedDid(did);
    final normalizedOperationId = _validatedOperationId(operationId);
    if (ttlSeconds != null && ttlSeconds <= 0) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    final confirmed = await _userPresence.confirm(reason: presenceReason);
    if (!confirmed) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.userPresenceRequired,
      );
    }
    final result = await _core.activateAuthorizedJoin(
      scope: scope,
      phone: _normalizedRequired(phone),
      otp: _normalizedRequired(otp),
      handle: normalizedHandle,
      did: normalizedDid,
      operationId: normalizedOperationId,
      ttlSeconds: ttlSeconds,
      userPresenceConfirmed: true,
    );
    return _validatedJoin(
      result,
      expectedHandle: normalizedHandle,
      expectedDid: normalizedDid,
    );
  }

  Future<DeviceJoinProgress> resumeAuthorizedJoinActivation({
    required String joinSessionId,
    bool recoveryExpected = false,
  }) async {
    final normalizedJoinSessionId = _validatedJoinSessionId(joinSessionId);
    final result = await _core.resumeAuthorizedJoinActivation(
      joinSessionId: normalizedJoinSessionId,
    );
    return _validatedJoin(
      result,
      expectedJoinSessionId: normalizedJoinSessionId,
      recoveryExpected: recoveryExpected,
    );
  }

  DeviceJoinProgress _validatedJoin(
    HandleRecoveryAuthorizedJoinProgress result, {
    String? expectedJoinSessionId,
    String? expectedHandle,
    String? expectedDid,
    bool recoveryExpected = false,
  }) {
    final join = result.join;
    if (!isCanonicalDeviceJoinSessionId(join.joinSessionId) ||
        (expectedJoinSessionId != null &&
            join.joinSessionId != expectedJoinSessionId) ||
        (expectedDid != null && join.did != expectedDid)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    final reset = result.joinTransitionReference;
    if (reset == null) {
      if (recoveryExpected) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.transitionMismatch,
        );
      }
      return join;
    }
    if (reset.sourceKind != HandleRecoveryTransitionSourceKind.joinedDevice ||
        reset.sourceId != join.joinSessionId ||
        reset.currentDid != join.did ||
        (expectedHandle != null && reset.handle != expectedHandle)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    return _projectRecoveryJoin(join, reset.handle);
  }
}

void _validateOperation(
  HandleRecoveryProgress operation, {
  HandleRecoveryOwner? expectedOwner,
  String? expectedOperationId,
}) {
  if (!_isCanonicalOpaqueReference(operation.operationId, maxRunes: 128) ||
      !_isCanonicalOpaqueReference(operation.ownerIdentityId, maxRunes: 255) ||
      _normalizedHandle(operation.handle) != operation.handle ||
      !operation.createdAt.isUtc ||
      !operation.updatedAt.isUtc ||
      !_hasSecondPrecision(operation.createdAt) ||
      !_hasSecondPrecision(operation.updatedAt) ||
      operation.updatedAt.isBefore(operation.createdAt) ||
      (expectedOwner != null &&
          (operation.ownerIdentityId != expectedOwner.localIdentityId ||
              operation.handle != expectedOwner.handle)) ||
      (expectedOperationId != null &&
          operation.operationId != expectedOperationId) ||
      (operation.discardAllowed && operation.commitAttempted)) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  // The frozen Core projection keeps account_user_id nullable until factor
  // exchange succeeds. A pre-attempt discard can therefore be terminal while
  // still having no account ID; commit/later transition facts cannot.
  final accountRequired =
      operation.readyToCommit ||
      operation.commitAttempted ||
      operation.lifecycleClass ==
          HandleRecoveryLifecycleClass.remoteCommitted ||
      operation.lifecycleClass ==
          HandleRecoveryLifecycleClass.localTransitionPending ||
      operation.lifecycleClass == HandleRecoveryLifecycleClass.applied;
  if ((accountRequired &&
          !_isCanonicalOpaqueReference(
            operation.accountUserId ?? '',
            maxRunes: 255,
          )) ||
      (operation.accountUserId != null &&
          !_isCanonicalOpaqueReference(
            operation.accountUserId!,
            maxRunes: 255,
          ))) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  final stateRootRequired = switch (operation.lifecycleClass) {
    HandleRecoveryLifecycleClass.localTransitionPending ||
    HandleRecoveryLifecycleClass.applied => true,
    HandleRecoveryLifecycleClass.preCommit ||
    HandleRecoveryLifecycleClass.remoteUnresolved ||
    HandleRecoveryLifecycleClass.remoteCommitted ||
    HandleRecoveryLifecycleClass.discardedPreAttempt ||
    HandleRecoveryLifecycleClass.quarantinedKeyUnavailable ||
    HandleRecoveryLifecycleClass.supersededByStateChange ||
    HandleRecoveryLifecycleClass.failedTerminal => false,
  };
  if ((stateRootRequired &&
          !_isSha256Fingerprint(operation.stateRootFingerprint)) ||
      (operation.stateRootFingerprint != null &&
          !_isSha256Fingerprint(operation.stateRootFingerprint))) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
}

bool _isSha256Fingerprint(String? value) =>
    value != null && RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value);

String _normalizedHandle(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized.runes.length > 320 ||
      normalized.contains(RegExp(r'\s', unicode: true))) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return normalized;
}

String _normalizedRequired(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return normalized;
}

String _validatedDid(String value) {
  if (!value.startsWith('did:wba:') || value.trim() != value) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return value;
}

String _validatedOperationId(String value) {
  if (!_isCanonicalOpaqueReference(value, maxRunes: 128)) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return value;
}

String _validatedOwnerReference(String value) {
  if (!_isCanonicalOpaqueReference(value, maxRunes: 255)) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return value;
}

String _validatedJoinSessionId(String value) {
  if (!isCanonicalDeviceJoinSessionId(value)) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return value;
}

bool _isCanonicalOpaqueReference(String value, {required int maxRunes}) {
  if (value.runes.isEmpty || value.runes.length > maxRunes) return false;
  return !value.runes.any(
    (rune) =>
        rune <= 0x1f ||
        rune == 0x7f ||
        RegExp(r'\s', unicode: true).hasMatch(String.fromCharCode(rune)),
  );
}

bool _hasSecondPrecision(DateTime value) =>
    value.millisecond == 0 && value.microsecond == 0;

DeviceJoinProgress _projectRecoveryJoin(
  DeviceJoinProgress join,
  String handle,
) => DeviceJoinProgress(
  joinSessionId: join.joinSessionId,
  did: join.did,
  protocolDeviceId: join.protocolDeviceId,
  side: join.side,
  phase: join.phase,
  remoteState: join.remoteState,
  expiresAt: join.expiresAt,
  sas: join.sas,
  authorizedDevice: join.authorizedDevice,
  cause: DeviceJoinCause.handleRecovery,
  handleRecovery: DeviceJoinHandleRecoveryContext(
    handle: handle,
    localOrdinaryDataWillMigrate: true,
  ),
);
