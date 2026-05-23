import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_auth_state.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/ports/auth_core_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/im_core_runtime_port.dart';
import 'package:awiki_me/src/application/ports/realtime_core_port.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImCoreAppSessionService', () {
    test(
      'restoreSession activates SDK default identity and ensures auth',
      () async {
        final runtime = _FakeRuntime();
        final identity = _session('id-default');
        final auth = _FakeAuth(
          ensureResult: AppAuthState(
            authenticated: true,
            subject: identity.did,
            expiresAt: DateTime.utc(2026, 5, 23, 9),
          ),
        );
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: auth,
        );

        final restored = await service.restoreSession();

        expect(restored?.identityId, 'id-default');
        expect(restored?.authenticated, isTrue);
        expect(restored?.expiresAt, DateTime.utc(2026, 5, 23, 9));
        expect(runtime.openCount, 1);
        expect(runtime.switchedIdentities, ['id-default']);
        expect(auth.ensureCount, 1);
      },
    );

    test('explicit local identity login is deliberately unsupported', () async {
      final service = ImCoreAppSessionService(
        runtime: _FakeRuntime(),
        identities: _FakeIdentities(),
        auth: _FakeAuth(),
      );

      expect(
        () => service.loginWithIdentity('id-other'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'refreshSession updates auth metadata for the active session',
      () async {
        final identity = _session('id-default');
        final auth = _FakeAuth(
          ensureResult: AppAuthState(
            authenticated: true,
            subject: identity.did,
          ),
          refreshResult: AppAuthState(
            authenticated: true,
            subject: identity.did,
            expiresAt: DateTime.utc(2026, 5, 24),
          ),
        );
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: auth,
        );

        await service.restoreSession();
        final refreshed = await service.refreshSession();

        expect(refreshed?.expiresAt, DateTime.utc(2026, 5, 24));
        expect(auth.refreshCount, 1);
      },
    );

    test('logout stops realtime and disposes runtime', () async {
      final runtime = _FakeRuntime();
      final realtime = _FakeRealtime();
      final service = ImCoreAppSessionService(
        runtime: runtime,
        identities: _FakeIdentities(defaultIdentity: _session('id-default')),
        auth: _FakeAuth(),
        realtime: realtime,
      );

      await service.restoreSession();
      await service.logout();

      expect(realtime.stopCount, 1);
      expect(runtime.disposeCount, 1);
      expect(await service.currentSession(), isNull);
    });
  });
}

AppSession _session(String id) {
  return AppSession(
    did: 'did:wba:awiki.ai:alice:e1_$id',
    identityId: id,
    displayName: 'Alice',
    handle: 'alice.awiki',
    localAlias: 'alice-local',
  );
}

class _FakeRuntime implements ImCoreRuntimePort {
  int openCount = 0;
  int disposeCount = 0;
  final List<String> switchedIdentities = <String>[];

  @override
  bool get isOpen => openCount > 0 && disposeCount == 0;

  @override
  Future<void> open() async {
    openCount += 1;
  }

  @override
  Future<List<String>> validate() async => const <String>[];

  @override
  Future<void> switchIdentity(String identityIdOrAlias) async {
    switchedIdentities.add(identityIdOrAlias);
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

class _FakeIdentities implements IdentityCorePort {
  _FakeIdentities({AppSession? defaultIdentity})
    : _defaultIdentity = defaultIdentity;

  final AppSession? _defaultIdentity;

  @override
  Future<AppSession?> defaultIdentity() async => _defaultIdentity;

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    if (_defaultIdentity != null) _defaultIdentity,
  ];

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async => _session('recovered');

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => _session('email');

  @override
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => _session('phone');

  @override
  Future<AppSession> resolveIdentity(String identityIdOrAlias) async {
    return _session(identityIdOrAlias);
  }
}

class _FakeAuth implements AuthCorePort {
  _FakeAuth({AppAuthState? ensureResult, AppAuthState? refreshResult})
    : _ensureResult = ensureResult ?? const AppAuthState(authenticated: true),
      _refreshResult = refreshResult ?? const AppAuthState(authenticated: true);

  final AppAuthState _ensureResult;
  final AppAuthState _refreshResult;
  int ensureCount = 0;
  int refreshCount = 0;

  @override
  Future<AppAuthState> ensureSession() async {
    ensureCount += 1;
    return _ensureResult;
  }

  @override
  Future<AppAuthState> login() async => _ensureResult;

  @override
  Future<AppAuthState> refreshSession() async {
    refreshCount += 1;
    return _refreshResult;
  }

  @override
  Future<AppAuthState> status() async => _ensureResult;
}

class _FakeRealtime implements RealtimeCorePort {
  int stopCount = 0;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates => const Stream.empty();

  @override
  bool get isRunning => stopCount == 0;

  @override
  Stream<RealtimeUpdate> get updates => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    stopCount += 1;
  }
}
