enum DeviceCapabilityState {
  ready,
  upgradeAvailable,
  approvalRequired,
  unsupported,
  blocked,
}

class DeviceCapabilityStatus {
  const DeviceCapabilityStatus({required this.deviceId, required this.state});
  final String deviceId;
  final DeviceCapabilityState state;
}

abstract interface class DeviceCapabilityUpgradePort {
  Future<DeviceCapabilityStatus> inspectDeviceCapabilities(
    String identityId, {
    String? targetDeviceId,
  });
  Future<DeviceCapabilityStatus> upgradeDeviceCapabilities(
    String identityId, {
    String? targetDeviceId,
    bool userPresenceConfirmed = false,
  });
}
