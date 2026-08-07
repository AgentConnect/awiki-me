// [INPUT]: Handle-owned Recovery intent, optional local identity hint, transient OTP, and user presence.
// [OUTPUT]: Secret-free coarse progress suitable for presentation.
// [POS]: Thin application orchestration; Core remains the only durable Recovery state machine.

import 'dart:convert';
import 'dart:math';

import '../domain/entities/device_management.dart';
import '../domain/entities/handle_recovery.dart';
import 'models/product_local_models.dart';
import 'ports/handle_recovery_core_port.dart';
import 'ports/user_presence_port.dart';
import 'product_local_store.dart';

typedef HandleRecoveryOperationIdFactory = String Function();

class HandleRecoveryService {
  HandleRecoveryService({
    required HandleRecoveryCorePort core,
    required UserPresencePort userPresence,
    required ProductLocalStore local,
    HandleRecoveryOperationIdFactory? operationIdFactory,
  }) : _core = core,
       _userPresence = userPresence,
       _local = local,
       _operationIdFactory =
           operationIdFactory ?? _secureHandleRecoveryOperationId;

  final HandleRecoveryCorePort _core;
  final UserPresencePort _userPresence;
  final ProductLocalStore _local;
  final HandleRecoveryOperationIdFactory _operationIdFactory;

  String createOperationId() {
    final operationId = _operationIdFactory();
    if (!_isCanonicalOpaqueReference(operationId)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.localStateUnavailable,
      );
    }
    return operationId;
  }

  Future<HandleRecoveryHostOperation> beginOrRestoreOperation({
    HandleRecoveryIdentityScope? scope,
    required String handle,
  }) async {
    final fullHandle = _normalizedHandle(handle);
    if (scope == null) {
      return HandleRecoveryHostOperation(
        operationId: createOperationId(),
        fullHandle: fullHandle,
      );
    }
    final localIdentityId = _validatedOpaqueReference(scope.localIdentityId);
    final existing = await _local.loadHandleRecoveryLocator(
      localIdentityId: localIdentityId,
    );
    if (existing != null) {
      _validateLocator(existing, expectedIdentityId: localIdentityId);
      if (existing.fullHandle != fullHandle) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.localStateUnavailable,
        );
      }
      return HandleRecoveryHostOperation(
        operationId: existing.operationId,
        fullHandle: existing.fullHandle,
        localIdentityId: existing.localIdentityId,
      );
    }
    final locator = ProductHandleRecoveryLocator(
      localIdentityId: localIdentityId,
      operationId: createOperationId(),
      fullHandle: fullHandle,
    );
    await _local.saveHandleRecoveryLocator(locator);
    return HandleRecoveryHostOperation(
      operationId: locator.operationId,
      fullHandle: locator.fullHandle,
      localIdentityId: locator.localIdentityId,
    );
  }

  Future<HandleRecoveryHostRestore?> restoreForIdentity(
    String localIdentityId,
  ) async {
    final normalizedIdentityId = _validatedOpaqueReference(localIdentityId);
    final locator = await _local.loadHandleRecoveryLocator(
      localIdentityId: normalizedIdentityId,
    );
    if (locator == null) return null;
    _validateLocator(locator, expectedIdentityId: normalizedIdentityId);
    final recoveryId = locator.recoveryId;
    if (recoveryId == null) {
      return HandleRecoveryHostRestore(locator: locator);
    }
    final progress = await status(recoveryId);
    if (progress.handle != locator.fullHandle ||
        progress.ownerIdentityId != normalizedIdentityId) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    if (progress.isCompleted) {
      await clearLocator(normalizedIdentityId);
      return null;
    }
    return HandleRecoveryHostRestore(locator: locator, progress: progress);
  }

  Future<void> clearLocator(String localIdentityId) {
    return _local.deleteHandleRecoveryLocator(
      localIdentityId: _validatedOpaqueReference(localIdentityId),
    );
  }

  Future<HandleRecoveryOtpResult> requestOtp({
    required String handle,
    required String phone,
    required String operationId,
  }) async {
    final normalizedHandle = _normalizedHandle(handle);
    final normalizedPhone = _normalizedRequired(phone);
    final normalizedOperationId = _validatedOpaqueReference(operationId);
    final result = await _core.requestHandleRecoveryOtp(
      handle: normalizedHandle,
      phone: normalizedPhone,
      operationId: normalizedOperationId,
    );
    if (!result.accepted ||
        result.handle != normalizedHandle ||
        result.operationId != normalizedOperationId) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    return result;
  }

  Future<HandleRecoveryProgress> prepare({
    HandleRecoveryIdentityScope? scope,
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
  }) async {
    final normalizedOperationId = _validatedOpaqueReference(operationId);
    final normalizedHandle = _normalizedHandle(handle);
    ProductHandleRecoveryLocator? locator;
    String? hintedIdentityId;
    if (scope != null) {
      hintedIdentityId = _validatedOpaqueReference(scope.localIdentityId);
      locator = await _local.loadHandleRecoveryLocator(
        localIdentityId: hintedIdentityId,
      );
      if (locator == null) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.localStateUnavailable,
        );
      }
      _validateLocator(locator, expectedIdentityId: hintedIdentityId);
      if (locator.operationId != normalizedOperationId ||
          locator.fullHandle != normalizedHandle) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.transitionMismatch,
        );
      }
    }
    final progress = await _core.prepareHandleRecovery(
      scope: scope,
      handle: normalizedHandle,
      phone: _normalizedRequired(phone),
      otp: _normalizedRequired(otp),
      operationId: normalizedOperationId,
    );
    if (progress.handle != normalizedHandle ||
        !_isCanonicalOpaqueReference(progress.ownerIdentityId) ||
        !_isCanonicalOpaqueReference(progress.recoveryId)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    if (hintedIdentityId != null &&
        progress.ownerIdentityId != hintedIdentityId) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    await _local.saveHandleRecoveryLocator(
      locator?.withRecoveryId(progress.recoveryId) ??
          ProductHandleRecoveryLocator(
            localIdentityId: progress.ownerIdentityId,
            operationId: normalizedOperationId,
            fullHandle: normalizedHandle,
            recoveryId: progress.recoveryId,
          ),
    );
    return progress;
  }

  Future<HandleRecoveryProgress> activate({
    required String recoveryId,
    required String presenceReason,
  }) async {
    final confirmed = await _userPresence.confirm(reason: presenceReason);
    if (!confirmed) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.userPresenceRequired,
      );
    }
    final progress = await _core.activateHandleRecovery(
      recoveryId: recoveryId,
      userPresenceConfirmed: true,
    );
    return _persistRegistryReset(
      progress,
      expectedSourceKind: HandleRecoveryTransitionSourceKind.initiator,
    );
  }

  Future<HandleRecoveryProgress> resume(String recoveryId) async {
    final progress = await _core.resumeHandleRecovery(recoveryId: recoveryId);
    return _persistRegistryReset(
      progress,
      expectedSourceKind: HandleRecoveryTransitionSourceKind.initiator,
    );
  }

  Future<HandleRecoveryProgress> status(String recoveryId) {
    return _core.handleRecoveryStatus(_validatedOpaqueReference(recoveryId));
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
    final normalizedOperationId = _validatedOpaqueReference(operationId);
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
    return _persistAuthorizedJoinReset(
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
    return _persistAuthorizedJoinReset(
      result,
      expectedJoinSessionId: normalizedJoinSessionId,
      recoveryExpected: recoveryExpected,
    );
  }

  Future<DeviceJoinProgress> _persistAuthorizedJoinReset(
    HandleRecoveryAuthorizedJoinProgress result, {
    String? expectedJoinSessionId,
    String? expectedHandle,
    String? expectedDid,
    bool recoveryExpected = false,
  }) async {
    final join = result.join;
    if (!isCanonicalDeviceJoinSessionId(join.joinSessionId) ||
        (expectedJoinSessionId != null &&
            join.joinSessionId != expectedJoinSessionId) ||
        (expectedDid != null && join.did != expectedDid)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    final reset = result.registryEpochReset;
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
    final recoveryJoin = _projectRecoveryJoin(join, reset.handle);
    if (join.phase != DeviceJoinPhase.authorized ||
        join.remoteState != DeviceJoinRemoteState.consumed) {
      return recoveryJoin;
    }
    await _persistRegistryEpochReset(reset);
    return recoveryJoin;
  }

  Future<HandleRecoveryProgress> _persistRegistryReset(
    HandleRecoveryProgress progress, {
    required HandleRecoveryTransitionSourceKind expectedSourceKind,
    String? expectedSourceId,
    String? expectedDid,
  }) async {
    final reset = progress.registryEpochReset;
    if (reset == null) {
      return progress;
    }
    if (!_phaseAllowsRegistryReset(progress.phase) ||
        reset.sourceKind != expectedSourceKind ||
        reset.handle != progress.handle ||
        (expectedSourceId != null && reset.sourceId != expectedSourceId) ||
        (expectedDid != null && reset.currentDid != expectedDid)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    await _persistRegistryEpochReset(reset);
    return progress;
  }

  Future<void> _persistRegistryEpochReset(
    HandleRecoveryRegistryEpochReset reset,
  ) {
    return _local.applyDeviceRegistryEpochReset(
      ProductDeviceRegistryEpochResetAuthorization(
        reference: ProductDeviceRegistryEpochResetReference(
          accountUserId: reset.accountUserId,
          ownerIdentityId: reset.ownerIdentityId,
          previousDid: reset.previousDid,
          currentDid: reset.currentDid,
          bindingGeneration: reset.bindingGeneration,
        ),
        handle: reset.handle,
        sourceKind:
            reset.sourceKind == HandleRecoveryTransitionSourceKind.initiator
            ? ProductIdentityTransitionSourceKind.initiator
            : ProductIdentityTransitionSourceKind.joinedDevice,
        sourceId: reset.sourceId,
      ),
    );
  }
}

class HandleRecoveryHostRestore {
  const HandleRecoveryHostRestore({required this.locator, this.progress});

  final ProductHandleRecoveryLocator locator;
  final HandleRecoveryProgress? progress;
}

class HandleRecoveryHostOperation {
  const HandleRecoveryHostOperation({
    required this.operationId,
    required this.fullHandle,
    this.localIdentityId,
  });

  final String operationId;
  final String fullHandle;
  final String? localIdentityId;
}

void _validateLocator(
  ProductHandleRecoveryLocator locator, {
  required String expectedIdentityId,
}) {
  if (locator.localIdentityId != expectedIdentityId ||
      !_isCanonicalOpaqueReference(locator.localIdentityId) ||
      !_isCanonicalOpaqueReference(locator.operationId) ||
      _normalizedHandle(locator.fullHandle) != locator.fullHandle ||
      (locator.recoveryId != null &&
          !_isCanonicalOpaqueReference(locator.recoveryId!))) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.localStateUnavailable,
    );
  }
}

String _normalizedHandle(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty || normalized.contains(RegExp(r'\s'))) {
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

String _validatedOpaqueReference(String value) {
  if (!_isCanonicalOpaqueReference(value)) {
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

bool _isCanonicalOpaqueReference(String value) {
  if (value.runes.isEmpty || value.runes.length > 128) return false;
  return !value.runes.any(
    (rune) =>
        rune <= 0x1f ||
        (rune >= 0x7f && rune <= 0x9f) ||
        RegExp(r'\s', unicode: true).hasMatch(String.fromCharCode(rune)),
  );
}

String _secureHandleRecoveryOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'handle-recovery-${base64Url.encode(bytes).replaceAll('=', '')}';
}

DeviceJoinProgress _projectRecoveryJoin(
  DeviceJoinProgress join,
  String handle,
) {
  return DeviceJoinProgress(
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
}

bool _phaseAllowsRegistryReset(HandleRecoveryProgressPhase phase) =>
    switch (phase) {
      HandleRecoveryProgressPhase.identityTransitionPending ||
      HandleRecoveryProgressPhase.identitySwitched ||
      HandleRecoveryProgressPhase.completed => true,
      HandleRecoveryProgressPhase.prepared ||
      HandleRecoveryProgressPhase.remoteCommitPending ||
      HandleRecoveryProgressPhase.remoteCommitted ||
      HandleRecoveryProgressPhase.blocked => false,
    };
