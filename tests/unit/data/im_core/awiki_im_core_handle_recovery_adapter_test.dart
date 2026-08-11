import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/handle_recovery_core_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_handle_recovery_adapter.dart';
import 'package:awiki_me/src/domain/entities/handle_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = HandleRecoveryOwner(
  localIdentityId: 'identity-alice',
  handle: 'alice.awiki.info',
);
const _stateRoot =
    'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  test('V4 adapter uses the Core-owned operation journal end to end', () async {
    final sdk = _FakeRecoveryCore();
    final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
      coreInstance: () async => sdk,
    );

    final otp = await adapter.requestOtp(
      handle: _owner.handle,
      localIdentityId: _owner.localIdentityId,
      phone: '+8613800138000',
    );
    expect(otp.operationId, 'recover-op-1');
    expect(otp.operation.ownerIdentityId, _owner.localIdentityId);
    expect(
      otp.operation.lifecycleClass,
      HandleRecoveryLifecycleClass.preCommit,
    );
    expect(otp.operation.readyToCommit, isFalse);
    expect(
      (sdk.selector! as core.IdIdentitySelector).id,
      _owner.localIdentityId,
    );

    final prepared = await adapter.prepare(
      operationId: otp.operationId,
      phone: '+8613800138000',
      otp: '987580',
    );
    expect(prepared.readyToCommit, isTrue);
    expect(prepared.accountUserId, 'account-1');
    expect(prepared.impact.unsupportedE2eeGroupCount, 2);
    expect(prepared.canDiscard, isTrue);

    final activated = await adapter.activate(
      operationId: otp.operationId,
      userPresenceConfirmed: true,
    );
    expect(
      activated.lifecycleClass,
      HandleRecoveryLifecycleClass.remoteUnresolved,
    );
    expect(activated.commitAttempted, isTrue);
    expect(activated.canDiscard, isFalse);

    final applied = await adapter.reconcile(otp.operationId);
    expect(applied.lifecycleClass, HandleRecoveryLifecycleClass.applied);
    expect(applied.stateRootFingerprint, _stateRoot);
    expect(applied.registryEpochReset?.sourceId, otp.operationId);
    expect(applied.registryEpochReset?.stateRootFingerprint, _stateRoot);

    final listed = await adapter.listOperations(_owner);
    expect(listed.single.lifecycleClass, HandleRecoveryLifecycleClass.applied);
    expect(
      (await adapter.getStatus(otp.operationId)).operationId,
      otp.operationId,
    );

    final receipt = await adapter.authorizedEpochReceipt(_owner);
    expect(receipt?.receiptSchemaVersion, '4');
    expect(receipt?.sourceId, otp.operationId);
    expect(receipt?.deviceAuthGeneration, 9);
    expect(receipt?.registryVersion, 11);
    expect(receipt?.stateRootFingerprint, _stateRoot);

    expect(
      sdk.calls,
      containsAll(<String>[
        'requestOtp',
        'prepare',
        'activate',
        'resume',
        'status',
        'list',
        'receipt',
      ]),
    );
  });

  test(
    'terminal discard and quarantine use summary without reloading Vault',
    () async {
      final sdk = _FakeRecoveryCore();
      final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );
      await adapter.requestOtp(
        handle: _owner.handle,
        localIdentityId: _owner.localIdentityId,
        phone: '+8613800138000',
      );

      await adapter.discardPreAttempt('recover-op-1');
      expect(
        sdk.summary.lifecycleClass,
        core.HandleRecoveryOperationLifecycle.discardedPreAttempt,
      );

      sdk.resetAwaitingFactor(
        keyState: core.HandleRecoveryKeyState.permanentlyUnavailable,
      );
      final statusCallsBefore = sdk.calls
          .where((call) => call == 'status')
          .length;
      final quarantined = await adapter.quarantineKeyUnavailable(
        operationId: 'recover-op-1',
        confirmed: true,
      );
      expect(
        quarantined.lifecycleClass,
        HandleRecoveryLifecycleClass.quarantinedKeyUnavailable,
      );
      expect(
        quarantined.keyState,
        HandleRecoveryKeyState.permanentlyUnavailable,
      );
      expect(
        sdk.calls.where((call) => call == 'status').length,
        statusCallsBefore,
        reason: 'quarantine must not reload an unreadable key',
      );
    },
  );

  test('progress projection uses the same retryability table', () async {
    final sdk = _FakeRecoveryCore()
      ..phase = core.HandleRecoveryPhase.remoteOutcomeUnknown
      ..summary = _summary(
        lifecycle: core.HandleRecoveryOperationLifecycle.remoteUnresolved,
        accountUserId: 'account-1',
        commitAttempted: true,
        lastErrorCode: 'result_absent',
      );
    final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
      coreInstance: () async => sdk,
    );

    final progress = await adapter.getStatus('recover-op-1');

    expect(progress.failureCode, HandleRecoveryFailureCode.resultAbsent);
    expect(progress.retryable, isTrue);
  });

  test(
    'applied progress rejects a mismatched authorized epoch receipt',
    () async {
      final sdk = _FakeRecoveryCore()..receiptSourceId = 'different-operation';
      final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
        coreInstance: () async => sdk,
      );

      await expectLater(
        adapter.reconcile('recover-op-1'),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.code,
            'code',
            HandleRecoveryFailureCode.transitionMismatch,
          ),
        ),
      );
    },
  );

  test('adapter maps the exact closed retryability table', () async {
    final sdk = _FakeRecoveryCore();
    final adapter = AwikiImCoreHandleRecoveryAdapter.withCoreInstance(
      coreInstance: () async => sdk,
    );

    const cases = <core.HandleRecoveryFailureCode, bool>{
      core.HandleRecoveryFailureCode.factorRetryRequired: true,
      core.HandleRecoveryFailureCode.resultAbsent: true,
      core.HandleRecoveryFailureCode.outcomeUnknown: true,
      core.HandleRecoveryFailureCode.localTransitionPending: true,
      core.HandleRecoveryFailureCode.localKeyUnavailable: false,
      core.HandleRecoveryFailureCode.localMigrationUnsupported: false,
      core.HandleRecoveryFailureCode.unknownEpoch: false,
    };
    for (final entry in cases.entries) {
      sdk.error = core.AwikiImCoreException(
        code: 'service_error',
        message: entry.key.name,
        handleRecoveryFailureCode: entry.key,
      );
      await expectLater(
        adapter.getStatus('recover-op-1'),
        throwsA(
          isA<HandleRecoveryFailure>().having(
            (error) => error.retryable,
            entry.key.name,
            entry.value,
          ),
        ),
      );
    }

    sdk.error = const core.AwikiImCoreException(
      code: 'unrelated_core_error',
      message: 'unrelated',
    );
    await expectLater(
      adapter.getStatus('recover-op-1'),
      throwsA(isA<core.AwikiImCoreException>()),
    );
  });

  test('adapter accepts only the structured OTP rate-limit shape', () async {
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
      adapter.requestOtp(
        handle: _owner.handle,
        localIdentityId: _owner.localIdentityId,
        phone: '+8613800138000',
      ),
      throwsA(
        isA<HandleRecoveryOtpRateLimited>()
            .having((error) => error.retryAfterSeconds, 'seconds', 37)
            .having(
              (error) => error.retryAt,
              'retryAt',
              DateTime.utc(2026, 8, 6, 12, 0, 37),
            ),
      ),
    );
  });

  test('legacy Join reset maps only to a Join transition reference', () {
    final reference = handleRecoveryJoinTransitionReferenceFromCore(
      const core.HandleRecoveryRegistryEpochReset(
        accountUserId: 'account-1',
        ownerIdentityId: 'identity-alice',
        handle: 'alice.awiki.info',
        previousDid: 'did:wba:awiki.info:users:alice-old',
        currentDid: 'did:wba:awiki.info:users:alice-new',
        bindingGeneration: '8',
        sourceKind: core.HandleRecoveryTransitionSourceKind.joinedDevice,
        sourceId: 'join-1',
      ),
    );

    expect(reference, isA<HandleRecoveryJoinTransitionReference>());
    expect(reference.accountUserId, 'account-1');
    expect(reference.ownerIdentityId, 'identity-alice');
    expect(reference.handle, 'alice.awiki.info');
    expect(reference.bindingGeneration, '8');
    expect(
      reference.sourceKind,
      HandleRecoveryTransitionSourceKind.joinedDevice,
    );
    expect(reference.sourceId, 'join-1');
  });
}

class _FakeRecoveryCore implements core.AwikiImCore {
  final List<String> calls = <String>[];
  core.IdentitySelector? selector;
  Object? error;
  String receiptSourceId = 'recover-op-1';
  core.HandleRecoveryPhase phase = core.HandleRecoveryPhase.awaitingFactor;
  late core.HandleRecoveryOperationSummary summary = _summary();

  void _checkError() {
    final current = error;
    if (current != null) throw current;
  }

  void resetAwaitingFactor({
    core.HandleRecoveryKeyState keyState =
        core.HandleRecoveryKeyState.available,
  }) {
    phase = core.HandleRecoveryPhase.awaitingFactor;
    summary = _summary(keyState: keyState);
  }

  @override
  Future<core.HandleRecoveryOtpResult> requestHandleRecoveryOtp({
    core.IdentitySelector? selector,
    required String fullHandle,
    required String phone,
  }) async {
    _checkError();
    calls.add('requestOtp');
    this.selector = selector;
    resetAwaitingFactor();
    return core.HandleRecoveryOtpResult(
      fullHandle: _owner.handle,
      ownerIdentityId: _owner.localIdentityId,
      operationId: 'recover-op-1',
      accepted: true,
      retryAfterSeconds: 60,
      retryAt: DateTime.utc(2026, 8, 6, 12, 1),
    );
  }

  @override
  Future<core.HandleRecoveryProgress> prepareHandleRecovery({
    required String operationId,
    required String phone,
    required String code,
  }) async {
    _checkError();
    calls.add('prepare');
    phase = core.HandleRecoveryPhase.readyToCommit;
    summary = _summary(accountUserId: 'account-1');
    return _progress();
  }

  @override
  Future<core.HandleRecoveryProgress> activateHandleRecovery({
    required String operationId,
    required bool userPresenceConfirmed,
  }) async {
    _checkError();
    calls.add('activate');
    phase = core.HandleRecoveryPhase.remoteOutcomeUnknown;
    summary = _summary(
      lifecycle: core.HandleRecoveryOperationLifecycle.remoteUnresolved,
      accountUserId: 'account-1',
      commitAttempted: true,
    );
    return _progress();
  }

  @override
  Future<core.HandleRecoveryProgress> resumeHandleRecovery(
    String operationId,
  ) async {
    _checkError();
    calls.add('resume');
    phase = core.HandleRecoveryPhase.applied;
    summary = _summary(
      lifecycle: core.HandleRecoveryOperationLifecycle.applied,
      accountUserId: 'account-1',
      commitAttempted: true,
      stateRootFingerprint: _stateRoot,
    );
    return _progress(stateRootFingerprint: _stateRoot);
  }

  @override
  Future<core.HandleRecoveryProgress> handleRecoveryStatus(
    String operationId,
  ) async {
    _checkError();
    calls.add('status');
    return _progress(stateRootFingerprint: summary.stateRootFingerprint);
  }

  @override
  Future<List<core.HandleRecoveryOperationSummary>>
  listHandleRecoveryOperations(core.IdentitySelector selector) async {
    _checkError();
    calls.add('list');
    this.selector = selector;
    return <core.HandleRecoveryOperationSummary>[summary];
  }

  @override
  Future<core.HandleRecoveryOperationSummary> discardHandleRecoveryPreAttempt(
    String operationId,
  ) async {
    _checkError();
    calls.add('discard');
    summary = _summary(
      lifecycle: core.HandleRecoveryOperationLifecycle.discardedPreAttempt,
      keyState: core.HandleRecoveryKeyState.destroyedPreAttempt,
    );
    return summary;
  }

  @override
  Future<core.HandleRecoveryOperationSummary>
  quarantineHandleRecoveryKeyUnavailable({
    required String operationId,
    required bool userPresenceConfirmed,
  }) async {
    _checkError();
    calls.add('quarantine');
    summary = _summary(
      lifecycle:
          core.HandleRecoveryOperationLifecycle.quarantinedKeyUnavailable,
      keyState: core.HandleRecoveryKeyState.permanentlyUnavailable,
    );
    return summary;
  }

  @override
  Future<core.HandleRecoveryAccountEpochReceipt?>
  authorizedHandleRecoveryReceipt(core.IdentitySelector selector) async {
    _checkError();
    calls.add('receipt');
    this.selector = selector;
    return core.HandleRecoveryAccountEpochReceipt(
      receiptSchemaVersion: '4',
      sourceKind: core.HandleRecoveryTransitionSourceKind.initiator,
      sourceId: receiptSourceId,
      accountUserId: 'account-1',
      ownerIdentityId: _owner.localIdentityId,
      fullHandle: _owner.handle,
      localPreviousDid: 'did:wba:awiki.info:users:alice-old',
      currentDid: 'did:wba:awiki.info:users:alice-new',
      bindingGeneration: '8',
      currentDeviceId: 'device-1',
      deviceAuthGeneration: 9,
      registryVersion: 11,
      stateRootFingerprint: _stateRoot,
      appliedAt: DateTime.utc(2026, 8, 6, 12, 10),
      metadataJson: '{}',
    );
  }

  core.HandleRecoveryProgress _progress({String? stateRootFingerprint}) =>
      core.HandleRecoveryProgress(
        operationId: 'recover-op-1',
        ownerIdentityId: _owner.localIdentityId,
        accountUserId: summary.accountUserId,
        fullHandle: _owner.handle,
        localPreviousDid: 'did:wba:awiki.info:users:alice-old',
        currentDid: 'did:wba:awiki.info:users:alice-new',
        bindingGeneration: '8',
        stateRootFingerprint: stateRootFingerprint,
        phase: phase,
        impact: const core.HandleRecoveryImpact(
          localOrdinaryDataWillMigrate: true,
          otherDevicesMustRejoin: true,
          unsupportedE2eeGroupCount: 2,
          unsupportedDidOnlyGroupCount: 1,
        ),
        registryEpochReset: phase == core.HandleRecoveryPhase.applied
            ? const core.HandleRecoveryRegistryEpochReset(
                accountUserId: 'account-1',
                ownerIdentityId: 'identity-alice',
                handle: 'alice.awiki.info',
                previousDid: 'did:wba:awiki.info:users:alice-old',
                currentDid: 'did:wba:awiki.info:users:alice-new',
                bindingGeneration: '8',
                sourceKind: core.HandleRecoveryTransitionSourceKind.initiator,
                sourceId: 'recover-op-1',
              )
            : null,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

core.HandleRecoveryOperationSummary _summary({
  core.HandleRecoveryOperationLifecycle lifecycle =
      core.HandleRecoveryOperationLifecycle.preCommit,
  String? accountUserId,
  bool commitAttempted = false,
  core.HandleRecoveryKeyState keyState = core.HandleRecoveryKeyState.available,
  String? stateRootFingerprint,
  String? lastErrorCode,
}) => core.HandleRecoveryOperationSummary(
  operationId: 'recover-op-1',
  ownerIdentityId: _owner.localIdentityId,
  accountUserId: accountUserId,
  fullHandle: _owner.handle,
  lifecycleClass: lifecycle,
  commitAttempted: commitAttempted,
  keyState: keyState,
  intentHash: 'sha256:intent',
  stateRootFingerprint: stateRootFingerprint,
  lastErrorCode: lastErrorCode,
  createdAt: DateTime.utc(2026, 8, 6, 12),
  updatedAt: DateTime.utc(2026, 8, 6, 12, 1),
);
