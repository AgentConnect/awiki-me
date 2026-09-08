// [INPUT]: Recovery UI intents plus the Core-owned operation service.
// [OUTPUT]: Secret-free V4.0 Recovery UI state with one post-commit auto-resume.
// [POS]: Presentation controller; it never persists an operation locator or phase.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/handle_recovery_service.dart';
import '../../application/ports/handle_recovery_core_port.dart';
import '../../domain/entities/handle_recovery.dart';
import '../shared/sms_otp_cooldown_provider.dart';
import 'handle_recovery_state.dart';
import 'handle_recovery_session.dart';
export 'handle_recovery_state.dart';

final handleRecoveryCorePortProvider = Provider<HandleRecoveryCorePort>(
  (ref) => throw UnimplementedError(
    'handleRecoveryCorePortProvider must be overridden by the Core adapter',
  ),
);

final handleRecoveryServiceProvider = Provider<HandleRecoveryService>(
  (ref) => HandleRecoveryService(
    core: ref.watch(handleRecoveryCorePortProvider),
    userPresence: ref.watch(userPresencePortProvider),
  ),
);

class HandleRecoveryController extends StateNotifier<HandleRecoveryState> {
  HandleRecoveryController(
    this._service,
    this._otpCooldown, {
    HandleRecoverySession? session,
    void Function()? onIdle,
  }) : _session = session,
       _onIdle = onIdle,
       super(const HandleRecoveryState());

  final HandleRecoverySession? _session;
  final void Function()? _onIdle;
  bool get isBusy => mounted && state.isBusy;

  int _generation = 0;
  bool _isCurrent(int generation) => mounted && generation == _generation;

  final HandleRecoveryService _service;
  final SmsOtpCooldownController _otpCooldown;

  Future<void> open(HandleRecoveryTarget target) async {
    if (state.isBusy) return;
    final generation = ++_generation;
    state = const HandleRecoveryState(
      isBusy: true,
      action: HandleRecoveryBusyAction.reading,
    );
    try {
      final id = target.localIdentityId;
      final restored = id == null
          ? await _service.restoreForHandle(target.handle)
          : await _service.restoreForOwner(
              scope: HandleRecoveryIdentityScope(localIdentityId: id),
              handle: target.handle,
            );
      if (!_isCurrent(generation)) return;
      state = HandleRecoveryState(
        owner: restored == null
            ? null
            : HandleRecoveryOwner(
                localIdentityId: restored.ownerIdentityId,
                handle: restored.handle,
              ),
        progress: restored,
      );
    } catch (error) {
      if (_isCurrent(generation)) {
        state = HandleRecoveryState(
          lookupFailed: true,
          error: handleRecoveryUiErrorFrom(error),
        );
      }
    } finally {
      _onIdle?.call();
    }
  }

  void reset() {
    if (state.isBusy) return;
    _generation += 1;
    state = const HandleRecoveryState();
  }

  void setRiskConfirmed(bool value) {
    if (state.isBusy) return;
    state = state.copyWith(riskConfirmed: value);
  }

  Future<void> requestOtp({
    required String handle,
    required String phone,
    String? localIdentityId,
  }) async {
    final generation = _generation;
    if (state.isBusy || !state.canRequestOtp) return;
    state = state.copyWith(
      isBusy: true,
      action: HandleRecoveryBusyAction.sendingOtp,
      clearError: true,
    );
    if (!await _otpCooldown.beginSend()) {
      if (_isCurrent(generation)) {
        state = state.copyWith(
          isBusy: false,
          action: HandleRecoveryBusyAction.none,
        );
      }
      _onIdle?.call();
      return;
    }
    if (!_isCurrent(generation)) {
      _otpCooldown.completeFailed();
      return;
    }
    try {
      final receipt = await _service.requestOtp(
        handle: handle,
        phone: phone,
        localIdentityId: localIdentityId,
        expectedOperationId: state.progress?.operationId,
      );
      await _otpCooldown.completeAcceptedAt(receipt.retryAt);
      if (_isCurrent(generation)) {
        state = state.copyWith(
          owner: HandleRecoveryOwner(
            localIdentityId: receipt.operation.ownerIdentityId,
            handle: receipt.operation.handle,
          ),
          progress: receipt.operation,
          otpPhone: phone.trim(),
        );
      }
    } catch (error) {
      if (error is HandleRecoveryOtpRateLimited) {
        await _otpCooldown.completeRateLimitedAt(error.retryAt);
      }
      if (_isCurrent(generation)) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      _otpCooldown.completeFailed();
      if (_isCurrent(generation)) {
        state = state.copyWith(
          isBusy: false,
          action: HandleRecoveryBusyAction.none,
        );
      }
      _onIdle?.call();
    }
  }

  Future<void> prepare({required String phone, required String otp}) async {
    final generation = _generation;
    if (state.isBusy || !state.otpRequested) return;
    state = state.copyWith(
      isBusy: true,
      action: HandleRecoveryBusyAction.verifying,
      clearError: true,
    );
    try {
      final operationId = state.progress?.operationId;
      if (operationId == null || state.otpPhone != phone.trim()) {
        throw const HandleRecoveryFailure(
          HandleRecoveryFailureCode.transitionMismatch,
        );
      }
      final progress = await _service.prepare(
        operationId: operationId,
        phone: phone,
        otp: otp,
      );
      if (_isCurrent(generation)) {
        state = state.copyWith(
          progress: progress,
          riskConfirmed: false,
          clearPhone: !progress.commitAttempted,
        );
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      final failure = handleRecoveryUiErrorFrom(error);
      final operationId = state.progress?.operationId;
      if (operationId != null) {
        try {
          final latest = await _service.status(operationId);
          if (_isCurrent(generation)) _acceptProgress(latest);
        } catch (_) {
          if (_isCurrent(generation)) {
            state = state.copyWith(
              error: HandleRecoveryUiError.localStateUnavailable,
            );
          }
        }
      }
      if (_isCurrent(generation)) {
        state = state.copyWith(error: state.effectiveError ?? failure);
      }
    } finally {
      if (_isCurrent(generation)) {
        state = state.copyWith(
          isBusy: false,
          action: HandleRecoveryBusyAction.none,
        );
      }
      _onIdle?.call();
    }
  }

  Future<void> activate({
    required String presenceReason,
    bool stopBeforeSession = false,
  }) async {
    if (state.isBusy || !state.canActivate) return;
    if (!state.riskConfirmed) {
      state = state.copyWith(
        error: HandleRecoveryUiError.riskConfirmationRequired,
      );
      return;
    }
    await _advance(
      activate: true,
      presenceReason: presenceReason,
      stopBeforeSession: stopBeforeSession,
    );
  }

  Future<void> resume({bool stopBeforeSession = false}) async {
    if (state.isBusy || !state.canResume) return;
    await _advance(activate: false, stopBeforeSession: stopBeforeSession);
  }

  Future<void> _advance({
    required bool activate,
    String presenceReason = '',
    required bool stopBeforeSession,
  }) async {
    final generation = _generation;
    final operationId = state.progress!.operationId;
    var authoritative = true;
    state = state.copyWith(
      isBusy: true,
      clearError: true,
      action: activate
          ? HandleRecoveryBusyAction.authenticating
          : HandleRecoveryBusyAction.recovering,
    );
    Future<void> pause() async {
      state = state.copyWith(action: HandleRecoveryBusyAction.recovering);
      await _session?.pauseCurrent();
      authoritative = false;
    }

    try {
      final next = activate
          ? await _service.activate(
              operationId: operationId,
              presenceReason: presenceReason,
              beforeCommit: pause,
            )
          : await (() async {
              await pause();
              return _service.resume(operationId);
            })();
      authoritative = true;
      if (_isCurrent(generation)) _acceptProgress(next);
    } catch (error) {
      if (!_isCurrent(generation)) return;
      HandleRecoveryUiError? failure = handleRecoveryUiErrorFrom(error);
      try {
        final latest = await _service.status(operationId);
        authoritative = true;
        if (_isCurrent(generation)) _acceptProgress(latest);
        // One bounded automatic continuation only after the initial commit action.
        if (activate &&
            state.canResume &&
            failure.action != HandleRecoveryUiAction.terminal &&
            failure != HandleRecoveryUiError.keyUnavailable &&
            failure != HandleRecoveryUiError.localStateUnavailable) {
          authoritative = false;
          final resumed = await _service.resume(operationId);
          authoritative = true;
          if (_isCurrent(generation)) _acceptProgress(resumed);
          failure = state.effectiveError;
        }
      } catch (refreshError) {
        // A failed continuation can itself advance durable state. Re-read without issuing another mutation.
        failure = handleRecoveryUiErrorFrom(refreshError);
        try {
          final latest = await _service.status(operationId);
          authoritative = true;
          if (_isCurrent(generation)) _acceptProgress(latest);
        } catch (_) {
          failure = HandleRecoveryUiError.localStateUnavailable;
        }
      }
      if (_isCurrent(generation) && state.progress?.isCompleted != true) {
        state = state.copyWith(
          error: state.effectiveError ?? failure,
          clearError: state.effectiveError == null && failure == null,
        );
      }
    } finally {
      if (_isCurrent(generation)) {
        if (authoritative && state.progress?.commitAttempted != true) {
          try {
            await _session?.restorePrevious();
          } catch (_) {
            state = state.copyWith(error: HandleRecoveryUiError.failed);
          }
        }
        if (_isCurrent(generation) &&
            !stopBeforeSession &&
            state.progress?.isCompleted == true) {
          await _enterSession();
        }
        if (_isCurrent(generation)) {
          state = state.copyWith(
            isBusy: false,
            action: HandleRecoveryBusyAction.none,
          );
        }
      }
      _onIdle?.call();
    }
  }

  void _acceptProgress(HandleRecoveryProgress progress) {
    state = state.copyWith(
      progress: progress,
      clearError: true,
      riskConfirmed:
          progress.failureCode == HandleRecoveryFailureCode.factorRetryRequired
          ? false
          : null,
    );
  }

  Future<void> enterMessages() async {
    if (state.isBusy ||
        state.progress?.isCompleted != true ||
        state.isTerminal) {
      return;
    }
    state = state.copyWith(isBusy: true);
    try {
      await _enterSession();
    } finally {
      if (mounted) {
        state = state.copyWith(
          isBusy: false,
          action: HandleRecoveryBusyAction.none,
        );
      }
      _onIdle?.call();
    }
  }

  Future<void> _enterSession() async {
    if (!mounted || _session == null) return;
    state = state.copyWith(
      action: HandleRecoveryBusyAction.entering,
      sessionActivationFailed: false,
    );
    try {
      final activated = await _session.activate(
        state.progress!.ownerIdentityId,
      );
      if (mounted) {
        state = state.copyWith(
          sessionActivated: activated,
          sessionActivationFailed: !activated,
        );
      }
    } catch (_) {
      if (mounted) state = state.copyWith(sessionActivationFailed: true);
    }
  }

  Future<void> restoreForOwner({
    required HandleRecoveryIdentityScope scope,
    required String handle,
  }) async {
    final generation = _generation;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final restored = await _service.restoreForOwner(
        scope: scope,
        handle: handle,
      );
      if (!_isCurrent(generation)) return;
      if (restored == null) {
        state = const HandleRecoveryState();
      } else {
        state = state.copyWith(
          owner: HandleRecoveryOwner(
            localIdentityId: restored.ownerIdentityId,
            handle: restored.handle,
          ),
          progress: restored,
        );
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (_isCurrent(generation)) {
        state = state.copyWith(
          isBusy: false,
          action: HandleRecoveryBusyAction.none,
        );
      }
      _onIdle?.call();
    }
  }

  Future<void> discardPreAttempt() async {
    final generation = _generation;
    final progress = state.progress;
    if (progress == null || !progress.canDiscard || state.isBusy) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _service.discardPreAttempt(progress.operationId);
      if (_isCurrent(generation)) {
        state = const HandleRecoveryState();
      }
    } catch (error) {
      if (_isCurrent(generation)) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (_isCurrent(generation)) {
        state = state.copyWith(
          isBusy: false,
          action: HandleRecoveryBusyAction.none,
        );
      }
      _onIdle?.call();
    }
  }

  Future<void> quarantineKeyUnavailable({
    required String presenceReason,
  }) async {
    final generation = _generation;
    final progress = state.progress;
    if (progress == null ||
        (progress.keyState != HandleRecoveryKeyState.permanentlyUnavailable &&
            state.error != HandleRecoveryUiError.keyUnavailable) ||
        state.isBusy) {
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final next = await _service.quarantineKeyUnavailable(
        operationId: progress.operationId,
        presenceReason: presenceReason,
      );
      if (_isCurrent(generation)) state = state.copyWith(progress: next);
    } catch (error) {
      if (_isCurrent(generation)) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (_isCurrent(generation)) {
        state = state.copyWith(
          isBusy: false,
          action: HandleRecoveryBusyAction.none,
        );
      }
      _onIdle?.call();
    }
  }

  void startAfterQuarantine() {
    if (state.progress?.lifecycleClass !=
        HandleRecoveryLifecycleClass.quarantinedKeyUnavailable) {
      return;
    }
    state = const HandleRecoveryState();
  }
}

typedef HandleRecoveryTarget = ({String handle, String? localIdentityId});

final handleRecoveryProvider = StateNotifierProvider.autoDispose
    .family<
      HandleRecoveryController,
      HandleRecoveryState,
      HandleRecoveryTarget
    >((ref, target) {
      final link = ref.keepAlive();
      var observed = true;
      late final HandleRecoveryController controller;
      void releaseWhenIdle() {
        if (controller.mounted && !observed && !controller.isBusy) link.close();
      }

      controller = HandleRecoveryController(
        ref.watch(handleRecoveryServiceProvider),
        ref.watch(handleRecoverySmsOtpCooldownProvider.notifier),
        session: RuntimeHandleRecoverySession(ref),
        onIdle: releaseWhenIdle,
      );
      ref.onCancel(() {
        observed = false;
        releaseWhenIdle();
      });
      ref.onResume(() {
        observed = true;
      });
      return controller;
    });
