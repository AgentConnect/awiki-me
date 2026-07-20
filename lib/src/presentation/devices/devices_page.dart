// [INPUT]: Device Registry, local Join/Recovery projections, root-transfer phase, and user actions.
// [OUTPUT]: Device management UI with ready-admin gates and secret-free root-import status.
// [POS]: Device administration surface; encrypted control JSON is never a renderable model.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../domain/entities/device_management.dart';
import '../../domain/entities/handle_recovery.dart';
import '../../l10n/l10n.dart';
import '../recovery/handle_recovery_panel.dart';
import '../recovery/handle_recovery_provider.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(devicesProvider.notifier).loadManagement());
        if (ref.read(handleRecoveryEnabledProvider)) {
          unawaited(ref.read(handleRecoveryProvider.notifier).restore());
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesProvider);
    final recoveryEnabled = ref.watch(handleRecoveryEnabledProvider);
    final recoveryState = ref.watch(handleRecoveryProvider);
    final registry = state.registry;
    final canManage = state.currentDeviceCanManage;
    final cancellableRecoveries = recoveryEnabled
        ? recoveryState.cancellableAdminSessions
              .where((_) => canManage)
              .toList(growable: false)
        : const <HandleRecoveryProgress>[];
    final rootTransferEnabled = ref.watch(
      multiDeviceRootTransferEnabledProvider,
    );
    final resumable = state.localJoins
        .where((join) => join.side == DeviceJoinSide.admin && !join.isTerminal)
        .where((_) => canManage)
        .toList();
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
                onTap: state.isLoading
                    ? null
                    : () => ref.read(devicesProvider.notifier).loadManagement(),
                child: const Icon(CupertinoIcons.refresh, size: 20),
              ),
            ),
            const SizedBox(height: 16),
            if (state.error ==
                DeviceManagementErrorKind
                    .sessionEstablishmentPending) ...<Widget>[
              AppSurface(
                color: context.awikiTheme.subtleSurface,
                child: Text(
                  deviceManagementErrorLabel(context.l10n, state.error!),
                  key: const Key('devices-root-session-pending'),
                  style: TextStyle(color: context.awikiTheme.infoAccent),
                ),
              ),
              const SizedBox(height: 12),
            ] else if (state.error != null) ...<Widget>[
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
            if (recoveryState.error != null && recoveryEnabled) ...<Widget>[
              AppSurface(
                color: context.awikiTheme.dangerContainer,
                child: Text(
                  handleRecoveryErrorLabel(context, recoveryState.error!),
                  key: const Key('handle-recovery-admin-error'),
                  style: TextStyle(color: context.awikiTheme.danger),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (cancellableRecoveries.isNotEmpty) ...<Widget>[
              _SectionLabel(context.l10n.handleRecoveryAdminSectionTitle),
              const SizedBox(height: 8),
              AppCardSection(
                key: const Key('handle-recovery-admin-section'),
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (
                      var index = 0;
                      index < cancellableRecoveries.length;
                      index++
                    ) ...<Widget>[
                      AppListTile(
                        title: cancellableRecoveries[index].canonicalHandle,
                        subtitle: context.l10n
                            .handleRecoveryAdminSectionSubtitle(
                              cancellableRecoveries[index].canonicalHandle,
                            ),
                        trailing: CupertinoButton(
                          key: Key(
                            'handle-recovery-cancel-${cancellableRecoveries[index].recoverySessionId}',
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          onPressed: recoveryState.isBusy
                              ? null
                              : () => _confirmCancelRecovery(
                                  cancellableRecoveries[index],
                                ),
                          child: Text(
                            context.l10n.handleRecoveryAdminCancel,
                            style: TextStyle(
                              color: context.awikiTheme.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (index != cancellableRecoveries.length - 1)
                        const AppSectionDivider(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
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
                            sessionEstablishmentPending: state
                                .isRootSessionEstablishing(
                                  registry.devices[index],
                                ),
                            rootTransferEnabled: rootTransferEnabled,
                            canStartRootTransfer: state.canStartRootTransfer(
                              registry.devices[index],
                            ),
                            canRetryRootTransfer: state.canRetryRootTransfer(
                              registry.devices[index],
                            ),
                            isActionPending: state.isActionPending,
                            onRootTransfer: () => ref
                                .read(devicesProvider.notifier)
                                .startOrRetryRootTransfer(
                                  recipient: registry.devices[index],
                                  presenceReason: context
                                      .l10n
                                      .deviceRootTransferPresenceReason,
                                ),
                          ),
                          if (index != registry.devices.length - 1)
                            const AppSectionDivider(),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 18),
            _SectionLabel(context.l10n.devicesPendingTitle),
            const SizedBox(height: 8),
            AppCardSection(
              padding: EdgeInsets.zero,
              child: registry == null || registry.pendingJoins.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.l10n.devicesPendingEmpty),
                    )
                  : Column(
                      children: <Widget>[
                        for (
                          var index = 0;
                          index < registry.pendingJoins.length;
                          index++
                        ) ...<Widget>[
                          AppListTile(
                            title:
                                registry.pendingJoins[index].protocolDeviceId,
                            subtitle: canManage
                                ? context.l10n.deviceReviewAction
                                : context.l10n.deviceManagementActionDisabled,
                            onTap: canManage
                                ? () =>
                                      _openPending(registry.pendingJoins[index])
                                : null,
                          ),
                          if (index != registry.pendingJoins.length - 1)
                            const AppSectionDivider(),
                        ],
                      ],
                    ),
            ),
            if (resumable.isNotEmpty) ...<Widget>[
              const SizedBox(height: 18),
              _SectionLabel(context.l10n.devicesLocalJoinsTitle),
              const SizedBox(height: 8),
              AppCardSection(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (var index = 0; index < resumable.length; index++) ...[
                      AppListTile(
                        title: resumable[index].protocolDeviceId,
                        subtitle: context.l10n.deviceResumeAction,
                        onTap: () => _openRestored(resumable[index]),
                      ),
                      if (index != resumable.length - 1)
                        const AppSectionDivider(),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openPending(PendingDeviceJoinSummary pending) async {
    await AppNavigator.push<void>(
      context,
      (_) => DeviceJoinApprovalSheet(pending: pending),
    );
    if (mounted) {
      await ref.read(devicesProvider.notifier).loadManagement();
    }
  }

  Future<void> _openRestored(DeviceJoinProgress restored) async {
    await AppNavigator.push<void>(
      context,
      (_) => DeviceJoinApprovalSheet(restored: restored),
    );
    if (mounted) {
      await ref.read(devicesProvider.notifier).loadManagement();
    }
  }

  Future<void> _confirmCancelRecovery(HandleRecoveryProgress recovery) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(context.l10n.handleRecoveryAdminCancelConfirmTitle),
        content: Text(context.l10n.handleRecoveryAdminCancelConfirmDetail),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            key: const Key('handle-recovery-cancel-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.handleRecoveryAdminCancelConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(handleRecoveryProvider.notifier)
          .cancel(
            recovery,
            intentConfirmed: true,
            presenceReason: context.l10n.handleRecoveryCancelPresenceReason,
          );
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
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.readiness,
    required this.sessionEstablishmentPending,
    required this.rootTransferEnabled,
    required this.canStartRootTransfer,
    required this.canRetryRootTransfer,
    required this.isActionPending,
    required this.onRootTransfer,
  });

  final DeviceSummary device;
  final DeviceManagementReadiness? readiness;
  final bool sessionEstablishmentPending;
  final bool rootTransferEnabled;
  final bool canStartRootTransfer;
  final bool canRetryRootTransfer;
  final bool isActionPending;
  final VoidCallback onRootTransfer;

  @override
  Widget build(BuildContext context) {
    final role = deviceRoleLabel(context.l10n, device.role);
    final status = deviceStatusLabel(context.l10n, device.status);
    final readinessLabel = sessionEstablishmentPending
        ? context.l10n.deviceRootTransferSessionPending
        : readiness == null
        ? null
        : deviceManagementReadinessLabel(context.l10n, readiness!);
    final canTransferRoot =
        rootTransferEnabled && (canStartRootTransfer || canRetryRootTransfer);
    return AppListTile(
      title: device.isCurrent
          ? '${device.protocolDeviceId} · ${context.l10n.deviceCurrent}'
          : device.protocolDeviceId,
      subtitle: <String>[
        role,
        status,
        if (readinessLabel != null) readinessLabel,
      ].join(' · '),
      trailing: canTransferRoot
          ? CupertinoButton(
              key: Key('root-transfer-${device.protocolDeviceId}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              onPressed: isActionPending ? null : onRootTransfer,
              child: Text(
                sessionEstablishmentPending
                    ? context.l10n.deviceRootTransferContinue
                    : canStartRootTransfer
                    ? context.l10n.deviceRootTransferStart
                    : context.l10n.deviceRootTransferRetry,
              ),
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
