// [INPUT]: Authorized Device Registry, Core-verified Join notices, and admin actions.
// [OUTPUT]: Device list and read-only notification-driven Join review entry.
// [POS]: Device administration surface; raw control JSON/checkpoints never enter previews or UI.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../domain/entities/device_management.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'device_join_approval_sheet.dart';
import 'device_labels.dart';
import 'devices_provider.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_refresh());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesProvider);
    final registry = state.displayRegistry;
    final canManage = state.currentDeviceCanManage;
    final deviceRevokeEnabled = ref.watch(
      multiDeviceDeviceRevokeEnabledProvider,
    );
    final joinRequests = state.visibleJoinRequests;
    final refreshPending = _isRefreshing || state.isLoading;
    return CupertinoPageScaffold(
      backgroundColor: context.awikiTheme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 820,
        includeBottomSafeArea: true,
        child: ListView(
          key: const Key('devices-page'),
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
          children: <Widget>[
            AwikiMeTopBar(
              title: context.l10n.devicesTitle,
              padding: EdgeInsets.zero,
              leading: TopBarActionButton(
                onTap: () => Navigator.of(context).maybePop(),
                child: const AwikiAssetIcon(
                  assetName: 'assets/icons/icon_left.svg',
                  color: AwikiMeColors.primaryDark,
                  size: 22,
                ),
              ),
              trailing: TopBarActionButton(
                key: const Key('devices-refresh'),
                onTap: refreshPending ? null : _refresh,
                semanticsLabel: context.l10n.commonRefresh,
                tooltip: context.l10n.commonRefresh,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: refreshPending
                      ? const CupertinoActivityIndicator(
                          key: Key('devices-refresh-loading'),
                          radius: 8,
                        )
                      : const Icon(
                          CupertinoIcons.refresh,
                          key: Key('devices-refresh-icon'),
                          size: 20,
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (state.error != null) ...<Widget>[
              AppSurface(
                color: context.awikiTheme.dangerContainer,
                child: Text(
                  deviceManagementErrorLabel(context.l10n, state.error!),
                  key: const Key('devices-error'),
                  style: TextStyle(color: context.awikiTheme.danger),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (state.revokeNotice != null) ...<Widget>[
              AppSurface(
                child: Text(
                  _deviceRevokeNoticeLabel(context, state.revokeNotice!),
                  key: const Key('device-revoke-notice'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _SectionLabel(context.l10n.devicesAuthorizedTitle),
            const SizedBox(height: 8),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: registry == null || registry.devices.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.l10n.devicesEmpty),
                    )
                  : Column(
                      children: <Widget>[
                        for (
                          var index = 0;
                          index < registry.devices.length;
                          index++
                        ) ...<Widget>[
                          _DeviceTile(
                            device: registry.devices[index],
                            readiness: state.readinessFor(
                              registry.devices[index],
                            ),
                            revokeEnabled: deviceRevokeEnabled,
                            canRevoke: state.canRevokeDevice(
                              registry.devices[index],
                            ),
                            isSubmitting:
                                state.revokeSubmittingDeviceId ==
                                registry.devices[index].protocolDeviceId,
                            isConfirming:
                                state.revokeConfirmingDeviceId ==
                                registry.devices[index].protocolDeviceId,
                            onRevoke: () =>
                                _confirmDeviceRevoke(registry.devices[index]),
                          ),
                          if (index != registry.devices.length - 1)
                            const AppSectionDivider(),
                        ],
                      ],
                    ),
            ),
            if (deviceRevokeEnabled && canManage) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                context.l10n.deviceRevokeProtectionHint,
                key: const Key('device-revoke-protection-hint'),
                style: TextStyle(
                  color: context.awikiTheme.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 18),
            _SectionLabel(context.l10n.devicesPendingTitle),
            const SizedBox(height: 8),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: joinRequests.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.l10n.devicesPendingEmpty),
                    )
                  : Column(
                      children: <Widget>[
                        for (
                          var index = 0;
                          index < joinRequests.length;
                          index++
                        ) ...<Widget>[
                          AppListTile(
                            title: joinRequests[index].protocolDeviceId,
                            subtitle:
                                '${joinRequests[index].candidateKeyFingerprint} · '
                                '${joinRequests[index].claimedByOther
                                    ? context.l10n.deviceJoinClaimedByOther
                                    : canManage
                                    ? context.l10n.deviceReviewAction
                                    : context.l10n.deviceManagementActionDisabled}',
                            onTap: canManage
                                ? () => _openPending(joinRequests[index])
                                : null,
                          ),
                          if (index != joinRequests.length - 1)
                            const AppSectionDivider(),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeviceRevoke(DeviceSummary device) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        key: const Key('device-revoke-confirm-dialog'),
        title: Text(context.l10n.deviceRevokeConfirmTitle),
        content: Text(
          context.l10n.deviceRevokeConfirmDetail(device.protocolDeviceId),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            key: const Key('device-revoke-confirm-action'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.deviceRevokeConfirmAction),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await ref
        .read(devicesProvider.notifier)
        .revokeDevice(
          target: device,
          presenceReason: context.l10n.deviceRevokePresenceReason,
        );
  }

  Future<void> _openPending(DeviceJoinRequestNotice request) async {
    await AppNavigator.push<void>(
      context,
      (_) => DeviceJoinApprovalSheet(request: request),
    );
    if (mounted) {
      await ref.read(devicesProvider.notifier).loadManagement();
    }
  }

  Future<void> _refresh() async {
    final state = ref.read(devicesProvider);
    if (_isRefreshing || state.isLoading) return;
    setState(() => _isRefreshing = true);
    try {
      if (state.revokeSubmittingDeviceId != null ||
          state.revokeConfirmingDeviceId != null) {
        await ref.read(devicesProvider.notifier).refreshRegistryOnly();
        return;
      }
      await ref.read(devicesProvider.notifier).loadManagement();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: context.awikiTheme.secondaryText,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.readiness,
    required this.revokeEnabled,
    required this.canRevoke,
    required this.isSubmitting,
    required this.isConfirming,
    required this.onRevoke,
  });

  final DeviceSummary device;
  final DeviceManagementReadiness? readiness;
  final bool revokeEnabled;
  final bool canRevoke;
  final bool isSubmitting;
  final bool isConfirming;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final role = deviceRoleLabel(context.l10n, device.role);
    final status = deviceStatusLabel(context.l10n, device.status);
    final readinessLabel = readiness == null
        ? null
        : deviceManagementReadinessLabel(context.l10n, readiness!);
    return AppListTile(
      title: device.isCurrent
          ? '${device.protocolDeviceId} · ${context.l10n.deviceCurrent}'
          : device.protocolDeviceId,
      subtitle: <String>[
        role,
        status,
        if (readinessLabel != null) readinessLabel,
      ].join(' · '),
      trailing: revokeEnabled && canRevoke
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (revokeEnabled && canRevoke)
                  CupertinoButton(
                    key: Key('device-revoke-${device.protocolDeviceId}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    onPressed: isSubmitting ? null : onRevoke,
                    child: isSubmitting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const CupertinoActivityIndicator(radius: 8),
                              const SizedBox(width: 6),
                              Text(context.l10n.deviceRevokeSubmitting),
                            ],
                          )
                        : Text(
                            isConfirming
                                ? context.l10n.deviceRevokeConfirmingAction
                                : context.l10n.deviceRevokeAction,
                            style: TextStyle(color: context.awikiTheme.danger),
                          ),
                  ),
              ],
            )
          : Icon(
              device.isCurrent
                  ? CupertinoIcons.device_phone_portrait
                  : CupertinoIcons.desktopcomputer,
              color: context.awikiTheme.secondaryText,
            ),
    );
  }
}

String _deviceRevokeNoticeLabel(
  BuildContext context,
  DeviceRevokeNotice notice,
) => switch (notice) {
  DeviceRevokeNotice.revoked => context.l10n.deviceRevokeSucceeded,
  DeviceRevokeNotice.revokedGroupsSyncing =>
    context.l10n.deviceRevokeSucceededGroupsSyncing,
  DeviceRevokeNotice.outcomeUnknown => context.l10n.deviceRevokeOutcomeUnknown,
  DeviceRevokeNotice.rejected => context.l10n.deviceRevokeRejected,
};
