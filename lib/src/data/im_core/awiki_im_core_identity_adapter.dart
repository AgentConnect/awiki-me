import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_session.dart';
import '../../application/models/daemon_subkey_authorization_revoke_result.dart';
import '../../application/ports/identity_core_port.dart';
import '../../application/ports/legacy_identity_upgrade_port.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/device_management.dart';
import '../../domain/entities/session_identity.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_device_management_adapter.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreIdentityAdapter
    implements
        IdentityCorePort,
        ExistingHandleContinuationPort,
        LegacyIdentityUpgradePort {
  AwikiImCoreIdentityAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;
  final Map<String, _PendingExistingHandleRegistration>
  _existingHandleContinuations = <String, _PendingExistingHandleRegistration>{};
  int _continuationSequence = 0;

  @override
  Future<List<AppSession>> listLocalIdentities() async {
    final coreInstance = await _runtime.coreInstance();
    final identities = await coreInstance.listIdentities();
    return identities.map(_mappers.appSessionFromIdentity).toList();
  }

  @override
  Future<AppSession?> defaultIdentity() async {
    final coreInstance = await _runtime.coreInstance();
    final identity = await coreInstance.defaultIdentity();
    return identity == null ? null : _mappers.appSessionFromIdentity(identity);
  }

  @override
  Future<AppSession> resolveIdentity(String identityIdOrAlias) async {
    final coreInstance = await _runtime.coreInstance();
    final identity = await _resolveIdentity(coreInstance, identityIdOrAlias);
    return _mappers.appSessionFromIdentity(identity);
  }

  @override
  Future<AppSession> updateDisplayNameProjection({
    required String identityId,
    String? displayName,
  }) async {
    final normalizedIdentityId = identityId.trim();
    if (normalizedIdentityId.isEmpty) {
      throw ArgumentError.value(identityId, 'identityId', 'must not be empty');
    }
    final coreInstance = await _runtime.coreInstance();
    final identity = await coreInstance.updateDisplayNameProjection(
      identityId: normalizedIdentityId,
      displayName: _nonEmpty(displayName),
    );
    return _mappers.appSessionFromIdentity(identity);
  }

  @override
  Future<SessionAccountBinding> activeSyncAccountBinding() {
    return _runtime.withCurrentClient((client) async {
      final binding = await client.activeSyncAccountBinding();
      return _mappers.sessionAccountBindingFromCore(binding);
    });
  }

  @override
  Future<UserSubkeyPackage> loadDaemonSubkeyPackage(
    String identityIdOrAlias,
  ) async {
    final coreInstance = await _runtime.coreInstance();
    final selector = _selectorFromString(identityIdOrAlias);
    try {
      final package = await coreInstance.loadDaemonSubkeyPackage(selector);
      return _mappers.userSubkeyPackageFromCore(package);
    } on core.AwikiImCoreException catch (error) {
      if (!_shouldTryLocalAliasFallback(selector, error)) {
        rethrow;
      }
    }
    final package = await coreInstance.loadDaemonSubkeyPackage(
      core.IdentitySelector.localAlias(
        _trimLeadingAt(identityIdOrAlias.trim()),
      ),
    );
    return _mappers.userSubkeyPackageFromCore(package);
  }

  @override
  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage(
    String identityIdOrAlias,
  ) async {
    final coreInstance = await _runtime.coreInstance();
    final selector = _selectorFromString(identityIdOrAlias);
    try {
      final package = await coreInstance.ensureDaemonSubkeyPackage(selector);
      return _mappers.userSubkeyPackageFromCore(package);
    } on core.AwikiImCoreException catch (error) {
      if (!_shouldTryLocalAliasFallback(selector, error)) {
        rethrow;
      }
    }
    final package = await coreInstance.ensureDaemonSubkeyPackage(
      core.IdentitySelector.localAlias(
        _trimLeadingAt(identityIdOrAlias.trim()),
      ),
    );
    return _mappers.userSubkeyPackageFromCore(package);
  }

  @override
  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
    String identityIdOrAlias,
  ) async {
    final coreInstance = await _runtime.coreInstance();
    final selector = _selectorFromString(identityIdOrAlias);
    try {
      final result = await coreInstance.revokeDaemonSubkeyAuthorization(
        selector,
      );
      return _mappers.daemonSubkeyAuthorizationRevokeResultFromCore(result);
    } on core.AwikiImCoreException catch (error) {
      if (!_shouldTryLocalAliasFallback(selector, error)) {
        rethrow;
      }
    }
    final result = await coreInstance.revokeDaemonSubkeyAuthorization(
      core.IdentitySelector.localAlias(
        _trimLeadingAt(identityIdOrAlias.trim()),
      ),
    );
    return _mappers.daemonSubkeyAuthorizationRevokeResultFromCore(result);
  }

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async {
    final coreInstance = await _runtime.coreInstance();
    final result = await _deleteLocalIdentity(coreInstance, identityIdOrAlias);
    return _mappers.appSessionFromIdentity(result.deleted);
  }

  @override
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  ) async {
    final coreInstance = await _runtime.coreInstance();
    final status = await _withIdentitySelectorFallback(
      identityIdOrAlias,
      coreInstance.legacyUpgradeStatus,
    );
    return _legacyUpgradeStatus(status);
  }

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) async {
    final coreInstance = await _runtime.coreInstance();
    final status = await _withIdentitySelectorFallback(
      identityIdOrAlias,
      coreInstance.upgradeLegacyIdentity,
    );
    return _legacyUpgradeStatus(status);
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async {
    final coreInstance = await _runtime.coreInstance();
    final result = await coreInstance.registerHandleWithPhone(
      localAlias: handle,
      requestedHandle: handle,
      phone: phone,
      otp: otp,
      inviteCode: inviteCode,
      profile: core.InitialProfile(displayName: displayName),
      makeDefault: true,
    );
    return _registrationResult(coreInstance, result);
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async {
    final coreInstance = await _runtime.coreInstance();
    final result = await coreInstance.registerHandleWithEmail(
      localAlias: handle,
      requestedHandle: handle,
      email: email,
      inviteCode: inviteCode,
      profile: core.InitialProfile(displayName: displayName),
      makeDefault: true,
    );
    return _registrationResult(coreInstance, result);
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async {
    final coreInstance = await _runtime.coreInstance();
    final result = await coreInstance.registerHandleWithoutContactVerification(
      localAlias: handle,
      requestedHandle: handle,
      inviteCode: inviteCode,
      profile: core.InitialProfile(displayName: displayName),
      makeDefault: true,
    );
    return _registrationResult(coreInstance, result);
  }

  Future<IdentityRegistrationResult> _registrationResult(
    core.AwikiImCore coreInstance,
    core.HandleRegistrationResult result,
  ) async {
    final normalizedState = result.state
        .trim()
        .replaceAll('-', '_')
        .toLowerCase();
    if (normalizedState == 'join_required' ||
        normalizedState == 'joinrequired') {
      final continuation = result.joinRequired;
      if (continuation == null) {
        throw StateError(
          'IM Core joinRequired registration did not include a continuation.',
        );
      }
      final mode = existingHandleJoinModeFromCore(continuation.mode);
      if (continuation.requiresUserPresence !=
          (mode == ExistingHandleJoinMode.handleRecoveryRebind)) {
        throw StateError('registration_join_preparation_invalid');
      }
      final continuationId =
          'existing-handle-${DateTime.now().microsecondsSinceEpoch}-${_continuationSequence++}';
      _existingHandleContinuations[continuationId] =
          _PendingExistingHandleRegistration(
            coreInstance: coreInstance,
            preparationId: continuation.preparationId,
            mode: mode,
            requiresUserPresence: continuation.requiresUserPresence,
          );
      return IdentityRegistrationResult(
        status: IdentityRegistrationStatus.joinRequired,
        existingHandleContinuationId: continuationId,
        existingHandleJoinMode: mode,
        existingHandleJoinRequiresUserPresence:
            continuation.requiresUserPresence,
        warnings: List<String>.unmodifiable(result.warnings),
      );
    }
    if (normalizedState != 'registered') {
      throw StateError(
        'IM Core returned unsupported registration state: ${result.state}',
      );
    }
    final identity = result.identity ?? result.defaultIdentityChange?.next;
    if (identity == null) {
      throw StateError('IM Core registration did not return an identity.');
    }
    return IdentityRegistrationResult(
      status: IdentityRegistrationStatus.registered,
      identity: _mappers.appSessionFromIdentity(identity),
      warnings: List<String>.unmodifiable(result.warnings),
    );
  }

  @override
  Future<DeviceJoinProgress> beginExistingHandleDeviceJoin(
    String continuationId, {
    required bool userPresenceConfirmed,
  }) async {
    final pending = _existingHandleContinuations[continuationId];
    if (pending == null || continuationId.trim() != continuationId) {
      throw StateError('existing_handle_continuation_unavailable');
    }
    if (pending.requiresUserPresence && !userPresenceConfirmed) {
      throw StateError('registration_join_user_presence_required');
    }
    final progress = await pending.coreInstance
        .beginPreparedRegistrationDeviceJoin(
          preparationId: pending.preparationId,
          operationId: 'awiki-me-register-join-${pending.preparationId}',
          userPresenceConfirmed: userPresenceConfirmed,
        );
    final mapped = preparedRegistrationJoinProgressFromCore(
      progress,
      pending.mode,
    );
    _existingHandleContinuations.remove(continuationId);
    return mapped;
  }

  @override
  Future<void> discardExistingHandleContinuation(String continuationId) async {
    _existingHandleContinuations.remove(continuationId);
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

class _PendingExistingHandleRegistration {
  const _PendingExistingHandleRegistration({
    required this.coreInstance,
    required this.preparationId,
    required this.mode,
    required this.requiresUserPresence,
  });

  final core.AwikiImCore coreInstance;
  final String preparationId;
  final ExistingHandleJoinMode mode;
  final bool requiresUserPresence;
}

ExistingHandleJoinMode existingHandleJoinModeFromCore(
  core.HandleRegistrationJoinMode value,
) => switch (value) {
  core.HandleRegistrationJoinMode.ordinary => ExistingHandleJoinMode.ordinary,
  core.HandleRegistrationJoinMode.handleRecoveryRebind =>
    ExistingHandleJoinMode.handleRecoveryRebind,
};

DeviceJoinProgress preparedRegistrationJoinProgressFromCore(
  core.AuthorizedJoinActivationProgress value,
  ExistingHandleJoinMode mode,
) {
  final join = deviceJoinProgressFromCore(value.join);
  final reset = value.registryEpochReset;
  if (mode == ExistingHandleJoinMode.ordinary) {
    if (reset != null) {
      throw StateError('registration_join_transition_mismatch');
    }
    return join;
  }
  if (reset == null ||
      reset.sourceKind !=
          core.HandleRecoveryTransitionSourceKind.joinedDevice ||
      reset.sourceId != join.joinSessionId ||
      reset.currentDid != join.did ||
      reset.handle.trim().isEmpty ||
      reset.handle.trim() != reset.handle) {
    throw StateError('registration_join_transition_mismatch');
  }
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
      handle: reset.handle,
      localOrdinaryDataWillMigrate: true,
    ),
  );
}

LegacyIdentityUpgradeStatus _legacyUpgradeStatus(
  core.LegacyUpgradeStatus status,
) {
  return switch (status) {
    core.LegacyUpgradeIdle() => const LegacyIdentityUpgradeStatus.idle(),
    core.LegacyUpgradeRunning() => const LegacyIdentityUpgradeStatus.running(),
    core.LegacyUpgradeRetryRequired(:final identityId, :final code) =>
      LegacyIdentityUpgradeStatus.retryRequired(
        identityId: identityId,
        failureCode: _safeLegacyUpgradeFailureCode(code),
      ),
    core.LegacyUpgradeCompleted() =>
      const LegacyIdentityUpgradeStatus.completed(),
  };
}

String _safeLegacyUpgradeFailureCode(String code) {
  const allowed = <String>{
    'auth_required',
    'legacy_upgrade_failed',
    'local_state_unavailable',
    'permission_denied',
    'service_error',
    'transport_unavailable',
  };
  final normalized = code.trim().toLowerCase();
  return allowed.contains(normalized) ? normalized : 'legacy_upgrade_failed';
}

Future<core.IdentitySummary> _resolveIdentity(
  core.AwikiImCore coreInstance,
  String value,
) async {
  final primary = _selectorFromString(value);
  try {
    return await coreInstance.resolveIdentity(primary);
  } on core.AwikiImCoreException catch (error) {
    if (!_shouldTryLocalAliasFallback(primary, error)) {
      rethrow;
    }
  }
  return coreInstance.resolveIdentity(
    core.IdentitySelector.localAlias(_trimLeadingAt(value.trim())),
  );
}

Future<core.DeleteLocalIdentityResult> _deleteLocalIdentity(
  core.AwikiImCore coreInstance,
  String value,
) async {
  final primary = _selectorFromString(value);
  try {
    return await coreInstance.deleteLocalIdentity(primary);
  } on core.AwikiImCoreException catch (error) {
    if (!_shouldTryLocalAliasFallback(primary, error)) {
      rethrow;
    }
  }
  return coreInstance.deleteLocalIdentity(
    core.IdentitySelector.localAlias(_trimLeadingAt(value.trim())),
  );
}

core.IdentitySelector _selectorFromString(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(value, 'identityIdOrAlias', 'must not be empty');
  }
  if (trimmed == 'default') {
    return const core.IdentitySelector.defaultIdentity();
  }
  if (trimmed.startsWith('did:')) {
    return core.IdentitySelector.did(trimmed);
  }
  if (trimmed.contains('.')) {
    return core.IdentitySelector.handle(trimmed);
  }
  return core.IdentitySelector.id(trimmed);
}

bool _shouldTryLocalAliasFallback(
  core.IdentitySelector selector,
  core.AwikiImCoreException error,
) {
  return selector is core.IdIdentitySelector &&
      error.code == 'identity_not_found';
}

Future<T> _withIdentitySelectorFallback<T>(
  String value,
  Future<T> Function(core.IdentitySelector selector) action,
) async {
  final selectors = identitySelectorCandidates(value);
  for (var index = 0; index < selectors.length; index += 1) {
    try {
      return await action(selectors[index]);
    } on core.AwikiImCoreException catch (error) {
      if (index + 1 == selectors.length || error.code != 'identity_not_found') {
        rethrow;
      }
    }
  }
  throw StateError('identity_selector_candidates_exhausted');
}

List<core.IdentitySelector> identitySelectorCandidates(String value) {
  final primary = _selectorFromString(value);
  if (primary is! core.IdIdentitySelector) {
    return <core.IdentitySelector>[primary];
  }
  return <core.IdentitySelector>[
    primary,
    core.IdentitySelector.localAlias(_trimLeadingAt(value.trim())),
  ];
}

String _trimLeadingAt(String value) {
  var start = 0;
  while (start < value.length && value.codeUnitAt(start) == 0x40) {
    start += 1;
  }
  return value.substring(start);
}
