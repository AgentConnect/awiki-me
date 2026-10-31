import 'package:awiki_im_core/awiki_im_core.dart' as core;
import '../../application/ports/pin_recovery_core_port.dart';
import '../../domain/entities/pin_recovery.dart';
import 'awiki_im_core_runtime.dart';
import 'awiki_im_core_device_management_adapter.dart' show AwikiImCoreInstance;

class AwikiImCorePinRecoveryAdapter implements PinRecoveryCorePort {
  AwikiImCorePinRecoveryAdapter({
    required AwikiImCoreRuntime runtime,
    required this.tenantId,
  }) : _instance = runtime.coreInstance;
  AwikiImCorePinRecoveryAdapter.withCoreInstance({
    required AwikiImCoreInstance coreInstance,
    required this.tenantId,
  }) : _instance = coreInstance;
  final AwikiImCoreInstance _instance;
  @override
  final String? tenantId;
  @override
  Future<bool> canBackup(String localIdentityId) => _run(
    (instance) async => (await instance.identityCustodyStatus(
      core.IdentitySelector.id(localIdentityId),
    )).rootControlAvailable,
  );
  @override
  Future<PinBackupStatus> backupStatus(String localIdentityId) =>
      _run((instance) async {
        final status = await instance.pinRecoveryBackupStatus(
          selector: core.IdentitySelector.id(localIdentityId),
        );
        return PinBackupStatus(
          did: status.did,
          state: PinBackupState.values.byName(status.state.name),
          fullHandle: status.fullHandle,
          bindingGeneration: status.bindingGeneration,
          activeEpoch: status.activeEpoch,
          errorCode: status.error?.code,
        );
      });
  Future<T> _run<T>(Future<T> Function(core.AwikiImCore instance) body) async {
    try {
      return await body(await _instance());
    } on core.AwikiImCoreException catch (error) {
      // Only stable codes cross into presentation, never native exception text.
      throw PinRecoveryFailure(error.serviceCode ?? error.code);
    }
  }

  @override
  Future<PinPhoneChallenge> requestPhoneCode(
    String phone, {
    String? resumeOperationId,
  }) => _run((instance) async {
    final tenant = tenantId;
    if (tenant == null) throw const PinRecoveryFailure('not_configured');
    final result = await instance.requestPinRecoveryPhoneCode(
      tenantId: tenant,
      phone: phone,
      resumeOperationId: resumeOperationId,
    );
    return PinPhoneChallenge(
      handle: result.challengeHandle,
      maskedPhone: result.maskedPhone,
      resendAfterSeconds: result.resendAfterSeconds,
    );
  });
  @override
  Future<String> verifyPhoneCode({
    required String challengeHandle,
    required String code,
  }) => _run(
    (instance) async => (await instance.verifyPinRecoveryPhoneCode(
      challengeHandle: challengeHandle,
      code: code,
    )).discoveryHandle,
  );
  @override
  Future<List<PinRecoveryTarget>> listTargets(String discoveryHandle) => _run(
    (instance) async => (await instance.listPinRecoveryTargets(
      discoveryHandle: discoveryHandle,
    )).map(_target).toList(growable: false),
  );
  @override
  Future<String> selectTarget({
    required String discoveryHandle,
    required String targetId,
  }) => _run(
    (instance) async => (await instance.selectPinRecoveryTarget(
      discoveryHandle: discoveryHandle,
      targetId: targetId,
    )).sessionHandle,
  );
  @override
  Future<PinRecoveryProgress> beginEnable({
    required String sessionHandle,
    required String localIdentityId,
    required bool userPresenceConfirmed,
  }) => _run(
    (instance) async => _progress(
      await instance.beginEnablePinRecovery(
        sessionHandle: sessionHandle,
        selector: core.IdentitySelector.id(localIdentityId),
        userPresenceConfirmed: userPresenceConfirmed,
      ),
    ),
  );
  @override
  Future<PinRecoveryProgress> beginRecover({
    required String sessionHandle,
    required String deviceLabel,
  }) => _run(
    (instance) async => _progress(
      await instance.beginPinRecovery(
        sessionHandle: sessionHandle,
        deviceLabel: deviceLabel,
      ),
    ),
  );
  @override
  Future<PinRecoveryProgress> submitPin({
    required String operationId,
    required String pin,
  }) => _run(
    (instance) async => _progress(
      await instance.submitPinRecoveryPin(operationId: operationId, pin: pin),
    ),
  );
  @override
  Future<PinRecoveryProgress> confirmDevice({
    required String operationId,
    required bool userPresenceConfirmed,
  }) => _run(
    (instance) async => _progress(
      await instance.confirmPinRecoveryDevice(
        operationId: operationId,
        userPresenceConfirmed: userPresenceConfirmed,
      ),
    ),
  );
  @override
  Future<PinRecoveryProgress> status(String operationId) => _run(
    (instance) async =>
        _progress(await instance.pinRecoveryStatus(operationId: operationId)),
  );
  @override
  Future<List<PinRecoveryProgress>> listPending() => _run(
    (instance) async => (await instance.listPendingPinRecoveryOperations())
        .map(_progress)
        .toList(growable: false),
  );
  @override
  Future<PinRecoveryProgress> resume(
    String operationId, {
    String? sessionHandle,
  }) => _run(
    (instance) async => _progress(
      await instance.resumePinRecovery(
        operationId: operationId,
        sessionHandle: sessionHandle,
      ),
    ),
  );
  @override
  Future<PinRecoveryProgress> cancel(String operationId) => _run(
    (instance) async =>
        _progress(await instance.cancelPinRecovery(operationId: operationId)),
  );
}

PinRecoveryTarget _target(core.PinRecoveryTarget value) => PinRecoveryTarget(
  targetId: value.targetId,
  fullHandle: value.fullHandle,
  did: value.did,
  bindingGeneration: value.bindingGeneration,
  activeEpoch: value.activeEpoch,
  canEnable: value.canEnable,
  canRecover: value.canRecover,
  unavailableReason: value.unavailableReason,
);
PinRecoveryProgress _progress(core.PinRecoveryProgress value) =>
    PinRecoveryProgress(
      operationId: value.operationId,
      nodeProgress: List.unmodifiable(
        value.nodeProgress.map(
          (node) => PinRealmProgress(
            realmId: node.realmId,
            phase: node.phase,
            errorCode: node.errorCode,
          ),
        ),
      ),
      kind: PinRecoveryKind.values.byName(value.kind.name),
      phase: PinRecoveryPhase.values.byName(value.phase.name),
      allowedActions: List.unmodifiable(
        value.allowedActions.map(
          (a) => PinRecoveryAction.values.byName(a.name),
        ),
      ),
      target: _target(value.target),
      attemptsUsed: value.attemptsUsed,
      attemptsLimit: value.attemptsLimit,
      needsPhoneVerification: value.needsPhoneVerification,
      recoveredIdentityId: switch (value.recoveredIdentity) {
        core.IdIdentitySelector(:final id) => id,
        null => null,
        _ => throw const PinRecoveryFailure('identity_selector_invalid'),
      },
      newDeviceId: value.newDeviceId,
      deviceLabel: value.deviceLabel,
      secureReadiness: PinRecoverySecureReadiness.values.byName(
        value.secureReadiness.name,
      ),
      cleanupRemaining: value.cleanupRemaining,
      errorCode: value.error?.code,
    );
