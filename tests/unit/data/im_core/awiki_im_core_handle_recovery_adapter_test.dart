import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_handle_recovery_adapter.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

const _didOld = 'did:wba:awiki.info:users:alice-old';
const _didNew = 'did:wba:awiki.info:users:alice-new';

void main() {
  test(
    'public facade adapter forwards all seven Recovery operations',
    () async {
      final sdk = _FakeRecoveryCore();
      final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );

      final otp = await adapter.requestHandleRecoveryOtp(
        handle: 'alice.awiki.info',
        phone: '+8613800138000',
        operationId: 'recover-op-1',
      );
      expect(otp.accepted, isTrue);
      expect(otp.operationId, 'recover-op-1');
      expect(otp.retryAfterSeconds, 60);
      expect(otp.retryAt, DateTime.utc(2026, 8, 6, 12, 1));

      final prepared = await adapter.prepareHandleRecovery(
        scope: const HandleRecoveryIdentityScope(
          localIdentityId: 'identity-alice',
        ),
        handle: 'alice.awiki.info',
        phone: '+8613800138000',
        otp: '987580',
        operationId: 'recover-op-1',
      );
      expect(sdk.selector, isA<core.IdIdentitySelector>());
      expect((sdk.selector! as core.IdIdentitySelector).id, 'identity-alice');
      expect(prepared.phase, HandleRecoveryProgressPhase.prepared);
      expect(prepared.impact.unsupportedE2eeGroupCount, 2);

      await adapter.activateHandleRecovery(
        recoveryId: 'recovery-1',
        userPresenceConfirmed: true,
      );
      await adapter.resumeHandleRecovery(recoveryId: 'recovery-1');
      await adapter.handleRecoveryStatus('recovery-1');

      final activatedJoin = await adapter.activateAuthorizedJoin(
        scope: const HandleRecoveryIdentityScope(
          localIdentityId: 'identity-alice',
        ),
        phone: '+8613800138000',
        otp: '987580',
        handle: 'alice.awiki.info',
        did: _didNew,
        operationId: 'join-op-1',
        ttlSeconds: 600,
        userPresenceConfirmed: true,
      );
      expect(sdk.selector, isA<core.IdIdentitySelector>());
      expect(activatedJoin.join.joinSessionId, 'join-recovery-1');
      expect(activatedJoin.join.phase, DeviceJoinPhase.authorized);
      expect(
        activatedJoin.registryEpochReset?.sourceKind,
        HandleRecoveryTransitionSourceKind.joinedDevice,
      );

      final resumedJoin = await adapter.resumeAuthorizedJoinActivation(
        joinSessionId: 'join-recovery-1',
      );
      expect(resumedJoin.join.did, _didNew);
      expect(sdk.calls, <String>[
        'requestOtp',
        'prepare',
        'activate',
        'resume',
        'status',
        'activateJoin',
        'resumeJoin',
      ]);
    },
  );

  test(
    'adapter maps legacy Registry authority without weakening fields',
    () async {
      final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
        coreInstance: () async => _FakeRecoveryCore(),
      );

      final authority = await adapter.legacyRegistryEpochAdoptionAuthority(
        'identity-alice',
      );
      expect(authority?.ownerIdentityId, 'identity-alice');
      expect(authority?.accountUserId, 'account-1');
      expect(authority?.currentDid, _didOld);
      expect(authority?.bindingGeneration, '7');
      expect(authority?.protocolDeviceId, 'device-old');
      expect(authority?.deviceAuthGeneration, '4');
      expect(authority?.provenanceId, 'checkpoint-1');
    },
  );

  test('adapter maps only the closed Core Recovery failure enum', () async {
    final sdk = _FakeRecoveryCore()
      ..error = const core.AwikiImCoreException(
        code: 'handle_recovery_remote_state_changed',
        message: 'changed',
        handleRecoveryFailureCode:
            core.HandleRecoveryFailureCode.remoteStateChanged,
      );
    final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
      coreInstance: () async => sdk,
    );

    await expectLater(
      adapter.handleRecoveryStatus('recovery-1'),
      throwsA(
        isA<HandleRecoveryFailure>().having(
          (error) => error.code,
          'code',
          HandleRecoveryFailureCode.remoteStateChanged,
        ),
      ),
    );

    sdk.error = const core.AwikiImCoreException(
      code: 'unrelated_core_error',
      message: 'unrelated',
    );
    await expectLater(
      adapter.handleRecoveryStatus('recovery-1'),
      throwsA(isA<core.AwikiImCoreException>()),
    );
  });

  test('adapter maps only a structured OTP rate-limit boundary', () async {
    final sdk = _FakeRecoveryCore()
      ..error = const core.AwikiImCoreException(
        code: 'service_error',
        message: 'rate limited',
        serviceDataJson:
            '{"code":"otp_rate_limited","retry_after_seconds":37,'
            '"retry_at":"2026-08-06T12:00:37Z"}',
      );
    final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
      coreInstance: () async => sdk,
    );

    await expectLater(
      adapter.requestHandleRecoveryOtp(
        handle: 'alice.awiki.info',
        phone: '+8613800138000',
        operationId: 'recover-op-1',
      ),
      throwsA(
        isA<HandleRecoveryOtpRateLimited>()
            .having((error) => error.retryAfterSeconds, 'retryAfterSeconds', 37)
            .having(
              (error) => error.retryAt,
              'retryAt',
              DateTime.utc(2026, 8, 6, 12, 0, 37),
            ),
      ),
    );

    sdk.error = const core.AwikiImCoreException(
      code: 'service_error',
      message: 'rate limited',
      serviceDataJson:
          '{"code":"otp_rate_limited","retry_after_seconds":37,'
          '"retry_at":"2026-08-06T12:00:37+00:00"}',
    );
    await expectLater(
      adapter.requestHandleRecoveryOtp(
        handle: 'alice.awiki.info',
        phone: '+8613800138000',
        operationId: 'recover-op-1',
      ),
      throwsA(isA<core.AwikiImCoreException>()),
    );
  });
}

class _FakeRecoveryCore implements core.AwikiImCore {
  final List<String> calls = <String>[];
  core.IdentitySelector? selector;
  Object? error;

  void _checkError() {
    final failure = error;
    if (failure != null) throw failure;
  }

  @override
  Future<core.LegacyRegistryEpochAdoptionAuthority?>
  legacyRegistryEpochAdoptionAuthority(core.IdentitySelector selector) async {
    _checkError();
    this.selector = selector;
    return const core.LegacyRegistryEpochAdoptionAuthority(
      ownerIdentityId: 'identity-alice',
      accountUserId: 'account-1',
      currentDid: _didOld,
      bindingGeneration: '7',
      protocolDeviceId: 'device-old',
      deviceAuthGeneration: '4',
      provenanceId: 'checkpoint-1',
    );
  }

  @override
  Future<core.HandleRecoveryOtpResult> requestHandleRecoveryOtp({
    required String phone,
    required String handle,
    required String operationId,
  }) async {
    _checkError();
    calls.add('requestOtp');
    return core.HandleRecoveryOtpResult(
      handle: handle,
      operationId: operationId,
      accepted: true,
      retryAfterSeconds: 60,
      retryAt: DateTime.utc(2026, 8, 6, 12, 1),
    );
  }

  @override
  Future<core.HandleRecoveryProgress> prepareHandleRecovery({
    required core.IdentitySelector selector,
    required String phone,
    required String code,
    required String handle,
    required String operationId,
  }) async {
    _checkError();
    this.selector = selector;
    calls.add('prepare');
    return _coreProgress(core.HandleRecoveryPhase.prepared);
  }

  @override
  Future<core.HandleRecoveryProgress> activateHandleRecovery({
    required String recoveryId,
    required bool userPresenceConfirmed,
  }) async {
    _checkError();
    calls.add('activate');
    return _coreProgress(core.HandleRecoveryPhase.remoteCommitPending);
  }

  @override
  Future<core.HandleRecoveryProgress> resumeHandleRecovery(
    String recoveryId,
  ) async {
    _checkError();
    calls.add('resume');
    return _coreProgress(core.HandleRecoveryPhase.completed);
  }

  @override
  Future<core.HandleRecoveryProgress> handleRecoveryStatus(
    String recoveryId,
  ) async {
    _checkError();
    calls.add('status');
    return _coreProgress(core.HandleRecoveryPhase.remoteCommitted);
  }

  @override
  Future<core.AuthorizedJoinActivationProgress> activateAuthorizedJoin({
    required core.IdentitySelector selector,
    required String phone,
    required String code,
    required String handle,
    required String did,
    required String operationId,
    int? ttlSeconds,
    required bool userPresenceConfirmed,
  }) async {
    _checkError();
    this.selector = selector;
    calls.add('activateJoin');
    return _coreJoinProgress();
  }

  @override
  Future<core.AuthorizedJoinActivationProgress> resumeAuthorizedJoinActivation(
    String joinSessionId,
  ) async {
    _checkError();
    calls.add('resumeJoin');
    return _coreJoinProgress();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

core.HandleRecoveryProgress _coreProgress(core.HandleRecoveryPhase phase) {
  return core.HandleRecoveryProgress(
    recoveryId: 'recovery-1',
    operationId: 'recover-op-1',
    ownerIdentityId: 'identity-alice',
    handle: 'alice.awiki.info',
    previousDid: _didOld,
    currentDid: _didNew,
    bindingGeneration: '8',
    phase: phase,
    impact: const core.HandleRecoveryImpact(
      localOrdinaryDataWillMigrate: true,
      otherDevicesMustRejoin: true,
      unsupportedE2eeGroupCount: 2,
      unsupportedDidOnlyGroupCount: 1,
    ),
  );
}

core.AuthorizedJoinActivationProgress _coreJoinProgress() {
  return const core.AuthorizedJoinActivationProgress(
    join: core.DeviceJoinProgress(
      session: core.DeviceJoinSessionSummary(
        joinSessionId: 'join-recovery-1',
        did: _didNew,
        protocolDeviceId: 'device-new',
        side: core.DeviceJoinSide.newDevice,
        phase: core.DeviceJoinPhase.authorized,
        expiresAt: '2030-01-01T00:00:00.000Z',
      ),
      remoteState: core.DeviceJoinRemoteState.consumed,
    ),
    registryEpochReset: core.HandleRecoveryRegistryEpochReset(
      accountUserId: 'account-1',
      ownerIdentityId: 'identity-alice',
      handle: 'alice.awiki.info',
      previousDid: _didOld,
      currentDid: _didNew,
      bindingGeneration: '8',
      sourceKind: core.HandleRecoveryTransitionSourceKind.joinedDevice,
      sourceId: 'join-recovery-1',
    ),
  );
}
