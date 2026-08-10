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
  const DeviceJoinApprovalSheet({super.key, required this.request});

  final DeviceJoinRequestNotice request;

  @override
  ConsumerState<DeviceJoinApprovalSheet> createState() =>
      _DeviceJoinApprovalSheetState();
}

class _DeviceJoinApprovalSheetState
    extends ConsumerState<DeviceJoinApprovalSheet> {
  bool _sasMatches = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(devicesProvider.notifier).selectJoinRequest(widget.request),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesProvider);
    final request =
        _requestForSession(state.joinRequests, widget.request.joinSessionId) ??
        widget.request;
    final candidateProgress = state.activeJoin;
    final progress =
        candidateProgress?.joinSessionId == request.joinSessionId &&
            candidateProgress?.side == DeviceJoinSide.admin
        ? candidateProgress
        : null;
    final sas =
        progress?.phase == DeviceJoinPhase.responseVerified ||
            progress?.phase == DeviceJoinPhase.approvalPrepared
        ? progress?.sas
        : null;
    final ready = sas != null;
    final terminal = request.isTerminal || progress?.isTerminal == true;

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
                    _requestStatusLabel(context, request, progress),
                    key: const Key('device-approval-phase'),
                    style: TextStyle(
                      color: context.awikiTheme.title,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    request.protocolDeviceId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.awikiTheme.secondaryText),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.deviceJoinFingerprint(
                      request.candidateKeyFingerprint,
                    ),
                    key: const Key('device-approval-fingerprint'),
                    style: TextStyle(color: context.awikiTheme.secondaryText),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.deviceJoinRequestWindow(
                      request.issuedAt.toLocal().toString(),
                      request.expiresAt.toLocal().toString(),
                    ),
                    style: TextStyle(
                      color: context.awikiTheme.secondaryText,
                      fontSize: 12,
                    ),
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
                        fontWeight: FontWeight.w400,
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
                  if (terminal)
                    _buildTerminalAction(state: state, progress: progress)
                  else if (request.claimedByOther)
                    AppSecondaryButton(
                      label: context.l10n.commonDone,
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  else if (ready) ...<Widget>[
                    _ApprovalSwitchRow(
                      key: const Key('device-sas-confirmation'),
                      label: context.l10n.deviceJoinSasMatches,
                      value: _sasMatches,
                      onChanged: state.isActionPending
                          ? null
                          : (value) => setState(() => _sasMatches = value),
                    ),
                    const SizedBox(height: 18),
                    AppPrimaryButton(
                      label: context.l10n.deviceJoinApprove,
                      semanticsIdentifier: 'multi-device-approve',
                      onPressed: !_sasMatches || state.isActionPending
                          ? null
                          : _approve,
                    ),
                    const SizedBox(height: 10),
                    AppDangerButton(
                      label: context.l10n.deviceJoinSasMismatch,
                      onPressed: state.isActionPending
                          ? null
                          : () => _reject(DeviceJoinRejectReason.sasMismatch),
                    ),
                    const SizedBox(height: 10),
                    AppSecondaryButton(
                      label: context.l10n.deviceJoinReject,
                      onPressed: state.isActionPending
                          ? null
                          : () => _reject(DeviceJoinRejectReason.userRejected),
                    ),
                  ] else if (progress == null &&
                      request.canStartVerification) ...<Widget>[
                    AppPrimaryButton(
                      label: context.l10n.deviceJoinStartVerification,
                      semanticsIdentifier: 'multi-device-start-verification',
                      onPressed: state.isActionPending
                          ? null
                          : () => ref
                                .read(devicesProvider.notifier)
                                .startVerification(request),
                    ),
                    const SizedBox(height: 10),
                    AppDangerButton(
                      label: context.l10n.deviceJoinReject,
                      onPressed: state.isActionPending
                          ? null
                          : () => _reject(DeviceJoinRejectReason.userRejected),
                    ),
                  ] else
                    AppDangerButton(
                      label: context.l10n.deviceJoinReject,
                      onPressed: state.isActionPending
                          ? null
                          : () => _reject(DeviceJoinRejectReason.userRejected),
                    ),
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
        .approveActiveAsMember(
          sasConfirmed: _sasMatches,
          presenceReason: context.l10n.deviceJoinUserPresenceReason,
        );
    if (approved && mounted) {
      setState(() => _sasMatches = false);
    }
  }

  Widget _buildTerminalAction({
    required DevicesState state,
    required DeviceJoinProgress? progress,
  }) {
    final recipient = progress?.authorizedDevice;
    final sender = state.registry?.currentDevice;
    final eligible =
        progress?.side == DeviceJoinSide.admin &&
        progress?.phase == DeviceJoinPhase.authorized &&
        recipient != null &&
        recipient.protocolDeviceId == progress!.protocolDeviceId &&
        recipient.status == DeviceStatus.active &&
        recipient.role == DeviceRole.member &&
        !recipient.managementReady &&
        !recipient.isCurrent &&
        sender?.canManageDevices == true &&
        sender!.protocolDeviceId != recipient.protocolDeviceId;
    if (!eligible) {
      return AppPrimaryButton(
        label: context.l10n.commonDone,
        onPressed: () => Navigator.of(context).maybePop(),
      );
    }

    final expectedContext = RootKeyTransferContext(
      joinSessionId: progress.joinSessionId,
      did: progress.did,
      recipientDeviceId: recipient.protocolDeviceId,
      recipientSigningKeyId: recipient.signingKeyId,
      recipientE2eeKeyId: recipient.e2eeKeyId,
    );
    final transfer = state.rootTransfer.context == expectedContext
        ? state.rootTransfer
        : const RootKeyTransferUiState();
    return switch (transfer.phase) {
      RootKeyTransferPhase.idle => AppPrimaryButton(
        key: const Key('root-transfer-grant-management'),
        label: context.l10n.deviceRootTransferGrantManagement,
        onPressed: () => ref
            .read(devicesProvider.notifier)
            .prepareRootTransferForActiveJoin(),
      ),
      RootKeyTransferPhase.preparing => AppPrimaryButton(
        key: const Key('root-transfer-preparing'),
        label: context.l10n.deviceRootTransferPreparing,
        onPressed: null,
      ),
      RootKeyTransferPhase.awaitingConfirmation => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.deviceRootTransferTarget(
              transfer.preparation!.recipient.deviceId,
              transfer.preparation!.recipient.signingKeyId,
              transfer.preparation!.recipient.e2eeKeyId,
            ),
            key: const Key('root-transfer-recipient-summary'),
            style: TextStyle(color: context.awikiTheme.secondaryText),
          ),
          const SizedBox(height: 16),
          AppPrimaryButton(
            key: const Key('root-transfer-confirm-send'),
            label: context.l10n.deviceRootTransferConfirm,
            onPressed: () => ref
                .read(devicesProvider.notifier)
                .confirmAndSendRootTransfer(
                  presenceReason: context.l10n.deviceRootTransferPresenceReason,
                ),
          ),
        ],
      ),
      RootKeyTransferPhase.sending => AppPrimaryButton(
        key: const Key('root-transfer-sending'),
        label: context.l10n.deviceRootTransferSending,
        onPressed: null,
      ),
      RootKeyTransferPhase.sent => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.deviceRootTransferSent,
            key: const Key('root-transfer-sent'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.awikiTheme.infoAccent),
          ),
          const SizedBox(height: 16),
          AppPrimaryButton(
            label: context.l10n.commonDone,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      RootKeyTransferPhase.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.deviceRootTransferFailed,
            key: const Key('root-transfer-failed'),
            style: TextStyle(color: context.awikiTheme.danger),
          ),
          const SizedBox(height: 16),
          AppPrimaryButton(
            label: context.l10n.commonDone,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    };
  }

  Future<void> _reject(DeviceJoinRejectReason reason) async {
    final request =
        _requestForSession(
          ref.read(devicesProvider).joinRequests,
          widget.request.joinSessionId,
        ) ??
        widget.request;
    final rejected = await ref
        .read(devicesProvider.notifier)
        .rejectJoin(request: request, reason: reason);
    if (rejected && mounted) {
      await Navigator.of(context).maybePop();
    }
  }
}

String _requestStatusLabel(
  BuildContext context,
  DeviceJoinRequestNotice request,
  DeviceJoinProgress? progress,
) {
  if (request.claimedByOther) {
    return context.l10n.deviceJoinClaimedByOther;
  }
  if (request.state == DeviceJoinRemoteState.rejected) {
    return context.l10n.deviceJoinRejected;
  }
  if (progress != null) {
    return deviceJoinPhaseLabel(context.l10n, progress);
  }
  return request.canStartVerification
      ? context.l10n.deviceJoinRequestReady
      : context.l10n.deviceJoinWaiting;
}

DeviceJoinRequestNotice? _requestForSession(
  List<DeviceJoinRequestNotice> requests,
  String joinSessionId,
) {
  for (final request in requests) {
    if (request.joinSessionId == joinSessionId) {
      return request;
    }
  }
  return null;
}

class _ApprovalSwitchRow extends StatelessWidget {
  const _ApprovalSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.awikiTheme.title,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 12),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
