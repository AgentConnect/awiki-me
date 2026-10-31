import 'dart:convert';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_pin_recovery_adapter.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_pin_recovery_config.dart';
import 'package:awiki_me/src/domain/entities/pin_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNative extends Fake implements core.AwikiImCore {
  Object? failure;
  String? lastOperation;
  core.PinRecoveryBackupState backupState = core.PinRecoveryBackupState.unknown;
  @override
  Future<core.PinRecoveryBackupStatus> pinRecoveryBackupStatus({
    required core.IdentitySelector selector,
  }) async => core.PinRecoveryBackupStatus(
    did: 'did:wba:awiki.info:user:alice',
    fullHandle: 'alice.awiki.info',
    bindingGeneration: '4',
    state: backupState,
    activeEpoch: backupState == core.PinRecoveryBackupState.active
        ? '18446744073709551615'
        : null,
    error: null,
  );
  @override
  Future<core.PinRecoveryProgress> submitPinRecoveryPin({
    required String operationId,
    required String pin,
  }) async {
    lastOperation = operationId;
    if (failure != null) throw failure!;
    return nativeProgress;
  }
}

const nativeProgress = core.PinRecoveryProgress(
  operationId: 'operation',
  kind: core.PinRecoveryKind.recover,
  phase: core.PinRecoveryPhase.localActivationPending,
  allowedActions: [
    core.PinRecoveryAction.retryLocalActivation,
    core.PinRecoveryAction.inspect,
  ],
  target: core.PinRecoveryTarget(
    targetId: 'target',
    fullHandle: 'alice.awiki.info',
    did: 'did:wba:awiki.info:user:alice',
    bindingGeneration: '4',
    activeEpoch: '18446744073709551615',
    canEnable: false,
    canRecover: true,
    unavailableReason: null,
  ),
  nodeProgress: [],
  attemptsUsed: 3,
  attemptsLimit: 10,
  needsPhoneVerification: false,
  needsUserConfirmation: false,
  recoveredIdentity: core.IdentitySelector.id('identity'),
  newDeviceId: 'device',
  deviceLabel: 'Verified device label',
  secureReadiness: core.PinRecoverySecureReadiness.prekeysPending,
  cleanupRemaining: 0,
  error: null,
);
void main() {
  test(
    'remote backup unknown stays distinct from disabled and active epochs keep precision',
    () async {
      final sdk = FakeNative();
      final adapter = AwikiImCorePinRecoveryAdapter.withCoreInstance(
        coreInstance: () async => sdk,
        tenantId: 'tenant',
      );
      expect(
        (await adapter.backupStatus('identity')).state,
        PinBackupState.unknown,
      );
      sdk.backupState = core.PinRecoveryBackupState.notEnabled;
      expect(
        (await adapter.backupStatus('identity')).state,
        PinBackupState.notEnabled,
      );
      sdk.backupState = core.PinRecoveryBackupState.active;
      final status = await adapter.backupStatus('identity');
      expect(status.state, PinBackupState.active);
      expect(status.activeEpoch, '18446744073709551615');
    },
  );

  test(
    'typed mapping preserves exact local resume, epoch and allowed actions',
    () async {
      final sdk = FakeNative();
      final adapter = AwikiImCorePinRecoveryAdapter.withCoreInstance(
        coreInstance: () async => sdk,
        tenantId: 'tenant',
      );
      final p = await adapter.submitPin(operationId: 'operation', pin: '0123');
      expect(p.operationId, 'operation');
      expect(p.target.activeEpoch, '18446744073709551615');
      expect(p.phase, PinRecoveryPhase.localActivationPending);
      expect(p.recoveredIdentityId, 'identity');
      expect(p.deviceLabel, 'Verified device label');
      expect(p.canEnter, false);
      expect(p.allowedActions, [
        PinRecoveryAction.retryLocalActivation,
        PinRecoveryAction.inspect,
      ]);
      expect(p.attemptsUsed, 3);
    },
  );
  test(
    'stable service code survives while native exception body is discarded',
    () async {
      final sdk = FakeNative()
        ..failure = const core.AwikiImCoreException(
          code: 'service_error',
          serviceCode: 'invalid_pin',
          message: 'sensitive response must stay native',
        );
      final adapter = AwikiImCorePinRecoveryAdapter.withCoreInstance(
        coreInstance: () async => sdk,
        tenantId: 'tenant',
      );
      await expectLater(
        adapter.submitPin(operationId: 'operation', pin: '0123'),
        throwsA(
          isA<PinRecoveryFailure>()
              .having((e) => e.code, 'stable code', 'invalid_pin')
              .having(
                (e) => e.toString(),
                'safe display',
                'PinRecoveryFailure',
              ),
        ),
      );
      expect(sdk.lastOperation, 'operation');
    },
  );
  test(
    'configuration requires installed trust, rejects duplicate tenants and insecure origin',
    () {
      expect(decodePinRecoveryTenants(''), isEmpty);
      final entry = {
        'tenant_id': 'tenant',
        'deployment_id': 'deployment',
        'control_base_url': 'https://awiki.info/user-service/v1/key-recovery',
        'config_signing_keys': {'config-key': 'public-test-key'},
      };
      String encode(Object o) => base64Encode(utf8.encode(jsonEncode(o)));
      expect(
        decodePinRecoveryTenants(encode([entry])).single.tenantId,
        'tenant',
      );
      expect(
        () => decodePinRecoveryTenants(encode([entry, entry])),
        throwsFormatException,
      );
      expect(
        () => decodePinRecoveryTenants(
          encode([
            {...entry, 'control_base_url': 'http://untrusted.invalid'},
          ]),
        ),
        throwsFormatException,
      );
    },
  );
}
