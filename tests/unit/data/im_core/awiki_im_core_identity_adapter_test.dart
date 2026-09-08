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

  test(
    'Core recovery admission returns typed continuation instead of registration',
    () async {
      final sdk = _IdentityErrorCore()
        ..registrationError = const core.AwikiImCoreException(
          code: 'service_error',
          message: 'safe',
          handleRecoveryFailureCode:
              core.HandleRecoveryFailureCode.recoveryInProgress,
        );
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );
      final result = await adapter.registerHandleWithPhone(
        phone: '+8613800138000',
        otp: '123456',
        handle: 'alice',
      );
      expect(result.status, IdentityRegistrationStatus.recoveryRequired);
      expect(result.identity, isNull);
      expect(result.existingHandleContinuationId, isNull);
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

  test(
    'new registration preparation supersedes only the same local Handle',
    () async {
      final sdk = _IdentityErrorCore();
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );
      final first = await adapter.registerHandleWithPhone(
        phone: '+8613800138000',
        otp: '123456',
        handle: 'alice',
      );
      final second = await adapter.registerHandleWithPhone(
        phone: '+8613800138000',
        otp: '654321',
        handle: 'alice',
      );

      expect(
        first.existingHandleContinuationId,
        isNot(second.existingHandleContinuationId),
      );
      await expectLater(
        adapter.beginExistingHandleDeviceJoin(
          first.existingHandleContinuationId!,
          userPresenceConfirmed: false,
        ),
        throwsA(isA<StateError>()),
      );
      final resumed = await adapter.beginExistingHandleDeviceJoin(
        second.existingHandleContinuationId!,
        userPresenceConfirmed: false,
      );
      expect(resumed.joinSessionId, 'join-registration-recovery');
    },
  );

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

  test(
    'adapter projects prepare, pending, and complete deletion APIs',
    () async {
      final sdk = _IdentityErrorCore();
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );

      final prepared = await adapter.prepareLocalIdentityDataDeletion(
        'identity-alice',
      );
      final pending = await adapter.pendingLocalIdentityDataDeletions();
      final completed = await adapter.completeLocalIdentityDataDeletion(
        prepared.deletionId,
      );

      expect(prepared.deletionId, 'delete-alice-1');
      expect(prepared.ownerIdentityId, 'identity-alice');
      expect(prepared.currentDid, 'did:wba:awiki.info:user:alice:e1_current');
      expect(pending, hasLength(1));
      expect(pending.single.deletionId, prepared.deletionId);
      expect(completed.identityId, 'identity-alice');
    },
  );

  test(
    'adapter maps every stable guard through all deletion entries',
    () async {
      const codes = <String>[
        'handle_recovery.precommit_discard_required',
        'handle_recovery.operation_must_resume',
        'handle_recovery.transition_must_complete',
        'handle_recovery.join_must_complete',
        'identity.local_data_deletion_pending',
        'identity.local_deletion_conflict',
      ];
      for (final code in codes) {
        final sdk = _IdentityErrorCore()
          ..deletionError = core.AwikiImCoreException(
            code: 'service_error',
            message: 'redacted deletion guard',
            serviceCode: code,
          );
        final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
          coreInstance: () async => sdk,
        );
        for (final action in <Future<Object?> Function()>[
          () => adapter.deleteLocalIdentity('identity-alice'),
          () => adapter.deleteLocalIdentityData('identity-alice'),
          () => adapter.prepareLocalIdentityDataDeletion('identity-alice'),
          () => adapter.completeLocalIdentityDataDeletion('delete-alice-1'),
        ]) {
          await expectLater(
            action(),
            throwsA(
              isA<AppStructuredError>().having(
                structuredAppErrorCode,
                'code',
                code,
              ),
            ),
          );
        }
      }
    },
  );
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
  Object? deletionError;

  static const _deletedIdentity = core.DeleteLocalIdentityResult(
    deleted: core.IdentitySummary(
      id: 'identity-alice',
      did: 'did:wba:awiki.info:user:alice:e1_current',
      handle: 'alice.awiki.info',
      localAlias: 'alice',
      isDefault: true,
      readyForAuth: false,
      readyForMessaging: false,
    ),
    wasDefault: true,
  );

  @override
  Future<core.DeleteLocalIdentityResult> deleteLocalIdentity(
    core.IdentitySelector selector,
  ) async {
    final error = deletionError;
    if (error != null) throw error;
    return _deletedIdentity;
  }

  @override
  Future<core.DeleteLocalIdentityResult> deleteLocalIdentityData(
    core.IdentitySelector selector,
  ) async {
    final error = deletionError;
    if (error != null) throw error;
    return _deletedIdentity;
  }

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
  Future<core.LocalIdentityDeletionTicket> prepareLocalIdentityDataDeletion(
    core.IdentitySelector selector,
  ) async {
    final error = deletionError;
    if (error != null) throw error;
    return const core.LocalIdentityDeletionTicket(
      deletionId: 'delete-alice-1',
      ownerIdentityId: 'identity-alice',
      currentDid: 'did:wba:awiki.info:user:alice:e1_current',
    );
  }

  @override
  Future<List<core.LocalIdentityDeletionTicket>>
  pendingLocalIdentityDataDeletions() async =>
      const <core.LocalIdentityDeletionTicket>[
        core.LocalIdentityDeletionTicket(
          deletionId: 'delete-alice-1',
          ownerIdentityId: 'identity-alice',
          currentDid: 'did:wba:awiki.info:user:alice:e1_current',
        ),
      ];

  @override
  Future<core.DeleteLocalIdentityResult> completeLocalIdentityDataDeletion(
    String deletionId,
  ) async {
    final error = deletionError;
    if (error != null) throw error;
    return _deletedIdentity;
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
