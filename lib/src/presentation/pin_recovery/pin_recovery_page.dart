import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/pin_recovery_service.dart';
import '../../application/tenant/app_tenant.dart';
import '../../app/app_services.dart';
import '../server_features/backend_capabilities_provider.dart';
import '../../domain/entities/pin_recovery.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../shared/widgets/awiki_glass.dart';
import '../recovery/handle_recovery_page.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/widgets/app_widgets.dart';
import 'pin_recovery_provider.dart';

class PinRecoveryPage extends ConsumerStatefulWidget {
  const PinRecoveryPage({
    super.key,
    this.localIdentityId,
    this.expectedDid,
    this.expectedHandle,
    this.initialOperation,
    this.offerBackup = false,
  });
  final String? localIdentityId, expectedDid, expectedHandle;
  final PinRecoveryProgress? initialOperation;
  final bool offerBackup;
  bool get enabling => localIdentityId != null;
  @override
  ConsumerState<PinRecoveryPage> createState() => _PinRecoveryPageState();
}

class _PinRecoveryPageState extends ConsumerState<PinRecoveryPage> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  final _device = TextEditingController(text: 'AWiki Me');
  PinPhoneChallenge? _challenge;
  int _phoneGeneration = 0;
  String? _discovery;
  String? _selectedTargetId;
  late final StorageScopeId _scopeId;
  bool get _current =>
      mounted &&
      ref.read(activeAppTenantProvider).storageScopeId == _scopeId &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  List<PinRecoveryTarget>? _targets;
  PinRecoveryProgress? _progress;
  PinBackupStatus? _backupStatus;
  String? _error;
  bool _busy = false, _unsupported = false, _loading = true, _begun = false;
  DateTime? _resendAt;
  Timer? _resendTimer;
  late final PinRecoveryService _service;
  @override
  void initState() {
    super.initState();
    _service = ref.read(pinRecoveryServiceProvider)!;
    _scopeId = ref.read(activeAppTenantProvider).storageScopeId;
    _phone.addListener(_phoneChanged);
    _progress = widget.initialOperation;
    _begun = !widget.offerBackup || _progress != null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    await _run(() async {
      if (widget.enabling) {
        try {
          final status = await _service.backupStatus(widget.localIdentityId!);
          if (mounted) {
            setState(
              () => _backupStatus = status.did == widget.expectedDid
                  ? status
                  : PinBackupStatus(
                      did: widget.expectedDid ?? '',
                      state: PinBackupState.unknown,
                    ),
            );
          }
        } catch (_) {
          if (mounted) {
            setState(
              () => _backupStatus = PinBackupStatus(
                did: widget.expectedDid ?? '',
                state: PinBackupState.unknown,
              ),
            );
          }
        }
      }
      if (widget.enabling &&
          !await _service.canBackup(widget.localIdentityId!)) {
        if (mounted) setState(() => _unsupported = true);
        return;
      }
      if (_progress == null) {
        final pending = await _service.listPending();
        final relevant = pending.where(
          (p) => widget.enabling
              ? p.kind == PinRecoveryKind.enable &&
                    p.target.did == widget.expectedDid
              : p.kind == PinRecoveryKind.recover,
        );
        // Present all recover candidates through the entry widget; only restore
        // automatically when there is one unambiguous operation in this scope.
        if (relevant.length == 1 && mounted) {
          setState(() => _progress = relevant.single);
        }
      }
    });
    if (mounted) setState(() => _loading = false);
  }

  void _phoneChanged() {
    _phoneGeneration++;
    _resendTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _challenge = null;
      _discovery = null;
      _targets = null;
      _resendAt = null;
      _otp.clear();
    });
  }

  @override
  void dispose() {
    _phone.removeListener(_phoneChanged);
    _resendTimer?.cancel();
    for (final c in [_phone, _otp, _pin, _confirmation, _device]) {
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on PinRecoveryFailure catch (e) {
      if (_progress == null && _selectedTargetId != null) {
        try {
          final pending = await _service.listPending();
          final sameTarget = pending.where(
            (p) =>
                p.target.targetId == _selectedTargetId &&
                p.kind ==
                    (widget.enabling
                        ? PinRecoveryKind.enable
                        : PinRecoveryKind.recover),
          );
          if (sameTarget.length == 1 && mounted) {
            setState(() => _progress = sameTarget.single);
          }
        } catch (_) {
          /* Core journal is discovered again on page reentry. */
        }
      }
      final operation = _progress;
      if (operation != null) {
        try {
          final current = await _service.status(operation.operationId);
          if (mounted) setState(() => _progress = current);
        } catch (_) {
          /* Keep the same operation available for exact retry. */
        }
      }
      if (mounted) setState(() => _error = e.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'operation_failed');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(pendingPinRecoveryProvider);
        if (widget.localIdentityId != null && widget.expectedDid != null) {
          ref.invalidate(
            pinBackupStatusProvider((
              widget.localIdentityId!,
              widget.expectedDid!,
            )),
          );
        }
      }
    }
  }

  Future<void> _sendCode() => _run(() async {
    final phoneGeneration = _phoneGeneration;
    final challenge = await _service.requestPhoneCode(
      _phone.text,
      resumeOperationId: _progress?.operationId,
    );
    if (!_current || phoneGeneration != _phoneGeneration) return;
    _resendTimer?.cancel();
    _resendTimer = Timer(Duration(seconds: challenge.resendAfterSeconds), () {
      if (mounted) setState(() => _resendAt = null);
    });
    setState(() {
      _challenge = challenge;
      _targets = null;
      _discovery = null;
      _resendAt = DateTime.now().add(
        Duration(seconds: challenge.resendAfterSeconds),
      );
    });
  });
  Future<void> _verify() => _run(() async {
    final phoneGeneration = _phoneGeneration;
    final code = _otp.text;
    _otp.clear();
    final result = await _service.verify(
      challengeHandle: _challenge!.handle,
      code: code,
    );
    if (!_current || phoneGeneration != _phoneGeneration) return;
    final targets = widget.enabling
        ? result.targets
              .where(
                (t) =>
                    t.did == widget.expectedDid &&
                    (widget.expectedHandle == null ||
                        t.fullHandle == widget.expectedHandle),
              )
              .toList()
        : result.targets;
    setState(() {
      _discovery = result.discoveryHandle;
      _targets = targets;
    });
  });
  Future<void> _select(PinRecoveryTarget target) => _run(() async {
    // Core rechecks authorization atomically at selection and at every advance.
    final current = _progress;
    if (current != null &&
        (target.targetId != current.target.targetId ||
            target.did != current.target.did ||
            target.bindingGeneration != current.target.bindingGeneration)) {
      throw const PinRecoveryFailure('target_mismatch');
    }
    final phoneGeneration = _phoneGeneration;
    _selectedTargetId = target.targetId;
    final presenceReason = context.l10n.pinBackupPresence;
    final session = await _service.select(_discovery!, target);
    if (!_current || phoneGeneration != _phoneGeneration) return;
    final next = current != null
        ? await _service.resume(current.operationId, sessionHandle: session)
        : widget.enabling
        ? await _service.beginEnable(
            sessionHandle: session,
            localIdentityId: widget.localIdentityId!,
            presenceReason: presenceReason,
            isCurrent: () => _current,
          )
        : await _service.beginRecover(
            sessionHandle: session,
            deviceLabel: _device.text,
          );
    if (mounted) {
      setState(() {
        _progress = next;
        _targets = null;
        _challenge = null;
        _discovery = null;
      });
    }
  });
  Future<void> _submitPin() => _run(() async {
    final pin = _pin.text, confirm = _confirmation.text;
    _pin.clear();
    _confirmation.clear();
    final next = await _service.submitPin(
      operationId: _progress!.operationId,
      pin: pin,
      confirmation: widget.enabling ? confirm : null,
    );
    if (mounted) setState(() => _progress = next);
  });
  Future<void> _advance(Future<PinRecoveryProgress> Function() action) => _run(
    () async {
      final next = await action();
      PinBackupStatus? backup;
      if (widget.localIdentityId != null &&
          next.phase == PinRecoveryPhase.cancelled) {
        try {
          final current = await _service.backupStatus(widget.localIdentityId!);
          backup = current.did == widget.expectedDid
              ? current
              : PinBackupStatus(
                  did: widget.expectedDid ?? '',
                  state: PinBackupState.unknown,
                );
        } catch (_) {
          backup = PinBackupStatus(
            did: widget.expectedDid ?? '',
            state: PinBackupState.unknown,
          );
        }
      }
      if (mounted) {
        setState(() {
          _progress = next;
          if (backup != null) _backupStatus = backup;
        });
      }
    },
  );
  Future<void> _enter() => _run(() async {
    final displayed = _progress;
    if (displayed == null || !displayed.canEnter) return;
    final identities = ref.read(identityCorePortProvider);
    final runtime = ref.read(appRuntimeProvider.notifier);
    final current = await _service.status(displayed.operationId);
    if (!_current) return;
    if (!current.canEnter ||
        current.operationId != displayed.operationId ||
        current.target.targetId != displayed.target.targetId ||
        current.target.did != displayed.target.did ||
        current.target.bindingGeneration !=
            displayed.target.bindingGeneration) {
      throw const PinRecoveryFailure('target_mismatch');
    }
    final id = current.recoveredIdentityId!;
    final local = await identities.resolveIdentity(id);
    if (!_current) return;
    if (local.identityId != id || local.did != current.target.did) {
      throw const PinRecoveryFailure('target_mismatch');
    }
    final activated = await runtime.loginWithLocalCredentialAndConfirm(
      id,
      isCurrent: () => _current,
    );
    if (!mounted || !_current) return;
    if (!activated) throw const PinRecoveryFailure('local_activation_pending');
    Navigator.of(context).popUntil((route) => route.isFirst);
  });
  Future<void> _forgot({PinRecoveryTarget? target}) async {
    if (!_current) return;
    final did = target?.did ?? _progress?.target.did ?? widget.expectedDid;
    var allowsV4 = false;
    if (did != null) {
      try {
        final identities = ref.read(identityCorePortProvider);
        final backendRead = ref.read(backendFeaturesFutureProvider);
        final method = await identities.identityMethodCapabilities(did);
        final backend = await backendRead;
        allowsV4 =
            method.handleRecovery &&
            backend.supports('identity.account_recovery');
      } catch (_) {
        /* Keep existing-device help when V4 is unavailable. */
      }
    }
    if (!mounted || !_current) return;
    final l = context.l10n;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: Text(l.pinRecoveryForgot),
        message: Text(l.pinRecoveryForgotInfo),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.of(popupContext).pop();
              Navigator.of(context).maybePop();
            },
            child: Text(l.pinRecoveryContinueExisting),
          ),
          if (allowsV4 &&
              (target != null ||
                  _progress?.target.fullHandle != null ||
                  widget.expectedHandle != null ||
                  _backupStatus?.fullHandle != null))
            CupertinoActionSheetAction(
              key: const Key('pin-recovery-v4-action'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(popupContext).pop();
                final handle =
                    target?.fullHandle ??
                    _progress?.target.fullHandle ??
                    widget.expectedHandle ??
                    _backupStatus!.fullHandle!;
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => HandleRecoveryPage(
                      initialHandle: handle,
                      initialPhone: '',
                      autoRequestOtp: false,
                      allowPhoneInput: true,
                      localIdentityId: widget.localIdentityId,
                    ),
                  ),
                );
              },
              child: Text(l.pinRecoveryV4),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(popupContext).pop(),
          child: Text(l.commonBack),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key, {
    bool secret = false,
    int? digits,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 6),
        ExcludeSemantics(
          excluding: secret,
          child: CupertinoTextField(
            key: Key(key),
            controller: controller,
            obscureText: secret,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: digits == null
                ? TextInputType.text
                : TextInputType.number,
            inputFormatters: digits == null
                ? null
                : [
                    FilteringTextInputFormatter.allow(RegExp('[0-9]')),
                    LengthLimitingTextInputFormatter(digits),
                  ],
            enabled: !_busy,
            padding: const EdgeInsets.all(12),
            placeholder: label,
          ),
        ),
      ],
    ),
  );
  Widget _button(String label, String key, VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: AppSecondaryButton(
      key: Key(key),
      label: label,
      onPressed: _busy ? null : onPressed,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final l = context.l10n, p = _progress;
    final needsPhone =
        p == null ||
        p.needsPhoneVerification ||
        p.allows(PinRecoveryAction.verifyPhone);
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              key: const Key('pin-recovery-page'),
              padding: const EdgeInsets.all(20),
              children: [
                AwikiMeTopBar(
                  title: widget.enabling
                      ? l.pinBackupTitle
                      : l.pinRecoveryTitle,
                  leading: AwikiBackButton(
                    onTap: () => Navigator.of(context).maybePop(),
                    semanticsLabel: l.commonBack,
                  ),
                ),
                if (_loading || _busy) const CupertinoActivityIndicator(),
                if (_backupStatus != null &&
                    ((p == null && (!widget.offerBackup || _begun)) ||
                        p?.phase == PinRecoveryPhase.cancelled))
                  Text(
                    pinBackupStateLabel(context, _backupStatus!.state),
                    key: const Key('pin-backup-current-status'),
                  ),
                if (_unsupported) Text(l.pinBackupUnsupported),
                if (!_loading &&
                    !_unsupported &&
                    (_backupStatus?.state != PinBackupState.active ||
                        p != null)) ...[
                  if (widget.enabling) Text(l.pinBackupOffer),
                  if (widget.enabling && !widget.offerBackup && p == null)
                    Text(l.pinRecoveryStatusCheck),
                  if (!_begun && p == null) ...[
                    Text(
                      pinBackupStateLabel(
                        context,
                        _backupStatus?.state ?? PinBackupState.unknown,
                      ),
                      key: Key(
                        _backupStatus?.state == PinBackupState.notEnabled
                            ? 'pin-backup-not-enabled'
                            : 'pin-backup-current-status',
                      ),
                    ),
                    _button(
                      l.pinBackupSet,
                      'pin-backup-start',
                      () => setState(() => _begun = true),
                    ),
                    _button(
                      l.pinBackupSkip,
                      'pin-backup-skip',
                      () => Navigator.of(context).pop(),
                    ),
                  ] else ...[
                    if (p != null) ...[
                      Text(p.target.fullHandle),
                      SelectableText(p.target.did),
                      if (p.deviceLabel != null)
                        Text(
                          '${l.pinRecoveryDeviceLabel}: ${p.deviceLabel}',
                          key: const Key('pin-recovery-device-label-confirmed'),
                        ),
                      Text(
                        pinRecoveryPhaseLabel(context, p),
                        key: const Key('pin-recovery-phase'),
                      ),
                      if (p.kind == PinRecoveryKind.recover)
                        Text(
                          '${l.pinRecoveryAttemptBudget}: ${p.attemptsUsed}/${p.attemptsLimit}',
                        ),
                      for (final node in p.nodeProgress)
                        Text('${node.realmId}: ${node.phase}'),
                      if (p.errorCode != null && _error == null && !_busy)
                        Text(pinRecoveryErrorLabel(context, p.errorCode!)),
                      if (p.phase ==
                          PinRecoveryPhase.awaitingDeviceConfirmation)
                        Text(l.pinRecoveryConfirmDescription),
                    ],
                    if (needsPhone &&
                        p?.phase != PinRecoveryPhase.cancelled) ...[
                      if (p != null) Text(l.pinRecoveryPhoneAgain),
                      _field(_phone, l.pinRecoveryPhone, 'pin-recovery-phone'),
                      _button(
                        l.pinRecoverySendCode,
                        'pin-recovery-send-code',
                        _resendAt != null && DateTime.now().isBefore(_resendAt!)
                            ? null
                            : _sendCode,
                      ),
                      if (_challenge != null) ...[
                        Text(_challenge!.maskedPhone),
                        _field(
                          _otp,
                          l.pinRecoveryCode,
                          'pin-recovery-otp',
                          secret: true,
                          digits: 6,
                        ),
                        _button(
                          l.pinRecoveryVerify,
                          'pin-recovery-verify',
                          _verify,
                        ),
                      ],
                      if (_targets != null) ...[
                        Text(
                          _targets!.isEmpty
                              ? l.pinRecoveryNoTargets
                              : l.pinRecoveryTargets,
                        ),
                        if (!widget.enabling)
                          _field(
                            _device,
                            l.pinRecoveryDeviceLabel,
                            'pin-recovery-device-label',
                          ),
                        for (final target in _targets!) ...[
                          _button(
                            target.fullHandle,
                            'pin-recovery-target-${target.targetId}',
                            (p != null ||
                                    (widget.enabling
                                        ? target.canEnable
                                        : target.canRecover))
                                ? () => _select(target)
                                : null,
                          ),
                          if (target.activeEpoch != null)
                            Text(l.pinBackupProtected),
                          if (!target.canRecover && !widget.enabling) ...[
                            Text(l.pinRecoveryUnavailable),
                            _button(
                              l.pinRecoveryV4,
                              'pin-recovery-v4-${target.targetId}',
                              () => _forgot(target: target),
                            ),
                          ],
                        ],
                      ],
                    ],
                    if (p?.allows(PinRecoveryAction.submitPin) == true) ...[
                      _field(
                        _pin,
                        l.pinRecoveryPin,
                        'pin-recovery-pin',
                        secret: true,
                        digits: 4,
                      ),
                      if (widget.enabling)
                        _field(
                          _confirmation,
                          l.pinRecoveryConfirmPin,
                          'pin-recovery-pin-confirm',
                          secret: true,
                          digits: 4,
                        ),
                      _button(
                        l.pinRecoverySubmit,
                        'pin-recovery-submit-pin',
                        _submitPin,
                      ),
                    ],
                    if (p?.allows(PinRecoveryAction.confirmDevice) == true)
                      _button(
                        l.pinRecoveryConfirmDevice,
                        'pin-recovery-confirm-device',
                        () => _advance(
                          () => _service.confirmDevice(
                            p!.operationId,
                            presenceReason: l.pinRecoveryPresence,
                            isCurrent: () => _current,
                          ),
                        ),
                      ),
                    if (p?.allows(PinRecoveryAction.resume) == true ||
                        p?.allows(PinRecoveryAction.retryLocalActivation) ==
                            true)
                      _button(
                        l.pinRecoveryResume,
                        'pin-recovery-resume',
                        () => _advance(() => _service.resume(p!.operationId)),
                      ),
                    if (p?.allows(PinRecoveryAction.cancel) == true)
                      _button(
                        l.pinRecoveryCancel,
                        'pin-recovery-cancel',
                        () => _advance(() => _service.cancel(p!.operationId)),
                      ),
                    if (p?.canEnter == true)
                      _button(l.pinRecoveryEnter, 'pin-recovery-enter', _enter),
                    if (p?.isProtected == true)
                      _button(
                        l.commonBack,
                        'pin-recovery-done',
                        () => Navigator.of(context).pop(),
                      ),
                  ],
                ],
                if (!_loading)
                  _button(l.pinRecoveryForgot, 'pin-recovery-forgot', _forgot),
                if (_error != null)
                  Text(
                    pinRecoveryErrorLabel(context, _error!),
                    key: const Key('pin-recovery-error'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String pinRecoveryPhaseLabel(
  BuildContext context,
  PinRecoveryProgress progress,
) {
  final l = context.l10n;
  return switch (progress.phase) {
    PinRecoveryPhase.awaitingPin => l.pinRecoveryAwaitingPin,
    PinRecoveryPhase.authorizing ||
    PinRecoveryPhase.registering => l.pinRecoveryRegistering,
    PinRecoveryPhase.verifyingBackup => l.pinRecoveryVerifying,
    PinRecoveryPhase.recoveringKey => l.pinRecoveryRecovering,
    PinRecoveryPhase.awaitingDeviceConfirmation => l.pinRecoveryConfirmDevice,
    PinRecoveryPhase.committing => l.pinRecoveryCommitting,
    PinRecoveryPhase.commitUnknown => l.pinRecoveryCommitUnknown,
    PinRecoveryPhase.localActivationPending => l.pinRecoveryLocalPending,
    PinRecoveryPhase.activeSecurePending => l.pinRecoverySecurePending,
    PinRecoveryPhase.cleanupPending ||
    PinRecoveryPhase.failed => l.pinBackupPending,
    PinRecoveryPhase.completed =>
      progress.isProtected ? l.pinBackupProtected : l.pinRecoveryReady,
    PinRecoveryPhase.cancelled => l.pinRecoveryCancelledOperation,
  };
}

String pinRecoveryErrorLabel(BuildContext context, String code) {
  final l = context.l10n;
  return switch (code) {
    'pin_format' => l.pinRecoveryPinFormat,
    'pin_mismatch' => l.pinRecoveryPinMismatch,
    'invalid_pin' || 'pin_recovery.invalid_pin' => l.pinRecoveryWrongPin,
    'guess_budget_exhausted' => l.pinRecoveryBudgetExhausted,
    'realm_unavailable' => l.pinRecoveryRealmUnavailable,
    _ => l.pinRecoveryFailure,
  };
}

String pinBackupStateLabel(BuildContext context, PinBackupState state) =>
    switch (state) {
      PinBackupState.unknown => context.l10n.pinBackupUnknown,
      PinBackupState.notEnabled => context.l10n.pinBackupNotEnabled,
      PinBackupState.pending => context.l10n.pinBackupPending,
      PinBackupState.active => context.l10n.pinBackupProtected,
    };
