import '../domain/entities/profile_patch.dart';
import '../domain/entities/user_profile.dart';
import 'ports/profile_core_port.dart';

abstract interface class ProfileApplicationService {
  Future<UserProfile> loadMyProfile();

  Future<UserProfile> updateProfile(ProfilePatch patch);

  Future<UserProfile> loadPublicProfile(String didOrHandle);
}

class ImCoreProfileApplicationService implements ProfileApplicationService {
  const ImCoreProfileApplicationService({required ProfileCorePort profiles})
    : _profiles = profiles;

  final ProfileCorePort _profiles;

  @override
  Future<UserProfile> loadMyProfile() {
    return _profiles.loadMyProfile();
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    return _profiles.loadPublicProfile(didOrHandle.trim());
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    return _profiles.updateProfile(patch);
  }
}
