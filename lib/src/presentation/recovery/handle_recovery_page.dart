// [INPUT]: Verified onboarding Handle/phone, a dedicated Recovery OTP, and UI intent.
// [OUTPUT]: Risk-gated Recovery presentation that opens Messages after activation.
// [POS]: App-only V4.0 surface; Core owns credentials, keys, proof, and state transitions.

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/handle_recovery.dart';
import '../../l10n/l10n.dart';
import '../../app/e2e_semantics.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/sms_otp_cooldown_provider.dart';
import '../shared/widgets/app_widgets.dart';
import 'handle_recovery_provider.dart';

class HandleRecoveryPage extends ConsumerStatefulWidget {
  const HandleRecoveryPage({
    super.key,
    required this.initialHandle,
    required this.initialPhone,
    this.autoRequestOtp = true,
  });

  final String initialHandle;
  final String initialPhone;
  final bool autoRequestOtp;

  @override
  ConsumerState<HandleRecoveryPage> createState() => _HandleRecoveryPageState();
}

class _HandleRecoveryPageState extends ConsumerState<HandleRecoveryPage> {
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.autoRequestOtp) await _requestOtp();
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(handleRecoveryProvider);
    final otpCooldown = ref.watch(handleRecoverySmsOtpCooldownProvider);
    final progress = state.progress;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.handleRecoveryTitle),
      ),
      child: SafeArea(
        child: AwikiAdaptiveScaffold(
          maxWidth: 620,
          includeBottomSafeArea: true,
          child: ListView(
            key: const Key('handle-recovery-page'),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
            children: <Widget>[
              AppCardSection(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      context.l10n.handleRecoveryIntro,
                      style: TextStyle(color: context.awikiTheme.secondaryText),
                    ),
                    const SizedBox(height: 16),
                    _RecoveryVerifiedValue(
                      key: const Key('handle-recovery-handle'),
                      label: context.l10n.handleRecoveryHandle,
                      value: widget.initialHandle,
                    ),
                    const SizedBox(height: 12),
                    _RecoveryVerifiedValue(
                      key: const Key('handle-recovery-phone'),
                      label: context.l10n.handleRecoveryPhone,
                      value: widget.initialPhone,
                    ),
                    const SizedBox(height: 12),
                    AppTextField(
                      key: const Key('handle-recovery-otp'),
                      controller: _otpController,
                      label: context.l10n.handleRecoveryOtp,
                      placeholder: '123456',
                      keyboardType: TextInputType.number,
                      enabled: state.otpRequested,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppSecondaryButton(
                            key: const Key('handle-recovery-send-otp'),
                            label: otpCooldown.isCoolingDown
                                ? context.l10n.onboardingResendOtpIn(
                                    otpCooldown.remainingSeconds,
                                  )
                                : context.l10n.handleRecoverySendOtp,
                            semanticsIdentifier: 'handle-recovery-send-otp',
                            onPressed:
                                state.isBusy ||
                                    !state.canRequestOtp ||
                                    !otpCooldown.canSend
                                ? null
                                : _requestOtp,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppPrimaryButton(
                            key: const Key('handle-recovery-verify'),
                            label: context.l10n.handleRecoveryVerify,
                            semanticsIdentifier: 'handle-recovery-verify',
                            onPressed: state.isBusy || !state.otpRequested
                                ? null
                                : _prepare,
                          ),
                        ),
                      ],
                    ),
                    if (progress?.canDiscard ?? false) ...<Widget>[
                      const SizedBox(height: 10),
                      AppSecondaryButton(
                        key: const Key('handle-recovery-cancel-otp'),
                        label: context.l10n.commonCancel,
                        onPressed: state.isBusy
                            ? null
                            : () => ref
                                  .read(handleRecoveryProvider.notifier)
                                  .discardPreAttempt(),
                      ),
                    ],
                  ],
                ),
              ),
              if (progress != null &&
                  progress.phase !=
                      HandleRecoveryProgressPhase.otpRequested) ...<Widget>[
                const SizedBox(height: 14),
                _RecoveryRiskCard(
                  state: state,
                  progress: progress,
                  onChanged: (value) => ref
                      .read(handleRecoveryProvider.notifier)
                      .setRiskConfirmed(value),
                ),
                const SizedBox(height: 14),
                AppCardSection(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        _phaseLabel(context, progress.phase),
                        key: const Key('handle-recovery-progress'),
                      ),
                      if (progress.isStillConfirming) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          context.l10n.handleRecoveryStillConfirming,
                          key: const Key('handle-recovery-still-confirming'),
                        ),
                      ],
                      const SizedBox(height: 14),
                      AppPrimaryButton(
                        key: const Key('handle-recovery-activate'),
                        label: context.l10n.handleRecoveryActivate,
                        semanticsIdentifier: 'handle-recovery-activate',
                        onPressed:
                            state.isBusy ||
                                !state.riskConfirmed ||
                                !progress.canActivate
                            ? null
                            : _activate,
                      ),
                      if (progress.canResume) ...<Widget>[
                        const SizedBox(height: 10),
                        AppSecondaryButton(
                          key: const Key('handle-recovery-resume'),
                          label: context.l10n.handleRecoveryResume,
                          semanticsIdentifier: 'handle-recovery-resume',
                          onPressed: state.isBusy ? null : _resume,
                        ),
                      ],
                      if ((progress.keyState ==
                                  HandleRecoveryKeyState
                                      .permanentlyUnavailable ||
                              state.error ==
                                  HandleRecoveryUiError.keyUnavailable) &&
                          progress.lifecycleClass !=
                              HandleRecoveryLifecycleClass
                                  .quarantinedKeyUnavailable) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(context.l10n.handleRecoveryKeyUnavailable),
                        const SizedBox(height: 10),
                        AppSecondaryButton(
                          key: const Key(
                            'handle-recovery-quarantine-key-unavailable',
                          ),
                          label: context.l10n.handleRecoveryQuarantine,
                          onPressed: state.isBusy
                              ? null
                              : () => ref
                                    .read(handleRecoveryProvider.notifier)
                                    .quarantineKeyUnavailable(
                                      presenceReason: context
                                          .l10n
                                          .handleRecoveryQuarantineReason,
                                    ),
                        ),
                      ],
                      if (progress.lifecycleClass ==
                          HandleRecoveryLifecycleClass
                              .quarantinedKeyUnavailable) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(context.l10n.handleRecoveryQuarantined),
                        const SizedBox(height: 10),
                        AppSecondaryButton(
                          key: const Key(
                            'handle-recovery-start-after-quarantine',
                          ),
                          label: context.l10n.handleRecoveryStartNew,
                          onPressed: state.isBusy
                              ? null
                              : () => ref
                                    .read(handleRecoveryProvider.notifier)
                                    .startAfterQuarantine(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (state.error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _errorLabel(context, state.error!, otpCooldown),
                  style: TextStyle(color: context.awikiTheme.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestOtp() {
    return ref
        .read(handleRecoveryProvider.notifier)
        .requestOtp(handle: widget.initialHandle, phone: widget.initialPhone);
  }

  Future<void> _prepare() async {
    final otp = _otpController.text;
    _otpController.clear();
    await ref
        .read(handleRecoveryProvider.notifier)
        .prepare(phone: widget.initialPhone, otp: otp);
  }

  Future<void> _activate() async {
    await ref
        .read(handleRecoveryProvider.notifier)
        .activate(presenceReason: context.l10n.handleRecoveryPresenceReason);
    await _activateRecoveredIdentityIfCompleted();
  }

  Future<void> _resume() async {
    await ref.read(handleRecoveryProvider.notifier).resume();
    await _activateRecoveredIdentityIfCompleted();
  }

  Future<void> _activateRecoveredIdentityIfCompleted() async {
    final progress = ref.read(handleRecoveryProvider).progress;
    if (progress == null || !progress.isCompleted) return;
    if (shouldStopHandleRecoveryBeforeProductReset(
      e2eEnabled: awikiE2eEnabled,
      crashCutEnabled: const bool.fromEnvironment(
        'AWIKI_E2E_HANDLE_RECOVERY_CRASH_BEFORE_PRODUCT_RESET',
      ),
    )) {
      return;
    }
    await ref
        .read(appRuntimeProvider.notifier)
        .loginWithLocalCredential(progress.ownerIdentityId);
    if (!mounted) return;
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.messages);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

bool shouldStopHandleRecoveryBeforeProductReset({
  required bool e2eEnabled,
  required bool crashCutEnabled,
  bool releaseMode = kReleaseMode,
}) => !releaseMode && e2eEnabled && crashCutEnabled;

class _RecoveryVerifiedValue extends StatelessWidget {
  const _RecoveryVerifiedValue({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: value,
      readOnly: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: context.awikiTheme.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(value),
        ],
      ),
    );
  }
}

class _RecoveryRiskCard extends StatelessWidget {
  const _RecoveryRiskCard({
    required this.state,
    required this.progress,
    required this.onChanged,
  });

  final HandleRecoveryState state;
  final HandleRecoveryProgress progress;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCardSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(context.l10n.handleRecoveryIrreversible),
          const SizedBox(height: 8),
          Text(context.l10n.handleRecoveryHandlePreserved),
          const SizedBox(height: 8),
          Text(context.l10n.handleRecoveryOtherDevicesRejoin),
          const SizedBox(height: 8),
          Text(context.l10n.handleRecoveryLocalOrdinaryMigration),
          const SizedBox(height: 8),
          Text(context.l10n.handleRecoveryOldE2eeUnavailable),
          const SizedBox(height: 8),
          Text(context.l10n.handleRecoverySingletonRisk),
          const SizedBox(height: 8),
          Text(context.l10n.handleRecoveryDidOnlyUnsupported),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(child: Text(context.l10n.handleRecoveryRiskConfirm)),
              CupertinoSwitch(
                key: const Key('handle-recovery-risk-confirmation'),
                value: state.riskConfirmed,
                onChanged: onChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _errorLabel(
  BuildContext context,
  HandleRecoveryUiError error,
  SmsOtpCooldownState otpCooldown,
) => switch (error) {
  HandleRecoveryUiError.riskConfirmationRequired =>
    context.l10n.handleRecoveryRiskRequired,
  HandleRecoveryUiError.notPrepared =>
    context.l10n.handleRecoveryErrorNotPrepared,
  HandleRecoveryUiError.userPresenceRequired =>
    context.l10n.handleRecoveryErrorUserPresenceRequired,
  HandleRecoveryUiError.transitionMismatch =>
    context.l10n.handleRecoveryErrorTransitionMismatch,
  HandleRecoveryUiError.transitionChainUnsupported =>
    context.l10n.handleRecoveryErrorTransitionChainUnsupported,
  HandleRecoveryUiError.remoteStateChanged =>
    context.l10n.handleRecoveryErrorRemoteStateChanged,
  HandleRecoveryUiError.resultAbsent =>
    context.l10n.handleRecoveryStillConfirming,
  HandleRecoveryUiError.outcomeUnknown =>
    context.l10n.handleRecoveryErrorOutcomeUnknown,
  HandleRecoveryUiError.localStateUnavailable =>
    context.l10n.handleRecoveryErrorLocalStateUnavailable,
  HandleRecoveryUiError.keyUnavailable =>
    context.l10n.handleRecoveryKeyUnavailable,
  HandleRecoveryUiError.migrationUnsupported =>
    context.l10n.handleRecoveryMigrationUnsupported,
  HandleRecoveryUiError.blocked => context.l10n.handleRecoveryErrorBlocked,
  HandleRecoveryUiError.rateLimited =>
    otpCooldown.isCoolingDown
        ? context.l10n.deviceJoinOtpRateLimited(otpCooldown.remainingSeconds)
        : context.l10n.handleRecoveryFailed,
  HandleRecoveryUiError.failed => context.l10n.handleRecoveryFailed,
};

String _phaseLabel(
  BuildContext context,
  HandleRecoveryProgressPhase phase,
) => switch (phase) {
  HandleRecoveryProgressPhase.otpRequested =>
    context.l10n.handleRecoveryOtpRequested,
  HandleRecoveryProgressPhase.prepared => context.l10n.handleRecoveryPrepared,
  HandleRecoveryProgressPhase.remoteCommitPending =>
    context.l10n.handleRecoveryRemotePending,
  HandleRecoveryProgressPhase.remoteCommitted =>
    context.l10n.handleRecoveryRemoteCommitted,
  HandleRecoveryProgressPhase.identityTransitionPending =>
    context.l10n.handleRecoveryIdentityPending,
  HandleRecoveryProgressPhase.identitySwitched =>
    context.l10n.handleRecoveryIdentitySwitched,
  HandleRecoveryProgressPhase.completed => context.l10n.handleRecoveryCompleted,
  HandleRecoveryProgressPhase.blocked => context.l10n.handleRecoveryBlocked,
};
