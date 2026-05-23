import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/app_session.dart';
import '../../application/ports/identity_core_port.dart';
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
    final identity = await coreInstance.resolveIdentity(
      _selectorFromString(identityIdOrAlias),
    );
    return _mappers.appSessionFromIdentity(identity);
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
