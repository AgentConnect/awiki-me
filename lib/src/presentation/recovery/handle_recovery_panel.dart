import 'package:flutter/cupertino.dart';

import '../../domain/entities/handle_recovery.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/app_widgets.dart';
import 'handle_recovery_provider.dart';

class HandleRecoveryPanel extends StatefulWidget {
  const HandleRecoveryPanel({
    super.key,
    required this.progress,
    required this.state,
    required this.phoneController,
    required this.reconfirmationOtpController,
    required this.onSendOtp,
    required this.onRefresh,
    required this.onFinalize,
    required this.onRetryActivation,
    required this.onDismiss,
  });

  final HandleRecoveryProgress progress;
  final HandleRecoveryState state;
  final TextEditingController phoneController;
  final TextEditingController reconfirmationOtpController;
  final VoidCallback onSendOtp;
  final VoidCallback onRefresh;
  final VoidCallback onFinalize;
  final VoidCallback onRetryActivation;
  final VoidCallback onDismiss;

  @override
  State<HandleRecoveryPanel> createState() => _HandleRecoveryPanelState();
}

class _HandleRecoveryPanelState extends State<HandleRecoveryPanel> {
  bool _risksConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final isBusy = widget.state.isBusy;
    return AppCardSection(
      key: const Key('handle-recovery-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.handleRecoveryTitle,
            style: TextStyle(
              color: context.awikiTheme.title,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.l10n.handleRecoveryWarning,
            key: const Key('handle-recovery-warning'),
            style: TextStyle(
              color: context.awikiTheme.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _RiskLine(context.l10n.handleRecoveryCreatesNewDid),
          _RiskLine(context.l10n.handleRecoverySignsOutOldDevices),
          _RiskLine(context.l10n.handleRecoveryNoHistoryOrGroupInheritance),
          const SizedBox(height: 18),
          _RecoveryStatus(progress: progress),
          if (widget.state.error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              handleRecoveryErrorLabel(context, widget.state.error!),
              key: const Key('handle-recovery-error'),
              style: TextStyle(color: context.awikiTheme.danger),
            ),
          ],
          if (progress.phase == HandleRecoveryPhase.cooling) ...<Widget>[
            const SizedBox(height: 16),
            AppSecondaryButton(
              label: context.l10n.handleRecoveryRefresh,
              semanticsIdentifier: 'handle-recovery-refresh',
              onPressed: isBusy ? null : widget.onRefresh,
            ),
          ] else if (progress.phase == HandleRecoveryPhase.ready) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              context.l10n.handleRecoveryReconfirmationHint,
              style: TextStyle(
                color: context.awikiTheme.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: widget.phoneController,
              label: context.l10n.onboardingPhone,
              placeholder: context.l10n.onboardingPhonePlaceholder,
              keyboardType: TextInputType.phone,
              semanticsIdentifier: 'handle-recovery-phone',
            ),
            const SizedBox(height: 10),
            AppTextField(
              controller: widget.reconfirmationOtpController,
              label: context.l10n.handleRecoveryReconfirmationOtp,
              placeholder: context.l10n.onboardingOtpPlaceholder,
              keyboardType: TextInputType.number,
              enabled: widget.state.reconfirmationOtpSent,
              semanticsIdentifier: 'handle-recovery-reconfirmation-otp',
            ),
            const SizedBox(height: 12),
            AppSecondaryButton(
              label: context.l10n.handleRecoverySendReconfirmationOtp,
              semanticsIdentifier: 'handle-recovery-send-final-otp',
              onPressed: isBusy ? null : widget.onSendOtp,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CupertinoSwitch(
                  key: const Key('handle-recovery-risk-confirmation'),
                  value: _risksConfirmed,
                  onChanged: isBusy
                      ? null
                      : (value) => setState(() => _risksConfirmed = value),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.handleRecoveryExplicitConfirmation,
                    style: TextStyle(
                      color: context.awikiTheme.title,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AppDangerButton(
              label: context.l10n.handleRecoveryFinalize,
              onPressed:
                  isBusy ||
                      !widget.state.reconfirmationOtpSent ||
                      !_risksConfirmed
                  ? null
                  : widget.onFinalize,
            ),
          ] else if (progress.localActivationPending) ...<Widget>[
            const SizedBox(height: 16),
            AppPrimaryButton(
              label: context.l10n.handleRecoveryRetryActivation,
              semanticsIdentifier: 'handle-recovery-retry-activation',
              onPressed: isBusy ? null : widget.onRetryActivation,
            ),
          ] else ...<Widget>[
            const SizedBox(height: 16),
            AppPrimaryButton(
              label: context.l10n.commonDone,
              onPressed: widget.onDismiss,
            ),
          ],
        ],
      ),
    );
  }
}

class _RiskLine extends StatelessWidget {
  const _RiskLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('• ', style: TextStyle(color: context.awikiTheme.danger)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: context.awikiTheme.title, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryStatus extends StatelessWidget {
  const _RecoveryStatus({required this.progress});

  final HandleRecoveryProgress progress;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = switch (progress.phase) {
      HandleRecoveryPhase.cooling => (
        context.l10n.handleRecoveryCoolingTitle,
        context.l10n.handleRecoveryCoolingUntil(
          _displayTime(progress.coolingUntil),
        ),
      ),
      HandleRecoveryPhase.ready => (
        context.l10n.handleRecoveryReadyTitle,
        context.l10n.handleRecoveryReadyDetail,
      ),
      HandleRecoveryPhase.cancelled => (
        context.l10n.handleRecoveryCancelledTitle,
        context.l10n.handleRecoveryCancelledDetail,
      ),
      HandleRecoveryPhase.expired => (
        context.l10n.handleRecoveryExpiredTitle,
        context.l10n.handleRecoveryExpiredDetail,
      ),
      HandleRecoveryPhase.consumed =>
        progress.localActivationPending
            ? (
                context.l10n.handleRecoveryActivationPendingTitle,
                context.l10n.handleRecoveryActivationPendingDetail,
              )
            : (
                context.l10n.handleRecoveryCompletedTitle,
                context.l10n.handleRecoveryCompletedDetail,
              ),
    };
    return AppSurface(
      color: progress.phase == HandleRecoveryPhase.ready
          ? context.awikiTheme.warningContainer
          : context.awikiTheme.subtleSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            key: const Key('handle-recovery-phase'),
            style: TextStyle(
              color: context.awikiTheme.title,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            style: TextStyle(
              color: context.awikiTheme.secondaryText,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

String handleRecoveryErrorLabel(
  BuildContext context,
  HandleRecoveryErrorKind error,
) {
  return switch (error) {
    HandleRecoveryErrorKind.unavailable =>
      context.l10n.handleRecoveryUnavailable,
    HandleRecoveryErrorKind.expired => context.l10n.handleRecoveryExpiredDetail,
    HandleRecoveryErrorKind.notReady => context.l10n.handleRecoveryNotReady,
    HandleRecoveryErrorKind.conflict => context.l10n.handleRecoveryConflict,
    HandleRecoveryErrorKind.network => context.l10n.networkUnavailableRetry,
    HandleRecoveryErrorKind.activation =>
      context.l10n.handleRecoveryActivationFailed,
    HandleRecoveryErrorKind.rejected =>
      context.l10n.handleRecoveryUserPresenceRejected,
    HandleRecoveryErrorKind.failed => context.l10n.operationFailedRetry,
  };
}

String _displayTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
