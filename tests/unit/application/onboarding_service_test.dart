import 'dart:async';

import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/daemon_subkey_authorization_revoke_result.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/legacy_identity_upgrade_port.dart';
import 'package:awiki_me/src/application/ports/profile_core_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
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
        legacyUpgrades: identities,
        sessions: sessions,
        profiles: profiles,
      );

      final result = await service.registerHandleWithPhone(
        phone: '13800138000',
        otp: ' 123 456 ',
        handle: ' Alice ',
        nickName: 'Alice',
        profileMarkdown: '# Alice',
      );

      expect(result.status, IdentityRegistrationStatus.registered);
      expect(result.identity?.identityId, 'phone-id');
      expect(identities.lastPhone, '+8613800138000');
      expect(identities.lastOtp, '123456');
      expect(identities.lastHandle, 'alice');
      expect(sessions.activated.map((item) => item.identityId), ['phone-id']);
      expect(profiles.patches.single.profileMarkdown, '# Alice');
    },
  );

  test('joinRequired does not activate identity or patch profile', () async {
    final identities = _FakeIdentities()
      ..registrationStatus = IdentityRegistrationStatus.joinRequired;
    final sessions = _FakeSessions();
    final profiles = _FakeProfiles();
    final service = ImCoreOnboardingService(
      identities: identities,
      legacyUpgrades: identities,
      sessions: sessions,
      profiles: profiles,
    );

    final result = await service.registerHandleWithPhone(
      phone: '+8613800138000',
      otp: '000000',
      handle: 'alice',
      profileMarkdown: '# Alice',
    );

    expect(result.status, IdentityRegistrationStatus.joinRequired);
    expect(result.identity, isNull);
    expect(result.joinProgress?.joinSessionId, 'join-1');
    expect(sessions.activated, isEmpty);
    expect(profiles.patches, isEmpty);
  });

  test(
    'registerHandleWithoutContactVerification validates phone and patches markdown',
    () async {
      final identities = _FakeIdentities();
      final sessions = _FakeSessions();
      final profiles = _FakeProfiles();
      final service = ImCoreOnboardingService(
        identities: identities,
        legacyUpgrades: identities,
        sessions: sessions,
        profiles: profiles,
      );

      final result = await service.registerHandleWithoutContactVerification(
        phone: '13800138000',
        handle: ' OpenAlice ',
        nickName: 'Open Alice',
        profileMarkdown: '# Open Alice',
      );

      expect(result.status, IdentityRegistrationStatus.registered);
      expect(result.identity?.identityId, 'open-id');
      expect(identities.lastHandle, 'openalice');
      expect(sessions.activated.map((item) => item.identityId), ['open-id']);
      expect(profiles.patches.single.profileMarkdown, '# Open Alice');
    },
  );

  test('superseded registration cannot activate its late identity', () async {
    final identities = _FakeIdentities();
    final registration = Completer<IdentityRegistrationResult>();
    identities.registerPhoneCompleter = registration;
    final sessions = _FakeSessions();
    final profiles = _FakeProfiles();
    final service = ImCoreOnboardingService(
      identities: identities,
      legacyUpgrades: identities,
      sessions: sessions,
      profiles: profiles,
    );
    final transition = sessions.beginSessionTransition();

    final pending = service.registerHandleWithPhone(
      phone: '13800138000',
      otp: '123456',
      handle: 'alice',
      nickName: 'Alice',
      profileMarkdown: '# Alice',
      transition: transition,
    );
    await pumpEventQueue();
    sessions.beginSessionTransition();
    registration.complete(
      IdentityRegistrationResult(
        status: IdentityRegistrationStatus.registered,
        identity: _session('late-id'),
      ),
    );

    await expectLater(pending, throwsA(isA<AppSessionTransitionSuperseded>()));
    expect(sessions.activated, isEmpty);
    expect(profiles.patches, isEmpty);
  });
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

class _FakeIdentities implements IdentityCorePort, LegacyIdentityUpgradePort {
  String? lastPhone;
  String? lastOtp;
  String? lastHandle;
  Completer<IdentityRegistrationResult>? registerPhoneCompleter;
  IdentityRegistrationStatus registrationStatus =
      IdentityRegistrationStatus.registered;

  @override
  Future<SessionAccountBinding> activeSyncAccountBinding() {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  ) async => const LegacyIdentityUpgradeStatus.idle();

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) async => const LegacyIdentityUpgradeStatus.completed();

  @override
  Future<AppSession?> defaultIdentity() async => null;

  @override
  Future<List<AppSession>> listLocalIdentities() async => const <AppSession>[];

  @override
  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => IdentityRegistrationResult(
    status: registrationStatus,
    identity: registrationStatus == IdentityRegistrationStatus.registered
        ? _session('email-id', handle: handle)
        : null,
  );

  @override
  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async {
    lastPhone = phone;
    lastOtp = otp;
    lastHandle = handle;
    final completer = registerPhoneCompleter;
    if (completer != null) {
      return completer.future;
    }
    return IdentityRegistrationResult(
      status: registrationStatus,
      identity: registrationStatus == IdentityRegistrationStatus.registered
          ? _session('phone-id', handle: handle)
          : null,
      joinProgress:
          registrationStatus == IdentityRegistrationStatus.joinRequired
          ? _joinProgress
          : null,
    );
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async {
    lastHandle = handle;
    return IdentityRegistrationResult(
      status: registrationStatus,
      identity: registrationStatus == IdentityRegistrationStatus.registered
          ? _session('open-id', handle: handle)
          : null,
    );
  }

  @override
  Future<AppSession> resolveIdentity(String identityIdOrAlias) async {
    return _session(identityIdOrAlias);
  }

  @override
  Future<UserSubkeyPackage> loadDaemonSubkeyPackage(String identityIdOrAlias) {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage(
    String identityIdOrAlias,
  ) {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
    String identityIdOrAlias,
  ) {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) {
    throw UnsupportedError('unsupported');
  }
}

final DeviceJoinProgress _joinProgress = DeviceJoinProgress(
  joinSessionId: 'join-1',
  did: 'did:wba:awiki.ai:alice:e1_join',
  protocolDeviceId: 'device-1',
  side: DeviceJoinSide.newDevice,
  phase: DeviceJoinPhase.pending,
  remoteState: DeviceJoinRemoteState.pending,
  expiresAt: DateTime.utc(2030),
);

class _FakeSessions
    with AppSessionTransitionGuard
    implements AppSessionService {
  final List<AppSession> activated = <AppSession>[];

  @override
  Future<AppSession> activateIdentity(
    AppSession identity, {
    AppSessionTransition? transition,
    Future<void> Function(AppSession session)? initializeIdentitySession,
  }) async {
    final requestedTransition = transition ?? beginSessionTransition();
    if (!isSessionTransitionCurrent(requestedTransition)) {
      throw const AppSessionTransitionSuperseded();
    }
    activated.add(identity);
    final session = identity.copyWith(authenticated: true);
    await initializeIdentitySession?.call(session);
    markSessionTransitionCommitted(requestedTransition);
    return session;
  }

  @override
  Future<AppSession?> currentSession() async =>
      activated.isEmpty ? null : activated.last;

  @override
  Future<AppSessionLease?> currentSessionLease() async =>
      sessionLeaseFor(activated.isEmpty ? null : activated.last);

  @override
  Future<List<AppSession>> listLocalIdentities() async => const <AppSession>[];

  @override
  Future<AppSession> loginWithIdentity(
    String identityIdOrAlias, {
    AppSessionTransition? transition,
  }) {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) {
    throw UnsupportedError('unsupported');
  }

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
