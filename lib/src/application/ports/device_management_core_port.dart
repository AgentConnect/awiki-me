import '../../domain/entities/device_management.dart';

/// The Join SMS endpoint rejected a resend until [retryAfterSeconds] elapses.
///
/// Only the bounded retry delay crosses this port. Raw response bodies and
/// provider diagnostics remain below the data boundary.
class DeviceJoinSmsOtpRateLimited implements Exception {
  const DeviceJoinSmsOtpRateLimited({required this.retryAfterSeconds});

  final int retryAfterSeconds;

  @override
  String toString() =>
      'DeviceJoinSmsOtpRateLimited(retryAfterSeconds: $retryAfterSeconds)';
}

/// Secret-free projection and action boundary used by AWiki Me.
///
/// The SMS OTP is a write-only input to [beginDeviceJoinWithSms]. The adapter
/// resolves the public Handle without requiring a selected local identity,
/// then exchanges and consumes the OTP in the same call; no account/join
/// token, private key, challenge plaintext, pairing secret, or root key may
/// cross this port.
/// Permanent revoke accepts only an identity selector, opaque target device ID,
/// and Host user-presence result; versions, hashes and proofs stay below Core.
abstract interface class DeviceManagementCorePort {
  Future<void> sendJoinSmsOtp({required String handle, required String phone});

  Future<String> resolveJoinDid(String handle);

  Future<List<DeviceJoinProgress>> localDeviceJoinSessions();

  Future<DeviceJoinProgress> beginDeviceJoinWithSms({
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
    required int ttlSeconds,
  });

  Future<DeviceJoinProgress> pollNewDeviceJoin(String joinSessionId);

  Future<DeviceJoinProgress> cancelNewDeviceJoin(String joinSessionId);

  Future<DeviceRegistrySnapshot> identityDeviceRegistry(String selector);

  Future<DeviceRevokeResult> revokeDevice({
    required String selector,
    required String targetDeviceId,
    required bool userPresenceConfirmed,
  });

  Future<List<DeviceJoinRequestNotice>> localDeviceJoinRequests(
    String selector,
  );

  Future<DeviceJoinProgress> localDeviceJoinVerificationProgress({
    required String selector,
    required String joinSessionId,
  });

  Future<DeviceJoinProgress> startDeviceJoinVerification({
    required String selector,
    required String joinSessionId,
    required String operationId,
    required int challengeTtlSeconds,
  });

  Future<DeviceJoinApprovalPrompt> prepareDeviceJoinApproval({
    required String selector,
    required String joinSessionId,
    required bool sasConfirmed,
  });

  Future<DeviceJoinProgress> confirmDeviceJoinApproval({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  });

  Future<DeviceJoinProgress> rejectDeviceJoin({
    required String selector,
    required String joinSessionId,
    required DeviceJoinRejectReason reason,
  });
}
