import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/ports/device_capability_upgrade_port.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/widgets/app_widgets.dart';
import 'device_capability_provider.dart';

class DeviceCapabilityCard extends ConsumerStatefulWidget {
  const DeviceCapabilityCard({super.key, this.targetDeviceId});
  final String? targetDeviceId;

  @override
  ConsumerState<DeviceCapabilityCard> createState() =>
      _DeviceCapabilityCardState();
}

class _DeviceCapabilityCardState extends ConsumerState<DeviceCapabilityCard> {
  bool _busy = false;
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(deviceCapabilityProvider(widget.targetDeviceId));
    final status = result.valueOrNull;
    if (!_failed &&
        !result.hasError &&
        (status == null || status.state == DeviceCapabilityState.ready)) {
      return const SizedBox.shrink();
    }
    final text = _failed || result.hasError
        ? context.l10n.deviceCapabilityRetry
        : switch (status!.state) {
            DeviceCapabilityState.approvalRequired =>
              context.l10n.deviceCapabilityApproval,
            DeviceCapabilityState.unsupported =>
              context.l10n.deviceCapabilityUnsupported,
            DeviceCapabilityState.blocked =>
              context.l10n.deviceCapabilityBlocked,
            _ => context.l10n.deviceCapabilityAvailable,
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(text, key: const Key('device-capability-status')),
            if (status?.state != DeviceCapabilityState.unsupported) ...[
              const SizedBox(height: 8),
              AppSecondaryButton(
                label:
                    status?.state == DeviceCapabilityState.upgradeAvailable &&
                        widget.targetDeviceId != null
                    ? context.l10n.deviceCapabilityApprove
                    : context.l10n.commonRefresh,
                onPressed: _busy
                    ? null
                    : () async {
                        if (status?.state ==
                                DeviceCapabilityState.upgradeAvailable &&
                            widget.targetDeviceId != null) {
                          await _approve();
                        } else {
                          setState(() => _failed = false);
                          ref.invalidate(
                            deviceCapabilityProvider(widget.targetDeviceId),
                          );
                        }
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final identityId = ref.read(sessionProvider).session?.localIdentityId;
    final port = ref.read(identityCorePortProvider);
    if (identityId == null || port is! DeviceCapabilityUpgradePort) return;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(context.l10n.deviceCapabilityApprove),
        content: Text(context.l10n.deviceCapabilityConfirm),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        ref.read(sessionProvider).session?.localIdentityId != identityId ||
        !identical(ref.read(identityCorePortProvider), port)) {
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    bool isCurrent() =>
        mounted &&
        ref.read(sessionProvider).session?.localIdentityId == identityId &&
        identical(ref.read(identityCorePortProvider), port);
    try {
      await (port as DeviceCapabilityUpgradePort).upgradeDeviceCapabilities(
        identityId,
        targetDeviceId: widget.targetDeviceId,
        userPresenceConfirmed: true,
      );
      if (isCurrent()) {
        ref.invalidate(deviceCapabilityProvider(widget.targetDeviceId));
      }
    } catch (_) {
      if (isCurrent()) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
