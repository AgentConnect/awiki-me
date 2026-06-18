import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_auth_state.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/ports/auth_core_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/im_core_runtime_port.dart';
import 'package:awiki_me/src/application/ports/realtime_core_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
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
            bearerToken: 'jwt-restored',
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
        expect(restored?.jwtToken, 'jwt-restored');
        expect(runtime.openCount, 1);
        expect(runtime.switchedIdentities, ['id-default']);
        expect(auth.ensureCount, 1);
      },
    );

    test(
      'restoreSession keeps the local identity when auth is temporarily offline',
      () async {
        final runtime = _FakeRuntime();
        final identity = _session('id-offline');
        final auth = _FakeAuth(
          ensureError: Exception(
            'transport unavailable: error sending request for url',
          ),
        );
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: auth,
        );

        final restored = await service.restoreSession();

        expect(restored?.identityId, 'id-offline');
        expect(restored?.authenticated, isFalse);
        expect(restored?.jwtToken, isNull);
        expect(runtime.switchedIdentities, ['id-offline']);
        expect(auth.ensureCount, 1);
      },
    );

    test('restoreSession still fails on non-transient auth errors', () async {
      final service = ImCoreAppSessionService(
        runtime: _FakeRuntime(),
        identities: _FakeIdentities(defaultIdentity: _session('id-auth')),
        auth: _FakeAuth(ensureError: StateError('private key missing')),
      );

      await expectLater(service.restoreSession(), throwsStateError);
    });

    test(
      'explicit local identity login activates a matching local identity',
      () async {
        final runtime = _FakeRuntime();
        final identity = _session('id-other');
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: _FakeAuth(),
        );

        final session = await service.loginWithIdentity('alice-local');

        expect(session.identityId, 'id-other');
        expect(session.authenticated, isTrue);
        expect(runtime.openCount, 1);
        expect(runtime.switchedIdentities, ['id-other']);
      },
    );

    test(
      'explicit local identity login matches bare handle from a local identity',
      () async {
        final runtime = _FakeRuntime();
        final identity = _session(
          'id-handle',
        ).copyWith(handle: 'alice.awiki.ai', localAlias: null);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: _FakeAuth(),
        );

        final session = await service.loginWithIdentity('@Alice');

        expect(session.identityId, 'id-handle');
        expect(runtime.switchedIdentities, ['id-handle']);
      },
    );

    test(
      'explicit local identity login can resolve a non-listed identity',
      () async {
        final runtime = _FakeRuntime();
        final identities = _FakeIdentities(
          resolvedIdentity: _session('id-resolved'),
        );
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: identities,
          auth: _FakeAuth(),
        );

        final session = await service.loginWithIdentity('id-resolved');

        expect(session.identityId, 'id-resolved');
        expect(identities.resolvedSelectors, ['id-resolved']);
        expect(runtime.switchedIdentities, ['id-resolved']);
      },
    );

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
            bearerToken: 'jwt-refreshed',
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
        expect(refreshed?.jwtToken, 'jwt-refreshed');
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

    test('logout keeps the current session while stopping realtime', () async {
      final runtime = _FakeRuntime();
      late ImCoreAppSessionService service;
      final realtime = _FakeRealtime(
        onStop: () async {
          expect(await service.currentSession(), isNotNull);
        },
      );
      service = ImCoreAppSessionService(
        runtime: runtime,
        identities: _FakeIdentities(defaultIdentity: _session('id-default')),
        auth: _FakeAuth(),
        realtime: realtime,
      );

      await service.restoreSession();
      await service.logout();

      expect(await service.currentSession(), isNull);
    });

    test(
      'deleteLocalIdentity deletes from identity store and clears current session',
      () async {
        final runtime = _FakeRuntime();
        final realtime = _FakeRealtime();
        final identity = _session('id-default');
        final identities = _FakeIdentities(defaultIdentity: identity);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: identities,
          auth: _FakeAuth(),
          realtime: realtime,
        );

        await service.restoreSession();
        final deleted = await service.deleteLocalIdentity('alice-local');

        expect(deleted.identityId, identity.identityId);
        expect(identities.deletedSelectors, ['alice-local']);
        expect(realtime.stopCount, 1);
        expect(runtime.disposeCount, 1);
        expect(await service.currentSession(), isNull);
      },
    );
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
  _FakeIdentities({AppSession? defaultIdentity, AppSession? resolvedIdentity})
    : _defaultIdentity = defaultIdentity,
      _resolvedIdentity = resolvedIdentity;

  final AppSession? _defaultIdentity;
  final AppSession? _resolvedIdentity;
  final List<String> resolvedSelectors = <String>[];
  final List<String> deletedSelectors = <String>[];

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
    resolvedSelectors.add(identityIdOrAlias);
    return _resolvedIdentity ?? _session(identityIdOrAlias);
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
  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias) async {
    deletedSelectors.add(identityIdOrAlias);
    return _defaultIdentity ?? _session(identityIdOrAlias);
  }
}

class _FakeAuth implements AuthCorePort {
  _FakeAuth({
    AppAuthState? ensureResult,
    AppAuthState? refreshResult,
    this.ensureError,
  }) : _ensureResult = ensureResult ?? const AppAuthState(authenticated: true),
       _refreshResult =
           refreshResult ?? const AppAuthState(authenticated: true);

  final AppAuthState _ensureResult;
  final AppAuthState _refreshResult;
  final Object? ensureError;
  int ensureCount = 0;
  int refreshCount = 0;

  @override
  Future<AppAuthState> ensureSession() async {
    ensureCount += 1;
    final error = ensureError;
    if (error != null) {
      throw error;
    }
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
  _FakeRealtime({this.onStop});

  final Future<void> Function()? onStop;
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
    await onStop?.call();
  }
}
