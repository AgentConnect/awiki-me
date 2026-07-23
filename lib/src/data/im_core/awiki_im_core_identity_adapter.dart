import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_session.dart';
import '../../application/models/daemon_subkey_authorization_revoke_result.dart';
import '../../application/ports/identity_core_port.dart';
import '../../application/ports/legacy_identity_upgrade_port.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_device_management_adapter.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreIdentityAdapter
    implements IdentityCorePort, LegacyIdentityUpgradePort {
  AwikiImCoreIdentityAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

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
    final status = await coreInstance.legacyUpgradeStatus(
      _selectorFromString(identityIdOrAlias),
    );
    return _legacyUpgradeStatus(status);
  }

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) async {
    final coreInstance = await _runtime.coreInstance();
    final status = await coreInstance.upgradeLegacyIdentity(
      _selectorFromString(identityIdOrAlias),
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
      final progress = await coreInstance.beginDeviceJoin(
        did: continuation.did,
        operationId:
            'awiki-me-register-join-${DateTime.now().microsecondsSinceEpoch}',
        accountVerificationGrant: continuation.accountVerificationGrant,
      );
      return IdentityRegistrationResult(
        status: IdentityRegistrationStatus.joinRequired,
        joinProgress: deviceJoinProgressFromCore(progress),
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
    );
  }
}

LegacyIdentityUpgradeStatus _legacyUpgradeStatus(
  core.LegacyUpgradeStatus status,
) {
  return switch (status) {
    core.LegacyUpgradeIdle() => const LegacyIdentityUpgradeStatus.idle(),
    core.LegacyUpgradeRunning() => const LegacyIdentityUpgradeStatus.running(),
    core.LegacyUpgradeRetryRequired(:final identityId) =>
      LegacyIdentityUpgradeStatus.retryRequired(identityId: identityId),
    core.LegacyUpgradeCompleted() =>
      const LegacyIdentityUpgradeStatus.completed(),
  };
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

String _trimLeadingAt(String value) {
  var start = 0;
  while (start < value.length && value.codeUnitAt(start) == 0x40) {
    start += 1;
  }
  return value.substring(start);
}
