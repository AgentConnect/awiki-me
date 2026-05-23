import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/data/compat/compat_awiki_account_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps AppSession to legacy SessionIdentity without JWT', () async {
    final gateway = CompatAwikiAccountGateway(
      sessions: _FakeSessions(defaultSession: _session('default-id')),
      onboarding: _FakeOnboarding(),
    );

    final restored = await gateway.restoreSession();
    final credentials = await gateway.listLocalCredentials();

    expect(restored?.did, contains('default-id'));
    expect(restored?.credentialName, 'alice-local');
    expect(restored?.jwtToken, isNull);
    expect(credentials.single.jwtToken, isNull);
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
      () => gateway.deleteLocalCredential('alice-local'),
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

  test(
    'registration delegates to onboarding and still returns no JWT',
    () async {
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
      expect(session.jwtToken, isNull);
    },
  );
}

AppSession _session(String id) {
  return AppSession(
    did: 'did:wba:awiki.ai:alice:e1_$id',
    identityId: id,
    displayName: 'Alice',
    handle: 'alice.awiki',
    localAlias: 'alice-local',
    authenticated: true,
  );
}

class _FakeSessions implements AppSessionService {
  _FakeSessions({AppSession? defaultSession})
    : _defaultSession = defaultSession;

  final AppSession? _defaultSession;

  @override
  Future<AppSession> activateIdentity(AppSession identity) async => identity;

  @override
  Future<AppSession?> currentSession() async => _defaultSession;

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    if (_defaultSession != null) _defaultSession,
  ];

  @override
  Future<AppSession> loginWithIdentity(String identityIdOrAlias) {
    throw UnsupportedError('unsupported');
  }

  @override
  Future<void> logout() async {}

  @override
  Future<AppSession?> refreshSession() async => _defaultSession;

  @override
  Future<AppSession?> restoreSession() async => _defaultSession;
}

class _FakeOnboarding implements OnboardingService {
  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async => _session('recovered-id');

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async => _session('email-id');

  @override
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async => _session('phone-id');
}
