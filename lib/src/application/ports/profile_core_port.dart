import 'dart:typed_data';

import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';

abstract interface class ProfileCorePort {
  Future<UserProfile> loadMyProfile();

  Future<UserProfile> updateProfile(ProfilePatch patch);

  Future<UserProfile> loadPublicProfile(String didOrHandle);
}

/// Optional capability: legacy adapters can continue to read/edit text profiles.
abstract interface class AvatarCorePort {
  Future<UserProfile> setAvatar({
    required String requestId,
    required String expectedProfileVersion,
    required Uint8List jpeg,
  });
  Future<UserProfile> clearAvatar({
    required String requestId,
    required String expectedProfileVersion,
  });
}
