import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/legacy_identity_upgrade_port.dart';
import 'package:awiki_me/src/data/compat/compat_awiki_account_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps AppSession to legacy SessionIdentity with JWT', () async {
    final gateway = CompatAwikiAccountGateway(
      sessions: _FakeSessions(
        defaultSession: _session('default-id', jwtToken: 'jwt-default'),
      ),
      onboarding: _FakeOnboarding(),
    );

    final restored = await gateway.restoreSession();
    final credentials = await gateway.listLocalCredentials();

    expect(restored?.did, contains('default-id'));
    expect(restored?.credentialName, 'alice-local');
    expect(restored?.jwtToken, 'jwt-default');
    expect(credentials.single.jwtToken, 'jwt-default');
  });

  test('maps AppSession to legacy SessionIdentity without JWT', () async {
    final gateway = CompatAwikiAccountGateway(
      sessions: _FakeSessions(defaultSession: _session('default-id')),
      onboarding: _FakeOnboarding(),
    );

    final restored = await gateway.restoreSession();

    expect(restored?.did, contains('default-id'));
    expect(restored?.jwtToken, isNull);
  });

  test('credential delete delegates to app session service', () async {
    final sessions = _FakeSessions(defaultSession: _session('default-id'));
    final gateway = CompatAwikiAccountGateway(
      sessions: sessions,
      onboarding: _FakeOnboarding(),
    );

    await gateway.deleteLocalCredential('alice-local');

    expect(sessions.deletedIdentities, ['alice-local']);
  });

  test('unsupported credential operations fail explicitly', () async {
    final gateway = CompatAwikiAccountGateway(
      sessions: _FakeSessions(defaultSession: _session('default-id')),
      onboarding: _FakeOnboarding(),
    );

    expect(
      () => gateway.loginWithLocalCredential('alice-local'),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => gateway.exportCurrentCredentialAsZip(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => gateway.importCredentialFromZip(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(() => gateway.currentAnpSession(), throwsA(isA<UnsupportedError>()));
  });

  test('registration delegates to onboarding and preserves JWT', () async {
    final gateway = CompatAwikiAccountGateway(
      sessions: _FakeSessions(),
      onboarding: _FakeOnboarding(),
    );

    final session = await gateway.registerHandle(
      phone: '+8613800138000',
      otp: '123456',
      handle: 'alice',
      nickName: 'Alice',
      profileMarkdown: '# Alice',
    );

    expect(session.credentialName, 'alice-local');
    expect(session.jwtToken, 'jwt-phone-id');
  });
}

AppSession _session(String id, {String? jwtToken}) {
  return AppSession(
    did: 'did:wba:awiki.ai:alice:e1_$id',
    identityId: id,
    displayName: 'Alice',
    handle: 'alice.awiki',
    localAlias: 'alice-local',
    authenticated: true,
    jwtToken: jwtToken,
  );
}

class _FakeSessions
    with AppSessionTransitionGuard
    implements AppSessionService {
  _FakeSessions({AppSession? defaultSession})
    : _defaultSession = defaultSession;

  final AppSession? _defaultSession;
  final List<String> deletedIdentities = <String>[];

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
    await initializeIdentitySession?.call(identity);
    markSessionTransitionCommitted(requestedTransition);
    return identity;
  }

  @override
  Future<AppSession?> currentSession() async => _defaultSession;

  @override
  Future<AppSessionLease?> currentSessionLease() async =>
      sessionLeaseFor(_defaultSession);

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    if (_defaultSession != null) _defaultSession,
  ];

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
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async {
    deletedIdentities.add(identityIdOrAlias);
    return _defaultSession ?? _session(identityIdOrAlias);
  }

  @override
  Future<AppSession?> refreshSession() async => _defaultSession;

  @override
  Future<AppSession?> restoreSession() async => _defaultSession;
}

class _FakeOnboarding implements OnboardingService {
  @override
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  ) async => const LegacyIdentityUpgradeStatus.completed();

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) async => const LegacyIdentityUpgradeStatus.completed();

  @override
  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) async => IdentityRegistrationResult(
    status: IdentityRegistrationStatus.registered,
    identity: _session('email-id', jwtToken: 'jwt-email-id'),
  );

  @override
  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) async => IdentityRegistrationResult(
    status: IdentityRegistrationStatus.registered,
    identity: _session('phone-id', jwtToken: 'jwt-phone-id'),
  );

  @override
  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) async => IdentityRegistrationResult(
    status: IdentityRegistrationStatus.registered,
    identity: _session('open-id', jwtToken: 'jwt-open-id'),
  );
}
