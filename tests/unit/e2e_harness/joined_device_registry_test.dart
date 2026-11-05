import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/joined_device_registry.dart';

DeviceSummary device({
  String id = 'admin-device',
  bool current = true,
  DeviceRole role = DeviceRole.admin,
  bool ready = true,
  DeviceStatus status = DeviceStatus.active,
}) => DeviceSummary(
  protocolDeviceId: id,
  signingKeyId: '$id-signing',
  e2eeKeyId: '$id-encryption',
  status: status,
  role: role,
  managementReady: ready,
  isCurrent: current,
);

DeviceSummary joined({
  DeviceRole role = DeviceRole.member,
  bool ready = false,
  bool current = false,
  DeviceStatus status = DeviceStatus.active,
}) => device(
  id: 'joined-device',
  role: role,
  ready: ready,
  current: current,
  status: status,
);

bool matches(
  List<DeviceSummary> devices, {
  String adminId = 'admin-device',
  String joinedId = 'joined-device',
}) => hasExactAdminAndJoinedDevice(
  DeviceRegistrySnapshot(did: 'did:wba:test.example:account', devices: devices),
  currentAdminDeviceId: adminId,
  joinedDeviceId: joinedId,
);

void main() {
  test('binds the exact rootless member before automatic management', () {
    expect(matches([device(), joined()]), isTrue);
  });

  test('binds the same exact device after automatic management completes', () {
    expect(
      matches([device(), joined(role: DeviceRole.admin, ready: true)]),
      isTrue,
    );
  });

  test('rejects contradictory joined role and readiness', () {
    for (final target in [
      joined(role: DeviceRole.admin),
      joined(ready: true),
    ]) {
      expect(matches([device(), target]), isFalse);
    }
  });

  test('rejects a different admin or joined device principal', () {
    final devices = [device(), joined()];
    expect(matches(devices, adminId: 'another-admin'), isFalse);
    expect(matches(devices, joinedId: 'another-joined-device'), isFalse);
    expect(matches(devices, adminId: 'joined-device'), isFalse);
    expect(matches(devices, joinedId: ''), isFalse);
  });

  test('requires the sole current device to be the bootstrap admin', () {
    expect(matches([device(current: false), joined()]), isFalse);
    expect(matches([device(), joined(current: true)]), isFalse);
    expect(
      matches([device(role: DeviceRole.member, ready: false), joined()]),
      isFalse,
    );
    expect(matches([device(ready: false), joined()]), isFalse);
  });

  test('rejects revoked devices before the explicit revoke action', () {
    expect(matches([device(status: DeviceStatus.revoked), joined()]), isFalse);
    expect(matches([device(), joined(status: DeviceStatus.revoked)]), isFalse);
  });

  test('rejects missing, duplicate, or third devices', () {
    expect(matches([device()]), isFalse);
    expect(matches([device(), device()]), isFalse);
    expect(matches([joined(), joined()]), isFalse);
    expect(
      matches([device(), joined(), device(id: 'third-device', current: false)]),
      isFalse,
    );
  });
}
