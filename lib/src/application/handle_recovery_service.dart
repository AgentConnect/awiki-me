import '../domain/entities/handle_recovery.dart';
import 'app_session_service.dart';
import 'models/app_session.dart';
import 'models/handle_recovery_completion.dart';
import 'ports/handle_recovery_port.dart';
import 'ports/user_presence_port.dart';

class HandleRecoveryException implements Exception {
  const HandleRecoveryException(this.code);

  final String code;

  @override
  String toString() => 'HandleRecoveryException($code)';
}

class HandleRecoveryService {
  const HandleRecoveryService({
    required HandleRecoveryPort recovery,
    required UserPresencePort userPresence,
    required AppSessionService sessions,
  }) : _recovery = recovery,
       _userPresence = userPresence,
       _sessions = sessions;

  final HandleRecoveryPort _recovery;
  final UserPresencePort _userPresence;
  final AppSessionService _sessions;

  Future<void> sendBeginSmsOtp({
    required String handle,
    required String handleDomain,
    required String phone,
  }) {
    return _recovery.sendRecoveryBeginSmsOtp(
      phone: _required(phone, 'phone'),
      handle: _normalizeHandle(handle),
      handleDomain: _normalizeDomain(handleDomain),
    );
  }

  Future<void> sendFinalizeSmsOtp({
    required HandleRecoveryProgress current,
    required String phone,
  }) {
    _validateProgress(current);
    if (!current.canFinalize) {
      throw const HandleRecoveryException('recovery_not_ready');
    }
    return _recovery.sendRecoveryFinalizeSmsOtp(
      phone: _required(phone, 'phone'),
      handle: current.handle,
      handleDomain: current.handleDomain,
      recoverySessionId: current.recoverySessionId,
    );
  }

  Future<List<HandleRecoveryProgress>> restoreLocalRecoveries() async {
    final sessions = await _recovery.localHandleRecoverySessions();
    final recoveryIds = <String>{};
    for (final session in sessions) {
      _validateProgress(session);
      if (!recoveryIds.add(session.recoverySessionId)) {
        throw const HandleRecoveryException('duplicate_recovery_projection');
      }
    }
    final activeRequesters = sessions.where(
      (session) =>
          session.side == HandleRecoverySide.requester && !session.isTerminal,
    );
    final pendingActivations = sessions.where(
      (session) => session.localActivationPending,
    );
    if (activeRequesters.length > 1 ||
        pendingActivations.length > 1 ||
        activeRequesters.isNotEmpty && pendingActivations.isNotEmpty) {
      throw const HandleRecoveryException('multiple_active_recoveries');
    }
    return sessions;
  }

  Future<HandleRecoveryProgress> beginWithSms({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    final normalizedHandle = _normalizeHandle(handle);
    final normalizedDomain = _normalizeDomain(handleDomain);
    final progress = await _recovery.beginHandleRecoveryWithSms(
      handle: normalizedHandle,
      handleDomain: normalizedDomain,
      phone: _required(phone, 'phone'),
      otp: _required(otp, 'otp'),
    );
    _validateProgress(progress);
    if (progress.side != HandleRecoverySide.requester ||
        progress.phase != HandleRecoveryPhase.cooling ||
        progress.handle != normalizedHandle ||
        progress.handleDomain != normalizedDomain) {
      throw const HandleRecoveryException('invalid_begin_projection');
    }
    return progress;
  }

  Future<HandleRecoveryProgress> poll(HandleRecoveryProgress current) async {
    _validateProgress(current);
    if (current.isTerminal) return current;
    final progress = await _recovery.pollHandleRecovery(
      current.recoverySessionId,
    );
    _validateSameRecovery(current, progress);
    _validateTransition(current.phase, progress.phase);
    return progress;
  }

  Future<HandleRecoveryProgress> cancel({
    required HandleRecoveryProgress current,
    required bool intentConfirmed,
    required String presenceReason,
  }) async {
    _validateProgress(current);
    if (!intentConfirmed) {
      throw const HandleRecoveryException('recovery_intent_not_confirmed');
    }
    if (!current.canCancel) {
      throw const HandleRecoveryException('recovery_not_cancellable');
    }
    final normalizedPresenceReason = _required(
      presenceReason,
      'presenceReason',
    );
    final present = await _userPresence.confirm(
      reason: normalizedPresenceReason,
    );
    if (!present) {
      throw const HandleRecoveryException('user_presence_denied');
    }
    final result = await _recovery.cancelHandleRecovery(
      selector: current.oldDid,
      recoverySessionId: current.recoverySessionId,
    );
    if (result.recoverySessionId != current.recoverySessionId) {
      throw const HandleRecoveryException('recovery_projection_mismatch');
    }
    _validateTransition(current.phase, result.phase);
    if (result.phase != HandleRecoveryPhase.cancelled) {
      throw const HandleRecoveryException('invalid_cancel_projection');
    }
    return HandleRecoveryProgress(
      recoverySessionId: current.recoverySessionId,
      handle: current.handle,
      handleDomain: current.handleDomain,
      oldDid: current.oldDid,
      side: current.side,
      phase: result.phase,
      coolingUntil: current.coolingUntil,
      expiresAt: current.expiresAt,
      canCancelFromThisDevice: false,
      newDid: current.newDid,
      localActivationPending: current.localActivationPending,
    );
  }

  Future<HandleRecoveryCompletion> finalizeWithSms({
    required HandleRecoveryProgress current,
    required String phone,
    required String otp,
    required bool intentConfirmed,
    required String presenceReason,
  }) async {
    _validateProgress(current);
    if (!intentConfirmed) {
      throw const HandleRecoveryException('recovery_intent_not_confirmed');
    }
    if (!current.canFinalize) {
      throw const HandleRecoveryException('recovery_not_ready');
    }
    final normalizedPhone = _required(phone, 'phone');
    final normalizedOtp = _required(otp, 'otp');
    final normalizedPresenceReason = _required(
      presenceReason,
      'presenceReason',
    );
    final present = await _userPresence.confirm(
      reason: normalizedPresenceReason,
    );
    if (!present) {
      throw const HandleRecoveryException('user_presence_denied');
    }
    final completion = await _recovery.finalizeHandleRecoveryWithSms(
      recoverySessionId: current.recoverySessionId,
      handle: current.handle,
      handleDomain: current.handleDomain,
      phone: normalizedPhone,
      otp: normalizedOtp,
    );
    if (completion.progress.newDid?.trim() == current.oldDid.trim() ||
        completion.session.did.trim() == current.oldDid.trim()) {
      throw const HandleRecoveryException('invalid_finalize_projection');
    }
    _validateSameRecovery(current, completion.progress);
    _validateTransition(current.phase, completion.progress.phase);
    final newDid = _required(
      completion.progress.newDid ?? completion.session.did,
      'newDid',
    );
    _required(completion.session.identityId, 'identityId');
    if (completion.progress.phase != HandleRecoveryPhase.consumed ||
        !completion.progress.localActivationPending ||
        !completion.session.authenticated ||
        newDid == current.oldDid ||
        completion.session.did != newDid) {
      throw const HandleRecoveryException('invalid_finalize_projection');
    }
    return completion;
  }

  Future<AppSession> resumeActivation(HandleRecoveryProgress current) async {
    _validateProgress(current);
    if (!current.localActivationPending) {
      throw const HandleRecoveryException('recovery_activation_not_pending');
    }
    final session = await _recovery.resumeRecoveryActivation(
      current.recoverySessionId,
    );
    _validateActivationSession(current, session);
    return session;
  }

  Future<AppSession> activateLocalIdentity({
    required HandleRecoveryProgress current,
    required AppSession candidate,
  }) async {
    _validateProgress(current);
    _validateActivationSession(current, candidate);
    // The cutover revoked the old DID. Clear its local active pointer before
    // selecting and authenticating the replacement identity through the
    // normal AppSessionService path.
    await _sessions.logout();
    final activated = await _sessions.activateIdentity(candidate);
    _validateActivationSession(current, activated);
    return activated;
  }

  Future<void> markActivationComplete(HandleRecoveryProgress current) {
    _validateProgress(current);
    if (!current.localActivationPending) {
      throw const HandleRecoveryException('recovery_activation_not_pending');
    }
    return _recovery.markRecoveryActivationComplete(current.recoverySessionId);
  }
}

void _validateActivationSession(
  HandleRecoveryProgress progress,
  AppSession session,
) {
  _required(session.identityId, 'identityId');
  final newDid = _required(progress.newDid ?? '', 'newDid');
  if (newDid == progress.oldDid ||
      !session.authenticated ||
      session.did != newDid) {
    throw const HandleRecoveryException('invalid_activation_projection');
  }
}

void _validateTransition(
  HandleRecoveryPhase current,
  HandleRecoveryPhase next,
) {
  final allowed = switch (current) {
    HandleRecoveryPhase.cooling => <HandleRecoveryPhase>{
      HandleRecoveryPhase.cooling,
      HandleRecoveryPhase.ready,
      HandleRecoveryPhase.cancelled,
      HandleRecoveryPhase.expired,
    },
    HandleRecoveryPhase.ready => <HandleRecoveryPhase>{
      HandleRecoveryPhase.ready,
      HandleRecoveryPhase.cancelled,
      HandleRecoveryPhase.expired,
      HandleRecoveryPhase.consumed,
    },
    HandleRecoveryPhase.cancelled => const <HandleRecoveryPhase>{
      HandleRecoveryPhase.cancelled,
    },
    HandleRecoveryPhase.expired => const <HandleRecoveryPhase>{
      HandleRecoveryPhase.expired,
    },
    HandleRecoveryPhase.consumed => const <HandleRecoveryPhase>{
      HandleRecoveryPhase.consumed,
    },
  };
  if (!allowed.contains(next)) {
    throw const HandleRecoveryException('invalid_recovery_transition');
  }
}

void _validateSameRecovery(
  HandleRecoveryProgress current,
  HandleRecoveryProgress next,
) {
  _validateProgress(next);
  if (next.recoverySessionId != current.recoverySessionId ||
      next.handle != current.handle ||
      next.handleDomain != current.handleDomain ||
      next.oldDid != current.oldDid ||
      next.side != current.side) {
    throw const HandleRecoveryException('recovery_projection_mismatch');
  }
}

void _validateProgress(HandleRecoveryProgress progress) {
  _required(progress.recoverySessionId, 'recoverySessionId');
  if (progress.handle != _normalizeHandle(progress.handle) ||
      progress.handleDomain != _normalizeDomain(progress.handleDomain)) {
    throw const HandleRecoveryException('invalid_handle_projection');
  }
  _required(progress.oldDid, 'oldDid');
  if (!progress.expiresAt.isAfter(progress.coolingUntil)) {
    throw const HandleRecoveryException('invalid_recovery_window');
  }
  if (progress.canCancelFromThisDevice &&
      progress.side != HandleRecoverySide.oldAdmin) {
    throw const HandleRecoveryException('invalid_cancel_projection');
  }
  if (progress.localActivationPending &&
      (progress.side != HandleRecoverySide.requester ||
          progress.phase != HandleRecoveryPhase.consumed ||
          progress.newDid == null ||
          progress.newDid!.trim().isEmpty ||
          progress.newDid!.trim() == progress.oldDid.trim())) {
    throw const HandleRecoveryException('invalid_activation_projection');
  }
}

String _normalizeHandle(String value) {
  final normalized = _required(value, 'handle').toLowerCase();
  if (normalized.length > 63 ||
      normalized.startsWith('-') ||
      normalized.endsWith('-') ||
      normalized.codeUnits.any(
        (unit) =>
            !((unit >= 97 && unit <= 122) ||
                (unit >= 48 && unit <= 57) ||
                unit == 45),
      )) {
    throw const HandleRecoveryException('invalid_handle');
  }
  return normalized;
}

String _normalizeDomain(String value) =>
    _required(value, 'handleDomain').toLowerCase();

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw HandleRecoveryException('invalid_$field');
  }
  return normalized;
}
