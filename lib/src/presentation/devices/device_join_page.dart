// [INPUT]: New-device Join projection, user form input, widget lifecycle, and authorized-device summary.
// [OUTPUT]: Lifecycle-safe OTP cooldown/SAS polling plus exact-DID member session activation.
// [POS]: New-device pairing surface; it never persists OTP, SAS, or root material.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../application/ports/device_management_core_port.dart';
import '../../domain/entities/device_management.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/sms_otp_cooldown_provider.dart';
import '../shared/widgets/app_widgets.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import 'device_labels.dart';
import 'devices_provider.dart';
import '../recovery/handle_recovery_provider.dart';

class DeviceJoinPage extends ConsumerStatefulWidget {
  const DeviceJoinPage({super.key, this.autoPoll = true});

  final bool autoPoll;

  @override
  ConsumerState<DeviceJoinPage> createState() => _DeviceJoinPageState();
}

class _DeviceJoinPageState extends ConsumerState<DeviceJoinPage> {
  final _handleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  Timer? _pollTimer;
  bool _otpSendFailed = false;
  bool _otpRateLimited = false;
  bool _activationPending = false;
  bool _activationFailed = false;
  String? _activatedJoinSessionId;
  DeviceJoinProgress? _recoveryActivationProgress;

  @override
  void initState() {
    super.initState();
    _handleController.addListener(_handleOtpTargetChanged);
    _phoneController.addListener(_handleOtpTargetChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(devicesProvider.notifier).loadNewDevice();
      if (!mounted) return;
      await _activateAuthorizedMember();
    });
    if (widget.autoPoll) {
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_pollAndActivate());
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _handleController.removeListener(_handleOtpTargetChanged);
    _phoneController.removeListener(_handleOtpTargetChanged);
    _handleController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesProvider);
    final otpCooldown = ref.watch(smsOtpCooldownProvider);
    final progress = state.activeJoin;
    final theme = context.awikiTheme;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        maxWidth: 620,
        includeBottomSafeArea: true,
        child: ListView(
          key: const Key('device-join-page'),
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
          children: <Widget>[
            AwikiMeTopBar(
              title: context.l10n.deviceJoinTitle,
              padding: EdgeInsets.zero,
              leading: TopBarActionButton(
                onTap: () => Navigator.of(context).maybePop(),
                semanticsLabel: context.l10n.commonBack,
                tooltip: context.l10n.commonBack,
                child: const AwikiAssetIcon(
                  assetName: 'assets/icons/icon_left.svg',
                  color: AwikiMeColors.primaryDark,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (state.error != null) ...<Widget>[
              _DeviceJoinNotice(
                key: const Key('device-join-error'),
                message: deviceManagementErrorLabel(context.l10n, state.error!),
                danger: true,
              ),
              const SizedBox(height: 12),
            ],
            if (_otpRateLimited && otpCooldown.isCoolingDown) ...<Widget>[
              _DeviceJoinNotice(
                message: context.l10n.deviceJoinOtpRateLimited(
                  otpCooldown.remainingSeconds,
                ),
                danger: true,
              ),
              const SizedBox(height: 12),
            ] else if (_otpSendFailed) ...<Widget>[
              _DeviceJoinNotice(
                message: context.l10n.deviceJoinErrorFailed,
                danger: true,
              ),
              const SizedBox(height: 12),
            ],
            if (progress == null)
              _buildStartForm(context, state, otpCooldown)
            else
              _buildProgress(context, state, progress),
          ],
        ),
      ),
    );
  }

  Widget _buildStartForm(
    BuildContext context,
    DevicesState state,
    SmsOtpCooldownState otpCooldown,
  ) {
    final responsive = context.awikiResponsive;
    return AppCardSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            context.l10n.deviceJoinEntrySubtitle,
            style: TextStyle(color: context.awikiTheme.secondaryText),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _phoneController,
            label: context.l10n.deviceJoinPhone,
            placeholder: '+8613800138000',
            keyboardType: TextInputType.phone,
            semanticsIdentifier: 'multi-device-join-phone',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _handleController,
            label: context.l10n.deviceJoinHandle,
            placeholder: 'alice',
            semanticsIdentifier: 'multi-device-join-handle',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _otpController,
            label: context.l10n.deviceJoinOtp,
            placeholder: '123456',
            keyboardType: TextInputType.number,
            semanticsIdentifier: 'multi-device-join-otp',
            suffix: AppInlineActionButton(
              label: otpCooldown.isCoolingDown
                  ? context.l10n.deviceJoinResendOtpIn(
                      otpCooldown.remainingSeconds,
                    )
                  : context.l10n.deviceJoinSendOtp,
              semanticsIdentifier: 'multi-device-send-otp',
              isLoading: otpCooldown.isSending,
              onPressed: state.isActionPending || !otpCooldown.canSend
                  ? null
                  : _sendOtp,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: responsive.isPhone
                  ? double.infinity
                  : responsive.displayScaled(148),
              child: AppPrimaryButton(
                label: context.l10n.deviceJoinStart,
                semanticsIdentifier: 'multi-device-start-join',
                onPressed: state.isActionPending ? null : _begin,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(
    BuildContext context,
    DevicesState state,
    DeviceJoinProgress progress,
  ) {
    final sas = progress.sas;
    return AppCardSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            deviceJoinPhaseLabel(context.l10n, progress),
            key: const Key('device-join-phase'),
            style: TextStyle(
              color: context.awikiTheme.title,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            progress.protocolDeviceId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: context.awikiTheme.secondaryText),
          ),
          if (progress.cause == DeviceJoinCause.handleRecovery) ...<Widget>[
            const SizedBox(height: 16),
            _HandleRecoveryJoinNotice(progress: progress),
          ],
          if (sas != null) ...<Widget>[
            const SizedBox(height: 24),
            Text(
              sas,
              key: const Key('device-join-sas'),
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
          if (!progress.isTerminal) ...<Widget>[
            AppSecondaryButton(
              label: context.l10n.deviceJoinRefresh,
              semanticsIdentifier: 'multi-device-refresh-join',
              onPressed: state.isActionPending ? null : _pollNow,
            ),
            const SizedBox(height: 10),
            AppDangerButton(
              label: context.l10n.deviceJoinCancel,
              onPressed: state.isActionPending
                  ? null
                  : () => ref
                        .read(devicesProvider.notifier)
                        .cancelNewDeviceActive(),
            ),
          ] else if (progress.phase != DeviceJoinPhase.authorized)
            AppPrimaryButton(
              label: context.l10n.deviceJoinStart,
              onPressed: () => ref.read(devicesProvider.notifier).clearActive(),
            )
          else if (_activationFailed)
            AppPrimaryButton(
              label: context.l10n.deviceJoinActivationRetry,
              onPressed: _activationPending ? null : _activateAuthorizedMember,
            )
          else if (progress.cause == DeviceJoinCause.handleRecovery &&
              _recoveryActivationProgress?.phase != DeviceJoinPhase.authorized)
            AppSecondaryButton(
              key: const Key('handle-recovery-join-resume'),
              label: context.l10n.handleRecoveryResume,
              semanticsIdentifier: 'handle-recovery-join-resume',
              onPressed: _activationPending
                  ? null
                  : () => _resumeRecoveryJoin(progress),
            )
          else
            AppPrimaryButton(
              label: _activationPending
                  ? context.l10n.deviceJoinActivating
                  : context.l10n.commonDone,
              onPressed: _activationPending
                  ? null
                  : () => Navigator.of(context).maybePop(),
            ),
        ],
      ),
    );
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    final handle = _handleController.text.trim();
    if (handle.isEmpty || phone.isEmpty) return;
    final cooldown = ref.read(smsOtpCooldownProvider.notifier);
    if (!await cooldown.beginSend()) return;
    setState(() {
      _otpSendFailed = false;
      _otpRateLimited = false;
    });
    try {
      final receipt = await ref
          .read(deviceManagementServiceProvider)
          .sendJoinSmsOtp(handle: handle, phone: phone);
      await cooldown.completeAcceptedAfter(receipt.retryAfterSeconds);
      if (mounted) AwikiMeToast.show(context, context.l10n.otpSent);
    } on DeviceJoinSmsOtpRateLimited catch (error) {
      await cooldown.completeRateLimitedAfter(error.retryAfterSeconds);
      if (mounted) setState(() => _otpRateLimited = true);
    } catch (_) {
      cooldown.completeFailed();
      if (mounted) setState(() => _otpSendFailed = true);
    } finally {
      cooldown.completeFailed();
    }
  }

  void _handleOtpTargetChanged() {
    if (!mounted) return;
    setState(() {
      _otpSendFailed = false;
      _otpRateLimited = false;
    });
  }

  Future<void> _begin() async {
    final otp = _otpController.text;
    _otpController.clear();
    await ref
        .read(devicesProvider.notifier)
        .beginNewDeviceJoin(
          handle: _handleController.text,
          phone: _phoneController.text,
          otp: otp,
          presenceReason: context.l10n.handleRecoveryPresenceReason,
        );
    if (!mounted) return;
    await _activateAuthorizedMember();
  }

  Future<void> _pollNow() => _pollAndActivate();

  Future<void> _pollAndActivate() async {
    if (!mounted) return;
    await ref.read(devicesProvider.notifier).pollNewDeviceActive();
    if (!mounted) return;
    await _activateAuthorizedMember();
  }

  Future<void> _activateAuthorizedMember() async {
    if (!mounted) return;
    var progress = ref.read(devicesProvider).activeJoin;
    if (progress == null ||
        progress.side != DeviceJoinSide.newDevice ||
        progress.phase != DeviceJoinPhase.authorized ||
        _activationPending ||
        _activatedJoinSessionId == progress.joinSessionId) {
      return;
    }
    if (mounted) {
      setState(() {
        _activationPending = true;
        _activationFailed = false;
      });
    }
    try {
      if (progress.authorizedDevice == null) {
        await ref.read(devicesProvider.notifier).pollNewDeviceActive();
        if (!mounted) return;
        progress = ref.read(devicesProvider).activeJoin;
      }
      final authorized = progress?.authorizedDevice;
      if (progress == null ||
          progress.side != DeviceJoinSide.newDevice ||
          progress.phase != DeviceJoinPhase.authorized ||
          authorized == null ||
          authorized.protocolDeviceId != progress.protocolDeviceId ||
          authorized.status != DeviceStatus.active ||
          authorized.role != DeviceRole.member ||
          authorized.managementReady ||
          !authorized.isCurrent) {
        throw StateError('invalid_authorized_device_projection');
      }
      if (progress.cause == DeviceJoinCause.handleRecovery) {
        final recoveryProgress = await ref
            .read(handleRecoveryServiceProvider)
            .resumeAuthorizedJoinActivation(
              joinSessionId: progress.joinSessionId,
              recoveryExpected: true,
            );
        if (mounted) {
          setState(() => _recoveryActivationProgress = recoveryProgress);
        }
      } else {
        await ref
            .read(appRuntimeProvider.notifier)
            .activateJoinedMember(progress.did);
      }
      _activatedJoinSessionId = progress.joinSessionId;
    } catch (_) {
      if (mounted) {
        setState(() => _activationFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _activationPending = false);
      }
    }
  }

  Future<void> _resumeRecoveryJoin(DeviceJoinProgress progress) async {
    if (_activationPending) return;
    setState(() {
      _activationPending = true;
      _activationFailed = false;
    });
    try {
      final recoveryProgress = await ref
          .read(handleRecoveryServiceProvider)
          .resumeAuthorizedJoinActivation(
            joinSessionId: progress.joinSessionId,
            recoveryExpected: true,
          );
      if (mounted) {
        setState(() => _recoveryActivationProgress = recoveryProgress);
      }
    } catch (_) {
      if (mounted) setState(() => _activationFailed = true);
    } finally {
      if (mounted) setState(() => _activationPending = false);
    }
  }
}

class _HandleRecoveryJoinNotice extends StatelessWidget {
  const _HandleRecoveryJoinNotice({required this.progress});

  final DeviceJoinProgress progress;

  @override
  Widget build(BuildContext context) {
    final recovery = progress.handleRecovery!;
    return AppSurface(
      key: const Key('handle-recovery-join-banner'),
      color: context.awikiTheme.warningContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(context.l10n.handleRecoveryJoinRestored(recovery.handle)),
          if (recovery.localOrdinaryDataWillMigrate)
            Text(context.l10n.handleRecoveryJoinLocalMigration),
          Text(context.l10n.handleRecoveryJoinE2eeUnsupported),
          Text(context.l10n.handleRecoveryJoinDidOnlyUnsupported),
        ],
      ),
    );
  }
}

class _DeviceJoinNotice extends StatelessWidget {
  const _DeviceJoinNotice({
    super.key,
    required this.message,
    this.danger = false,
  });

  final String message;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      color: danger
          ? context.awikiTheme.dangerContainer
          : context.awikiTheme.warningContainer,
      child: Text(
        message,
        style: TextStyle(
          color: danger ? context.awikiTheme.danger : context.awikiTheme.title,
        ),
      ),
    );
  }
}

Future<void> openDeviceJoinPage(BuildContext context) {
  return AppNavigator.push<void>(context, (_) => const DeviceJoinPage());
}
