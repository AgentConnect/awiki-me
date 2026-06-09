import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_session.dart';
import '../../application/ports/identity_core_port.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreIdentityAdapter implements IdentityCorePort {
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
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async {
    final coreInstance = await _runtime.coreInstance();
    final result = await _deleteLocalIdentity(coreInstance, identityIdOrAlias);
    return _mappers.appSessionFromIdentity(result.deleted);
  }

  @override
  Future<AppSession> registerHandleWithPhone({
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
    final identity = result.identity ?? result.defaultIdentityChange?.next;
    if (identity == null) {
      throw StateError('IM Core registration did not return an identity.');
    }
    return _mappers.appSessionFromIdentity(identity);
  }

  @override
  Future<AppSession> registerHandleWithEmail({
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
    final identity = result.identity ?? result.defaultIdentityChange?.next;
    if (identity == null) {
      throw StateError('IM Core registration did not return an identity.');
    }
    return _mappers.appSessionFromIdentity(identity);
  }

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    final coreInstance = await _runtime.coreInstance();
    final result = await coreInstance.recoverHandle(
      handle: handle,
      phone: phone,
      otp: otp,
    );
    final identity =
        result.recoveredIdentity ?? await coreInstance.defaultIdentity();
    if (identity == null) {
      throw StateError('IM Core recovery did not return an identity.');
    }
    return _mappers.appSessionFromIdentity(identity);
  }
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
