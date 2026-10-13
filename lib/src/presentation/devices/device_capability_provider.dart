import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/ports/device_capability_upgrade_port.dart';
import '../../application/tenant/app_tenant.dart';
import '../app_shell/providers/session_provider.dart';

/// One independent, non-blocking check per active identity/tenant. Only this
/// device may be upgraded automatically; another device needs explicit approval.
final deviceCapabilityProvider =
    FutureProvider.family<DeviceCapabilityStatus?, String?>((
      ref,
      target,
    ) async {
      ref.watch(activeAppTenantProvider);
      final identityId = ref.watch(
        sessionProvider.select((state) => state.session?.localIdentityId),
      );
      final port = ref.watch(identityCorePortProvider);
      if (identityId == null || port is! DeviceCapabilityUpgradePort) {
        return null;
      }
      var current = true;
      ref.onDispose(() => current = false);
      final upgrades = port as DeviceCapabilityUpgradePort;
      var status = await upgrades.inspectDeviceCapabilities(
        identityId,
        targetDeviceId: target,
      );
      if (current &&
          target == null &&
          status.state == DeviceCapabilityState.upgradeAvailable) {
        status = await upgrades.upgradeDeviceCapabilities(identityId);
      }
      return current ? status : null;
    });
