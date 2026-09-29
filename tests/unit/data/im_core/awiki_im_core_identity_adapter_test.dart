import 'dart:async';

import '../../identity_method_test_support.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/application/ports/identity_core_port.dart';
import 'package:awiki_me/src/core/app_error_classifier.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_identity_adapter.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('prepared Join keeps the real adapter result beyond UI timeout', (
    tester,
  ) async {
    final pending = Completer<void>();
    final native = _IdentityErrorCore()..pendingJoin = pending;
    final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
      coreInstance: () async => native,
    );
    final registration = await adapter.registerHandleWithPhone(
      phone: 'fixture-contact',
      otp: 'fixture-code',
      handle: 'alice',
    );
    final continuation = registration.existingHandleContinuationId!;
    final container = ProviderContainer(
      overrides: [
        identityCorePortProvider.overrideWithValue(adapter),
        onboardingProvider.overrideWith(
          (ref) => _PreparedJoinController(ref, continuation),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(onboardingProvider.notifier);
    var completed = false;
    final first = controller
        .beginExistingHandleDeviceJoin(presenceReason: 'fixture')
        .then((value) {
          completed = true;
          return value;
        });
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    expect(completed, isFalse);
    expect(container.read(onboardingProvider).isExistingHandleJoinBusy, isTrue);
    expect(container.read(uiFeedbackProvider), isNull);
    expect(
      await controller.beginExistingHandleDeviceJoin(
        presenceReason: 'duplicate',
      ),
      isFalse,
    );
    expect(native.joinCalls, 1);

    pending.complete();
    await tester.pump();
    expect(await first, isTrue);
    expect(
      container.read(onboardingProvider).isExistingHandleJoinBusy,
      isFalse,
    );
    expect(
      container.read(onboardingProvider).existingHandleContinuationId,
      isNull,
    );
    expect(
      container.read(devicesProvider).activeJoin?.joinSessionId,
      'join-registration-recovery',
    );
    // The production adapter actually consumed the continuation. No second
    // Core invocation is needed to recover the result of the first call.
    await expectLater(
      adapter.beginExistingHandleDeviceJoin(
        continuation,
        userPresenceConfirmed: false,
      ),
      throwsStateError,
    );
    expect(native.joinCalls, 1);
  });

  testWidgets(
    'prepared Join failure retries the same real adapter preparation and operation',
    (tester) async {
      final native = _IdentityErrorCore()
        ..joinError = TimeoutException('fixture transport timeout');
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => native,
      );
      final registration = await adapter.registerHandleWithPhone(
        phone: 'fixture-contact',
        otp: 'fixture-code',
        handle: 'alice',
      );
      final continuation = registration.existingHandleContinuationId!;
      final container = ProviderContainer(
        overrides: [
          identityCorePortProvider.overrideWithValue(adapter),
          onboardingProvider.overrideWith(
            (ref) => _PreparedJoinController(ref, continuation),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(onboardingProvider.notifier);
      expect(
        await controller.beginExistingHandleDeviceJoin(
          presenceReason: 'fixture',
        ),
        isFalse,
      );
      expect(
        container.read(onboardingProvider).existingHandleContinuationId,
        continuation,
      );
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'requestTimeoutRetry',
      );
      final operationId = native.lastJoinOperationId;
      final preparationId = native.lastJoinPreparationId;
      native.joinError = null;
      expect(
        await controller.beginExistingHandleDeviceJoin(
          presenceReason: 'explicit retry',
        ),
        isTrue,
      );
      expect(native.joinCalls, 2);
      expect(native.lastJoinOperationId, operationId);
      expect(native.lastJoinPreparationId, preparationId);
      expect(
        container.read(devicesProvider).activeJoin?.joinSessionId,
        'join-registration-recovery',
      );
      expect(
        container.read(onboardingProvider).existingHandleContinuationId,
        isNull,
      );
    },
  );

  test(
    'Web selection is forwarded while existing Handle capability comes from Core',
    () async {
      final native = _IdentityErrorCore();
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => native,
      );
      final existingWba = await adapter.registerHandleWithPhone(
        didMethod: IdentityDidMethod.web,
        phone: 'test-contact',
        otp: 'test-code',
        handle: 'alice',
      );
      expect(native.lastDidMethod, core.DidMethod.web);
      expect(
        existingWba.existingHandleMethodCapabilities?.method,
        IdentityDidMethod.wba,
      );
      expect(
        existingWba.existingHandleMethodCapabilities?.handleRecovery,
        isTrue,
      );
      native.methodCapabilities = coreWebMethodCapabilities;
      final existingWeb = await adapter.registerHandleWithPhone(
        didMethod: IdentityDidMethod.web,
        phone: 'test-contact',
        otp: 'test-code',
        handle: 'alice',
      );
      expect(
        existingWeb.existingHandleMethodCapabilities?.method,
        IdentityDidMethod.web,
      );
      expect(
        existingWeb.existingHandleMethodCapabilities?.handleRecovery,
        isFalse,
      );
    },
  );

  test(
    'deletion impact reads the exact Core identity and preserves errors',
    () async {
      final native = _IdentityErrorCore();
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => native,
      );
      expect(
        await adapter.hasPendingLocalIdentityRecovery('identity-alice'),
        isFalse,
      );
      native.pendingRecovery = true;
      expect(
        await adapter.hasPendingLocalIdentityRecovery('identity-alice'),
        isTrue,
      );
      expect(native.impactSelectors, hasLength(2));
      for (final selector in native.impactSelectors) {
        expect(selector, isA<core.IdIdentitySelector>());
        expect((selector as core.IdIdentitySelector).id, 'identity-alice');
      }
      native.impactError = StateError('local store unavailable');
      await expectLater(
        adapter.hasPendingLocalIdentityRecovery('identity-alice'),
        throwsStateError,
      );
    },
  );

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

  test(
    'prepared Join reserves clock skew without extending server TTL',
    () async {
      final sdk = _IdentityErrorCore();
      final adapter = AwikiImCoreIdentityAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );
      final registration = await adapter.registerHandleWithPhone(
        phone: 'test-contact',
        otp: 'test-code',
        handle: 'alice',
      );
      final progress = await adapter.beginExistingHandleDeviceJoin(
        registration.existingHandleContinuationId!,
        userPresenceConfirmed: false,
      );

      expect(sdk.lastJoinTtlSeconds, 570);
      expect(sdk.lastJoinPreparationId, 'prepared-join-1');
      expect(sdk.lastJoinOperationId, 'awiki-me-register-join-prepared-join-1');
      expect(sdk.lastJoinUserPresenceConfirmed, isFalse);
      expect(progress.joinSessionId, 'join-registration-recovery');
      final issuedAt = DateTime.utc(2026, 9, 29, 13, 32, 29, 184, 671);
      final expiresAt = issuedAt.add(
        Duration(seconds: sdk.lastJoinTtlSeconds!),
      );
      for (final skew in <Duration>[
        Duration.zero,
        const Duration(microseconds: 5719),
        const Duration(seconds: 30),
      ]) {
        final serverNow = issuedAt.subtract(skew);
        expect(expiresAt.isAfter(serverNow), isTrue);
        expect(
          expiresAt.difference(issuedAt),
          lessThanOrEqualTo(const Duration(seconds: 600)),
        );
        expect(
          expiresAt.difference(serverNow),
          lessThanOrEqualTo(const Duration(seconds: 600)),
        );
        expect(
          issuedAt.isAfter(serverNow.add(const Duration(seconds: 30))),
          isFalse,
        );
      }
      await expectLater(
        adapter.beginExistingHandleDeviceJoin(
          registration.existingHandleContinuationId!,
          userPresenceConfirmed: false,
        ),
        throwsStateError,
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
  core.IdentityMethodCapabilities methodCapabilities =
      coreWbaMethodCapabilities;
  core.DidMethod? lastDidMethod;

  @override
  Future<core.IdentityMethodCapabilities> identityMethodCapabilities(
    String did,
  ) async => methodCapabilities;

  bool pendingRecovery = false;
  Object? impactError;
  final impactSelectors = <core.IdentitySelector>[];
  @override
  Future<bool> hasPendingLocalIdentityRecovery(
    core.IdentitySelector selector,
  ) async {
    impactSelectors.add(selector);
    if (impactError != null) throw impactError!;
    return pendingRecovery;
  }

  Object? registrationError;
  Object? joinError;
  Completer<void>? pendingJoin;
  int joinCalls = 0;
  int? lastJoinTtlSeconds;
  String? lastJoinPreparationId;
  String? lastJoinOperationId;
  bool? lastJoinUserPresenceConfirmed;
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
    core.DidMethod didMethod = core.DidMethod.wba,
    String? localAlias,
    required String requestedHandle,
    required String phone,
    String? otp,
    String? inviteCode,
    core.InitialProfile profile = const core.InitialProfile(),
    bool makeDefault = true,
  }) async {
    lastDidMethod = didMethod;
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
    lastJoinTtlSeconds = ttlSeconds;
    lastJoinPreparationId = preparationId;
    lastJoinOperationId = operationId;
    lastJoinUserPresenceConfirmed = userPresenceConfirmed;
    joinCalls++;
    if (pendingJoin != null) await pendingJoin!.future;
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

class _PreparedJoinController extends OnboardingController {
  _PreparedJoinController(super.ref, String continuation) {
    state = state.copyWith(
      existingHandleContinuationId: continuation,
      existingHandleJoinMode: ExistingHandleJoinMode.ordinary,
    );
  }
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
