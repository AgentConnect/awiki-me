import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/core/app_error_classifier.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_identity_adapter.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dotless local alias falls back after identity id lookup', () {
    final selectors = identitySelectorCandidates('cgw-038');

    expect(selectors, hasLength(2));
    expect(selectors[0], isA<core.IdIdentitySelector>());
    expect((selectors[0] as core.IdIdentitySelector).id, 'cgw-038');
    expect(selectors[1], isA<core.LocalAliasIdentitySelector>());
    expect((selectors[1] as core.LocalAliasIdentitySelector).alias, 'cgw-038');
  });

  test('unambiguous selectors do not add a local alias fallback', () {
    expect(
      identitySelectorCandidates('default').single,
      isA<core.DefaultIdentitySelector>(),
    );
    expect(
      identitySelectorCandidates('did:wba:awiki.info:user:alice:e1_a').single,
      isA<core.DidIdentitySelector>(),
    );
    expect(
      identitySelectorCandidates('alice.awiki.info').single,
      isA<core.HandleIdentitySelector>(),
    );
  });

  test(
    'registration_recovery_join projects only the Core mode and reset reference',
    () {
      expect(
        existingHandleJoinModeFromCore(
          core.HandleRegistrationJoinMode.handleRecoveryRebind,
        ),
        ExistingHandleJoinMode.handleRecoveryRebind,
      );
      final projected = preparedRegistrationJoinProgressFromCore(
        _authorizedRegistrationJoin(
          reset: const core.HandleRecoveryRegistryEpochReset(
            accountUserId: 'account-alice',
            ownerIdentityId: 'owner-alice',
            handle: 'alice.awiki.info',
            previousDid: 'did:wba:awiki.info:user:alice:e1_previous',
            currentDid: 'did:wba:awiki.info:user:alice:e1_current',
            bindingGeneration: '8',
            sourceKind: core.HandleRecoveryTransitionSourceKind.joinedDevice,
            sourceId: 'join-registration-recovery',
          ),
        ),
        ExistingHandleJoinMode.handleRecoveryRebind,
      );

      expect(projected.cause, DeviceJoinCause.handleRecovery);
      expect(projected.handleRecovery?.handle, 'alice.awiki.info');
      expect(projected.joinSessionId, 'join-registration-recovery');
    },
  );

  test('registration_recovery_join fails closed on an ordinary-mode reset', () {
    expect(
      () => preparedRegistrationJoinProgressFromCore(
        _authorizedRegistrationJoin(
          reset: const core.HandleRecoveryRegistryEpochReset(
            accountUserId: 'account-alice',
            ownerIdentityId: 'owner-alice',
            handle: 'alice.awiki.info',
            previousDid: 'did:wba:awiki.info:user:alice:e1_previous',
            currentDid: 'did:wba:awiki.info:user:alice:e1_current',
            bindingGeneration: '8',
            sourceKind: core.HandleRecoveryTransitionSourceKind.joinedDevice,
            sourceId: 'join-registration-recovery',
          ),
        ),
        ExistingHandleJoinMode.ordinary,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'adapter maps structured registration errors at the Core seam',
    () async {
      final sdk = _IdentityErrorCore()..registrationError = _recoveryStateError;
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );

      await expectLater(
        adapter.registerHandleWithPhone(
          phone: '+8613800138000',
          otp: '123456',
          handle: 'alice',
        ),
        throwsA(
          isA<AppStructuredError>().having(
            structuredAppErrorCode,
            'code',
            'identity.registration_recovery_state_invalid',
          ),
        ),
      );
    },
  );

  test('adapter preserves structured errors through prepared Join', () async {
    final sdk = _IdentityErrorCore();
    final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
      coreInstance: () async => sdk,
    );
    final registration = await adapter.registerHandleWithPhone(
      phone: '+8613800138000',
      otp: '123456',
      handle: 'alice',
    );
    sdk.joinError = _recoveryStateError;

    await expectLater(
      adapter.beginExistingHandleDeviceJoin(
        registration.existingHandleContinuationId!,
        userPresenceConfirmed: false,
      ),
      throwsA(
        isA<AppStructuredError>().having(
          structuredAppErrorCode,
          'code',
          'identity.registration_recovery_state_invalid',
        ),
      ),
    );
  });

  test('adapter preserves structured errors through legacy upgrade', () async {
    final sdk = _IdentityErrorCore()..upgradeError = _recoveryStateError;
    final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
      coreInstance: () async => sdk,
    );

    await expectLater(
      adapter.upgradeLegacyIdentity('default'),
      throwsA(
        isA<AppStructuredError>().having(
          structuredAppErrorCode,
          'code',
          'identity.registration_recovery_state_invalid',
        ),
      ),
    );
  });
}

const _recoveryStateError = core.AwikiImCoreException(
  code: 'service_error',
  message: 'registration recovery state is invalid',
  serviceDataJson:
      '{"awiki_code":"identity.registration_recovery_state_invalid"}',
);

class _IdentityErrorCore implements core.AwikiImCore {
  Object? registrationError;
  Object? joinError;
  Object? upgradeError;

  @override
  Future<core.HandleRegistrationResult> registerHandleWithPhone({
    String? localAlias,
    required String requestedHandle,
    required String phone,
    String? otp,
    String? inviteCode,
    core.InitialProfile profile = const core.InitialProfile(),
    bool makeDefault = true,
  }) async {
    final error = registrationError;
    if (error != null) throw error;
    return const core.HandleRegistrationResult(
      handle: 'alice.awiki.info',
      method: 'phone',
      state: 'join_required',
      joinRequired: core.HandleRegistrationJoinRequiredPreparation(
        preparationId: 'prepared-join-1',
        mode: core.HandleRegistrationJoinMode.ordinary,
        requiresUserPresence: false,
        expectedDid: 'did:wba:awiki.info:user:alice:e1_joining',
        fullHandle: 'alice.awiki.info',
      ),
    );
  }

  @override
  Future<core.AuthorizedJoinActivationProgress>
  beginPreparedRegistrationDeviceJoin({
    required String preparationId,
    required String operationId,
    int ttlSeconds = 600,
    required bool userPresenceConfirmed,
  }) async {
    final error = joinError;
    if (error != null) throw error;
    return _authorizedRegistrationJoin();
  }

  @override
  Future<core.LegacyUpgradeStatus> upgradeLegacyIdentity(
    core.IdentitySelector selector,
  ) async {
    final error = upgradeError;
    if (error != null) throw error;
    return const core.LegacyUpgradeStatus.completed();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

core.AuthorizedJoinActivationProgress _authorizedRegistrationJoin({
  core.HandleRecoveryRegistryEpochReset? reset,
}) => core.AuthorizedJoinActivationProgress(
  join: const core.DeviceJoinProgress(
    session: core.DeviceJoinSessionSummary(
      joinSessionId: 'join-registration-recovery',
      did: 'did:wba:awiki.info:user:alice:e1_current',
      protocolDeviceId: 'device-registration-recovery',
      side: core.DeviceJoinSide.newDevice,
      phase: core.DeviceJoinPhase.pending,
      expiresAt: '2030-01-01T00:00:00Z',
    ),
    remoteState: core.DeviceJoinRemoteState.pending,
  ),
  registryEpochReset: reset,
);
