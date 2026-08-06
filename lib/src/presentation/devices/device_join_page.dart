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
import '../shared/widgets/app_widgets.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import 'device_labels.dart';
import 'devices_provider.dart';
import '../recovery/handle_recovery_provider.dart';

final deviceJoinClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

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
  Timer? _otpCooldownTimer;
  final Map<String, DateTime> _otpRetryAtByTarget = <String, DateTime>{};
  final Set<String> _rateLimitedOtpTargets = <String>{};
  bool _sendingOtp = false;
  bool _normalizingPhoneInput = false;
  bool _otpSendFailed = false;
  bool _otpDailyLimitReached = false;
  bool _otpServiceUnavailable = false;
  bool _otpRateLimited = false;
  int _otpRetryAfterSeconds = 0;
  bool _activationPending = false;
  bool _activationFailed = false;
  String? _activatedJoinSessionId;
  DeviceJoinProgress? _recoveryActivationProgress;

  @override
  void initState() {
    super.initState();
    _handleController.addListener(_handleOtpTargetChanged);
    _phoneController.addListener(_handleOtpTargetChanged);
    _otpController.addListener(_handleJoinInputChanged);
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
    _otpCooldownTimer?.cancel();
    _handleController.removeListener(_handleOtpTargetChanged);
    _phoneController.removeListener(_handleOtpTargetChanged);
    _otpController.removeListener(_handleJoinInputChanged);
    _handleController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(devicesProvider);
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
            if (_otpRateLimited && _otpRetryAfterSeconds > 0) ...<Widget>[
              _DeviceJoinNotice(
                message: context.l10n.deviceJoinOtpRateLimited(
                  _otpRetryAfterSeconds,
                ),
                danger: true,
              ),
              const SizedBox(height: 12),
            ] else if (_otpDailyLimitReached) ...<Widget>[
              _DeviceJoinNotice(
                message: context.l10n.deviceJoinOtpDailyLimitReached,
                danger: true,
              ),
              const SizedBox(height: 12),
            ] else if (_otpServiceUnavailable) ...<Widget>[
              _DeviceJoinNotice(
                message: context.l10n.deviceJoinOtpUnavailable,
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
              _buildStartForm(context, state)
            else
              _buildProgress(context, state, progress),
          ],
        ),
      ),
    );
  }

  Widget _buildStartForm(BuildContext context, DevicesState state) {
    final responsive = context.awikiResponsive;
    final canSendOtp =
        _currentOtpTargetKey != null &&
        !state.isActionPending &&
        !_sendingOtp &&
        _otpRetryAfterSeconds == 0;
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
            placeholder: context.l10n.onboardingPhonePlaceholder,
            keyboardType: TextInputType.phone,
            showLabel: !responsive.isPhone,
            prefix: const AppPhoneCountryCodePrefix(),
            semanticsIdentifier: 'multi-device-join-phone',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _handleController,
            label: context.l10n.deviceJoinHandle,
            placeholder: context.l10n.onboardingHandlePlaceholder,
            showLabel: !responsive.isPhone,
            semanticsIdentifier: 'multi-device-join-handle',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _otpController,
            label: context.l10n.deviceJoinOtp,
            placeholder: context.l10n.onboardingOtpPlaceholder,
            keyboardType: TextInputType.number,
            showLabel: !responsive.isPhone,
            semanticsIdentifier: 'multi-device-join-otp',
            suffix: AppInlineActionButton(
              label: _otpRetryAfterSeconds > 0
                  ? context.l10n.deviceJoinResendOtpIn(_otpRetryAfterSeconds)
                  : context.l10n.deviceJoinSendOtp,
              semanticsIdentifier: 'multi-device-send-otp',
              isLoading: _sendingOtp,
              loadingLabel: context.l10n.deviceJoinSendingOtp,
              onPressed: canSendOtp ? _sendOtp : null,
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
    final phone = _normalizedPhone;
    final handle = _handleController.text.trim();
    final targetKey = _otpTargetKey(handle: handle, phone: phone);
    if (targetKey == null || _sendingOtp || _otpRetryAfterSeconds > 0) return;
    ref.read(devicesProvider.notifier).clearError();
    setState(() {
      _sendingOtp = true;
      _otpSendFailed = false;
      _otpDailyLimitReached = false;
      _otpServiceUnavailable = false;
    });
    try {
      final receipt = await ref
          .read(deviceManagementServiceProvider)
          .sendJoinSmsOtp(handle: handle, phone: phone);
      if (!mounted) return;
      _startOtpCooldown(
        targetKey: targetKey,
        seconds: receipt.retryAfterSeconds,
        rateLimited: false,
      );
      AwikiMeToast.show(context, context.l10n.otpSent);
    } on DeviceJoinSmsOtpRateLimited catch (error) {
      if (mounted) {
        _startOtpCooldown(
          targetKey: targetKey,
          seconds: error.retryAfterSeconds,
          rateLimited: true,
        );
      }
    } on DeviceJoinSmsOtpDailyLimitReached {
      if (mounted && _currentOtpTargetKey == targetKey) {
        setState(() => _otpDailyLimitReached = true);
      }
    } on DeviceJoinSmsOtpUnavailable {
      if (mounted && _currentOtpTargetKey == targetKey) {
        setState(() => _otpServiceUnavailable = true);
      }
    } catch (_) {
      if (mounted && _currentOtpTargetKey == targetKey) {
        setState(() => _otpSendFailed = true);
      }
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  String? _otpTargetKey({required String handle, required String phone}) {
    final normalizedHandle = handle.trim().toLowerCase();
    final normalizedPhone = _normalizePhone(phone);
    if (normalizedHandle.isEmpty || !_isValidChinaMobile(normalizedPhone)) {
      return null;
    }
    return '$normalizedHandle\u0000$normalizedPhone';
  }

  String get _normalizedPhone => _normalizePhone(_phoneController.text);

  String _normalizePhone(String phone) {
    final compact = phone.trim().replaceAll(RegExp(r'[\s-]+'), '');
    if (compact.isEmpty || compact.startsWith('+')) return compact;
    return '+86$compact';
  }

  bool _isValidChinaMobile(String phone) =>
      RegExp(r'^\+861\d{10}$').hasMatch(phone);

  String? get _currentOtpTargetKey => _otpTargetKey(
    handle: _handleController.text,
    phone: _phoneController.text,
  );

  void _handleOtpTargetChanged() {
    if (!mounted) return;
    _handleJoinInputChanged();
    if (!_normalizingPhoneInput) {
      final raw = _phoneController.text.trim();
      if (raw.startsWith('+86')) {
        _normalizingPhoneInput = true;
        final local = raw.substring(3).trimLeft();
        _phoneController.value = TextEditingValue(
          text: local,
          selection: TextSelection.collapsed(offset: local.length),
        );
        _normalizingPhoneInput = false;
      }
    }
    _syncOtpCooldownForCurrentTarget(clearFailure: true);
  }

  void _handleJoinInputChanged() {
    if (!mounted) return;
    ref.read(devicesProvider.notifier).clearError();
  }

  void _startOtpCooldown({
    required String targetKey,
    required int seconds,
    required bool rateLimited,
  }) {
    final boundedSeconds = seconds.clamp(1, 3600).toInt();
    final retryAt = ref
        .read(deviceJoinClockProvider)()
        .toUtc()
        .add(Duration(seconds: boundedSeconds));
    final previousRetryAt = _otpRetryAtByTarget[targetKey];
    if (previousRetryAt == null || retryAt.isAfter(previousRetryAt)) {
      _otpRetryAtByTarget[targetKey] = retryAt;
    }
    if (rateLimited) {
      _rateLimitedOtpTargets.add(targetKey);
    } else {
      _rateLimitedOtpTargets.remove(targetKey);
    }
    _syncOtpCooldownForCurrentTarget();
  }

  void _syncOtpCooldownForCurrentTarget({bool clearFailure = false}) {
    _otpCooldownTimer?.cancel();
    final targetKey = _currentOtpTargetKey;
    final retryAt = targetKey == null ? null : _otpRetryAtByTarget[targetKey];
    final remaining = _otpSecondsRemaining(retryAt);
    if (targetKey != null && remaining == 0) {
      _otpRetryAtByTarget.remove(targetKey);
      _rateLimitedOtpTargets.remove(targetKey);
    }
    setState(() {
      if (clearFailure) {
        _otpSendFailed = false;
        _otpDailyLimitReached = false;
        _otpServiceUnavailable = false;
      }
      _otpRateLimited =
          targetKey != null &&
          remaining > 0 &&
          _rateLimitedOtpTargets.contains(targetKey);
      _otpRetryAfterSeconds = remaining;
    });
    if (remaining == 0) return;
    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final currentTargetKey = _currentOtpTargetKey;
      final currentRetryAt = currentTargetKey == null
          ? null
          : _otpRetryAtByTarget[currentTargetKey];
      final next = _otpSecondsRemaining(currentRetryAt);
      if (next == 0) {
        timer.cancel();
        if (currentTargetKey != null) {
          _otpRetryAtByTarget.remove(currentTargetKey);
          _rateLimitedOtpTargets.remove(currentTargetKey);
        }
        setState(() {
          _otpRateLimited = false;
          _otpRetryAfterSeconds = 0;
        });
        return;
      }
      setState(() => _otpRetryAfterSeconds = next);
    });
  }

  int _otpSecondsRemaining(DateTime? retryAt) {
    if (retryAt == null) return 0;
    final milliseconds = retryAt
        .difference(ref.read(deviceJoinClockProvider)().toUtc())
        .inMilliseconds;
    if (milliseconds <= 0) return 0;
    return ((milliseconds + 999) ~/ 1000).clamp(1, 3600).toInt();
  }

  Future<void> _begin() async {
    final otp = _otpController.text;
    _otpController.clear();
    await ref
        .read(devicesProvider.notifier)
        .beginNewDeviceJoin(
          handle: _handleController.text,
          phone: _normalizedPhone,
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
