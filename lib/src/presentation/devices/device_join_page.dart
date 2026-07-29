// [INPUT]: New-device Join projection, user form input, widget lifecycle, and authorized-device summary.
// [OUTPUT]: Lifecycle-safe OTP/SAS polling plus exact-DID member session activation.
// [POS]: New-device pairing surface; it never persists OTP, SAS, or root material.

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../domain/entities/device_management.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import 'device_labels.dart';
import 'devices_provider.dart';

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
  bool _sendingOtp = false;
  bool _otpSendFailed = false;
  bool _activationPending = false;
  bool _activationFailed = false;
  String? _activatedJoinSessionId;

  @override
  void initState() {
    super.initState();
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
            if (_otpSendFailed) ...<Widget>[
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
            controller: _handleController,
            label: context.l10n.deviceJoinHandle,
            placeholder: 'alice',
            semanticsIdentifier: 'multi-device-join-handle',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _phoneController,
            label: context.l10n.deviceJoinPhone,
            placeholder: '+8613800138000',
            keyboardType: TextInputType.phone,
            semanticsIdentifier: 'multi-device-join-phone',
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _otpController,
            label: context.l10n.deviceJoinOtp,
            placeholder: '123456',
            keyboardType: TextInputType.number,
            semanticsIdentifier: 'multi-device-join-otp',
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: AppSecondaryButton(
                  label: context.l10n.deviceJoinSendOtp,
                  semanticsIdentifier: 'multi-device-send-otp',
                  onPressed: state.isActionPending || _sendingOtp
                      ? null
                      : _sendOtp,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppPrimaryButton(
                  label: context.l10n.deviceJoinStart,
                  semanticsIdentifier: 'multi-device-start-join',
                  onPressed: state.isActionPending ? null : _begin,
                ),
              ),
            ],
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
    if (phone.isEmpty || handle.isEmpty) return;
    setState(() {
      _sendingOtp = true;
      _otpSendFailed = false;
    });
    try {
      await ref
          .read(deviceManagementServiceProvider)
          .sendJoinSmsOtp(handle: handle, phone: phone);
    } catch (_) {
      if (mounted) setState(() => _otpSendFailed = true);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
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
      await ref
          .read(appRuntimeProvider.notifier)
          .activateJoinedMember(progress.did);
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
