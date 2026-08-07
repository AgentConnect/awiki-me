// [INPUT]: Frozen public AwikiImCore Handle Recovery facade and exact selectors.
// [OUTPUT]: App-owned V4 operation, receipt, and authorized-Join projections.
// [POS]: Production boundary adapter; it never recreates or persists Core state.

import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/product_local_models.dart';
import '../../application/ports/handle_recovery_core_port.dart';
import '../../application/ports/legacy_registry_epoch_adoption_port.dart';
import '../../domain/entities/handle_recovery.dart';
import 'awiki_im_core_device_management_adapter.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreHandleRecoveryAdapter
    implements HandleRecoveryCorePort, LegacyRegistryEpochAdoptionPort {
  AwikiImCoreHandleRecoveryAdapter({required AwikiImCoreRuntime runtime})
    : _coreInstance = runtime.coreInstance;

  AwikiImCoreHandleRecoveryAdapter.withCoreInstance({
    required AwikiImCoreInstance coreInstance,
  }) : _coreInstance = coreInstance;

  final AwikiImCoreInstance _coreInstance;

  @override
  Future<LegacyRegistryEpochAdoptionAuthority?>
  legacyRegistryEpochAdoptionAuthority(String identitySelector) async {
    if (identitySelector.isEmpty ||
        identitySelector.trim() != identitySelector) {
      return null;
    }
    final instance = await _coreInstance();
    final authority = await instance.legacyRegistryEpochAdoptionAuthority(
      core.IdentitySelector.id(identitySelector),
    );
    if (authority == null) return null;
    return LegacyRegistryEpochAdoptionAuthority(
      ownerIdentityId: authority.ownerIdentityId,
      accountUserId: authority.accountUserId,
      currentDid: authority.currentDid,
      bindingGeneration: authority.bindingGeneration,
      protocolDeviceId: authority.protocolDeviceId,
      deviceAuthGeneration: authority.deviceAuthGeneration,
      provenanceId: authority.provenanceId,
    );
  }

  @override
  Future<HandleRecoveryOtpResult> requestOtp({
    required HandleRecoveryOwner owner,
    required String phone,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final result = await instance.requestHandleRecoveryOtp(
        selector: _ownerSelector(owner),
        phone: phone,
      );
      final operation = await _loadOperation(
        instance,
        operationId: result.operationId,
        owner: owner,
      );
      if (result.fullHandle != operation.handle) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.transitionMismatch,
        );
      }
      return HandleRecoveryOtpResult(
        operation: operation,
        accepted: result.accepted,
        retryAfterSeconds: result.retryAfterSeconds,
        retryAt: result.retryAt,
      );
    });
  }

  @override
  Future<HandleRecoveryProgress> prepare({
    required String operationId,
    required String phone,
    required String otp,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final progress = await instance.prepareHandleRecovery(
        operationId: operationId,
        phone: phone,
        code: otp,
      );
      return _mergeOperation(instance, progress);
    });
  }

  @override
  Future<List<HandleRecoveryProgress>> listOperations(
    HandleRecoveryOwner owner,
  ) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final summaries = await instance.listHandleRecoveryOperations(
        _ownerSelector(owner),
      );
      return Future.wait(
        summaries.map((summary) async {
          if (summary.keyState != core.HandleRecoveryKeyState.available ||
              !_coreLifecycleIsReadable(summary.lifecycleClass)) {
            return _operationFromSummary(summary);
          }
          try {
            final progress = await instance.handleRecoveryStatus(
              summary.operationId,
            );
            return _operationFromCore(progress, summary);
          } on core.AwikiImCoreException catch (error) {
            if (error.handleRecoveryFailureCode !=
                core.HandleRecoveryFailureCode.localKeyUnavailable) {
              rethrow;
            }
            return _operationFromSummary(summary);
          }
        }),
      );
    });
  }

  @override
  Future<HandleRecoveryProgress> getStatus(String operationId) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final progress = await instance.handleRecoveryStatus(operationId);
      return _mergeOperation(instance, progress);
    });
  }

  @override
  Future<HandleRecoveryProgress> activate({
    required String operationId,
    required bool userPresenceConfirmed,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final progress = await instance.activateHandleRecovery(
        operationId: operationId,
        userPresenceConfirmed: userPresenceConfirmed,
      );
      return _mergeOperation(instance, progress);
    });
  }

  @override
  Future<HandleRecoveryProgress> reconcile(String operationId) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final progress = await instance.resumeHandleRecovery(operationId);
      return _mergeOperation(instance, progress);
    });
  }

  @override
  Future<void> discardPreAttempt(String operationId) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      await instance.discardHandleRecoveryPreAttempt(operationId);
    });
  }

  @override
  Future<HandleRecoveryProgress> quarantineKeyUnavailable({
    required String operationId,
    required bool confirmed,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final summary = await instance.quarantineHandleRecoveryKeyUnavailable(
        operationId: operationId,
        userPresenceConfirmed: confirmed,
      );
      // Quarantine is specifically the key-unreadable escape hatch. Do not
      // call status after Core has proven the key unavailable.
      return _operationFromSummary(summary);
    });
  }

  @override
  Future<HandleRecoveryRegistryEpochReset?> authorizedEpochReceipt(
    HandleRecoveryOwner owner,
  ) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      final receipt = await instance.authorizedHandleRecoveryReceipt(
        _ownerSelector(owner),
      );
      return receipt == null ? null : _epochReceiptFromCore(receipt);
    });
  }

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> activateAuthorizedJoin({
    required HandleRecoveryIdentityScope scope,
    required String phone,
    required String otp,
    required String handle,
    required String did,
    required String operationId,
    int? ttlSeconds,
    required bool userPresenceConfirmed,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      return handleRecoveryAuthorizedJoinProgressFromCore(
        await instance.activateAuthorizedJoin(
          selector: _identitySelector(scope),
          phone: phone,
          code: otp,
          handle: handle,
          did: did,
          operationId: operationId,
          ttlSeconds: ttlSeconds,
          userPresenceConfirmed: userPresenceConfirmed,
        ),
      );
    });
  }

  @override
  Future<HandleRecoveryAuthorizedJoinProgress> resumeAuthorizedJoinActivation({
    required String joinSessionId,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      return handleRecoveryAuthorizedJoinProgressFromCore(
        await instance.resumeAuthorizedJoinActivation(joinSessionId),
      );
    });
  }
}

core.IdentitySelector _identitySelector(HandleRecoveryIdentityScope scope) {
  final identityId = scope.localIdentityId;
  if (identityId.isEmpty || identityId.trim() != identityId) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return core.IdentitySelector.id(identityId);
}

core.IdentitySelector _ownerSelector(HandleRecoveryOwner owner) {
  final identityId = owner.localIdentityId;
  if (identityId.isEmpty || identityId.trim() != identityId) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return core.IdentitySelector.id(identityId);
}

Future<HandleRecoveryProgress> _loadOperation(
  core.AwikiImCore instance, {
  required String operationId,
  required HandleRecoveryOwner owner,
}) async {
  final summaries = await instance.listHandleRecoveryOperations(
    _ownerSelector(owner),
  );
  final matches = summaries
      .where((summary) => summary.operationId == operationId)
      .toList();
  if (matches.length != 1) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  // OTP send/re-send must not immediately reconcile an unresolved remote
  // outcome. The authoritative summary already carries the lifecycle,
  // commit-attempt, key, and operation identity needed by the App boundary.
  return _operationFromSummary(matches.single);
}

Future<HandleRecoveryProgress> _mergeOperation(
  core.AwikiImCore instance,
  core.HandleRecoveryProgress progress,
) async {
  final summaries = await instance.listHandleRecoveryOperations(
    core.IdentitySelector.id(progress.ownerIdentityId),
  );
  final matches = summaries
      .where((summary) => summary.operationId == progress.operationId)
      .toList();
  if (matches.length != 1) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return _operationFromCore(progress, matches.single);
}

HandleRecoveryProgress _operationFromCore(
  core.HandleRecoveryProgress progress,
  core.HandleRecoveryOperationSummary summary,
) {
  final stateRoot = _consistentOptionalValue(
    progress.stateRootFingerprint,
    summary.stateRootFingerprint,
  );
  if (progress.operationId != summary.operationId ||
      progress.ownerIdentityId != summary.ownerIdentityId ||
      progress.fullHandle != summary.fullHandle ||
      (progress.accountUserId != null &&
          summary.accountUserId != null &&
          progress.accountUserId != summary.accountUserId)) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  final failureCode = progress.failureCode == null
      ? _failureCodeFromStableString(summary.lastErrorCode)
      : handleRecoveryFailureCodeFromCore(progress.failureCode!);
  return HandleRecoveryProgress(
    operationId: summary.operationId,
    ownerIdentityId: summary.ownerIdentityId,
    accountUserId: progress.accountUserId ?? summary.accountUserId,
    handle: summary.fullHandle,
    lifecycleClass: _lifecycleFromCore(summary.lifecycleClass),
    impact: _impactFromCore(progress.impact),
    commitAttempted: summary.commitAttempted,
    keyState: _keyStateFromCore(summary.keyState),
    resultAbsent: failureCode == HandleRecoveryFailureCode.resultAbsent,
    readyToCommit:
        progress.phase == core.HandleRecoveryPhase.readyToCommit ||
        progress.phase == core.HandleRecoveryPhase.prepared,
    localMigration: _localMigration(
      failureCode: failureCode,
      lastErrorCode: summary.lastErrorCode,
    ),
    discardAllowed:
        summary.lifecycleClass ==
            core.HandleRecoveryOperationLifecycle.preCommit &&
        !summary.commitAttempted &&
        summary.keyState == core.HandleRecoveryKeyState.available,
    intentHash: summary.intentHash,
    stateRootFingerprint: stateRoot,
    supersededByOperationId: summary.supersededByOperationId,
    lastErrorCode: summary.lastErrorCode,
    createdAt: summary.createdAt,
    updatedAt: summary.updatedAt,
    failureCode: failureCode,
    retryable: _isRetryableFailure(failureCode),
  );
}

HandleRecoveryProgress _operationFromSummary(
  core.HandleRecoveryOperationSummary summary,
) {
  final failureCode = _failureCodeFromStableString(summary.lastErrorCode);
  return HandleRecoveryProgress(
    operationId: summary.operationId,
    ownerIdentityId: summary.ownerIdentityId,
    accountUserId: summary.accountUserId,
    handle: summary.fullHandle,
    lifecycleClass: _lifecycleFromCore(summary.lifecycleClass),
    // Terminal and key-unreadable summaries intentionally do not reload the
    // Vault. These conservative values are not used to authorize a commit.
    impact: const HandleRecoveryImpact(
      localOrdinaryDataWillMigrate: true,
      otherDevicesMustRejoin: true,
    ),
    commitAttempted: summary.commitAttempted,
    keyState: _keyStateFromCore(summary.keyState),
    resultAbsent: failureCode == HandleRecoveryFailureCode.resultAbsent,
    readyToCommit: false,
    localMigration: _localMigration(
      failureCode: failureCode,
      lastErrorCode: summary.lastErrorCode,
    ),
    discardAllowed:
        summary.lifecycleClass ==
            core.HandleRecoveryOperationLifecycle.preCommit &&
        !summary.commitAttempted &&
        summary.keyState == core.HandleRecoveryKeyState.available,
    intentHash: summary.intentHash,
    stateRootFingerprint: summary.stateRootFingerprint,
    supersededByOperationId: summary.supersededByOperationId,
    lastErrorCode: summary.lastErrorCode,
    createdAt: summary.createdAt,
    updatedAt: summary.updatedAt,
    failureCode: failureCode,
    retryable: _isRetryableFailure(failureCode),
  );
}

bool _coreLifecycleIsReadable(
  core.HandleRecoveryOperationLifecycle lifecycle,
) =>
    lifecycle == core.HandleRecoveryOperationLifecycle.preCommit ||
    lifecycle == core.HandleRecoveryOperationLifecycle.remoteUnresolved ||
    lifecycle == core.HandleRecoveryOperationLifecycle.remoteCommitted ||
    lifecycle == core.HandleRecoveryOperationLifecycle.localTransitionPending ||
    lifecycle == core.HandleRecoveryOperationLifecycle.applied;

HandleRecoveryLifecycleClass _lifecycleFromCore(
  core.HandleRecoveryOperationLifecycle value,
) => switch (value) {
  core.HandleRecoveryOperationLifecycle.preCommit =>
    HandleRecoveryLifecycleClass.preCommit,
  core.HandleRecoveryOperationLifecycle.remoteUnresolved =>
    HandleRecoveryLifecycleClass.remoteUnresolved,
  core.HandleRecoveryOperationLifecycle.remoteCommitted =>
    HandleRecoveryLifecycleClass.remoteCommitted,
  core.HandleRecoveryOperationLifecycle.localTransitionPending =>
    HandleRecoveryLifecycleClass.localTransitionPending,
  core.HandleRecoveryOperationLifecycle.applied =>
    HandleRecoveryLifecycleClass.applied,
  core.HandleRecoveryOperationLifecycle.discardedPreAttempt =>
    HandleRecoveryLifecycleClass.discardedPreAttempt,
  core.HandleRecoveryOperationLifecycle.quarantinedKeyUnavailable =>
    HandleRecoveryLifecycleClass.quarantinedKeyUnavailable,
  core.HandleRecoveryOperationLifecycle.supersededByStateChange =>
    HandleRecoveryLifecycleClass.supersededByStateChange,
  core.HandleRecoveryOperationLifecycle.failedTerminal =>
    HandleRecoveryLifecycleClass.failedTerminal,
};

HandleRecoveryKeyState _keyStateFromCore(core.HandleRecoveryKeyState value) =>
    switch (value) {
      core.HandleRecoveryKeyState.available => HandleRecoveryKeyState.available,
      core.HandleRecoveryKeyState.temporarilyLocked =>
        HandleRecoveryKeyState.temporarilyLocked,
      core.HandleRecoveryKeyState.permanentlyUnavailable =>
        HandleRecoveryKeyState.permanentlyUnavailable,
      core.HandleRecoveryKeyState.destroyedPreAttempt =>
        HandleRecoveryKeyState.destroyedPreAttempt,
    };

HandleRecoveryImpact _impactFromCore(core.HandleRecoveryImpact value) =>
    HandleRecoveryImpact(
      localOrdinaryDataWillMigrate: value.localOrdinaryDataWillMigrate,
      otherDevicesMustRejoin: value.otherDevicesMustRejoin,
      unsupportedE2eeGroupCount: value.unsupportedE2eeGroupCount,
      unsupportedDidOnlyGroupCount: value.unsupportedDidOnlyGroupCount,
    );

HandleRecoveryLocalMigration _localMigration({
  required HandleRecoveryFailureCode? failureCode,
  required String? lastErrorCode,
}) {
  if (failureCode == HandleRecoveryFailureCode.localMigrationUnsupported ||
      lastErrorCode == 'local_migration_unsupported') {
    return HandleRecoveryLocalMigration.preCommitUnsupported;
  }
  return HandleRecoveryLocalMigration.supported;
}

String? _consistentOptionalValue(String? first, String? second) {
  if (first != null && second != null && first != second) {
    throw const HandleRecoveryFailure(
      HandleRecoveryFailureCode.transitionMismatch,
    );
  }
  return first ?? second;
}

HandleRecoveryFailureCode? _failureCodeFromStableString(String? value) =>
    switch (value) {
      'factor_retry_required' => HandleRecoveryFailureCode.factorRetryRequired,
      'result_absent' => HandleRecoveryFailureCode.resultAbsent,
      'outcome_unknown' || 'handle_recovery_outcome_unknown' =>
        HandleRecoveryFailureCode.outcomeUnknown,
      'local_key_unavailable' => HandleRecoveryFailureCode.localKeyUnavailable,
      'local_transition_pending' =>
        HandleRecoveryFailureCode.localTransitionPending,
      'local_migration_unsupported' =>
        HandleRecoveryFailureCode.localMigrationUnsupported,
      'unknown_epoch' => HandleRecoveryFailureCode.unknownEpoch,
      'handle_recovery_not_prepared' => HandleRecoveryFailureCode.notPrepared,
      'handle_recovery_user_presence_required' =>
        HandleRecoveryFailureCode.userPresenceRequired,
      'handle_recovery_transition_mismatch' =>
        HandleRecoveryFailureCode.transitionMismatch,
      'handle_recovery_transition_chain_unsupported' =>
        HandleRecoveryFailureCode.transitionChainUnsupported,
      'handle_recovery_remote_state_changed' =>
        HandleRecoveryFailureCode.remoteStateChanged,
      'handle_recovery_local_state_unavailable' =>
        HandleRecoveryFailureCode.localStateUnavailable,
      'handle_recovery_blocked' => HandleRecoveryFailureCode.blocked,
      _ => null,
    };

bool _isRetryableFailure(HandleRecoveryFailureCode? value) => switch (value) {
  HandleRecoveryFailureCode.factorRetryRequired ||
  HandleRecoveryFailureCode.resultAbsent ||
  HandleRecoveryFailureCode.outcomeUnknown ||
  HandleRecoveryFailureCode.localTransitionPending => true,
  HandleRecoveryFailureCode.notPrepared ||
  HandleRecoveryFailureCode.userPresenceRequired ||
  HandleRecoveryFailureCode.transitionMismatch ||
  HandleRecoveryFailureCode.transitionChainUnsupported ||
  HandleRecoveryFailureCode.remoteStateChanged ||
  HandleRecoveryFailureCode.localStateUnavailable ||
  HandleRecoveryFailureCode.localKeyUnavailable ||
  HandleRecoveryFailureCode.localMigrationUnsupported ||
  HandleRecoveryFailureCode.unknownEpoch ||
  HandleRecoveryFailureCode.blocked ||
  null => false,
};

HandleRecoveryRegistryEpochReset _epochReceiptFromCore(
  core.HandleRecoveryAccountEpochReceipt value,
) => HandleRecoveryRegistryEpochReset(
  receiptSchemaVersion: value.receiptSchemaVersion,
  accountUserId: value.accountUserId,
  ownerIdentityId: value.ownerIdentityId,
  handle: value.fullHandle,
  previousDid: value.localPreviousDid,
  currentDid: value.currentDid,
  bindingGeneration: value.bindingGeneration,
  currentDeviceId: value.currentDeviceId,
  deviceAuthGeneration: value.deviceAuthGeneration,
  registryVersion: value.registryVersion,
  stateRootFingerprint: value.stateRootFingerprint,
  appliedAt: value.appliedAt,
  metadataJson: value.metadataJson,
  sourceKind: switch (value.sourceKind) {
    core.HandleRecoveryTransitionSourceKind.initiator =>
      HandleRecoveryTransitionSourceKind.initiator,
    core.HandleRecoveryTransitionSourceKind.joinedDevice =>
      HandleRecoveryTransitionSourceKind.joinedDevice,
  },
  sourceId: value.sourceId,
);

Future<T> _runRecovery<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on core.AwikiImCoreException catch (error) {
    final rateLimit = handleRecoveryOtpRateLimitFromCore(error);
    if (rateLimit != null) throw rateLimit;
    final failureCode = error.handleRecoveryFailureCode;
    if (failureCode == null) rethrow;
    final projected = handleRecoveryFailureCodeFromCore(failureCode);
    throw HandleRecoveryFailure(
      projected,
      retryable: _isRetryableFailure(projected),
    );
  }
}

HandleRecoveryOtpRateLimited? handleRecoveryOtpRateLimitFromCore(
  core.AwikiImCoreException error,
) {
  final raw = error.serviceDataJson;
  if (raw == null) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded['code'] != 'otp_rate_limited') return null;
  final seconds = int.tryParse(
    decoded['retry_after_seconds']?.toString() ?? '',
  );
  final retryAtRaw = decoded['retry_at']?.toString();
  final retryAt = retryAtRaw == null ? null : DateTime.tryParse(retryAtRaw);
  if (seconds == null ||
      seconds < 1 ||
      seconds > 3600 ||
      retryAt == null ||
      !retryAt.isUtc ||
      !retryAtRaw!.endsWith('Z')) {
    return null;
  }
  return HandleRecoveryOtpRateLimited(
    retryAfterSeconds: seconds,
    retryAt: retryAt,
  );
}

HandleRecoveryAuthorizedJoinProgress
handleRecoveryAuthorizedJoinProgressFromCore(
  core.AuthorizedJoinActivationProgress value,
) {
  return HandleRecoveryAuthorizedJoinProgress(
    join: deviceJoinProgressFromCore(value.join),
    joinTransitionReference: value.registryEpochReset == null
        ? null
        : handleRecoveryJoinTransitionReferenceFromCore(
            value.registryEpochReset!,
          ),
  );
}

HandleRecoveryJoinTransitionReference
handleRecoveryJoinTransitionReferenceFromCore(
  core.HandleRecoveryRegistryEpochReset value,
) {
  return HandleRecoveryJoinTransitionReference(
    accountUserId: value.accountUserId,
    ownerIdentityId: value.ownerIdentityId,
    handle: value.handle,
    previousDid: value.previousDid,
    currentDid: value.currentDid,
    bindingGeneration: value.bindingGeneration,
    sourceKind: switch (value.sourceKind) {
      core.HandleRecoveryTransitionSourceKind.initiator =>
        HandleRecoveryTransitionSourceKind.initiator,
      core.HandleRecoveryTransitionSourceKind.joinedDevice =>
        HandleRecoveryTransitionSourceKind.joinedDevice,
    },
    sourceId: value.sourceId,
  );
}

HandleRecoveryFailureCode handleRecoveryFailureCodeFromCore(
  core.HandleRecoveryFailureCode value,
) => switch (value) {
  core.HandleRecoveryFailureCode.factorRetryRequired =>
    HandleRecoveryFailureCode.factorRetryRequired,
  core.HandleRecoveryFailureCode.resultAbsent =>
    HandleRecoveryFailureCode.resultAbsent,
  core.HandleRecoveryFailureCode.outcomeUnknown =>
    HandleRecoveryFailureCode.outcomeUnknown,
  core.HandleRecoveryFailureCode.localKeyUnavailable =>
    HandleRecoveryFailureCode.localKeyUnavailable,
  core.HandleRecoveryFailureCode.localTransitionPending =>
    HandleRecoveryFailureCode.localTransitionPending,
  core.HandleRecoveryFailureCode.localMigrationUnsupported =>
    HandleRecoveryFailureCode.localMigrationUnsupported,
  core.HandleRecoveryFailureCode.unknownEpoch =>
    HandleRecoveryFailureCode.unknownEpoch,
  core.HandleRecoveryFailureCode.notPrepared =>
    HandleRecoveryFailureCode.notPrepared,
  core.HandleRecoveryFailureCode.userPresenceRequired =>
    HandleRecoveryFailureCode.userPresenceRequired,
  core.HandleRecoveryFailureCode.transitionMismatch =>
    HandleRecoveryFailureCode.transitionMismatch,
  core.HandleRecoveryFailureCode.transitionChainUnsupported =>
    HandleRecoveryFailureCode.transitionChainUnsupported,
  core.HandleRecoveryFailureCode.remoteStateChanged =>
    HandleRecoveryFailureCode.remoteStateChanged,
  core.HandleRecoveryFailureCode.localStateUnavailable =>
    HandleRecoveryFailureCode.localStateUnavailable,
  core.HandleRecoveryFailureCode.blocked => HandleRecoveryFailureCode.blocked,
};
