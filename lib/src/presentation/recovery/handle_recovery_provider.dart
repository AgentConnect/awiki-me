// [INPUT]: Recovery service, active App identity, runtime activation, and UI actions.
// [OUTPUT]: Requester state plus secret-free old-admin notices for presentation.
// [POS]: Recovery presentation state; raw control payloads/checkpoints never enter UI.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/handle_recovery_service.dart';
import '../../application/models/app_session.dart';
import '../../application/models/handle_recovery_completion.dart';
import '../../domain/entities/handle_recovery.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';

const Object _unset = Object();

enum HandleRecoveryErrorKind {
  unavailable,
  expired,
  notReady,
  conflict,
  network,
  activation,
  rejected,
  failed,
}

class HandleRecoveryState {
  const HandleRecoveryState({
    this.sessions = const <HandleRecoveryProgress>[],
    this.oldAdminNotices = const <OldAdminRecoveryNotice>[],
    this.activeRequester,
    this.terminalRequester,
    this.activationPending,
    this.isLoading = false,
    this.isActionPending = false,
    this.reconfirmationOtpSent = false,
    this.error,
  });

  final List<HandleRecoveryProgress> sessions;
  final List<OldAdminRecoveryNotice> oldAdminNotices;

  /// A requester-side Recovery that may still transition remotely.
  final HandleRecoveryProgress? activeRequester;

  /// A just-observed cancelled/expired requester result shown for acknowledgement.
  final HandleRecoveryProgress? terminalRequester;

  /// Remote cutover is consumed; only local identity/E2EE activation may retry.
  final HandleRecoveryProgress? activationPending;
  final bool isLoading;
  final bool isActionPending;
  final bool reconfirmationOtpSent;
  final HandleRecoveryErrorKind? error;

  bool get isBusy => isLoading || isActionPending;

  List<HandleRecoveryProgress> get cancellableAdminSessions =>
      sessions.where((session) => session.canCancel).toList(growable: false);

  HandleRecoveryState copyWith({
    List<HandleRecoveryProgress>? sessions,
    List<OldAdminRecoveryNotice>? oldAdminNotices,
    Object? activeRequester = _unset,
    Object? terminalRequester = _unset,
    Object? activationPending = _unset,
    bool? isLoading,
    bool? isActionPending,
    bool? reconfirmationOtpSent,
    Object? error = _unset,
  }) {
    return HandleRecoveryState(
      sessions: sessions ?? this.sessions,
      oldAdminNotices: oldAdminNotices ?? this.oldAdminNotices,
      activeRequester: identical(activeRequester, _unset)
          ? this.activeRequester
          : activeRequester as HandleRecoveryProgress?,
      terminalRequester: identical(terminalRequester, _unset)
          ? this.terminalRequester
          : terminalRequester as HandleRecoveryProgress?,
      activationPending: identical(activationPending, _unset)
          ? this.activationPending
          : activationPending as HandleRecoveryProgress?,
      isLoading: isLoading ?? this.isLoading,
      isActionPending: isActionPending ?? this.isActionPending,
      reconfirmationOtpSent:
          reconfirmationOtpSent ?? this.reconfirmationOtpSent,
      error: identical(error, _unset)
          ? this.error
          : error as HandleRecoveryErrorKind?,
    );
  }
}

class HandleRecoveryController extends StateNotifier<HandleRecoveryState> {
  HandleRecoveryController(this.ref) : super(const HandleRecoveryState());

  final Ref ref;
  int _generation = 0;

  // Kept only between an already-consumed finalize and AppRuntime activation.
  // It is never placed in provider state and Core remains the restart authority.
  AppSession? _pendingActivationSession;

  bool get _enabled => ref.read(handleRecoveryEnabledProvider);

  bool _isCurrentOperation(int operation) =>
      mounted && operation == _generation;

  Future<void> restore() async {
    if (!_enabled || state.isBusy) return;
    final operation = ++_generation;
    _pendingActivationSession = null;
    state = state.copyWith(
      isLoading: true,
      isActionPending: false,
      error: null,
    );
    try {
      final service = ref.read(handleRecoveryServiceProvider);
      final oldDid = ref.read(sessionProvider).session?.did;
      final sessions = await service.restoreLocalRecoveries();
      final notices = oldDid == null
          ? const <OldAdminRecoveryNotice>[]
          : await service.restoreOldAdminNotices(oldDid);
      if (!_isCurrentOperation(operation)) return;
      if (oldDid != ref.read(sessionProvider).session?.did) {
        state = state.copyWith(
          oldAdminNotices: const <OldAdminRecoveryNotice>[],
          isLoading: false,
        );
        return;
      }
      state = state.copyWith(
        sessions: sessions,
        oldAdminNotices: notices,
        activeRequester: _singleActiveRequester(sessions),
        terminalRequester: null,
        activationPending: _singlePendingActivation(sessions),
        isLoading: false,
        reconfirmationOtpSent: false,
        error: null,
      );
    } catch (error) {
      if (!_isCurrentOperation(operation)) return;
      state = state.copyWith(
        sessions: const <HandleRecoveryProgress>[],
        oldAdminNotices: const <OldAdminRecoveryNotice>[],
        activeRequester: null,
        terminalRequester: null,
        activationPending: null,
        isLoading: false,
        error: _classifyRecoveryError(error),
      );
    }
  }

  Future<HandleRecoveryProgress> begin({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    _requireEnabled();
    if (state.isActionPending) {
      throw const HandleRecoveryException('recovery_action_in_progress');
    }
    final operation = ++_generation;
    _pendingActivationSession = null;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      reconfirmationOtpSent: false,
      error: null,
    );
    try {
      final progress = await ref
          .read(handleRecoveryServiceProvider)
          .beginWithSms(
            handle: handle,
            handleDomain: handleDomain,
            phone: phone,
            otp: otp,
          );
      if (_isCurrentOperation(operation)) {
        state = state.copyWith(
          sessions: _replaceRecovery(state.sessions, progress),
          activeRequester: progress,
          terminalRequester: null,
          activationPending: null,
          isLoading: false,
          isActionPending: false,
          error: null,
        );
      }
      return progress;
    } catch (error) {
      if (_isCurrentOperation(operation)) {
        state = state.copyWith(
          isLoading: false,
          isActionPending: false,
          error: _classifyRecoveryError(error),
        );
      }
      rethrow;
    }
  }

  Future<void> pollActive() async {
    final current = state.activeRequester;
    if (!_enabled ||
        current == null ||
        current.isTerminal ||
        state.isActionPending) {
      return;
    }
    final operation = ++_generation;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      error: null,
    );
    try {
      final progress = await ref
          .read(handleRecoveryServiceProvider)
          .poll(current);
      if (!_isCurrentOperation(operation)) return;
      _applyRequesterProgress(progress);
    } catch (error) {
      if (!_isCurrentOperation(operation)) return;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyRecoveryError(error),
      );
    }
  }

  Future<bool> sendReconfirmationOtp(String phone) async {
    _requireEnabled();
    final current = state.activeRequester;
    if (current == null || !current.canFinalize || state.isActionPending) {
      return false;
    }
    final operation = ++_generation;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      error: null,
    );
    try {
      await ref
          .read(handleRecoveryServiceProvider)
          .sendFinalizeSmsOtp(current: current, phone: phone);
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        isActionPending: false,
        reconfirmationOtpSent: true,
        error: null,
      );
      return true;
    } catch (error) {
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyRecoveryError(error),
      );
      return false;
    }
  }

  Future<bool> finalize({
    required String phone,
    required String otp,
    required bool intentConfirmed,
    required String presenceReason,
  }) async {
    _requireEnabled();
    final current = state.activeRequester;
    if (current == null ||
        !current.canFinalize ||
        !state.reconfirmationOtpSent ||
        state.isActionPending) {
      return false;
    }
    final operation = ++_generation;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      error: null,
    );
    HandleRecoveryCompletion completion;
    try {
      completion = await ref
          .read(handleRecoveryServiceProvider)
          .finalizeWithSms(
            current: current,
            phone: phone,
            otp: otp,
            intentConfirmed: intentConfirmed,
            presenceReason: presenceReason,
          );
    } catch (error) {
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyRecoveryError(error),
      );
      return false;
    }
    if (!_isCurrentOperation(operation)) return false;
    _pendingActivationSession = completion.session;
    state = state.copyWith(
      sessions: _replaceRecovery(state.sessions, completion.progress),
      activeRequester: null,
      terminalRequester: null,
      activationPending: completion.progress,
      isActionPending: true,
      reconfirmationOtpSent: false,
      error: null,
    );
    return _activatePending(completion.progress, operation);
  }

  Future<bool> retryActivation() async {
    _requireEnabled();
    final pending = state.activationPending;
    if (pending == null || state.isActionPending) return false;
    final operation = ++_generation;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      error: null,
    );
    return _activatePending(pending, operation);
  }

  Future<bool> cancel(
    HandleRecoveryProgress current, {
    required bool intentConfirmed,
    required String presenceReason,
  }) async {
    _requireEnabled();
    if (!current.canCancel || state.isActionPending) return false;
    final operation = ++_generation;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      error: null,
    );
    try {
      final progress = await ref
          .read(handleRecoveryServiceProvider)
          .cancel(
            current: current,
            intentConfirmed: intentConfirmed,
            presenceReason: presenceReason,
          );
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        sessions: _replaceRecovery(state.sessions, progress),
        isActionPending: false,
        error: null,
      );
      return true;
    } catch (error) {
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyRecoveryError(error),
      );
      return false;
    }
  }

  Future<bool> cancelOldAdminNotice(
    OldAdminRecoveryNotice notice, {
    required bool intentConfirmed,
    required String presenceReason,
  }) async {
    _requireEnabled();
    if (state.isActionPending) return false;
    final operation = ++_generation;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      error: null,
    );
    try {
      await ref
          .read(handleRecoveryServiceProvider)
          .cancelOldAdminNotice(
            notice: notice,
            intentConfirmed: intentConfirmed,
            presenceReason: presenceReason,
          );
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        oldAdminNotices: _removeOldAdminNotice(
          state.oldAdminNotices,
          notice.eventId,
        ),
        isActionPending: false,
        error: null,
      );
      return true;
    } catch (error) {
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        oldAdminNotices: _dropStaleNotice(error)
            ? _removeOldAdminNotice(state.oldAdminNotices, notice.eventId)
            : state.oldAdminNotices,
        isActionPending: false,
        error: _classifyRecoveryError(error),
      );
      return false;
    }
  }

  Future<bool> dismissOldAdminNotice(OldAdminRecoveryNotice notice) async {
    _requireEnabled();
    if (state.isActionPending) return false;
    final operation = ++_generation;
    state = state.copyWith(
      isLoading: false,
      isActionPending: true,
      error: null,
    );
    try {
      await ref
          .read(handleRecoveryServiceProvider)
          .dismissOldAdminNotice(notice);
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        oldAdminNotices: _removeOldAdminNotice(
          state.oldAdminNotices,
          notice.eventId,
        ),
        isActionPending: false,
        error: null,
      );
      return true;
    } catch (error) {
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        isActionPending: false,
        error: _classifyRecoveryError(error),
      );
      return false;
    }
  }

  void clearTerminalRequester() {
    if (state.terminalRequester == null || state.isBusy) return;
    _generation += 1;
    state = state.copyWith(terminalRequester: null, error: null);
  }

  Future<bool> _activatePending(
    HandleRecoveryProgress progress,
    int operation,
  ) async {
    if (!_isCurrentOperation(operation)) return false;
    try {
      if (!_isRuntimeActivated(progress)) {
        final service = ref.read(handleRecoveryServiceProvider);
        final runtime = ref.read(appRuntimeProvider.notifier);
        await runtime.prepareIdentityActivation();
        final candidate =
            _pendingActivationSession ??
            await service.resumeActivation(progress);
        _pendingActivationSession = candidate;
        final session = await service.activateLocalIdentity(
          current: progress,
          candidate: candidate,
        );
        await runtime.activateSession(session.toLegacySessionIdentity());
        if (!_isRuntimeActivated(progress)) {
          throw const HandleRecoveryException(
            'recovery_runtime_activation_mismatch',
          );
        }
      }
      _pendingActivationSession = null;
      await ref
          .read(handleRecoveryServiceProvider)
          .markActivationComplete(progress);
      if (!_isCurrentOperation(operation)) return false;
      _pendingActivationSession = null;
      state = state.copyWith(
        sessions: _removeRecovery(state.sessions, progress.recoverySessionId),
        activationPending: null,
        isActionPending: false,
        error: null,
      );
      return true;
    } catch (_) {
      if (!_isCurrentOperation(operation)) return false;
      final runtimeActivated = _isRuntimeActivated(progress);
      _pendingActivationSession = null;
      if (!runtimeActivated) {
        await ref
            .read(appRuntimeProvider.notifier)
            .rollbackIdentityActivation();
      }
      if (!_isCurrentOperation(operation)) return false;
      state = state.copyWith(
        activationPending: progress,
        isActionPending: false,
        error: HandleRecoveryErrorKind.activation,
      );
      return false;
    }
  }

  bool _isRuntimeActivated(HandleRecoveryProgress progress) {
    final newDid = progress.newDid;
    if (newDid == null || newDid == progress.oldDid) return false;
    return ref.read(appRuntimeProvider).activatedDid == newDid &&
        ref.read(sessionProvider).session?.did == newDid;
  }

  void _applyRequesterProgress(HandleRecoveryProgress progress) {
    final sessions = _replaceRecovery(state.sessions, progress);
    if (!progress.isTerminal) {
      state = state.copyWith(
        sessions: sessions,
        activeRequester: progress,
        terminalRequester: null,
        isActionPending: false,
        error: null,
      );
      return;
    }
    if (progress.localActivationPending) {
      state = state.copyWith(
        sessions: sessions,
        activeRequester: null,
        terminalRequester: null,
        activationPending: progress,
        isActionPending: false,
        error: null,
      );
      return;
    }
    state = state.copyWith(
      sessions: sessions,
      activeRequester: null,
      terminalRequester:
          progress.phase == HandleRecoveryPhase.cancelled ||
              progress.phase == HandleRecoveryPhase.expired
          ? progress
          : null,
      isActionPending: false,
      reconfirmationOtpSent: false,
      error: null,
    );
  }

  void _requireEnabled() {
    if (!_enabled) {
      throw const HandleRecoveryException('handle_recovery_unavailable');
    }
  }
}

final handleRecoveryProvider =
    StateNotifierProvider<HandleRecoveryController, HandleRecoveryState>(
      (ref) => HandleRecoveryController(ref),
    );

List<HandleRecoveryProgress> _replaceRecovery(
  List<HandleRecoveryProgress> sessions,
  HandleRecoveryProgress replacement,
) {
  return <HandleRecoveryProgress>[
    for (final session in sessions)
      if (session.recoverySessionId != replacement.recoverySessionId) session,
    replacement,
  ];
}

List<HandleRecoveryProgress> _removeRecovery(
  List<HandleRecoveryProgress> sessions,
  String recoverySessionId,
) {
  return sessions
      .where((session) => session.recoverySessionId != recoverySessionId)
      .toList(growable: false);
}

List<OldAdminRecoveryNotice> _removeOldAdminNotice(
  List<OldAdminRecoveryNotice> notices,
  String eventId,
) => notices
    .where((notice) => notice.eventId != eventId)
    .toList(growable: false);

bool _dropStaleNotice(Object error) {
  if (error is! HandleRecoveryException) return false;
  return error.code == 'recovery_notice_unavailable' ||
      error.code.contains('expired');
}

HandleRecoveryProgress? _singleActiveRequester(
  List<HandleRecoveryProgress> sessions,
) {
  final matches = sessions
      .where(
        (session) =>
            session.side == HandleRecoverySide.requester && !session.isTerminal,
      )
      .toList(growable: false);
  return matches.isEmpty ? null : matches.single;
}

HandleRecoveryProgress? _singlePendingActivation(
  List<HandleRecoveryProgress> sessions,
) {
  final matches = sessions
      .where((session) => session.localActivationPending)
      .toList(growable: false);
  return matches.isEmpty ? null : matches.single;
}

HandleRecoveryErrorKind _classifyRecoveryError(Object error) {
  final code = switch (error) {
    HandleRecoveryException(:final code) => code,
    _ => error.toString().toLowerCase(),
  };
  if (code.contains('disabled') || code.contains('unavailable')) {
    return HandleRecoveryErrorKind.unavailable;
  }
  if (code.contains('expired')) return HandleRecoveryErrorKind.expired;
  if (code.contains('cooling') || code.contains('not_ready')) {
    return HandleRecoveryErrorKind.notReady;
  }
  if (code.contains('presence') || code.contains('intent')) {
    return HandleRecoveryErrorKind.rejected;
  }
  if (code.contains('conflict') ||
      code.contains('mismatch') ||
      code.contains('multiple_active')) {
    return HandleRecoveryErrorKind.conflict;
  }
  if (code.contains('network') ||
      code.contains('socket') ||
      code.contains('timeout')) {
    return HandleRecoveryErrorKind.network;
  }
  return HandleRecoveryErrorKind.failed;
}
