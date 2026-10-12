import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/ports/device_capability_upgrade_port.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/devices/device_capability_card.dart';
import 'package:awiki_me/src/presentation/devices/device_capability_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

const _session = SessionIdentity(
  did: 'did:wba:example.test:alice',
  credentialName: 'alice',
  displayName: 'Alice',
  localIdentityId: 'owner-alice',
);

class _Port extends FakeIdentityCorePort
    implements DeviceCapabilityUpgradePort {
  DeviceCapabilityState state = DeviceCapabilityState.upgradeAvailable;
  int inspections = 0;
  int upgrades = 0;
  Completer<DeviceCapabilityStatus>? deferred;
  bool fail = false;
  @override
  Future<DeviceCapabilityStatus> inspectDeviceCapabilities(
    String identityId, {
    String? targetDeviceId,
  }) async {
    inspections++;
    if (fail) throw StateError('offline');
    return deferred?.future ??
        DeviceCapabilityStatus(deviceId: targetDeviceId ?? 'own', state: state);
  }

  @override
  Future<DeviceCapabilityStatus> upgradeDeviceCapabilities(
    String identityId, {
    String? targetDeviceId,
    bool userPresenceConfirmed = false,
  }) async {
    upgrades++;
    expect(targetDeviceId == null || userPresenceConfirmed, isTrue);
    return DeviceCapabilityStatus(
      deviceId: targetDeviceId ?? 'own',
      state: DeviceCapabilityState.ready,
    );
  }
}

ProviderContainer _container(_Port port) {
  final container = ProviderContainer(
    overrides: [
      identityCorePortProvider.overrideWithValue(port),
      activeAppTenantProvider.overrideWithValue(defaultTenantProfile()),
      sessionProvider.overrideWith(
        (ref) => SessionController()..setSession(_session),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test(
    'own ready-admin upgrade runs once and other devices never auto-upgrade',
    () async {
      final port = _Port();
      final container = _container(port);
      expect(
        (await container.read(deviceCapabilityProvider(null).future))!.state,
        DeviceCapabilityState.ready,
      );
      await container.read(deviceCapabilityProvider(null).future);
      expect(port.upgrades, 1);
      expect(
        (await container.read(
          deviceCapabilityProvider('member').future,
        ))!.state,
        DeviceCapabilityState.upgradeAvailable,
      );
      expect(port.upgrades, 1);
    },
  );

  test(
    'member waits for approval without blocking the active session',
    () async {
      final port = _Port()..state = DeviceCapabilityState.approvalRequired;
      final container = _container(port);
      expect(
        (await container.read(deviceCapabilityProvider(null).future))!.state,
        DeviceCapabilityState.approvalRequired,
      );
      expect(port.upgrades, 0);
      expect(container.read(sessionProvider).session, _session);
    },
  );

  test(
    'a late inspection after logout cannot start a capability mutation',
    () async {
      final port = _Port()..deferred = Completer<DeviceCapabilityStatus>();
      final container = _container(port);
      final pending = container.read(deviceCapabilityProvider(null).future);
      container.read(sessionProvider.notifier).setSession(null);
      await container.read(deviceCapabilityProvider(null).future);
      port.deferred!.complete(
        const DeviceCapabilityStatus(
          deviceId: 'own',
          state: DeviceCapabilityState.upgradeAvailable,
        ),
      );
      await pending;
      expect(port.upgrades, 0);
    },
  );

  testWidgets(
    'failure has one quiet inline retry and keeps the account usable',
    (tester) async {
      final port = _Port()..fail = true;
      await tester.pumpWidget(
        buildLocalizedTestApp(
          session: _session,
          home: const CupertinoPageScaffold(child: DeviceCapabilityCard()),
          providerOverrides: [identityCorePortProvider.overrideWithValue(port)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-capability-status')), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(port.upgrades, 0);
      port.fail = false;
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-capability-status')), findsNothing);
      expect(port.upgrades, 1);
    },
  );
}
