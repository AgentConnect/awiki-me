import '../../domain/entities/pin_recovery.dart';

abstract interface class PinRecoveryCorePort {
  /// Null means this Host has no installed trusted configuration for this tenant.
  String? get tenantId;
  Future<bool> canBackup(String localIdentityId);
  Future<PinBackupStatus> backupStatus(String localIdentityId);
  Future<PinPhoneChallenge> requestPhoneCode(
    String phone, {
    String? resumeOperationId,
  });
  Future<String> verifyPhoneCode({
    required String challengeHandle,
    required String code,
  });
  Future<List<PinRecoveryTarget>> listTargets(String discoveryHandle);
  Future<String> selectTarget({
    required String discoveryHandle,
    required String targetId,
  });
  Future<PinRecoveryProgress> beginEnable({
    required String sessionHandle,
    required String localIdentityId,
    required bool userPresenceConfirmed,
  });
  Future<PinRecoveryProgress> beginRecover({
    required String sessionHandle,
    required String deviceLabel,
  });
  Future<PinRecoveryProgress> submitPin({
    required String operationId,
    required String pin,
  });
  Future<PinRecoveryProgress> confirmDevice({
    required String operationId,
    required bool userPresenceConfirmed,
  });
  Future<PinRecoveryProgress> status(String operationId);
  Future<List<PinRecoveryProgress>> listPending();
  Future<PinRecoveryProgress> resume(
    String operationId, {
    String? sessionHandle,
  });
  Future<PinRecoveryProgress> cancel(String operationId);
}
