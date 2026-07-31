import 'dart:async';

import 'package:awiki_me/src/application/active_session_store.dart';
import 'package:awiki_me/src/application/app_session_service.dart';
import 'package:awiki_me/src/application/models/app_auth_state.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/daemon_subkey_authorization_revoke_result.dart';
import 'package:awiki_me/src/application/ports/auth_core_port.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/application/ports/im_core_runtime_port.dart';
import 'package:awiki_me/src/application/ports/legacy_identity_upgrade_port.dart';
import 'package:awiki_me/src/application/ports/realtime_core_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
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
        final identities = _FakeIdentities(defaultIdentity: identity);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: identities,
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
        expect(restored?.ownerIdentityId, 'id-default');
        expect(restored?.accountId, 'account-id-default');
        expect(restored?.protocolDeviceId, 'protocol-device-id-default');
        expect(runtime.openCount, 1);
        expect(runtime.vaultChecks, ['id-default']);
        expect(runtime.switchedIdentities, ['id-default']);
        expect(auth.ensureCount, 1);
      },
    );

    test(
      'restoreSession upgrades a legacy active identity before activation',
      () async {
        final identity = _session('id-legacy');
        final legacyUpgrades = _FakeLegacyUpgrades(
          initialStatus: const LegacyIdentityUpgradeStatus.idle(),
          upgradeStatus: const LegacyIdentityUpgradeStatus.completed(),
        );
        final runtime = _FakeRuntime();
        final identities = _FakeIdentities(defaultIdentity: identity);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: identities,
          auth: _FakeAuth(),
          legacyUpgrades: legacyUpgrades,
          activeSessionStore: _FakeActiveSessionStore(identity.identityId),
        );

        final restored = await service.restoreSession();

        expect(restored?.identityId, identity.identityId);
        expect(legacyUpgrades.statusSelectors, <String>[identity.identityId]);
        expect(legacyUpgrades.upgradeSelectors, <String>[identity.identityId]);
        expect(identities.listCount, 2);
        expect(runtime.switchedIdentities, <String>[identity.identityId]);
      },
    );

    test('restoreSession leaves retryable legacy identity inactive', () async {
      final identity = _session('id-legacy-retry');
      final activeStore = _FakeActiveSessionStore(identity.identityId);
      final runtime = _FakeRuntime();
      final service = ImCoreAppSessionService(
        runtime: runtime,
        identities: _FakeIdentities(defaultIdentity: identity),
        auth: _FakeAuth(),
        legacyUpgrades: _FakeLegacyUpgrades(
          initialStatus: const LegacyIdentityUpgradeStatus.idle(),
          upgradeStatus: LegacyIdentityUpgradeStatus.retryRequired(
            identityId: identity.identityId,
            failureCode: 'permission_denied',
          ),
        ),
        activeSessionStore: activeStore,
      );

      final restored = await service.restoreSession();

      expect(restored, isNull);
      expect(runtime.vaultChecks, isEmpty);
      expect(runtime.switchedIdentities, isEmpty);
      expect(activeStore.activeIdentityId, identity.identityId);
    });

    test(
      'restoreSession keeps the local identity when auth is temporarily offline',
      () async {
        final runtime = _FakeRuntime();
        final identity = _session('id-offline').copyWith(
          authenticated: true,
          expiresAt: DateTime.utc(2026, 5, 22),
          jwtToken: 'stale-jwt',
        );
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
        expect(restored?.expiresAt, isNull);
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
      'activateIdentity fails closed when the active binding mismatches identity',
      () async {
        final identity = _session('id-binding');
        final identities = _FakeIdentities(
          defaultIdentity: identity,
          activeBinding: const SessionAccountBinding(
            ownerIdentityId: 'another-owner',
            accountId: 'account-binding',
            currentDid: 'did:wba:awiki.ai:alice:e1_id-binding',
            protocolDeviceId: 'protocol-device-binding',
            identityGeneration: '1',
            deviceAuthGeneration: '2',
          ),
        );
        final active = _FakeActiveSessionStore('id-previous');
        final auth = _FakeAuth();
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: identities,
          auth: auth,
          activeSessionStore: active,
        );

        await expectLater(
          service.loginWithIdentity('alice-local'),
          throwsStateError,
        );

        expect(identities.activeBindingCount, 1);
        expect(auth.ensureCount, 0);
        expect(await active.readActiveIdentityId(), isNull);
        expect(await service.currentSession(), isNull);
      },
    );

    test(
      'activateIdentity does not infer a binding when Core reports unavailable',
      () async {
        final active = _FakeActiveSessionStore('id-previous');
        final identities = _FakeIdentities(
          defaultIdentity: _session('id-unavailable'),
          activeBindingError: StateError(
            'active_sync_account_binding_unavailable',
          ),
        );
        final auth = _FakeAuth();
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: identities,
          auth: auth,
          activeSessionStore: active,
        );

        await expectLater(
          service.loginWithIdentity('alice-local'),
          throwsStateError,
        );

        expect(auth.ensureCount, 0);
        expect(await active.readActiveIdentityId(), isNull);
        expect(await service.currentSession(), isNull);
      },
    );

    test(
      'activateIdentity rejects non-canonical binding generations',
      () async {
        final identity = _session('id-generation');
        final auth = _FakeAuth();
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(
            defaultIdentity: identity,
            activeBinding: SessionAccountBinding(
              ownerIdentityId: identity.identityId,
              accountId: 'account-generation',
              currentDid: identity.did,
              protocolDeviceId: 'protocol-device-generation',
              identityGeneration: '01',
              deviceAuthGeneration: '2',
            ),
          ),
          auth: auth,
          activeSessionStore: _FakeActiveSessionStore(),
        );

        await expectLater(
          service.loginWithIdentity('alice-local'),
          throwsStateError,
        );
        expect(auth.ensureCount, 0);
      },
    );

    test('activateIdentity rejects zero binding generations', () async {
      final identity = _session('id-zero-generation');

      for (final generations in [
        (identity: '0', deviceAuth: '2'),
        (identity: '1', deviceAuth: '0'),
      ]) {
        final auth = _FakeAuth();
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(
            defaultIdentity: identity,
            activeBinding: SessionAccountBinding(
              ownerIdentityId: identity.identityId,
              accountId: 'account-zero-generation',
              currentDid: identity.did,
              protocolDeviceId: 'protocol-device-zero-generation',
              identityGeneration: generations.identity,
              deviceAuthGeneration: generations.deviceAuth,
            ),
          ),
          auth: auth,
          activeSessionStore: _FakeActiveSessionStore(),
        );

        await expectLater(
          service.loginWithIdentity('alice-local'),
          throwsStateError,
        );
        expect(auth.ensureCount, 0);
      }
    });

    test('activateIdentity rejects reserved protocol device id', () async {
      final identity = _session('id-reserved-device');
      final auth = _FakeAuth();
      final service = ImCoreAppSessionService(
        runtime: _FakeRuntime(),
        identities: _FakeIdentities(
          defaultIdentity: identity,
          activeBinding: SessionAccountBinding(
            ownerIdentityId: identity.identityId,
            accountId: 'account-reserved-device',
            currentDid: identity.did,
            protocolDeviceId: 'default',
            identityGeneration: '1',
            deviceAuthGeneration: '2',
          ),
        ),
        auth: auth,
        activeSessionStore: _FakeActiveSessionStore(),
      );

      await expectLater(
        service.loginWithIdentity('alice-local'),
        throwsStateError,
      );
      expect(auth.ensureCount, 0);
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

    test(
      'session leases are committed, cancellable, and relogin-scoped',
      () async {
        final identity = _session('id-default');
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: _FakeAuth(),
          activeSessionStore: _FakeActiveSessionStore(identity.identityId),
        );

        await service.restoreSession();
        final restoredLease = await service.currentSessionLease();
        expect(restoredLease?.session.identityId, identity.identityId);

        service.cancelPendingSessionTransition(restoredLease!.transition);
        expect(
          (await service.currentSessionLease())?.transition,
          same(restoredLease.transition),
        );

        final pending = service.beginSessionTransition();
        expect(await service.currentSessionLease(), isNull);
        service.cancelPendingSessionTransition(pending);
        expect(
          (await service.currentSessionLease())?.transition,
          same(restoredLease.transition),
        );

        await service.loginWithIdentity(identity.localAlias!);
        final reloginLease = await service.currentSessionLease();
        expect(reloginLease?.session.identityId, identity.identityId);
        expect(reloginLease?.transition, isNot(same(restoredLease.transition)));
      },
    );

    test('abort clears only the matching committed session', () async {
      final identity = _session('id-default');
      final active = _FakeActiveSessionStore(identity.identityId);
      final realtime = _FakeRealtime();
      final service = ImCoreAppSessionService(
        runtime: _FakeRuntime(),
        identities: _FakeIdentities(defaultIdentity: identity),
        auth: _FakeAuth(),
        activeSessionStore: active,
        realtime: realtime,
      );
      await service.restoreSession();
      await realtime.start();
      final lease = (await service.currentSessionLease())!;

      expect(await service.abortSessionIfCurrent(lease), isTrue);

      expect(await service.currentSession(), isNull);
      expect(await service.currentSessionLease(), isNull);
      expect(await active.readActiveIdentityId(), isNull);
      expect(realtime.stopCount, 1);
    });

    test(
      'abort preserves the committed lease when its identity invariant fails',
      () async {
        final identity = _session('id-default');
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: _FakeAuth(),
          activeSessionStore: _FakeActiveSessionStore(identity.identityId),
        );
        await service.restoreSession();
        final lease = (await service.currentSessionLease())!;
        final mismatchedLease = AppSessionLease(
          session: _session('id-other'),
          transition: lease.transition,
        );

        expect(await service.abortSessionIfCurrent(mismatchedLease), isFalse);

        final current = await service.currentSessionLease();
        expect(current?.transition, same(lease.transition));
        expect(current?.session.identityId, identity.identityId);
      },
    );

    test(
      'abort stops realtime even when active-session cleanup fails',
      () async {
        final identity = _session('id-default');
        final active = _FakeActiveSessionStore(identity.identityId)
          ..clearError = StateError('active session store unavailable');
        final realtime = _FakeRealtime();
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: _FakeAuth(),
          activeSessionStore: active,
          realtime: realtime,
        );
        await service.restoreSession();
        await realtime.start();
        final lease = (await service.currentSessionLease())!;

        await expectLater(
          service.abortSessionIfCurrent(lease),
          throwsStateError,
        );

        expect(await service.currentSession(), isNull);
        expect(await service.currentSessionLease(), isNull);
        expect(realtime.stopCount, 1);
        expect(await active.readActiveIdentityId(), identity.identityId);
      },
    );

    test('an old lease cannot abort a replacement session', () async {
      final first = _session('id-first');
      final second = _session(
        'id-second',
      ).copyWith(handle: 'bob.awiki', localAlias: 'bob-local');
      final active = _FakeActiveSessionStore(first.identityId);
      final service = ImCoreAppSessionService(
        runtime: _FakeRuntime(),
        identities: _FakeIdentities(
          defaultIdentity: first,
          extraIdentities: <AppSession>[second],
        ),
        auth: _FakeAuth(),
        activeSessionStore: active,
      );
      await service.restoreSession();
      final firstLease = (await service.currentSessionLease())!;
      await service.loginWithIdentity(second.localAlias!);

      expect(await service.abortSessionIfCurrent(firstLease), isFalse);

      expect((await service.currentSession())?.identityId, second.identityId);
      expect(
        (await service.currentSessionLease())?.session.identityId,
        second.identityId,
      );
      expect(await active.readActiveIdentityId(), second.identityId);
    });

    test(
      'failed login intent restores the previous committed session lease',
      () async {
        final first = _session('id-first');
        final second = _session(
          'id-second',
        ).copyWith(handle: 'bob.awiki', localAlias: 'bob-local');
        final runtime = _FakeRuntime(
          vaultErrorsByIdentity: <String, Object>{
            second.identityId: StateError('second vault unavailable'),
          },
        );
        final active = _FakeActiveSessionStore(first.identityId);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(
            defaultIdentity: first,
            extraIdentities: <AppSession>[second],
          ),
          auth: _FakeAuth(),
          activeSessionStore: active,
        );
        await service.restoreSession();
        final firstLease = await service.currentSessionLease();

        await expectLater(
          service.loginWithIdentity(second.localAlias!),
          throwsStateError,
        );

        final restoredLease = await service.currentSessionLease();
        expect(restoredLease?.session.identityId, first.identityId);
        expect(restoredLease?.transition, same(firstLease!.transition));
        expect(await active.readActiveIdentityId(), first.identityId);
        expect(runtime.switchedIdentities, <String>[first.identityId]);
      },
    );

    test(
      'auth failure after identity cutover fails closed without restoring the old lease',
      () async {
        final first = _session('id-first');
        final second = _session(
          'id-second',
        ).copyWith(handle: 'bob.awiki', localAlias: 'bob-local');
        final secondAuth = Completer<AppAuthState>();
        final runtime = _FakeRuntime();
        final realtime = _FakeRealtime();
        final active = _FakeActiveSessionStore(first.identityId);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(
            defaultIdentity: first,
            extraIdentities: <AppSession>[second],
          ),
          auth: _FakeAuth(ensureCompleter: secondAuth, ensureCompleterCall: 2),
          activeSessionStore: active,
          realtime: realtime,
        );
        await service.restoreSession();
        await realtime.start();
        final firstLease = (await service.currentSessionLease())!;

        final switching = service.loginWithIdentity(second.localAlias!);
        await pumpEventQueue();

        expect(runtime.switchedIdentities, <String>[
          first.identityId,
          second.identityId,
        ]);
        expect(realtime.stopCount, 1);
        expect(realtime.isRunning, isFalse);
        expect(await service.currentSession(), isNull);
        expect(await service.currentSessionLease(), isNull);

        secondAuth.completeError(StateError('second authentication failed'));
        await expectLater(switching, throwsStateError);

        expect(await service.currentSession(), isNull);
        expect(await service.currentSessionLease(), isNull);
        expect(
          service.isSessionTransitionCurrent(firstLease.transition),
          isFalse,
        );
        expect(await active.readActiveIdentityId(), first.identityId);
        expect(realtime.stopCount, 1);
        expect(realtime.isRunning, isFalse);
      },
    );

    test(
      'active-session store failure after identity cutover fails closed without restoring the old lease',
      () async {
        final first = _session('id-first');
        final second = _session(
          'id-second',
        ).copyWith(handle: 'bob.awiki', localAlias: 'bob-local');
        final runtime = _FakeRuntime();
        final realtime = _FakeRealtime();
        final active = _FakeActiveSessionStore(first.identityId);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(
            defaultIdentity: first,
            extraIdentities: <AppSession>[second],
          ),
          auth: _FakeAuth(),
          activeSessionStore: active,
          realtime: realtime,
        );
        await service.restoreSession();
        await realtime.start();
        final firstLease = (await service.currentSessionLease())!;
        active.writeError = StateError('active session store unavailable');

        await expectLater(
          service.loginWithIdentity(second.localAlias!),
          throwsStateError,
        );

        expect(runtime.switchedIdentities, <String>[
          first.identityId,
          second.identityId,
        ]);
        expect(await service.currentSession(), isNull);
        expect(await service.currentSessionLease(), isNull);
        expect(
          service.isSessionTransitionCurrent(firstLease.transition),
          isFalse,
        );
        expect(await active.readActiveIdentityId(), first.identityId);
        expect(realtime.stopCount, 1);
        expect(realtime.isRunning, isFalse);
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

    test(
      'logout stops realtime even when active-session cleanup fails',
      () async {
        final identity = _session('id-default');
        final active = _FakeActiveSessionStore(identity.identityId)
          ..clearError = StateError('active session store unavailable');
        final realtime = _FakeRealtime();
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(defaultIdentity: identity),
          auth: _FakeAuth(),
          activeSessionStore: active,
          realtime: realtime,
        );
        await service.restoreSession();
        await realtime.start();

        await expectLater(service.logout(), throwsStateError);

        expect(await service.currentSession(), isNull);
        expect(await service.currentSessionLease(), isNull);
        expect(realtime.stopCount, 1);
        expect(await active.readActiveIdentityId(), identity.identityId);
      },
    );

    test(
      'logout invalidates the session before realtime shutdown completes',
      () async {
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
        final logout = service.logout();
        var logoutCompleted = false;
        unawaited(logout.then((_) => logoutCompleted = true));
        await pumpEventQueue();

        expect(await service.currentSession(), isNull);
        expect(await active.readActiveIdentityId(), isNull);
        expect(runtime.disposeCount, 0);
        expect(realtime.stopCount, 1);
        expect(logoutCompleted, isFalse);
        stopCompleter.complete();
        await logout;
        expect(logoutCompleted, isTrue);
      },
    );

    test('logout bounds an unresponsive realtime shutdown', () async {
      final stopCompleter = Completer<void>();
      final realtime = _FakeRealtime(onStop: () async => stopCompleter.future);
      final service = ImCoreAppSessionService(
        runtime: _FakeRuntime(),
        identities: _FakeIdentities(defaultIdentity: _session('id-default')),
        auth: _FakeAuth(),
        activeSessionStore: _FakeActiveSessionStore('id-default'),
        realtime: realtime,
        realtimeCleanupTimeout: const Duration(milliseconds: 20),
      );

      await service.restoreSession();
      await service.logout();

      expect(await service.currentSession(), isNull);
      expect(realtime.stopCount, 1);
      stopCompleter.complete();
    });

    test(
      'identity switch waits for the previous realtime owner to stop',
      () async {
        final oldOwnerStop = Completer<void>();
        final runtime = _FakeRuntime();
        final realtime = _FakeRealtime(onStop: () async => oldOwnerStop.future);
        final first = _session('id-first');
        final second = _session(
          'id-second',
        ).copyWith(handle: 'bob.awiki', localAlias: 'bob-local');
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(
            defaultIdentity: first,
            extraIdentities: <AppSession>[second],
          ),
          auth: _FakeAuth(),
          activeSessionStore: _FakeActiveSessionStore(first.identityId),
          realtime: realtime,
        );

        await service.restoreSession();
        await realtime.start();
        final switching = service.loginWithIdentity(second.identityId);
        await pumpEventQueue();

        expect(await service.currentSession(), isNull);
        expect(runtime.switchedIdentities, <String>[first.identityId]);
        expect(realtime.stopCount, 1);

        oldOwnerStop.complete();
        final activated = await switching;

        expect(activated.identityId, second.identityId);
        expect(runtime.switchedIdentities, <String>[
          first.identityId,
          second.identityId,
        ]);
      },
    );

    test(
      'a superseded prepared activation cannot commit over a newer login',
      () async {
        final first = _session('id-first');
        final prepared = _session(
          'id-prepared',
        ).copyWith(handle: 'prepared.awiki', localAlias: 'prepared-local');
        final latest = _session(
          'id-latest',
        ).copyWith(handle: 'latest.awiki', localAlias: 'latest-local');
        final runtime = _FakeRuntime();
        final active = _FakeActiveSessionStore(first.identityId);
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(
            defaultIdentity: first,
            extraIdentities: <AppSession>[latest],
          ),
          auth: _FakeAuth(),
          activeSessionStore: active,
          realtime: _FakeRealtime(),
        );
        await service.restoreSession();

        final initializerStarted = Completer<void>();
        final releaseInitializer = Completer<void>();
        final preparedTransition = service.beginSessionTransition();
        final staleActivation = service.activateIdentity(
          prepared,
          transition: preparedTransition,
          initializeIdentitySession: (_) async {
            initializerStarted.complete();
            await releaseInitializer.future;
          },
        );
        await initializerStarted.future;

        final latestLogin = service.loginWithIdentity(latest.localAlias!);
        releaseInitializer.complete();

        await expectLater(
          staleActivation,
          throwsA(isA<AppSessionTransitionSuperseded>()),
        );
        final activated = await latestLogin;

        expect(activated.identityId, latest.identityId);
        expect((await service.currentSession())?.identityId, latest.identityId);
        expect(await active.readActiveIdentityId(), latest.identityId);
        expect(runtime.switchedIdentities, <String>[
          first.identityId,
          prepared.identityId,
          latest.identityId,
        ]);
      },
    );

    test(
      'a superseded login normalizes its late auth error before the latest login',
      () async {
        final first = _session('id-first');
        final stale = _session(
          'id-stale',
        ).copyWith(handle: 'stale.awiki', localAlias: 'stale-local');
        final latest = _session(
          'id-latest',
        ).copyWith(handle: 'latest.awiki', localAlias: 'latest-local');
        final staleAuth = Completer<AppAuthState>();
        final auth = _FakeAuth(
          ensureCompleter: staleAuth,
          ensureCompleterCall: 2,
        );
        final service = ImCoreAppSessionService(
          runtime: _FakeRuntime(),
          identities: _FakeIdentities(
            defaultIdentity: first,
            extraIdentities: <AppSession>[stale, latest],
          ),
          auth: auth,
          activeSessionStore: _FakeActiveSessionStore(first.identityId),
          realtime: _FakeRealtime(),
        );
        await service.restoreSession();

        final staleLogin = service.loginWithIdentity(stale.localAlias!);
        await pumpEventQueue();
        final latestLogin = service.loginWithIdentity(latest.localAlias!);
        staleAuth.completeError(StateError('session_expired'));

        await expectLater(
          staleLogin,
          throwsA(isA<AppSessionTransitionSuperseded>()),
        );
        final activated = await latestLogin;

        expect(activated.identityId, latest.identityId);
        expect((await service.currentSession())?.identityId, latest.identityId);
      },
    );

    test('a refresh cannot publish after a newer identity intent', () async {
      final first = _session('id-first');
      final latest = _session(
        'id-latest',
      ).copyWith(handle: 'latest.awiki', localAlias: 'latest-local');
      final refreshResult = Completer<AppAuthState>();
      final auth = _FakeAuth(refreshCompleter: refreshResult);
      final service = ImCoreAppSessionService(
        runtime: _FakeRuntime(),
        identities: _FakeIdentities(
          defaultIdentity: first,
          extraIdentities: <AppSession>[latest],
        ),
        auth: auth,
        activeSessionStore: _FakeActiveSessionStore(first.identityId),
      );
      await service.restoreSession();

      final staleRefresh = service.refreshSession();
      await pumpEventQueue();
      expect(auth.refreshCount, 1);
      final latestLogin = service.loginWithIdentity(latest.localAlias!);
      refreshResult.complete(
        AppAuthState(
          authenticated: true,
          subject: first.did,
          bearerToken: 'stale-token',
        ),
      );

      expect(await staleRefresh, isNull);
      final activated = await latestLogin;
      expect(activated.identityId, latest.identityId);
      expect((await service.currentSession())?.identityId, latest.identityId);
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
      'disposeRuntime still disposes core and reports realtime cleanup failure',
      () async {
        final runtime = _FakeRuntime();
        final realtime = _FakeRealtime(
          onStop: () async => throw StateError('realtime stop failed'),
        );
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: _FakeIdentities(defaultIdentity: _session('id-default')),
          auth: _FakeAuth(),
          activeSessionStore: _FakeActiveSessionStore('id-default'),
          realtime: realtime,
        );

        await service.restoreSession();

        await expectLater(service.disposeRuntime(), throwsStateError);
        expect(realtime.stopCount, 1);
        expect(runtime.disposeCount, 1);
        expect(await service.currentSession(), isNull);
      },
    );

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
        await pumpEventQueue();

        expect(deleted.identityId, identity.identityId);
        expect(identities.deletedSelectors, ['alice-local']);
        expect(realtime.stopCount, 1);
        expect(runtime.disposeCount, 1);
        expect(await service.currentSession(), isNull);
      },
    );

    test(
      'deleteLocalIdentity is offline-first when realtime and runtime cleanup are slow',
      () async {
        final realtimeStop = Completer<void>();
        final runtimeDispose = Completer<void>();
        final runtime = _FakeRuntime(
          onDispose: () async => runtimeDispose.future,
        );
        final realtime = _FakeRealtime(onStop: () async => realtimeStop.future);
        final identity = _session('id-default');
        final identities = _FakeIdentities(defaultIdentity: identity);
        final active = _FakeActiveSessionStore('id-default');
        final service = ImCoreAppSessionService(
          runtime: runtime,
          identities: identities,
          auth: _FakeAuth(),
          activeSessionStore: active,
          realtime: realtime,
        );

        await service.restoreSession();
        final deleted = await service
            .deleteLocalIdentity('alice-local')
            .timeout(const Duration(seconds: 1));

        expect(deleted.identityId, identity.identityId);
        expect(identities.deletedSelectors, ['alice-local']);
        expect(await active.readActiveIdentityId(), isNull);
        expect(await service.currentSession(), isNull);
        expect(realtime.stopCount, 1);
        expect(runtime.disposeCount, 0);

        realtimeStop.complete();
        await pumpEventQueue();
        expect(runtime.disposeCount, 1);
        runtimeDispose.complete();
        await pumpEventQueue();
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
  _FakeRuntime({
    this.vaultError,
    this.vaultErrorsByIdentity = const {},
    this.onDispose,
  });

  final Object? vaultError;
  final Map<String, Object> vaultErrorsByIdentity;
  final Future<void> Function()? onDispose;
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
    final error = vaultErrorsByIdentity[identityIdOrAlias] ?? vaultError;
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
    await onDispose?.call();
  }
}

class _FakeIdentities implements IdentityCorePort {
  _FakeIdentities({
    AppSession? defaultIdentity,
    AppSession? resolvedIdentity,
    List<AppSession> extraIdentities = const <AppSession>[],
    SessionAccountBinding? activeBinding,
    this.activeBindingError,
  }) : _defaultIdentity = defaultIdentity,
       _resolvedIdentity = resolvedIdentity,
       _extraIdentities = extraIdentities,
       _activeBinding =
           activeBinding ??
           _bindingFor(
             defaultIdentity ?? resolvedIdentity ?? _session('id-default'),
           );

  final AppSession? _defaultIdentity;
  final AppSession? _resolvedIdentity;
  final List<AppSession> _extraIdentities;
  final SessionAccountBinding _activeBinding;
  final Object? activeBindingError;
  final List<String> resolvedSelectors = <String>[];
  final List<String> deletedSelectors = <String>[];
  int activeBindingCount = 0;
  int listCount = 0;

  @override
  Future<SessionAccountBinding> activeSyncAccountBinding() async {
    activeBindingCount += 1;
    final error = activeBindingError;
    if (error != null) {
      throw error;
    }
    return _activeBinding;
  }

  @override
  Future<AppSession?> defaultIdentity() async => _defaultIdentity;

  @override
  Future<List<AppSession>> listLocalIdentities() async {
    listCount += 1;
    return <AppSession>[
      if (_defaultIdentity != null) _defaultIdentity,
      ..._extraIdentities,
    ];
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => IdentityRegistrationResult(
    status: IdentityRegistrationStatus.registered,
    identity: _session('email'),
  );

  @override
  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => IdentityRegistrationResult(
    status: IdentityRegistrationStatus.registered,
    identity: _session('phone'),
  );

  @override
  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String handle,
    String? inviteCode,
    String? displayName,
  }) async => IdentityRegistrationResult(
    status: IdentityRegistrationStatus.registered,
    identity: _session('open'),
  );

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

class _FakeLegacyUpgrades implements LegacyIdentityUpgradePort {
  _FakeLegacyUpgrades({
    required this.initialStatus,
    required this.upgradeStatus,
  });

  final LegacyIdentityUpgradeStatus initialStatus;
  final LegacyIdentityUpgradeStatus upgradeStatus;
  final List<String> statusSelectors = <String>[];
  final List<String> upgradeSelectors = <String>[];

  @override
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  ) async {
    statusSelectors.add(identityIdOrAlias);
    return initialStatus;
  }

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) async {
    upgradeSelectors.add(identityIdOrAlias);
    return upgradeStatus;
  }
}

SessionAccountBinding _bindingFor(AppSession identity) {
  return SessionAccountBinding(
    ownerIdentityId: identity.identityId,
    accountId: 'account-${identity.identityId}',
    currentDid: identity.did,
    protocolDeviceId: 'protocol-device-${identity.identityId}',
    identityGeneration: '1',
    deviceAuthGeneration: '2',
  );
}

class _FakeActiveSessionStore implements ActiveSessionStore {
  _FakeActiveSessionStore([this.activeIdentityId])
    : failWriteOnce = false,
      writeBeforeFailure = false;

  _FakeActiveSessionStore.failing([this.activeIdentityId])
    : failWriteOnce = true,
      writeBeforeFailure = true;

  String? activeIdentityId;
  Object? clearError;
  Object? writeError;
  bool failWriteOnce;
  final bool writeBeforeFailure;

  @override
  Future<void> clearActiveIdentityId() async {
    final error = clearError;
    if (error != null) {
      throw error;
    }
    activeIdentityId = null;
  }

  @override
  Future<String?> readActiveIdentityId() async => activeIdentityId;

  @override
  Future<void> writeActiveIdentityId(String identityId) async {
    final error = writeError;
    if (error != null) {
      throw error;
    }
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
    this.ensureCompleter,
    this.ensureCompleterCall,
    this.refreshCompleter,
  }) : _ensureResult = ensureResult ?? const AppAuthState(authenticated: true),
       _refreshResult =
           refreshResult ?? const AppAuthState(authenticated: true);

  final AppAuthState _ensureResult;
  final AppAuthState _refreshResult;
  final Object? ensureError;
  final Completer<AppAuthState>? ensureCompleter;
  final int? ensureCompleterCall;
  final Completer<AppAuthState>? refreshCompleter;
  int ensureCount = 0;
  int refreshCount = 0;

  @override
  Future<AppAuthState> ensureSession() async {
    ensureCount += 1;
    if (ensureCount == ensureCompleterCall) {
      return ensureCompleter!.future;
    }
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
    final completer = refreshCompleter;
    if (completer != null) {
      return completer.future;
    }
    return _refreshResult;
  }

  @override
  Future<AppAuthState> status() async => _ensureResult;
}

class _FakeRealtime implements RealtimeCorePort {
  _FakeRealtime({this.onStop});

  final Future<void> Function()? onStop;
  int stopCount = 0;
  bool _isRunning = false;

  @override
  Stream<RealtimeConnectionStatus> get connectionStates => const Stream.empty();

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<RealtimeUpdate> get updates => const Stream.empty();

  @override
  Future<void> start() async {
    _isRunning = true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _isRunning = false;
    await onStop?.call();
  }
}
