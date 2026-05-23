import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/profile_core_port.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreProfileAdapter implements ProfileCorePort {
  AwikiImCoreProfileAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<UserProfile> loadMyProfile() async {
    final profile = await (await _runtime.currentClient()).profile
        .loadMyProfile();
    return _mappers.userProfileFromCore(profile);
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    final profile = await (await _runtime.currentClient()).profile
        .loadPublicProfile(_identitySubject(didOrHandle));
    return _mappers.userProfileFromCore(profile);
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    final profile = await (await _runtime.currentClient()).profile
        .updateProfile(_mappers.profilePatchToCore(patch));
    return _mappers.userProfileFromCore(profile);
  }
}

core.IdentitySubject _identitySubject(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('did:')) {
    return core.IdentitySubject.did(trimmed);
  }
  if (trimmed.contains('.')) {
    return core.IdentitySubject.handle(trimmed);
  }
  return core.IdentitySubject.any(trimmed);
}
