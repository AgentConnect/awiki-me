import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(devicesProvider.notifier).loadManagement());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesProvider);
    final registry = state.registry;
    final resumable = state.localJoins
        .where((join) => join.side == DeviceJoinSide.admin && !join.isTerminal)
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
                          _DeviceTile(device: registry.devices[index]),
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
                            subtitle: context.l10n.deviceReviewAction,
                            onTap: () =>
                                _openPending(registry.pendingJoins[index]),
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
  const _DeviceTile({required this.device});

  final DeviceSummary device;

  @override
  Widget build(BuildContext context) {
    final role = deviceRoleLabel(context.l10n, device.role);
    final status = deviceStatusLabel(context.l10n, device.status);
    final readiness = device.role == DeviceRole.admin
        ? device.managementReady
              ? context.l10n.deviceManagementReady
              : context.l10n.deviceManagementPending
        : null;
    return AppListTile(
      title: device.isCurrent
          ? '${device.protocolDeviceId} · ${context.l10n.deviceCurrent}'
          : device.protocolDeviceId,
      subtitle: <String>[
        role,
        status,
        if (readiness != null) readiness,
      ].join(' · '),
      trailing: Icon(
        device.isCurrent
            ? CupertinoIcons.device_phone_portrait
            : CupertinoIcons.desktopcomputer,
        color: context.awikiTheme.secondaryText,
      ),
    );
  }
}
