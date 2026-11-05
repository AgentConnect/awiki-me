// Test-only exact device binding after ordinary Join authorization.
// Automatic management can finish while unrelated group fixtures are prepared;
// both legal target states retain the same exact device and current admin.
import 'package:awiki_me/src/domain/entities/device_management.dart';

bool hasExactAdminAndJoinedDevice(
  DeviceRegistrySnapshot registry, {
  required String currentAdminDeviceId,
  required String joinedDeviceId,
}) {
  if (currentAdminDeviceId.isEmpty ||
      joinedDeviceId.isEmpty ||
      currentAdminDeviceId == joinedDeviceId ||
      registry.devices.length != 2) {
    return false;
  }
  final currentAdmin = registry.devices.where(
    (device) =>
        device.protocolDeviceId == currentAdminDeviceId &&
        device.isCurrent &&
        device.role == DeviceRole.admin &&
        device.managementReady &&
        device.status == DeviceStatus.active,
  );
  final joinedDevice = registry.devices.where(
    (device) =>
        device.protocolDeviceId == joinedDeviceId &&
        !device.isCurrent &&
        ((device.role == DeviceRole.member && !device.managementReady) ||
            (device.role == DeviceRole.admin && device.managementReady)) &&
        device.status == DeviceStatus.active,
  );
  return currentAdmin.length == 1 && joinedDevice.length == 1;
}
