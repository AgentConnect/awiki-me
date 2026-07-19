import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/device_management.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'device_labels.dart';
import 'devices_provider.dart';

class DeviceJoinApprovalSheet extends ConsumerStatefulWidget {
  const DeviceJoinApprovalSheet({
    super.key,
    this.pending,
    this.restored,
    this.autoPoll = true,
  }) : assert(pending != null || restored != null);

  final PendingDeviceJoinSummary? pending;
  final DeviceJoinProgress? restored;
  final bool autoPoll;

  @override
  ConsumerState<DeviceJoinApprovalSheet> createState() =>
      _DeviceJoinApprovalSheetState();
}

class _DeviceJoinApprovalSheetState
    extends ConsumerState<DeviceJoinApprovalSheet> {
  Timer? _pollTimer;
  bool _sasMatches = false;
  bool _allowAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final restored = widget.restored;
      if (restored != null) {
        ref.read(devicesProvider.notifier).resume(restored);
        await ref.read(devicesProvider.notifier).pollActive();
      } else {
        await ref.read(devicesProvider.notifier).claim(widget.pending!);
      }
    });
    if (widget.autoPoll) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) {
          unawaited(ref.read(devicesProvider.notifier).pollActive());
        }
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesProvider);
    final progress = state.activeJoin;
    final sas = progress?.sas;
    final ready =
        progress?.side == DeviceJoinSide.admin &&
        progress?.phase == DeviceJoinPhase.responseVerified &&
        sas != null;
    return CupertinoPageScaffold(
      backgroundColor: context.awikiTheme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 620,
        includeBottomSafeArea: true,
        child: ListView(
          key: const Key('device-join-approval-sheet'),
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
          children: <Widget>[
            AwikiMeTopBar(
              title: context.l10n.deviceJoinApprovalTitle,
              padding: EdgeInsets.zero,
              leading: TopBarActionButton(
                onTap: () => Navigator.of(context).maybePop(),
                child: const AwikiAssetIcon(
                  assetName: 'assets/icons/icon_left.svg',
                  color: AwikiMeColors.primaryDark,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (state.error != null) ...<Widget>[
              AppSurface(
                color: context.awikiTheme.dangerContainer,
                child: Text(
                  deviceManagementErrorLabel(context.l10n, state.error!),
                  key: const Key('device-approval-error'),
                  style: TextStyle(color: context.awikiTheme.danger),
                ),
              ),
              const SizedBox(height: 12),
            ],
            AppCardSection(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    progress == null
                        ? context.l10n.deviceJoinWaiting
                        : deviceJoinPhaseLabel(context.l10n, progress),
                    key: const Key('device-approval-phase'),
                    style: TextStyle(
                      color: context.awikiTheme.title,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress?.protocolDeviceId ??
                        widget.pending?.protocolDeviceId ??
                        '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.awikiTheme.secondaryText),
                  ),
                  if (sas != null) ...<Widget>[
                    const SizedBox(height: 24),
                    Text(
                      sas,
                      key: const Key('device-approval-sas'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.awikiTheme.title,
                        fontSize: 38,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.deviceJoinSasHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.awikiTheme.secondaryText),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (ready) ...<Widget>[
                    _ApprovalSwitchRow(
                      key: const Key('device-sas-confirmation'),
                      label: context.l10n.deviceJoinSasMatches,
                      value: _sasMatches,
                      onChanged: state.isActionPending
                          ? null
                          : (value) => setState(() => _sasMatches = value),
                    ),
                    const SizedBox(height: 12),
                    _ApprovalSwitchRow(
                      key: const Key('device-admin-toggle'),
                      label: context.l10n.deviceJoinAllowAdmin,
                      detail: context.l10n.deviceJoinAllowAdminHint,
                      value: _allowAdmin,
                      onChanged: state.isActionPending
                          ? null
                          : (value) => setState(() => _allowAdmin = value),
                    ),
                    const SizedBox(height: 18),
                    AppPrimaryButton(
                      label: context.l10n.deviceJoinApprove,
                      semanticsIdentifier: 'multi-device-approve',
                      onPressed: !_sasMatches || state.isActionPending
                          ? null
                          : _approve,
                    ),
                  ] else if (progress?.isTerminal != true)
                    AppSecondaryButton(
                      label: context.l10n.deviceJoinRefresh,
                      onPressed: state.isActionPending
                          ? null
                          : () =>
                                ref.read(devicesProvider.notifier).pollActive(),
                    ),
                  if (progress?.isTerminal != true) ...<Widget>[
                    const SizedBox(height: 10),
                    AppDangerButton(
                      label: context.l10n.deviceJoinCancel,
                      onPressed: state.isActionPending
                          ? null
                          : () => ref
                                .read(devicesProvider.notifier)
                                .cancelActive(),
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: 10),
                    AppPrimaryButton(
                      label: context.l10n.commonDone,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final approved = await ref
        .read(devicesProvider.notifier)
        .approveActive(
          role: _allowAdmin ? DeviceRole.admin : DeviceRole.member,
          sasConfirmed: _sasMatches,
          presenceReason: context.l10n.deviceJoinUserPresenceReason,
        );
    if (approved && mounted) {
      setState(() {
        _sasMatches = false;
        _allowAdmin = false;
      });
    }
  }
}

class _ApprovalSwitchRow extends StatelessWidget {
  const _ApprovalSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: context.awikiTheme.title,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (detail != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  detail!,
                  style: TextStyle(
                    color: context.awikiTheme.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
