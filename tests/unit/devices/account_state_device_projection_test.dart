import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:awiki_me/src/presentation/devices/devices_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cached Registry wins display while fresh Core facts authorize', () {
    const fresh = DeviceRegistrySnapshot(
      did: 'did:wba:example.test:alice',
      registryVersion: '1',
      devices: <DeviceSummary>[
        DeviceSummary(
          protocolDeviceId: 'device-1',
          signingKeyId: 'did:key:old-signing',
          e2eeKeyId: 'did:key:old-e2ee',
          status: DeviceStatus.active,
          role: DeviceRole.admin,
          managementReady: true,
          isCurrent: true,
          authGeneration: '1',
        ),
      ],
    );
    const cached = DeviceRegistrySnapshot(
      did: 'did:wba:example.test:alice',
      registryVersion: '2',
      devices: <DeviceSummary>[
        DeviceSummary(
          protocolDeviceId: 'device-1',
          signingKeyId: 'did:key:new-signing',
          e2eeKeyId: 'did:key:new-e2ee',
          status: DeviceStatus.revoked,
          role: DeviceRole.member,
          managementReady: false,
          isCurrent: true,
          authGeneration: '2',
        ),
      ],
    );
    const state = DevicesState(registry: fresh, cachedRegistry: cached);

    expect(state.displayRegistry?.registryVersion, '2');
    expect(state.displayRegistry?.currentDevice?.status, DeviceStatus.revoked);
    expect(
      state.currentDeviceCanManage,
      isTrue,
      reason: 'authorization remains derived from the fresh Core Registry',
    );
  });

  test('cached admin cannot authorize without fresh Core Registry', () {
    const cached = DeviceRegistrySnapshot(
      did: 'did:wba:example.test:alice',
      registryVersion: '1',
      devices: <DeviceSummary>[
        DeviceSummary(
          protocolDeviceId: 'device-1',
          signingKeyId: 'did:key:signing',
          e2eeKeyId: 'did:key:e2ee',
          status: DeviceStatus.active,
          role: DeviceRole.admin,
          managementReady: true,
          isCurrent: true,
          authGeneration: '1',
        ),
      ],
    );
    const state = DevicesState(cachedRegistry: cached);

    expect(state.displayRegistry, same(cached));
    expect(state.currentDeviceCanManage, isFalse);
  });

  test('newer fresh Core Registry is not hidden by stale cache', () {
    const state = DevicesState(
      registry: DeviceRegistrySnapshot(
        did: 'did:wba:example.test:alice',
        registryVersion: '18446744073709551615',
      ),
      cachedRegistry: DeviceRegistrySnapshot(
        did: 'did:wba:example.test:alice',
        registryVersion: '18446744073709551614',
      ),
    );

    expect(state.displayRegistry, same(state.registry));
  });

  test('newer account cache is displayed over older fresh Core read', () {
    const state = DevicesState(
      registry: DeviceRegistrySnapshot(
        did: 'did:wba:example.test:alice',
        registryVersion: '999999999999999999999999999999999998',
      ),
      cachedRegistry: DeviceRegistrySnapshot(
        did: 'did:wba:example.test:alice',
        registryVersion: '999999999999999999999999999999999999',
      ),
    );

    expect(state.displayRegistry, same(state.cachedRegistry));
  });
}
