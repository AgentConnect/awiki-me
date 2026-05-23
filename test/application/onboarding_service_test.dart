import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/profile_core_port.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'registerHandleWithPhone normalizes input and patches markdown',
    () async {
      final identities = _FakeIdentities();
      final sessions = _FakeSessions();
      final profiles = _FakeProfiles();
      final service = ImCoreOnboardingService(
        identities: identities,
        sessions: sessions,
        profiles: profiles,
      );

      final session = await service.registerHandleWithPhone(
        phone: '13800138000',
        otp: ' 123 456 ',
        handle: ' Alice ',
        nickName: 'Alice',
        profileMarkdown: '# Alice',
      );

      expect(session.identityId, 'phone-id');
      expect(identities.lastPhone, '+8613800138000');
      expect(identities.lastOtp, '123456');
      expect(identities.lastHandle, 'alice');
      expect(sessions.activated.map((item) => item.identityId), ['phone-id']);
      expect(profiles.patches.single.profileMarkdown, '# Alice');
    },
  );

  test(
    'recoverHandle activates recovered identity without profile patch',
    () async {
      final identities = _FakeIdentities();
      final sessions = _FakeSessions();
      final profiles = _FakeProfiles();
      final service = ImCoreOnboardingService(
        identities: identities,
        sessions: sessions,
        profiles: profiles,
      );

      final session = await service.recoverHandle(
        phone: '+8613800138000',
        otp: '000000',
        handle: 'alice',
      );

      expect(session.identityId, 'recovered-id');
      expect(sessions.activated.map((item) => item.identityId), [
        'recovered-id',
      ]);
      expect(profiles.patches, isEmpty);
    },
  );
}

AppSession _session(String id, {String handle = 'alice'}) {
  return AppSession(
    did: 'did:wba:awiki.ai:$handle:e1_$id',
    identityId: id,
    displayName: handle,
    handle: '$handle.awiki',
    localAlias: handle,
  );
}

class _FakeIdentities implements IdentityCorePort {
  String? lastPhone;
  String? lastOtp;
  String? lastHandle;

  @override
  Future<AppSession?> defaultIdentity() async => null;

  @override
  Future<List<AppSession>> listLocalIdentities() async => const <AppSession>[];

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    lastPhone = phone;
    lastOtp = otp;
    lastHandle = handle;
    return _session('recovered-id', handle: handle);
  }

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => _session('email-id', handle: handle);

  @override
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async {
    lastPhone = phone;
    lastOtp = otp;
    lastHandle = handle;
    return _session('phone-id', handle: handle);
  }

  @override
  Future<AppSession> resolveIdentity(String identityIdOrAlias) async {
    return _session(identityIdOrAlias);
  }
}

class _FakeSessions implements AppSessionService {
  final List<AppSession> activated = <AppSession>[];

  @override
  Future<AppSession> activateIdentity(AppSession identity) async {
    activated.add(identity);
    return identity.copyWith(authenticated: true);
  }

  @override
  Future<AppSession?> currentSession() async =>
      activated.isEmpty ? null : activated.last;

  @override
  Future<List<AppSession>> listLocalIdentities() async => const <AppSession>[];

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AppSession?> refreshSession() async =>
      activated.isEmpty ? null : activated.last;

  @override
  Future<AppSession?> restoreSession() async =>
      activated.isEmpty ? null : activated.last;
}

class _FakeProfiles implements ProfileCorePort {
  final List<ProfilePatch> patches = <ProfilePatch>[];

  @override
  Future<UserProfile> loadMyProfile() async => const UserProfile(
    did: 'did:wba:awiki.ai:alice:e1_profile',
    nickName: 'Alice',
    bio: '',
    tags: <String>[],
    profileMarkdown: '',
  );

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) => loadMyProfile();

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async {
    patches.add(patch);
    return const UserProfile(
      did: 'did:wba:awiki.ai:alice:e1_profile',
      nickName: 'Alice',
      bio: '',
      tags: <String>[],
      profileMarkdown: '# Alice',
    );
  }
}
