// [INPUT]: Recovery UI intents plus the Core-owned operation service.
// [OUTPUT]: Secret-free V4.0 Recovery UI state with one post-commit auto-resume.
// [POS]: Presentation controller; it never persists an operation locator or phase.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/handle_recovery_service.dart';
import '../../application/ports/handle_recovery_core_port.dart';
import '../../domain/entities/handle_recovery.dart';
import '../shared/sms_otp_cooldown_provider.dart';

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
  dependencies: [handleRecoveryCorePortProvider, userPresencePortProvider],
);

enum HandleRecoveryUiAction { terminal, exactResume, userAction, localBlocked }

enum HandleRecoveryUiError {
  activationRequired,
  recoveryInProgress,
  actionNotAllowed,
  stateChanged,
  unknownEpoch,
  factorRetryRequired,
  localTransitionPending,
  localTransitionSuperseded,
  riskConfirmationRequired,
  notPrepared,
  userPresenceRequired,
  transitionMismatch,
  transitionChainUnsupported,
  remoteStateChanged,
  resultAbsent,
  outcomeUnknown,
  localStateUnavailable,
  keyUnavailable,
  migrationUnsupported,
  blocked,
  rateLimited,
  failed,
}

extension HandleRecoveryUiErrorDetails on HandleRecoveryUiError {
  HandleRecoveryFailureCode? get code => switch (this) {
    HandleRecoveryUiError.activationRequired =>
      HandleRecoveryFailureCode.activationRequired,
    HandleRecoveryUiError.recoveryInProgress =>
      HandleRecoveryFailureCode.recoveryInProgress,
    HandleRecoveryUiError.actionNotAllowed =>
      HandleRecoveryFailureCode.actionNotAllowed,
    HandleRecoveryUiError.stateChanged =>
      HandleRecoveryFailureCode.stateChanged,
    HandleRecoveryUiError.unknownEpoch =>
      HandleRecoveryFailureCode.unknownEpoch,
    HandleRecoveryUiError.localTransitionSuperseded =>
      HandleRecoveryFailureCode.localTransitionSuperseded,
    HandleRecoveryUiError.factorRetryRequired =>
      HandleRecoveryFailureCode.factorRetryRequired,
    HandleRecoveryUiError.localTransitionPending =>
      HandleRecoveryFailureCode.localTransitionPending,
    HandleRecoveryUiError.notPrepared => HandleRecoveryFailureCode.notPrepared,
    HandleRecoveryUiError.userPresenceRequired =>
      HandleRecoveryFailureCode.userPresenceRequired,
    HandleRecoveryUiError.transitionMismatch =>
      HandleRecoveryFailureCode.transitionMismatch,
    HandleRecoveryUiError.transitionChainUnsupported =>
      HandleRecoveryFailureCode.transitionChainUnsupported,
    HandleRecoveryUiError.remoteStateChanged =>
      HandleRecoveryFailureCode.remoteStateChanged,
    HandleRecoveryUiError.resultAbsent =>
      HandleRecoveryFailureCode.resultAbsent,
    HandleRecoveryUiError.outcomeUnknown =>
      HandleRecoveryFailureCode.outcomeUnknown,
    HandleRecoveryUiError.localStateUnavailable =>
      HandleRecoveryFailureCode.localStateUnavailable,
    HandleRecoveryUiError.keyUnavailable =>
      HandleRecoveryFailureCode.localKeyUnavailable,
    HandleRecoveryUiError.migrationUnsupported =>
      HandleRecoveryFailureCode.localMigrationUnsupported,
    HandleRecoveryUiError.blocked => HandleRecoveryFailureCode.blocked,
    HandleRecoveryUiError.riskConfirmationRequired ||
    HandleRecoveryUiError.rateLimited ||
    HandleRecoveryUiError.failed => null,
  };

  HandleRecoveryUiAction get action => switch (this) {
    HandleRecoveryUiError.stateChanged ||
    HandleRecoveryUiError.localTransitionSuperseded ||
    HandleRecoveryUiError.notPrepared ||
    HandleRecoveryUiError.transitionMismatch ||
    HandleRecoveryUiError.transitionChainUnsupported ||
    HandleRecoveryUiError.remoteStateChanged ||
    HandleRecoveryUiError.migrationUnsupported =>
      HandleRecoveryUiAction.terminal,
    HandleRecoveryUiError.localTransitionPending ||
    HandleRecoveryUiError.resultAbsent ||
    HandleRecoveryUiError.outcomeUnknown => HandleRecoveryUiAction.exactResume,
    HandleRecoveryUiError.activationRequired ||
    HandleRecoveryUiError.factorRetryRequired ||
    HandleRecoveryUiError.riskConfirmationRequired ||
    HandleRecoveryUiError.userPresenceRequired ||
    HandleRecoveryUiError.keyUnavailable ||
    HandleRecoveryUiError.rateLimited => HandleRecoveryUiAction.userAction,
    HandleRecoveryUiError.recoveryInProgress ||
    HandleRecoveryUiError.actionNotAllowed ||
    HandleRecoveryUiError.unknownEpoch ||
    HandleRecoveryUiError.localStateUnavailable ||
    HandleRecoveryUiError.blocked ||
    HandleRecoveryUiError.failed => HandleRecoveryUiAction.localBlocked,
  };

  String get safeCode => code?.name ?? name;
}

HandleRecoveryUiError handleRecoveryUiErrorFrom(Object error) {
  if (error is HandleRecoveryOtpRateLimited) {
    return HandleRecoveryUiError.rateLimited;
  }
  if (error is! HandleRecoveryFailure) return HandleRecoveryUiError.failed;
  return switch (error.code) {
    HandleRecoveryFailureCode.activationRequired =>
      HandleRecoveryUiError.activationRequired,
    HandleRecoveryFailureCode.recoveryInProgress =>
      HandleRecoveryUiError.recoveryInProgress,
    HandleRecoveryFailureCode.actionNotAllowed =>
      HandleRecoveryUiError.actionNotAllowed,
    HandleRecoveryFailureCode.stateChanged =>
      HandleRecoveryUiError.stateChanged,
    HandleRecoveryFailureCode.notPrepared => HandleRecoveryUiError.notPrepared,
    HandleRecoveryFailureCode.userPresenceRequired =>
      HandleRecoveryUiError.userPresenceRequired,
    HandleRecoveryFailureCode.transitionMismatch =>
      HandleRecoveryUiError.transitionMismatch,
    HandleRecoveryFailureCode.transitionChainUnsupported =>
      HandleRecoveryUiError.transitionChainUnsupported,
    HandleRecoveryFailureCode.remoteStateChanged =>
      HandleRecoveryUiError.remoteStateChanged,
    HandleRecoveryFailureCode.resultAbsent =>
      HandleRecoveryUiError.resultAbsent,
    HandleRecoveryFailureCode.outcomeUnknown =>
      HandleRecoveryUiError.outcomeUnknown,
    HandleRecoveryFailureCode.localStateUnavailable =>
      HandleRecoveryUiError.localStateUnavailable,
    HandleRecoveryFailureCode.localKeyUnavailable =>
      HandleRecoveryUiError.keyUnavailable,
    HandleRecoveryFailureCode.localMigrationUnsupported =>
      HandleRecoveryUiError.migrationUnsupported,
    HandleRecoveryFailureCode.factorRetryRequired =>
      HandleRecoveryUiError.factorRetryRequired,
    HandleRecoveryFailureCode.localTransitionSuperseded =>
      HandleRecoveryUiError.localTransitionSuperseded,
    HandleRecoveryFailureCode.localTransitionPending =>
      HandleRecoveryUiError.localTransitionPending,
    HandleRecoveryFailureCode.unknownEpoch =>
      HandleRecoveryUiError.unknownEpoch,
    HandleRecoveryFailureCode.blocked => HandleRecoveryUiError.blocked,
  };
}

class HandleRecoveryState {
  const HandleRecoveryState({
    this.authoritative = false,
    this.allowedActions = const [],
    this.riskConfirmed = false,
    this.isBusy = false,
    this.otpPhone,
    this.owner,
    this.progress,
    this.error,
  });

  final bool authoritative;
  final List<HandleRecoveryAction> allowedActions;
  bool allows(HandleRecoveryAction action) =>
      authoritative && allowedActions.contains(action);
  final bool riskConfirmed;
  final bool isBusy;
  final String? otpPhone;
  final HandleRecoveryOwner? owner;
  final HandleRecoveryProgress? progress;
  final HandleRecoveryUiError? error;

  bool get canRequestOtp =>
      allows(HandleRecoveryAction.requestOtp) ||
      (progress == null && allows(HandleRecoveryAction.startNew));

  bool get otpRequested =>
      allows(HandleRecoveryAction.prepare) && progress != null;

  String? get otpOperationId => progress?.operationId;
  String? get otpHandle => owner?.handle ?? progress?.handle;
  String? get localIdentityId => owner?.localIdentityId;

  HandleRecoveryState copyWith({
    bool? authoritative,
    List<HandleRecoveryAction>? allowedActions,
    bool? riskConfirmed,
    bool? isBusy,
    String? otpPhone,
    HandleRecoveryOwner? owner,
    HandleRecoveryProgress? progress,
    HandleRecoveryUiError? error,
    bool clearError = false,
    bool clearPhone = false,
    bool clearOperation = false,
  }) {
    return HandleRecoveryState(
      authoritative: authoritative ?? this.authoritative,
      allowedActions: allowedActions ?? this.allowedActions,
      riskConfirmed: riskConfirmed ?? this.riskConfirmed,
      isBusy: isBusy ?? this.isBusy,
      otpPhone: clearPhone ? null : (otpPhone ?? this.otpPhone),
      owner: clearOperation ? null : (owner ?? this.owner),
      progress: clearOperation ? null : (progress ?? this.progress),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HandleRecoveryController extends StateNotifier<HandleRecoveryState> {
  HandleRecoveryController(
    this._service,
    this._otpCooldown, {
    bool Function()? isPageCurrent,
  }) : _isPageCurrent = isPageCurrent,
       super(const HandleRecoveryState());

  final HandleRecoveryService _service;
  final SmsOtpCooldownController _otpCooldown;
  final bool Function()? _isPageCurrent;
  int _epoch = 0;
  String? _handle;
  String? _localIdentityId;

  int get epoch => _epoch;
  bool isCurrent(int epoch) =>
      mounted && epoch == _epoch && (_isPageCurrent?.call() ?? true);

  void invalidate() => _epoch++;

  void reset() {
    _epoch++;
    _handle = null;
    _localIdentityId = null;
    state = const HandleRecoveryState();
  }

  @override
  void dispose() {
    _epoch++;
    super.dispose();
  }

  void setRiskConfirmed(bool value) {
    if (!state.isBusy) {
      state = state.copyWith(riskConfirmed: value, clearError: true);
    }
  }

  Future<void> _refresh(int epoch, {String? expectedOperationId}) async {
    final handle = _handle;
    if (!isCurrent(epoch) || handle == null) return;
    final context = await _service.inspectContext(
      handle: handle,
      localIdentityId: _localIdentityId,
    );
    if (!isCurrent(epoch)) return;
    final progress = context.progress;
    if (expectedOperationId != null &&
        progress?.operationId != expectedOperationId) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    state = state.copyWith(
      clearOperation: progress == null,
      owner: progress == null
          ? null
          : HandleRecoveryOwner(
              localIdentityId: progress.ownerIdentityId,
              handle: progress.handle,
            ),
      progress: progress,
      allowedActions: context.allowedActions,
      authoritative: true,
      riskConfirmed:
          state.progress?.operationId == progress?.operationId &&
          state.riskConfirmed,
      error: context.blockedReason == null
          ? null
          : handleRecoveryUiErrorFrom(
              HandleRecoveryFailure(context.blockedReason!),
            ),
      clearError: context.blockedReason == null,
    );
  }

  Future<void> _run(Future<void> Function(int epoch) action) async {
    if (state.isBusy) return;
    final epoch = ++_epoch;
    final expectedOperationId = state.progress?.operationId;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await action(epoch);
    } catch (error) {
      if (!isCurrent(epoch)) return;
      try {
        await _refresh(epoch, expectedOperationId: expectedOperationId);
      } catch (_) {
        if (isCurrent(epoch)) {
          state = state.copyWith(
            authoritative: false,
            allowedActions: const [],
          );
        }
      }
      if (isCurrent(epoch)) {
        state = state.copyWith(error: handleRecoveryUiErrorFrom(error));
      }
    } finally {
      if (isCurrent(epoch)) state = state.copyWith(isBusy: false);
    }
  }

  Future<void> initialize({
    required String handle,
    String? localIdentityId,
    bool startNew = false,
  }) async {
    reset();
    _handle = handle;
    _localIdentityId = localIdentityId;
    await _run((epoch) async {
      await _refresh(epoch);
      if (isCurrent(epoch) &&
          startNew &&
          state.allows(HandleRecoveryAction.startNew)) {
        state = state.copyWith(
          clearOperation: true,
          clearPhone: true,
          riskConfirmed: false,
          allowedActions: const [HandleRecoveryAction.startNew],
        );
      }
    });
  }

  Future<void> restoreForOwner({
    required HandleRecoveryIdentityScope scope,
    required String handle,
  }) => initialize(handle: handle, localIdentityId: scope.localIdentityId);

  Future<void> requestOtp({
    required String handle,
    required String phone,
    String? localIdentityId,
  }) async {
    if (_handle != handle || _localIdentityId != localIdentityId) {
      await initialize(handle: handle, localIdentityId: localIdentityId);
    }
    if (!state.canRequestOtp) return;
    await _run((epoch) async {
      if (!await _otpCooldown.beginSend()) return;
      try {
        if (!isCurrent(epoch)) return;
        final receipt = await _service.requestOtp(
          handle: handle,
          phone: phone,
          localIdentityId: localIdentityId,
          expectedOperationId: state.progress?.operationId,
        );
        await _otpCooldown.completeAcceptedAt(receipt.retryAt);
        if (!isCurrent(epoch)) return;
        _accept(receipt.operation, epoch);
        state = state.copyWith(otpPhone: phone.trim(), riskConfirmed: false);
      } on HandleRecoveryOtpRateLimited catch (error) {
        await _otpCooldown.completeRateLimitedAt(error.retryAt);
        rethrow;
      } finally {
        _otpCooldown.completeFailed();
      }
    });
  }

  void _accept(HandleRecoveryProgress progress, int epoch) {
    if (!isCurrent(epoch)) return;
    if (progress.handle != _handle ||
        (state.progress != null &&
            progress.operationId != state.progress!.operationId)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.transitionMismatch,
      );
    }
    state = state.copyWith(
      progress: progress,
      owner: HandleRecoveryOwner(
        localIdentityId: progress.ownerIdentityId,
        handle: progress.handle,
      ),
      allowedActions: progress.allowedActions,
      authoritative: true,
      error: progress.failureCode == null
          ? null
          : handleRecoveryUiErrorFrom(
              HandleRecoveryFailure(progress.failureCode!),
            ),
      clearError: progress.failureCode == null,
    );
  }

  Future<void> prepare({required String phone, required String otp}) => _run((
    epoch,
  ) async {
    final progress = state.progress;
    if (progress == null || !state.allows(HandleRecoveryAction.prepare)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.actionNotAllowed,
      );
    }
    // The phone is transient. Reentry may verify the same operation with a new
    // factor without recovering the old phone from App storage.
    state = state.copyWith(riskConfirmed: false);
    _accept(
      await _service.prepare(
        operationId: progress.operationId,
        phone: phone,
        otp: otp,
      ),
      epoch,
    );
  });

  Future<void> activate({required String presenceReason}) async {
    final progress = state.progress;
    if (progress == null ||
        state.isBusy ||
        !state.allows(HandleRecoveryAction.activate)) {
      return;
    }
    if (!state.riskConfirmed) {
      state = state.copyWith(
        error: HandleRecoveryUiError.riskConfirmationRequired,
      );
      return;
    }
    await _run((epoch) async {
      try {
        _accept(
          await _service.activate(
            operationId: progress.operationId,
            presenceReason: presenceReason,
            isCurrent: () => isCurrent(epoch),
          ),
          epoch,
        );
      } catch (_) {
        if (!isCurrent(epoch)) return;
        await _refresh(epoch, expectedOperationId: progress.operationId);
        if (!isCurrent(epoch)) return;
        if (state.allows(HandleRecoveryAction.activateIdentity)) return;
        if (!state.allows(HandleRecoveryAction.resume)) rethrow;
        _accept(await _service.resume(progress.operationId), epoch);
      }
    });
  }

  Future<void> resume() => _run((epoch) async {
    final progress = state.progress;
    if (progress == null || !state.allows(HandleRecoveryAction.resume)) {
      throw const HandleRecoveryFailure(
        HandleRecoveryFailureCode.actionNotAllowed,
      );
    }
    _accept(await _service.resume(progress.operationId), epoch);
  });

  Future<void> discardPreAttempt() => _run((epoch) async {
    final progress = state.progress;
    if (progress == null ||
        !state.allows(HandleRecoveryAction.discardPreAttempt)) {
      return;
    }
    await _service.discardPreAttempt(progress.operationId);
    await _refresh(epoch);
    if (isCurrent(epoch) && state.allows(HandleRecoveryAction.startNew)) {
      state = state.copyWith(
        clearOperation: true,
        clearPhone: true,
        riskConfirmed: false,
      );
    }
  });

  Future<void> quarantineKeyUnavailable({required String presenceReason}) =>
      _run((epoch) async {
        final progress = state.progress;
        if (progress == null ||
            !state.allows(HandleRecoveryAction.quarantineKeyUnavailable)) {
          return;
        }
        await _service.quarantineKeyUnavailable(
          operationId: progress.operationId,
          presenceReason: presenceReason,
          isCurrent: () => isCurrent(epoch),
        );
        await _refresh(epoch);
      });

  void startAfterQuarantine() {
    if (!state.isBusy && state.allows(HandleRecoveryAction.startNew)) {
      _epoch++;
      state = state.copyWith(
        clearOperation: true,
        clearPhone: true,
        riskConfirmed: false,
      );
    }
  }
}

final handleRecoveryProvider =
    StateNotifierProvider<HandleRecoveryController, HandleRecoveryState>(
      (ref) => HandleRecoveryController(
        ref.watch(handleRecoveryServiceProvider),
        ref.watch(handleRecoverySmsOtpCooldownProvider.notifier),
      ),
    );
