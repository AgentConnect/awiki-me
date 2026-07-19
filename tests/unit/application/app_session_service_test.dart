import 'dart:async';

import 'package:awiki_me/src/application/active_session_store.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_auth_state.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/daemon_subkey_authorization_revoke_result.dart';
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
      'restoreSession does not treat SDK default identity as login state',
      () async {
        final runtime = _FakeRuntime();
        final identity = _session('id-default');
        final auth = _FakeAuth();
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: auth,
          activeSessionStore: _FakeActiveSessionStore(),
        );

        final restored = await service.restoreSession();

        expect(restored, isNull);
        expect(runtime.openCount, 1);
        expect(runtime.switchedIdentities, isEmpty);
        expect(auth.ensureCount, 0);
      },
    );

    test(
      'restoreSession activates stored active identity and ensures auth',
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
          activeSessionStore: _FakeActiveSessionStore('id-default'),
        );

        final restored = await service.restoreSession();

        expect(restored?.identityId, 'id-default');
        expect(restored?.authenticated, isTrue);
        expect(restored?.expiresAt, DateTime.utc(2026, 5, 23, 9));
        expect(restored?.jwtToken, 'jwt-restored');
        expect(runtime.openCount, 1);
        expect(runtime.vaultChecks, ['id-default']);
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
          activeSessionStore: _FakeActiveSessionStore('id-offline'),
        );

        final restored = await service.restoreSession();

        expect(restored?.identityId, 'id-offline');
        expect(restored?.authenticated, isFalse);
        expect(restored?.jwtToken, isNull);
        expect(runtime.vaultChecks, ['id-offline']);
        expect(runtime.switchedIdentities, ['id-offline']);
        expect(auth.ensureCount, 1);
      },
    );

    test('restoreSession still fails on non-transient auth errors', () async {
      final runtime = _FakeRuntime();
      final service = ImCoreAppSessionService(
        runtime: runtime,
        identities: _FakeIdentities(defaultIdentity: _session('id-auth')),
        auth: _FakeAuth(ensureError: StateError('private key missing')),
        activeSessionStore: _FakeActiveSessionStore('id-auth'),
      );

      await expectLater(service.restoreSession(), throwsStateError);
      expect(runtime.vaultChecks, ['id-auth']);
    });

    test(
      'activateIdentity fails closed when identity vault verify fails',
      () async {
        final runtime = _FakeRuntime(
          vaultError: StateError('vault verify failed'),
        );
        final active = _FakeActiveSessionStore();
        final auth = _FakeAuth();
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: _session('id-vault')),
          auth: auth,
          activeSessionStore: active,
        );

        await expectLater(
          service.loginWithIdentity('alice-local'),
          throwsStateError,
        );
        expect(runtime.vaultChecks, ['id-vault']);
        expect(runtime.switchedIdentities, isEmpty);
        expect(auth.ensureCount, 0);
        expect(await active.readActiveIdentityId(), isNull);
        expect(await service.currentSession(), isNull);
      },
    );

    test(
      'activateIdentity clears partial state when active-session persistence fails',
      () async {
        final runtime = _FakeRuntime();
        final active = _FakeActiveSessionStore.failing('id-old');
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(
            defaultIdentity: _session('id-replacement'),
          ),
          auth: _FakeAuth(),
          activeSessionStore: active,
        );

        await expectLater(
          service.loginWithIdentity('alice-local'),
          throwsStateError,
        );

        expect(runtime.switchedIdentities, ['id-replacement']);
        expect(await active.readActiveIdentityId(), isNull);
        expect(await service.currentSession(), isNull);
      },
    );

    test(
      'explicit local identity login activates a matching local identity',
      () async {
        final runtime = _FakeRuntime();
        final identity = _session('id-other');
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: _FakeAuth(),
          activeSessionStore: _FakeActiveSessionStore(),
        );

        final session = await service.loginWithIdentity('alice-local');

        expect(session.identityId, 'id-other');
        expect(session.authenticated, isTrue);
        expect(runtime.openCount, 1);
        expect(runtime.vaultChecks, ['id-other']);
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
          activeSessionStore: _FakeActiveSessionStore(),
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
          activeSessionStore: _FakeActiveSessionStore(),
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
          activeSessionStore: _FakeActiveSessionStore('id-default'),
        );

        await service.restoreSession();
        final refreshed = await service.refreshSession();

        expect(refreshed?.expiresAt, DateTime.utc(2026, 5, 24));
        expect(refreshed?.jwtToken, 'jwt-refreshed');
        expect(auth.refreshCount, 1);
      },
    );

    test('logout clears active identity without disposing runtime', () async {
      final runtime = _FakeRuntime();
      final realtime = _FakeRealtime();
      final active = _FakeActiveSessionStore('id-default');
      final service = ImCoreAppSessionService(
        runtime: runtime,
        identities: _FakeIdentities(defaultIdentity: _session('id-default')),
        auth: _FakeAuth(),
        activeSessionStore: active,
        realtime: realtime,
      );

      await service.restoreSession();
      await service.logout();
      await pumpEventQueue();

      expect(realtime.stopCount, 1);
      expect(runtime.disposeCount, 0);
      expect(await service.currentSession(), isNull);
      expect(await active.readActiveIdentityId(), isNull);
    });

    test('logout is not blocked by slow realtime shutdown', () async {
      final runtime = _FakeRuntime();
      final stopCompleter = Completer<void>();
      final realtime = _FakeRealtime(
        onStop: () async {
          await stopCompleter.future;
        },
      );
      final active = _FakeActiveSessionStore('id-default');
      final service = ImCoreAppSessionService(
        runtime: runtime,
        identities: _FakeIdentities(defaultIdentity: _session('id-default')),
        auth: _FakeAuth(),
        activeSessionStore: active,
        realtime: realtime,
      );

      await service.restoreSession();
      await service.logout();

      expect(await service.currentSession(), isNull);
      expect(await active.readActiveIdentityId(), isNull);
      expect(runtime.disposeCount, 0);
      expect(realtime.stopCount, 1);
      stopCompleter.complete();
      await pumpEventQueue();
    });

    test('disposeRuntime stops realtime and disposes runtime', () async {
      final runtime = _FakeRuntime();
      final realtime = _FakeRealtime();
      final service = ImCoreAppSessionService(
        runtime: runtime,
        identities: _FakeIdentities(defaultIdentity: _session('id-default')),
        auth: _FakeAuth(),
        activeSessionStore: _FakeActiveSessionStore('id-default'),
        realtime: realtime,
      );

      await service.restoreSession();
      await service.disposeRuntime();

      expect(realtime.stopCount, 1);
      expect(runtime.disposeCount, 1);
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
          activeSessionStore: _FakeActiveSessionStore('id-default'),
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

    test(
      'listLocalIdentities filters identities from another DID domain',
      () async {
        final identities = _FakeIdentities(
          defaultIdentity: _session('id-default'),
          extraIdentities: <AppSession>[
            _session(
              'id-test',
            ).copyWith(did: 'did:wba:anpclaw.com:alice:e1_id-test'),
          ],
        );
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: identities,
          auth: _FakeAuth(),
          expectedDidDomain: 'awiki.ai',
        );

        final local = await service.listLocalIdentities();

        expect(local.map((item) => item.identityId), ['id-default']);
      },
    );

    test(
      'loginWithIdentity rejects cross-domain local identities locally',
      () async {
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(
            defaultIdentity: _session(
              'id-test',
            ).copyWith(did: 'did:wba:anpclaw.com:alice:e1_id-test'),
          ),
          auth: _FakeAuth(),
          expectedDidDomain: 'awiki.ai',
        );

        await expectLater(
          service.loginWithIdentity('alice-local'),
          throwsStateError,
        );
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
  _FakeRuntime({this.vaultError});

  final Object? vaultError;
  int openCount = 0;
  int disposeCount = 0;
  final List<String> switchedIdentities = <String>[];
  final List<String> vaultChecks = <String>[];

  @override
  bool get isOpen => openCount > 0 && disposeCount == 0;

  @override
  Future<void> open() async {
    openCount += 1;
  }

  @override
  Future<List<String>> validate() async => const <String>[];

  @override
  Future<void> ensureIdentityVault(String identityIdOrAlias) async {
    vaultChecks.add(identityIdOrAlias);
    final error = vaultError;
    if (error != null) {
      throw error;
    }
  }

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
  _FakeIdentities({
    AppSession? defaultIdentity,
    AppSession? resolvedIdentity,
    List<AppSession> extraIdentities = const <AppSession>[],
  }) : _defaultIdentity = defaultIdentity,
       _resolvedIdentity = resolvedIdentity,
       _extraIdentities = extraIdentities;

  final AppSession? _defaultIdentity;
  final AppSession? _resolvedIdentity;
  final List<AppSession> _extraIdentities;
  final List<String> resolvedSelectors = <String>[];
  final List<String> deletedSelectors = <String>[];

  @override
  Future<AppSession?> defaultIdentity() async => _defaultIdentity;

  @override
  Future<List<AppSession>> listLocalIdentities() async => <AppSession>[
    if (_defaultIdentity != null) _defaultIdentity,
    ..._extraIdentities,
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
  Future<AppSession> registerHandleWithoutContactVerification({
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => _session('open');

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
  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
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

class _FakeActiveSessionStore implements ActiveSessionStore {
  _FakeActiveSessionStore([this.activeIdentityId])
    : failWriteOnce = false,
      writeBeforeFailure = false;

  _FakeActiveSessionStore.failing([this.activeIdentityId])
    : failWriteOnce = true,
      writeBeforeFailure = true;

  String? activeIdentityId;
  bool failWriteOnce;
  final bool writeBeforeFailure;

  @override
  Future<void> clearActiveIdentityId() async {
    activeIdentityId = null;
  }

  @override
  Future<String?> readActiveIdentityId() async => activeIdentityId;

  @override
  Future<void> writeActiveIdentityId(String identityId) async {
    if (failWriteOnce) {
      failWriteOnce = false;
      if (writeBeforeFailure) {
        activeIdentityId = identityId;
      }
      throw StateError('active_session_write_failed');
    }
    activeIdentityId = identityId;
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
