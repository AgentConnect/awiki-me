// [INPUT]: Stable owner, transient phone/OTP input, explicit confirmation, and operation IDs.
// [OUTPUT]: Secret-free Core-owned Recovery operation and epoch projections.
// [POS]: App-owned adapter seam; the App never creates or persists operation state.

import '../../domain/entities/handle_recovery.dart';

class HandleRecoveryOtpRateLimited implements Exception {
  const HandleRecoveryOtpRateLimited({
    required this.retryAfterSeconds,
    required this.retryAt,
  });

  final int retryAfterSeconds;
  final DateTime retryAt;
}

abstract interface class HandleRecoveryCorePort {
  /// Core creates and durably indexes the operation before sending the OTP.
  Future<HandleRecoveryOtpResult> requestOtp({
    required HandleRecoveryOwner owner,
    required String phone,
  });

  Future<HandleRecoveryProgress> prepare({
    required String operationId,
    required String phone,
    required String otp,
  });

  Future<List<HandleRecoveryProgress>> listOperations(
    HandleRecoveryOwner owner,
  );

  /// Read-only projection. Implementations must not advance Core state.
  Future<HandleRecoveryProgress> getStatus(String operationId);

  Future<HandleRecoveryProgress> activate({
    required String operationId,
    required bool userPresenceConfirmed,
  });

  Future<HandleRecoveryProgress> reconcile(String operationId);

  Future<void> discardPreAttempt(String operationId);

  Future<HandleRecoveryProgress> quarantineKeyUnavailable({
    required String operationId,
    required bool confirmed,
  });

  Future<HandleRecoveryRegistryEpochReset?> authorizedEpochReceipt(
    HandleRecoveryOwner owner,
  );

  Future<HandleRecoveryAuthorizedJoinProgress> activateAuthorizedJoin({
    required HandleRecoveryIdentityScope scope,
    required String phone,
    required String otp,
    required String handle,
    required String did,
    required String operationId,
    int? ttlSeconds,
    required bool userPresenceConfirmed,
  });

  Future<HandleRecoveryAuthorizedJoinProgress> resumeAuthorizedJoinActivation({
    required String joinSessionId,
  });
}
