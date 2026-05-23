import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';

abstract interface class ProfileCorePort {
  Future<UserProfile> loadMyProfile();

  Future<UserProfile> updateProfile(ProfilePatch patch);

  Future<UserProfile> loadPublicProfile(String didOrHandle);
}
