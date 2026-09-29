import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/device_management.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/awiki_glass_controls.dart';
import '../../core/date_time_formatter.dart';
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
  Timer? _statusRefresh;

  @override
  void initState() {
    super.initState();
    // Display refresh only. Core owns all durable retry timing and network work.
    _statusRefresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        unawaited(ref.read(devicesProvider.notifier).refreshManagementStatus());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(devicesProvider.notifier).selectJoinRequest(widget.request),
        );
      }
    });
  }

  @override
  void dispose() {
    _statusRefresh?.cancel();
    super.dispose();
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

    final theme = context.awikiTheme;
    final l10n = context.l10n;
    final busy = state.isActionPending;
    final Widget body;
    if (terminal) {
      body = _TerminalBody(
        title: _requestStatusLabel(context, request, progress),
        // Anything other than an authorized join ended without adding the
        // device, so it takes the warning mark.
        rejected: progress?.phase != DeviceJoinPhase.authorized,
        action: _buildTerminalAction(state: state, progress: progress),
      );
    } else if (ready) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SheetTitle(l10n.deviceJoinCompareTitle),
          const SizedBox(height: 6),
          Text(
            l10n.deviceJoinSasHint,
            style: TextStyle(
              color: theme.secondaryText,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: theme.glassLens,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.deviceJoinLocalSasLabel,
                  style: TextStyle(color: theme.secondaryText, fontSize: 12),
                ),
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: const Key('device-approval-sas'),
                  child: AwikiSasDigits(code: sas),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          AwikiCheckRow(
            key: const Key('device-sas-confirmation'),
            label: l10n.deviceJoinSasMatches,
            value: _sasMatches,
            onChanged: busy
                ? null
                : (value) => setState(() => _sasMatches = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              AwikiPillButton(
                label: l10n.deviceJoinSasMismatch,
                tone: AwikiPillTone.dangerText,
                onPressed: busy
                    ? null
                    : () => _reject(DeviceJoinRejectReason.sasMismatch),
              ),
              const Spacer(),
              Flexible(
                flex: 3,
                child: AwikiPillButton(
                  label: l10n.deviceJoinApprove,
                  semanticsIdentifier: 'multi-device-approve',
                  onPressed: !_sasMatches || busy ? null : _approve,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: AwikiPillButton(
              label: l10n.deviceJoinReject,
              tone: AwikiPillTone.text,
              height: 36,
              onPressed: busy
                  ? null
                  : () => _reject(DeviceJoinRejectReason.userRejected),
            ),
          ),
        ],
      );
    } else {
      final canStart = progress == null && request.canStartVerification;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SheetTitle(l10n.deviceJoinApprovalTitle),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: theme.glassLens,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.glass,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.glassEdgeActive,
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    CupertinoIcons.device_laptop,
                    size: 20,
                    color: theme.title,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        request.protocolDeviceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.title, fontSize: 16),
                      ),
                      Text(
                        _requestStatusLabel(context, request, progress),
                        key: const Key('device-approval-phase'),
                        style: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AwikiDetailRows(
            key: const Key('device-approval-fingerprint'),
            monoLast: true,
            rows: <(String, String)>[
              (
                l10n.deviceJoinIssuedAtLabel,
                DateTimeFormatter.requestTime(request.issuedAt.toLocal()),
              ),
              (
                l10n.deviceJoinExpiresAtLabel,
                DateTimeFormatter.requestTime(request.expiresAt.toLocal()),
              ),
              (
                l10n.deviceJoinFingerprintLabel,
                request.candidateKeyFingerprint,
              ),
            ],
          ),
          if (canStart) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              l10n.deviceJoinOpenHint,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (request.claimedByOther)
            AwikiPillButton(
              label: l10n.commonDone,
              tone: AwikiPillTone.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            Row(
              children: <Widget>[
                AwikiPillButton(
                  label: l10n.deviceJoinReject,
                  tone: AwikiPillTone.dangerOutline,
                  onPressed: busy
                      ? null
                      : () => _reject(DeviceJoinRejectReason.userRejected),
                ),
                const Spacer(),
                AwikiPillButton(
                  label: l10n.commonLater,
                  tone: AwikiPillTone.text,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                if (canStart) ...<Widget>[
                  const SizedBox(width: 6),
                  AwikiPillButton(
                    label: l10n.deviceJoinStartVerification,
                    semanticsIdentifier: 'multi-device-start-verification',
                    busy: busy,
                    onPressed: busy
                        ? null
                        : () => ref
                              .read(devicesProvider.notifier)
                              .startVerification(request),
                  ),
                ],
              ],
            ),
        ],
      );
    }
    return Column(
      key: const Key('device-join-approval-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.error != null) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.dangerContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              deviceManagementErrorLabel(l10n, state.error!),
              key: const Key('device-approval-error'),
              style: TextStyle(color: theme.danger, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
        ],
        body,
      ],
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
    // The terminal notification can arrive before the approval result and its
    // authorized-device summary. Do not offer a premature exit from this flow.
    if (state.isActionPending) {
      return AwikiPillButton(
        key: const Key('device-join-finalizing'),
        label: context.l10n.deviceJoinFinalizing,
        expand: true,
        onPressed: null,
      );
    }
    DeviceJoinManagementStatus? management;
    for (final status in state.managementStatuses) {
      if (status.joinSessionId == widget.request.joinSessionId &&
          status.recipientDeviceId == widget.request.protocolDeviceId) {
        management = status;
        break;
      }
    }
    final label = management?.requiresRejoin == true
        ? context.l10n.deviceJoinManagementRejoinRequired
        : switch (management?.phase) {
            'failed' => context.l10n.deviceJoinManagementFailed,
            'waiting_for_recipient' => context.l10n.deviceJoinManagementWaiting,
            'management_registered' =>
              context.l10n.deviceJoinManagementRegistered,
            _ => context.l10n.deviceJoinManagementConfiguring,
          };
    if (state.registry?.methodCapabilities?.rootTransfer != true ||
        progress?.phase != DeviceJoinPhase.authorized) {
      return Align(
        alignment: Alignment.centerRight,
        child: AwikiPillButton(
          label: context.l10n.commonDone,
          tone: AwikiPillTone.secondary,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          label,
          key: const Key('device-join-management-phase'),
          textAlign: TextAlign.center,
        ),
        if (management?.canRetry == true) ...<Widget>[
          const SizedBox(height: 12),
          AwikiPillButton(
            key: const Key('device-join-management-retry'),
            expand: true,
            label: context.l10n.commonRetry,
            onPressed: state.isActionPending
                ? null
                : () => ref
                      .read(devicesProvider.notifier)
                      .retryJoinManagement(widget.request.joinSessionId),
          ),
        ],
        const SizedBox(height: 12),
        AwikiPillButton(
          label: context.l10n.commonDone,
          tone: AwikiPillTone.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
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

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.awikiTheme.title,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

/// Final state: a round status mark, the outcome and the closing action.
class _TerminalBody extends StatelessWidget {
  const _TerminalBody({
    required this.title,
    required this.rejected,
    required this.action,
  });

  final String title;
  final bool rejected;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final tint = rejected ? theme.danger : theme.success;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              rejected
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.checkmark,
              color: tint,
              size: 22,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          key: const Key('device-approval-phase'),
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.title, fontSize: 20, height: 1.3),
        ),
        const SizedBox(height: 16),
        action,
      ],
    );
  }
}

/// Opens the join approval: a floating glass sheet on phones and a centered
/// glass dialog on wider layouts.
Future<void> showDeviceJoinApproval(
  BuildContext context,
  DeviceJoinRequestNotice request,
) {
  if (context.awikiResponsive.isPhone) {
    return showAwikiGlassSheet<void>(
      context,
      builder: (_) => DeviceJoinApprovalSheet(request: request),
    );
  }
  return showCupertinoDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AwikiGlassPanel(
            child: SingleChildScrollView(
              child: DeviceJoinApprovalSheet(request: request),
            ),
          ),
        ),
      ),
    ),
  );
}
