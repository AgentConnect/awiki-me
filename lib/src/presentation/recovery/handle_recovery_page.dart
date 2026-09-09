// [INPUT]: Verified onboarding Handle/phone, a dedicated Recovery OTP, and UI intent.
// [OUTPUT]: Risk-gated Recovery presentation that quiesces the old session and
// opens Messages only after replacement-session activation.
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
import 'handle_recovery_session.dart';

class HandleRecoveryPage extends StatelessWidget {
  const HandleRecoveryPage({
    super.key,
    required this.initialHandle,
    required this.initialPhone,
    this.autoRequestOtp = true,
    this.startNew = false,
    this.localIdentityId,
    this.allowPhoneInput = false,
  });

  final String initialHandle;
  final String initialPhone;
  final bool autoRequestOtp;
  final bool startNew;
  final String? localIdentityId;
  final bool allowPhoneInput;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    return ProviderScope(
      key: ValueKey((initialHandle, localIdentityId)),
      overrides: [
        handleRecoveryProvider.overrideWith(
          (ref) => HandleRecoveryController(
            ref.watch(handleRecoveryServiceProvider),
            ref.watch(handleRecoverySmsOtpCooldownProvider.notifier),
            session: ref.watch(handleRecoverySessionProvider),
            isPageCurrent: () => route?.isCurrent ?? true,
          ),
        ),
      ],
      child: _HandleRecoveryView(
        initialHandle: initialHandle,
        initialPhone: initialPhone,
        autoRequestOtp: autoRequestOtp,
        startNew: startNew,
        localIdentityId: localIdentityId,
        allowPhoneInput: allowPhoneInput,
      ),
    );
  }
}

class _HandleRecoveryView extends ConsumerStatefulWidget {
  const _HandleRecoveryView({
    required this.initialHandle,
    required this.initialPhone,
    this.autoRequestOtp = true,
    this.startNew = false,
    this.localIdentityId,
    this.allowPhoneInput = false,
  });

  final String initialHandle;
  final String initialPhone;
  final bool autoRequestOtp;
  final bool startNew;
  final String? localIdentityId;
  final bool allowPhoneInput;

  @override
  ConsumerState<_HandleRecoveryView> createState() =>
      _HandleRecoveryViewState();
}

class _HandleRecoveryViewState extends ConsumerState<_HandleRecoveryView> {
  final _otpController = TextEditingController();
  late final TextEditingController _phoneController;
  bool _isActivatingRecoveredIdentity = false;
  bool _sessionActivationFailed = false;
  bool _phoneInputRequired = false;
  bool? _wasRouteCurrent;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhone);
    _phoneController.addListener(_handlePhoneInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref
          .read(handleRecoveryProvider.notifier)
          .initialize(
            handle: widget.initialHandle,
            localIdentityId: widget.localIdentityId,
            startNew: widget.startNew,
          );
      if (!mounted) return;
      if (widget.autoRequestOtp &&
          ref.read(handleRecoveryProvider).canRequestOtp) {
        await _requestOtp();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (_wasRouteCurrent != null && current != _wasRouteCurrent) {
      ref.read(handleRecoveryProvider.notifier).invalidate();
      if (current) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref
              .read(handleRecoveryProvider.notifier)
              .initialize(
                handle: widget.initialHandle,
                localIdentityId: widget.localIdentityId,
              );
        });
      }
    }
    _wasRouteCurrent = current;
  }

  @override
  void dispose() {
    _otpController.dispose();
    _phoneController.removeListener(_handlePhoneInputChanged);
    _phoneController.dispose();
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
              if (state.isBusy || _isActivatingRecoveredIdentity) ...<Widget>[
                Row(
                  children: <Widget>[
                    const CupertinoActivityIndicator(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isActivatingRecoveredIdentity
                            ? context.l10n.handleRecoveryEntering
                            : state.authoritative
                            ? context.l10n.handleRecoveryRunning
                            : context.l10n.handleRecoveryChecking,
                        key: const Key('handle-recovery-busy'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
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
                    if (state.canRequestOtp ||
                        state.allows(HandleRecoveryAction.prepare)) ...<Widget>[
                      const SizedBox(height: 12),
                      if (widget.allowPhoneInput)
                        AppTextField(
                          key: const Key('handle-recovery-phone-input'),
                          controller: _phoneController,
                          label: context.l10n.handleRecoveryPhone,
                          placeholder: context.l10n.onboardingPhonePlaceholder,
                          keyboardType: TextInputType.phone,
                          enabled: !state.isBusy && state.otpPhone == null,
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
                    ],
                    if (state.allows(
                      HandleRecoveryAction.discardPreAttempt,
                    )) ...<Widget>[
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
                if (state.allows(HandleRecoveryAction.activate) &&
                    !state.isBusy)
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
                      if (state.allows(HandleRecoveryAction.activateIdentity))
                        AppPrimaryButton(
                          key: const Key('handle-recovery-enter-messages'),
                          label: context.l10n.handleRecoveryEnterMessages,
                          semanticsIdentifier: 'handle-recovery-enter-messages',
                          onPressed:
                              state.isBusy || _isActivatingRecoveredIdentity
                              ? null
                              : _activateRecoveredIdentityIfCompleted,
                        )
                      else if (state.allows(HandleRecoveryAction.activate))
                        AppPrimaryButton(
                          key: const Key('handle-recovery-activate'),
                          label: context.l10n.handleRecoveryActivate,
                          semanticsIdentifier: 'handle-recovery-activate',
                          onPressed:
                              state.isBusy ||
                                  !state.riskConfirmed ||
                                  !state.allows(HandleRecoveryAction.activate)
                              ? null
                              : _activate,
                        ),
                      if (_sessionActivationFailed) ...<Widget>[
                        const SizedBox(height: 10),
                        Text(
                          context.l10n.handleRecoverySessionActivationFailed,
                          key: const Key(
                            'handle-recovery-session-activation-failed',
                          ),
                          style: TextStyle(color: context.awikiTheme.danger),
                        ),
                      ],
                      if (state.allows(
                        HandleRecoveryAction.resume,
                      )) ...<Widget>[
                        const SizedBox(height: 10),
                        AppSecondaryButton(
                          key: const Key('handle-recovery-resume'),
                          label: context.l10n.handleRecoveryResume,
                          semanticsIdentifier: 'handle-recovery-resume',
                          onPressed: state.isBusy ? null : _resume,
                        ),
                      ],
                      if (state.allows(
                        HandleRecoveryAction.quarantineKeyUnavailable,
                      )) ...<Widget>[
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
                      if (state.allows(HandleRecoveryAction.startNew) &&
                          !state.allows(
                            HandleRecoveryAction.activateIdentity,
                          )) ...<Widget>[
                        const SizedBox(height: 10),
                        if (progress.lifecycleClass ==
                            HandleRecoveryLifecycleClass
                                .quarantinedKeyUnavailable)
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
              if (!state.authoritative && !state.isBusy)
                AppSecondaryButton(
                  key: const Key('handle-recovery-retry-lookup'),
                  label: context.l10n.commonRetry,
                  onPressed: () => ref
                      .read(handleRecoveryProvider.notifier)
                      .initialize(
                        handle: widget.initialHandle,
                        localIdentityId: widget.localIdentityId,
                      ),
                ),
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
        .read(handleRecoveryProvider.notifier)
        .requestOtp(
          handle: widget.initialHandle,
          phone: phone,
          localIdentityId: widget.localIdentityId,
        );
  }

  Future<void> _prepare() async {
    final otp = _otpController.text;
    _otpController.clear();
    await ref
        .read(handleRecoveryProvider.notifier)
        .prepare(phone: _phoneController.text, otp: otp);
  }

  Future<void> _activate() async {
    final controller = ref.read(handleRecoveryProvider.notifier);
    final activation = controller.activate(
      presenceReason: context.l10n.handleRecoveryPresenceReason,
    );
    final epoch = controller.epoch;
    await activation;
    if (!mounted || !controller.isCurrent(epoch)) return;
    await _activateRecoveredIdentityIfCompleted();
  }

  Future<void> _resume() async {
    final controller = ref.read(handleRecoveryProvider.notifier);
    final resuming = controller.resume();
    final epoch = controller.epoch;
    await resuming;
    if (!mounted || !controller.isCurrent(epoch)) return;
    await _activateRecoveredIdentityIfCompleted();
  }

  Future<void> _activateRecoveredIdentityIfCompleted() async {
    if (!mounted || _isActivatingRecoveredIdentity) return;
    final progress = ref.read(handleRecoveryProvider).progress;
    if (progress == null ||
        progress.handle != widget.initialHandle ||
        !ref
            .read(handleRecoveryProvider)
            .allows(HandleRecoveryAction.activateIdentity)) {
      return;
    }
    if (shouldStopHandleRecoveryBeforeProductReset(
      e2eEnabled: awikiE2eEnabled,
      crashCutEnabled: const bool.fromEnvironment(
        'AWIKI_E2E_HANDLE_RECOVERY_CRASH_BEFORE_PRODUCT_RESET',
      ),
    )) {
      return;
    }
    final controller = ref.read(handleRecoveryProvider.notifier);
    final epoch = controller.epoch;
    bool isCurrent() => mounted && controller.isCurrent(epoch);
    setState(() {
      _isActivatingRecoveredIdentity = true;
      _sessionActivationFailed = false;
    });
    try {
      final activated = await ref
          .read(appRuntimeProvider.notifier)
          .loginWithLocalCredentialAndConfirm(
            progress.ownerIdentityId,
            isCurrent: isCurrent,
          );
      if (!mounted || !isCurrent()) return;
      if (!activated) {
        setState(() => _sessionActivationFailed = true);
        return;
      }
      ref
          .read(shellDestinationProvider.notifier)
          .select(ShellDestination.messages);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } finally {
      if (isCurrent()) {
        setState(() => _isActivatingRecoveredIdentity = false);
      }
    }
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
          Text(
            progress.impact.localOrdinaryDataWillMigrate
                ? context.l10n.handleRecoveryLocalOrdinaryMigration
                : context.l10n.handleRecoveryFreshDataNotice,
          ),
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
                onChanged:
                    state.isBusy || !state.allows(HandleRecoveryAction.activate)
                    ? null
                    : onChanged,
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
  HandleRecoveryUiError.activationRequired =>
    context.l10n.handleRecoveryRiskRequired,
  HandleRecoveryUiError.recoveryInProgress ||
  HandleRecoveryUiError.actionNotAllowed =>
    context.l10n.handleRecoveryErrorBlocked,
  HandleRecoveryUiError.stateChanged =>
    context.l10n.handleRecoveryErrorRemoteStateChanged,
  HandleRecoveryUiError.unknownEpoch =>
    context.l10n.handleRecoveryErrorLocalStateUnavailable,
  HandleRecoveryUiError.factorRetryRequired =>
    context.l10n.handleRecoveryFactorRequired,
  HandleRecoveryUiError.localTransitionSuperseded =>
    context.l10n.handleRecoveryLocalSuperseded,
  HandleRecoveryUiError.localTransitionPending =>
    context.l10n.handleRecoveryAwaitingLocal,
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
    context.l10n.handleRecoveryAwaitingResult,
  HandleRecoveryProgressPhase.remoteCommitted =>
    context.l10n.handleRecoveryRemoteCommitted,
  HandleRecoveryProgressPhase.identityTransitionPending ||
  HandleRecoveryProgressPhase.identitySwitched =>
    context.l10n.handleRecoveryAwaitingLocal,
  HandleRecoveryProgressPhase.completed => context.l10n.handleRecoveryCompleted,
  HandleRecoveryProgressPhase.blocked => context.l10n.handleRecoveryBlocked,
};
