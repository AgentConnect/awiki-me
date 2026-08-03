// [INPUT]: Typed host intent, transient phone/OTP input, user-presence result, and safe references.
// [OUTPUT]: Secret-free coarse Recovery progress from the frozen Core facade boundary.
// [POS]: App-owned adapter seam; generated Core bindings implement this only in Wave 2.

import '../../domain/entities/handle_recovery.dart';

abstract interface class HandleRecoveryCorePort {
  Future<HandleRecoveryOtpResult> requestHandleRecoveryOtp({
    required String handle,
    required String phone,
    required String operationId,
  });

  Future<HandleRecoveryProgress> prepareHandleRecovery({
    required HandleRecoveryIdentityScope scope,
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
  });

  Future<HandleRecoveryProgress> activateHandleRecovery({
    required String recoveryId,
    required bool userPresenceConfirmed,
  });

  Future<HandleRecoveryProgress> resumeHandleRecovery({
    required String recoveryId,
  });

  /// Read-only. Implementations must not advance Core state.
  Future<HandleRecoveryProgress> handleRecoveryStatus(String recoveryId);

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
