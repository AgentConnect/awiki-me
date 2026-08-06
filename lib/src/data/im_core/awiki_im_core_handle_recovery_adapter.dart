// [INPUT]: Frozen public AwikiImCore Handle Recovery facade and exact identity selectors.
// [OUTPUT]: App-owned secret-free Recovery and legacy Registry-adoption projections.
// [POS]: Production boundary adapter; it does not recreate or persist Core state.

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
  Future<HandleRecoveryOtpResult> requestHandleRecoveryOtp({
    required String handle,
    required String phone,
    required String operationId,
  }) async {
    try {
      return await _runRecovery(() async {
        final instance = await _coreInstance();
        final result = await instance.requestHandleRecoveryOtp(
          phone: phone,
          handle: handle,
          operationId: operationId,
        );
        return HandleRecoveryOtpResult(
          handle: result.handle,
          operationId: result.operationId,
          accepted: result.accepted,
          retryAfterSeconds: result.retryAfterSeconds,
          retryAt: result.retryAt,
        );
      });
    } on core.AwikiImCoreException catch (error) {
      final rateLimited = _handleRecoveryOtpRateLimit(error);
      if (rateLimited != null) throw rateLimited;
      rethrow;
    }
  }

  @override
  Future<HandleRecoveryProgress> prepareHandleRecovery({
    required HandleRecoveryIdentityScope scope,
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      return handleRecoveryProgressFromCore(
        await instance.prepareHandleRecovery(
          selector: _identitySelector(scope),
          phone: phone,
          code: otp,
          handle: handle,
          operationId: operationId,
        ),
      );
    });
  }

  @override
  Future<HandleRecoveryProgress> activateHandleRecovery({
    required String recoveryId,
    required bool userPresenceConfirmed,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      return handleRecoveryProgressFromCore(
        await instance.activateHandleRecovery(
          recoveryId: recoveryId,
          userPresenceConfirmed: userPresenceConfirmed,
        ),
      );
    });
  }

  @override
  Future<HandleRecoveryProgress> resumeHandleRecovery({
    required String recoveryId,
  }) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      return handleRecoveryProgressFromCore(
        await instance.resumeHandleRecovery(recoveryId),
      );
    });
  }

  @override
  Future<HandleRecoveryProgress> handleRecoveryStatus(String recoveryId) {
    return _runRecovery(() async {
      final instance = await _coreInstance();
      return handleRecoveryProgressFromCore(
        await instance.handleRecoveryStatus(recoveryId),
      );
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

Future<T> _runRecovery<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on core.AwikiImCoreException catch (error) {
    final failureCode = error.handleRecoveryFailureCode;
    if (failureCode == null) rethrow;
    throw HandleRecoveryFailure(handleRecoveryFailureCodeFromCore(failureCode));
  }
}

HandleRecoveryOtpRateLimited? _handleRecoveryOtpRateLimit(
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

HandleRecoveryProgress handleRecoveryProgressFromCore(
  core.HandleRecoveryProgress value,
) {
  return HandleRecoveryProgress(
    recoveryId: value.recoveryId,
    handle: value.handle,
    phase: switch (value.phase) {
      core.HandleRecoveryPhase.prepared => HandleRecoveryProgressPhase.prepared,
      core.HandleRecoveryPhase.remoteCommitPending =>
        HandleRecoveryProgressPhase.remoteCommitPending,
      core.HandleRecoveryPhase.remoteCommitted =>
        HandleRecoveryProgressPhase.remoteCommitted,
      core.HandleRecoveryPhase.identityTransitionPending =>
        HandleRecoveryProgressPhase.identityTransitionPending,
      core.HandleRecoveryPhase.identitySwitched =>
        HandleRecoveryProgressPhase.identitySwitched,
      core.HandleRecoveryPhase.completed =>
        HandleRecoveryProgressPhase.completed,
      core.HandleRecoveryPhase.blocked => HandleRecoveryProgressPhase.blocked,
    },
    impact: HandleRecoveryImpact(
      localOrdinaryDataWillMigrate: value.impact.localOrdinaryDataWillMigrate,
      otherDevicesMustRejoin: value.impact.otherDevicesMustRejoin,
      unsupportedE2eeGroupCount: value.impact.unsupportedE2eeGroupCount,
      unsupportedDidOnlyGroupCount: value.impact.unsupportedDidOnlyGroupCount,
    ),
    registryEpochReset: value.registryEpochReset == null
        ? null
        : handleRecoveryRegistryEpochResetFromCore(value.registryEpochReset!),
    failureCode: value.failureCode == null
        ? null
        : handleRecoveryFailureCodeFromCore(value.failureCode!),
  );
}

HandleRecoveryAuthorizedJoinProgress
handleRecoveryAuthorizedJoinProgressFromCore(
  core.AuthorizedJoinActivationProgress value,
) {
  return HandleRecoveryAuthorizedJoinProgress(
    join: deviceJoinProgressFromCore(value.join),
    registryEpochReset: value.registryEpochReset == null
        ? null
        : handleRecoveryRegistryEpochResetFromCore(value.registryEpochReset!),
  );
}

HandleRecoveryRegistryEpochReset handleRecoveryRegistryEpochResetFromCore(
  core.HandleRecoveryRegistryEpochReset value,
) {
  return HandleRecoveryRegistryEpochReset(
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
  core.HandleRecoveryFailureCode.outcomeUnknown =>
    HandleRecoveryFailureCode.outcomeUnknown,
  core.HandleRecoveryFailureCode.localStateUnavailable =>
    HandleRecoveryFailureCode.localStateUnavailable,
  core.HandleRecoveryFailureCode.blocked => HandleRecoveryFailureCode.blocked,
};
