// [INPUT]: Verified onboarding Handle/phone, a dedicated Recovery OTP, and UI intent.
// [OUTPUT]: Risk-gated Recovery presentation that quiesces the old session and
// opens Messages only after replacement-session activation.
// [POS]: App-only V4.0 surface; Core owns credentials, keys, proof, and state transitions.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/handle_recovery.dart';
import '../../l10n/l10n.dart';
import '../../app/e2e_semantics.dart';
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
    this.localIdentityId,
    this.allowPhoneInput = false,
  });

  final String initialHandle;
  final String initialPhone;
  final bool autoRequestOtp;
  final String? localIdentityId;
  final bool allowPhoneInput;

  @override
  ConsumerState<HandleRecoveryPage> createState() => _HandleRecoveryPageState();
}

class _HandleRecoveryPageState extends ConsumerState<HandleRecoveryPage> {
  final _otpController = TextEditingController();
  late final TextEditingController _phoneController;
  bool _showDetails = false;
  bool _isSlow = false;
  Timer? _slowTimer;
  bool _phoneInputRequired = false;

  HandleRecoveryTarget get _target => (
    handle: widget.initialHandle.trim().toLowerCase(),
    localIdentityId: widget.localIdentityId,
  );

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone);
    _phoneController.addListener(_handlePhoneInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(handleRecoveryProvider(_target).notifier).open(_target);
      if (!mounted) return;
      final state = ref.read(handleRecoveryProvider(_target));
      if (widget.autoRequestOtp &&
          state.error == null &&
          state.canRequestOtp &&
          state.progress == null) {
        await _requestOtp();
      }
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _otpController.dispose();
    _phoneController.removeListener(_handlePhoneInputChanged);
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HandleRecoveryState>(handleRecoveryProvider(_target), (
      previous,
      next,
    ) {
      if (previous?.isBusy != next.isBusy) {
        _slowTimer?.cancel();
        if (next.isBusy) {
          _slowTimer = Timer(const Duration(seconds: 20), () {
            if (mounted) setState(() => _isSlow = true);
          });
        } else if (_isSlow) {
          setState(() => _isSlow = false);
        }
      }
      if (next.sessionActivated && previous?.sessionActivated != true) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _navigateIfActivated(),
        );
      }
    });
    final state = ref.watch(handleRecoveryProvider(_target));
    final otpCooldown = ref.watch(handleRecoverySmsOtpCooldownProvider);
    final progress = state.progress;
    final stage = state.viewStage;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(context.l10n.handleRecoveryTitle),
      ),
      child: SafeArea(
        child: AwikiAdaptiveScaffold(
          maxWidth: 620,
          includeBottomSafeArea: true,
          child: PopScope(
            canPop: !state.isBusy,
            child: ListView(
              key: const Key('handle-recovery-page'),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
              children: <Widget>[
                _RecoveryVerifiedValue(
                  key: const Key('handle-recovery-handle'),
                  label: context.l10n.handleRecoveryHandle,
                  value: widget.initialHandle,
                ),
                const SizedBox(height: 16),
                if (state.isBusy) ...<Widget>[
                  Row(
                    children: <Widget>[
                      const CupertinoActivityIndicator(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _busyLabel(context, state.action),
                          key: const Key('handle-recovery-busy'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                if (_isSlow && state.isBusy) ...<Widget>[
                  Text(
                    context.l10n.handleRecoverySlowOperation,
                    key: const Key('handle-recovery-slow'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (state.effectiveError != null && !state.isBusy) ...<Widget>[
                  Text(
                    _errorLabel(context, state.effectiveError!, otpCooldown),
                    key: const Key('handle-recovery-error'),
                    style: TextStyle(color: context.awikiTheme.danger),
                  ),
                  const SizedBox(height: 12),
                ],
                if (stage == HandleRecoveryViewStage.verification)
                  AppCardSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          context.l10n.handleRecoveryIntro,
                          style: TextStyle(
                            color: context.awikiTheme.secondaryText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.allowPhoneInput)
                          AppTextField(
                            key: const Key('handle-recovery-phone-input'),
                            controller: _phoneController,
                            label: context.l10n.handleRecoveryPhone,
                            placeholder:
                                context.l10n.onboardingPhonePlaceholder,
                            keyboardType: TextInputType.phone,
                            enabled: !state.isBusy && !state.otpRequested,
                            semanticsIdentifier: 'handle-recovery-phone-input',
                          )
                        else
                          _RecoveryVerifiedValue(
                            key: const Key('handle-recovery-phone'),
                            label: context.l10n.handleRecoveryPhone,
                            value: widget.initialPhone,
                          ),
                        if (_phoneInputRequired) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            context.l10n.onboardingIncompletePhoneContent,
                            key: const Key('handle-recovery-phone-required'),
                            style: TextStyle(color: context.awikiTheme.danger),
                          ),
                        ],
                        const SizedBox(height: 12),
                        AppTextField(
                          key: const Key('handle-recovery-otp'),
                          controller: _otpController,
                          label: context.l10n.handleRecoveryOtp,
                          placeholder: '123456',
                          keyboardType: TextInputType.number,
                          enabled: !state.isBusy && state.otpRequested,
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
                            label:
                                context.l10n.handleRecoveryCancelBeforeCommit,
                            onPressed: state.isBusy
                                ? null
                                : () => ref
                                      .read(
                                        handleRecoveryProvider(
                                          _target,
                                        ).notifier,
                                      )
                                      .discardPreAttempt(),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (stage == HandleRecoveryViewStage.confirmation &&
                    progress != null &&
                    !state.isBusy) ...<Widget>[
                  const SizedBox(height: 14),
                  _RecoveryRiskCard(
                    state: state,
                    progress: progress,
                    showDetails: _showDetails,
                    onToggleDetails: () =>
                        setState(() => _showDetails = !_showDetails),
                    onChanged: (value) => ref
                        .read(handleRecoveryProvider(_target).notifier)
                        .setRiskConfirmed(value),
                  ),
                ],
                if (progress != null &&
                    !state.isBusy &&
                    stage != HandleRecoveryViewStage.verification &&
                    stage != HandleRecoveryViewStage.reading) ...<Widget>[
                  const SizedBox(height: 14),
                  AppCardSection(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          _stageLabel(context, state),
                          key: const Key('handle-recovery-progress'),
                        ),
                        const SizedBox(height: 14),
                        if (stage == HandleRecoveryViewStage.completed &&
                            !state.isTerminal)
                          AppPrimaryButton(
                            key: const Key('handle-recovery-enter-messages'),
                            label: context.l10n.handleRecoveryEnterMessages,
                            semanticsIdentifier:
                                'handle-recovery-enter-messages',
                            onPressed: state.isBusy
                                ? null
                                : _activateRecoveredIdentityIfCompleted,
                          )
                        else if (stage == HandleRecoveryViewStage.confirmation)
                          AppPrimaryButton(
                            key: const Key('handle-recovery-activate'),
                            label: context.l10n.handleRecoveryActivate,
                            semanticsIdentifier: 'handle-recovery-activate',
                            onPressed:
                                state.isBusy ||
                                    !state.riskConfirmed ||
                                    !state.canActivate
                                ? null
                                : _activate,
                          ),
                        if (state.sessionActivationFailed) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.handleRecoverySessionActivationFailed,
                            key: const Key(
                              'handle-recovery-session-activation-failed',
                            ),
                            style: TextStyle(color: context.awikiTheme.danger),
                          ),
                        ],
                        if (state.canResume) ...<Widget>[
                          const SizedBox(height: 10),
                          AppPrimaryButton(
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
                                      .read(
                                        handleRecoveryProvider(
                                          _target,
                                        ).notifier,
                                      )
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
                                      .read(
                                        handleRecoveryProvider(
                                          _target,
                                        ).notifier,
                                      )
                                      .startAfterQuarantine(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (stage != HandleRecoveryViewStage.verification &&
                    !state.isBusy &&
                    (progress?.canDiscard ?? false))
                  AppSecondaryButton(
                    key: const Key('handle-recovery-cancel-otp'),
                    label: context.l10n.handleRecoveryCancelBeforeCommit,
                    onPressed: () => ref
                        .read(handleRecoveryProvider(_target).notifier)
                        .discardPreAttempt(),
                  ),
                if (stage == HandleRecoveryViewStage.blocked &&
                    progress?.lifecycleClass !=
                        HandleRecoveryLifecycleClass.quarantinedKeyUnavailable)
                  AppSecondaryButton(
                    key: const Key('handle-recovery-retry-lookup'),
                    label: context.l10n.commonRetry,
                    onPressed: state.isBusy
                        ? null
                        : () => ref
                              .read(handleRecoveryProvider(_target).notifier)
                              .open(_target),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handlePhoneInputChanged() {
    if (_phoneInputRequired && _phoneController.text.trim().isNotEmpty) {
      setState(() => _phoneInputRequired = false);
    }
  }

  Future<void> _requestOtp() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      if (mounted && !_phoneInputRequired) {
        setState(() => _phoneInputRequired = true);
      }
      return Future<void>.value();
    }
    return ref
        .read(handleRecoveryProvider(_target).notifier)
        .requestOtp(
          handle: widget.initialHandle,
          phone: phone,
          localIdentityId: widget.localIdentityId,
        );
  }

  Future<void> _prepare() async {
    final otp = _otpController.text;
    _otpController.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    await ref
        .read(handleRecoveryProvider(_target).notifier)
        .prepare(phone: _phoneController.text, otp: otp);
  }

  bool get _stopBeforeSession => shouldStopHandleRecoveryBeforeProductReset(
    e2eEnabled: awikiE2eEnabled,
    crashCutEnabled: const bool.fromEnvironment(
      'AWIKI_E2E_HANDLE_RECOVERY_CRASH_BEFORE_PRODUCT_RESET',
    ),
  );

  Future<void> _activate() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await ref
        .read(handleRecoveryProvider(_target).notifier)
        .activate(
          presenceReason: context.l10n.handleRecoveryPresenceReason,
          stopBeforeSession: _stopBeforeSession,
        );
    _navigateIfActivated();
  }

  Future<void> _resume() async {
    await ref
        .read(handleRecoveryProvider(_target).notifier)
        .resume(stopBeforeSession: _stopBeforeSession);
    _navigateIfActivated();
  }

  Future<void> _activateRecoveredIdentityIfCompleted() async {
    await ref.read(handleRecoveryProvider(_target).notifier).enterMessages();
    _navigateIfActivated();
  }

  void _navigateIfActivated() {
    if (!mounted ||
        !ref.read(handleRecoveryProvider(_target)).sessionActivated) {
      return;
    }
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
              fontWeight: FontWeight.w400,
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
    required this.showDetails,
    required this.onToggleDetails,
  });

  final HandleRecoveryState state;
  final HandleRecoveryProgress progress;
  final ValueChanged<bool> onChanged;
  final bool showDetails;
  final VoidCallback onToggleDetails;

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
          Text(
            progress.impact.localOrdinaryDataWillMigrate
                ? context.l10n.handleRecoveryLocalOrdinaryMigration
                : context.l10n.handleRecoveryFreshDataNotice,
          ),
          const SizedBox(height: 8),
          Text(context.l10n.handleRecoveryEncryptionNotice),
          CupertinoButton(
            onPressed: onToggleDetails,
            child: Text(context.l10n.handleRecoveryDetails),
          ),
          if (showDetails) ...<Widget>[
            Text(context.l10n.handleRecoveryOldE2eeUnavailable),
            const SizedBox(height: 8),
            Text(context.l10n.handleRecoverySingletonRisk),
            const SizedBox(height: 8),
            Text(context.l10n.handleRecoveryDidOnlyUnsupported),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(child: Text(context.l10n.handleRecoveryRiskConfirm)),
              CupertinoSwitch(
                key: const Key('handle-recovery-risk-confirmation'),
                value: state.riskConfirmed,
                onChanged: state.isBusy ? null : onChanged,
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
  HandleRecoveryUiError.factorRetryRequired =>
    context.l10n.handleRecoveryFactorExpired,
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

String _stageLabel(BuildContext context, HandleRecoveryState state) {
  if (state.viewStage == HandleRecoveryViewStage.blocked) {
    return context.l10n.handleRecoveryNeedsAttention;
  }
  if (state.progress?.isCompleted ?? false) {
    return context.l10n.handleRecoveryCompleted;
  }
  if (state.canActivate) return context.l10n.handleRecoveryPrepared;
  if (state.progress?.lifecycleClass ==
      HandleRecoveryLifecycleClass.remoteUnresolved) {
    return context.l10n.handleRecoveryAwaitingResult;
  }
  return context.l10n.handleRecoveryAwaitingLocal;
}

String _busyLabel(
  BuildContext context,
  HandleRecoveryBusyAction action,
) => switch (action) {
  HandleRecoveryBusyAction.reading => context.l10n.handleRecoveryChecking,
  HandleRecoveryBusyAction.sendingOtp => context.l10n.handleRecoverySendingOtp,
  HandleRecoveryBusyAction.verifying => context.l10n.handleRecoveryVerifying,
  HandleRecoveryBusyAction.authenticating =>
    context.l10n.handleRecoveryAuthenticating,
  HandleRecoveryBusyAction.recovering => context.l10n.handleRecoveryRunning,
  HandleRecoveryBusyAction.entering => context.l10n.handleRecoveryEntering,
  HandleRecoveryBusyAction.none => context.l10n.handleRecoveryChecking,
};
