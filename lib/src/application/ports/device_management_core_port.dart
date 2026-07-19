import '../../domain/entities/device_management.dart';

/// Secret-free projection and action boundary used by AWiki Me.
///
/// The SMS OTP is a write-only input to [beginDeviceJoinWithSms]. The adapter
/// exchanges and consumes it in the same call; no account/join token, private
/// key, challenge plaintext, pairing secret, or root key may cross this port.
abstract interface class DeviceManagementCorePort {
  Future<void> sendJoinSmsOtp(String phone);

  Future<List<DeviceJoinProgress>> localDeviceJoinSessions();

  Future<DeviceJoinProgress> beginDeviceJoinWithSms({
    required String did,
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
    required int ttlSeconds,
  });

  Future<DeviceJoinProgress> pollNewDeviceJoin(String joinSessionId);

  Future<DeviceJoinProgress> cancelNewDeviceJoin(String joinSessionId);

  Future<DeviceRegistrySnapshot> identityDeviceRegistry(String selector);

  Future<DeviceJoinProgress> claimDeviceJoin({
    required String selector,
    required String joinSessionId,
    required String operationId,
    required int challengeTtlSeconds,
  });

  Future<DeviceJoinProgress> pollAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  });

  Future<DeviceJoinApprovalPrompt> prepareDeviceJoinApproval({
    required String selector,
    required String joinSessionId,
    required DeviceRole role,
    required bool sasConfirmed,
  });

  Future<DeviceJoinProgress> confirmDeviceJoinApproval({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  });

  Future<DeviceJoinProgress> cancelAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  });
}
