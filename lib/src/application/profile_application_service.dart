import 'dart:typed_data';

import '../domain/entities/profile_patch.dart';
import '../domain/entities/session_identity.dart';
import '../domain/entities/user_profile.dart';
import 'ports/account_state_sync_port.dart';
import 'ports/profile_core_port.dart';

abstract interface class ProfileApplicationService {
  Future<UserProfile> loadMyProfile();

  Future<UserProfile> updateProfile(ProfilePatch patch);

  Future<UserProfile> loadPublicProfile(String didOrHandle);
}

class ImCoreProfileApplicationService
    implements ProfileApplicationService, AvatarCorePort {
  const ImCoreProfileApplicationService({required ProfileCorePort profiles})
    : _profiles = profiles;

  final ProfileCorePort _profiles;

  AvatarCorePort get _avatars => _profiles is AvatarCorePort
      ? _profiles as AvatarCorePort
      : throw UnsupportedError('avatar.unavailable');
  @override
  Future<UserProfile> setAvatar({
    required String requestId,
    required String expectedProfileVersion,
    required Uint8List jpeg,
  }) => _avatars.setAvatar(
    requestId: requestId,
    expectedProfileVersion: expectedProfileVersion,
    jpeg: jpeg,
  );
  @override
  Future<UserProfile> clearAvatar({
    required String requestId,
    required String expectedProfileVersion,
  }) => _avatars.clearAvatar(
    requestId: requestId,
    expectedProfileVersion: expectedProfileVersion,
  );

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

class ProfileMutationResult {
  const ProfileMutationResult({
    required this.profile,
    required this.profileVersion,
  });

  final UserProfile profile;
  final String? profileVersion;
}

abstract interface class VersionedProfileApplicationService {
  Future<ProfileMutationResult> updateProfileVersioned(ProfilePatch patch);
}

class AccountStateProfileApplicationService
    implements
        ProfileApplicationService,
        VersionedProfileApplicationService,
        AvatarCorePort {
  const AccountStateProfileApplicationService({
    required ProfileApplicationService delegate,
    required AccountStateProfileMutationPort mutations,
    required SessionIdentity? Function() sessionProvider,
  }) : _delegate = delegate,
       _mutations = mutations,
       _sessionProvider = sessionProvider;

  final ProfileApplicationService _delegate;

  Future<UserProfile> _avatarMutation(
    Future<UserProfile> Function(AvatarCorePort) operation,
  ) async {
    final before = _sessionProvider();
    if (before == null || _delegate is! AvatarCorePort)
      throw StateError('avatar.unavailable');
    final profile = await operation(_delegate as AvatarCorePort);
    if (!_sameProfileMutationSession(before, _sessionProvider()) ||
        profile.did != before.did)
      throw StateError('profile_mutation_session_changed');
    return profile;
  }

  @override
  Future<UserProfile> setAvatar({
    required String requestId,
    required String expectedProfileVersion,
    required Uint8List jpeg,
  }) => _avatarMutation(
    (port) => port.setAvatar(
      requestId: requestId,
      expectedProfileVersion: expectedProfileVersion,
      jpeg: jpeg,
    ),
  );
  @override
  Future<UserProfile> clearAvatar({
    required String requestId,
    required String expectedProfileVersion,
  }) => _avatarMutation(
    (port) => port.clearAvatar(
      requestId: requestId,
      expectedProfileVersion: expectedProfileVersion,
    ),
  );

  final AccountStateProfileMutationPort _mutations;
  final SessionIdentity? Function() _sessionProvider;

  @override
  Future<UserProfile> loadMyProfile() => _delegate.loadMyProfile();

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) =>
      _delegate.loadPublicProfile(didOrHandle);

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async =>
      (await updateProfileVersioned(patch)).profile;

  @override
  Future<ProfileMutationResult> updateProfileVersioned(
    ProfilePatch patch,
  ) async {
    final before = _sessionProvider();
    final binding = before?.accountBinding;
    if (before == null || binding == null) {
      final profile = await _delegate.updateProfile(patch);
      return ProfileMutationResult(
        profile: profile,
        profileVersion: profile.profileVersion,
      );
    }
    final mutation = await _mutations.updateAccountProfile(patch);
    final after = _sessionProvider();
    if (!_sameProfileMutationSession(before, after)) {
      throw StateError('profile_mutation_session_changed');
    }
    final profile = mutation.profile;
    return ProfileMutationResult(
      profileVersion: mutation.profileVersion,
      profile: UserProfile(
        did: before.did,
        displayName: profile.nickName ?? '',
        bio: profile.bio ?? '',
        tags: profile.tags,
        profileMarkdown: profile.profileMd ?? '',
        handle: before.handle,
        avatarUri: profile.avatarUrl,
        profileUri: mutation.profileUri,
        fullHandle: before.handle,
        profileVersion: mutation.profileVersion,
      ),
    );
  }
}

bool _sameProfileMutationSession(
  SessionIdentity before,
  SessionIdentity? after,
) {
  final beforeBinding = before.accountBinding;
  final afterBinding = after?.accountBinding;
  return after != null &&
      before.did == after.did &&
      beforeBinding != null &&
      afterBinding != null &&
      beforeBinding.ownerIdentityId == afterBinding.ownerIdentityId &&
      beforeBinding.accountId == afterBinding.accountId &&
      beforeBinding.currentDid == afterBinding.currentDid &&
      beforeBinding.protocolDeviceId == afterBinding.protocolDeviceId &&
      beforeBinding.identityGeneration == afterBinding.identityGeneration &&
      beforeBinding.deviceAuthGeneration == afterBinding.deviceAuthGeneration;
}
