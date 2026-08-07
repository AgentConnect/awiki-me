import '../core/app_error_classifier.dart';
import '../domain/entities/device_management.dart';
import 'models/device_revoke_outcome.dart';
import 'ports/device_management_core_port.dart';
import 'ports/user_presence_port.dart';

class DeviceManagementException implements Exception {
  const DeviceManagementException(this.code);

  final String code;

  @override
  String toString() => 'DeviceManagementException($code)';
}

class DeviceManagementService {
  DeviceManagementService({
    required DeviceManagementCorePort core,
    required UserPresencePort userPresence,
    DateTime Function()? now,
  }) : _core = core,
       _userPresence = userPresence,
       _now = now ?? DateTime.now;

  final DeviceManagementCorePort _core;
  final UserPresencePort _userPresence;
  final DateTime Function() _now;
  final Set<String> _approvalSessionsInFlight = <String>{};
  final Set<String> _revokeDeviceIdsInFlight = <String>{};

  Future<DeviceJoinSmsOtpSendReceipt> sendJoinSmsOtp({
    required String handle,
    required String phone,
  }) {
    return _core.sendJoinSmsOtp(
      handle: _required(handle, 'handle').toLowerCase(),
      phone: _required(phone, 'phone'),
    );
  }

  Future<String> resolveNewDeviceJoinDid(String handle) async {
    final did = await _core.resolveJoinDid(
      _required(handle, 'handle').toLowerCase(),
    );
    if (!did.startsWith('did:wba:') || did.trim() != did) {
      throw const DeviceManagementException('invalid_join_target_did');
    }
    return did;
  }

  Future<DeviceRegistrySnapshot> loadRegistry(String selector) async {
    return _core.identityDeviceRegistry(_required(selector, 'selector'));
  }

  Future<List<DeviceJoinProgress>> restoreLocalJoins() async {
    final sessions = await _core.localDeviceJoinSessions();
    for (final session in sessions) {
      _validateProgress(session);
    }
    return sessions;
  }

  Future<bool> canResumeAuthorizedNewDeviceJoin(
    DeviceJoinProgress progress,
  ) async {
    _validateProgress(progress);
    if (progress.side != DeviceJoinSide.newDevice ||
        progress.phase != DeviceJoinPhase.authorized) {
      return false;
    }
    if (!progress.expiresAt.isAfter(_now().toUtc())) {
      return false;
    }
    final hasExactLocalBinding = await _core.localIdentityMatchesDevice(
      did: _required(progress.did, 'did'),
      protocolDeviceId: _required(
        progress.protocolDeviceId,
        'protocolDeviceId',
      ),
    );
    if (!hasExactLocalBinding) {
      return false;
    }
    late final DeviceRegistrySnapshot registry;
    try {
      registry = await _core.identityDeviceRegistry(progress.did);
    } catch (error) {
      final kind = classifyAppError(error);
      if (kind == AppErrorKind.authentication ||
          kind == AppErrorKind.didNotFoundOrRevoked) {
        return false;
      }
      rethrow;
    }
    final current = registry.currentDevice;
    return registry.did == progress.did &&
        current != null &&
        current.protocolDeviceId == progress.protocolDeviceId &&
        current.status == DeviceStatus.active &&
        current.role == DeviceRole.member &&
        !current.managementReady;
  }

  Future<List<DeviceJoinRequestNotice>> restoreAdminJoinRequests(
    String selector,
  ) async {
    final requests = await _core.localDeviceJoinRequests(
      _required(selector, 'selector'),
    );
    for (final request in requests) {
      _validateRequest(request);
    }
    return requests;
  }

  Future<DeviceJoinProgress> restoreAdminVerificationProgress({
    required String selector,
    required String joinSessionId,
  }) async {
    final progress = await _core.localDeviceJoinVerificationProgress(
      selector: _required(selector, 'selector'),
      joinSessionId: _requiredJoinSessionId(joinSessionId),
    );
    _validateProgress(progress);
    if (progress.side != DeviceJoinSide.admin) {
      throw const DeviceManagementException('invalid_admin_join_progress');
    }
    return progress;
  }

  Future<DeviceRevokeResult> revoke({
    required String selector,
    required String targetDeviceId,
    required String presenceReason,
  }) async {
    final normalizedSelector = _required(selector, 'selector');
    final normalizedTarget = _required(targetDeviceId, 'targetDeviceId');
    if (!_revokeDeviceIdsInFlight.add(normalizedTarget)) {
      throw const DeviceManagementException('revoke_already_in_progress');
    }
    try {
      final confirmed = await _userPresence.confirm(
        reason: _required(presenceReason, 'presenceReason'),
      );
      if (!confirmed) {
        throw const DeviceRevokeException(
          DeviceRevokeOutcomeCategory.cancelledBeforeSubmit,
          code: 'user_presence_denied',
        );
      }
      final result = await _core.revokeDevice(
        selector: normalizedSelector,
        targetDeviceId: normalizedTarget,
        userPresenceConfirmed: true,
      );
      if (result.did != normalizedSelector ||
          result.targetDeviceId != normalizedTarget ||
          result.status != DeviceRevokeStatus.revoked) {
        throw const DeviceManagementException('invalid_revoke_result');
      }
      return result;
    } finally {
      _revokeDeviceIdsInFlight.remove(normalizedTarget);
    }
  }

  Future<DeviceJoinProgress> beginNewDeviceJoinWithSms({
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
    int ttlSeconds = 600,
  }) async {
    final normalizedHandle = _required(handle, 'handle').toLowerCase();
    final progress = await _core.beginDeviceJoinWithSms(
      handle: normalizedHandle,
      phone: _required(phone, 'phone'),
      otp: _required(otp, 'otp'),
      operationId: _required(operationId, 'operationId'),
      ttlSeconds: ttlSeconds,
    );
    _validateProgress(progress);
    return progress;
  }

  Future<DeviceJoinProgress> startVerification({
    required String selector,
    required String joinSessionId,
    required String operationId,
    int challengeTtlSeconds = 240,
  }) async {
    final result = await _core.startDeviceJoinVerification(
      selector: _required(selector, 'selector'),
      joinSessionId: _requiredJoinSessionId(joinSessionId),
      operationId: _required(operationId, 'operationId'),
      challengeTtlSeconds: challengeTtlSeconds,
    );
    _validateProgress(result);
    if (result.side != DeviceJoinSide.admin) {
      throw const DeviceManagementException('invalid_admin_join_progress');
    }
    return result;
  }

  Future<DeviceJoinProgress> pollNewDeviceJoin({
    required DeviceJoinProgress progress,
  }) async {
    _validateProgress(progress);
    if (progress.side != DeviceJoinSide.newDevice) {
      throw const DeviceManagementException('invalid_new_device_join_progress');
    }
    final next = await _core.pollNewDeviceJoin(progress.joinSessionId);
    _validateProgress(next);
    if (next.side != DeviceJoinSide.newDevice ||
        next.joinSessionId != progress.joinSessionId ||
        next.did != progress.did ||
        next.protocolDeviceId != progress.protocolDeviceId) {
      throw const DeviceManagementException('invalid_new_device_join_progress');
    }
    if (progress.phase == DeviceJoinPhase.authorized &&
        next.phase != DeviceJoinPhase.authorized) {
      throw const DeviceManagementException(
        'invalid_authorized_device_projection',
      );
    }
    if (next.phase == DeviceJoinPhase.authorized &&
        (next.authorizedDevice == null ||
            next.authorizedDevice!.protocolDeviceId != next.protocolDeviceId)) {
      throw const DeviceManagementException(
        'missing_authorized_device_projection',
      );
    }
    return next;
  }

  Future<DeviceJoinProgress> cancelNewDeviceJoin({
    required DeviceJoinProgress progress,
  }) async {
    _validateProgress(progress);
    if (progress.side != DeviceJoinSide.newDevice) {
      throw const DeviceManagementException('invalid_new_device_join_progress');
    }
    final next = await _core.cancelNewDeviceJoin(progress.joinSessionId);
    _validateProgress(next);
    if (next.side != DeviceJoinSide.newDevice) {
      throw const DeviceManagementException('invalid_new_device_join_progress');
    }
    return next;
  }

  Future<DeviceJoinProgress> approveAsMember({
    required String selector,
    required DeviceJoinProgress progress,
    required String displayedSas,
    required bool sasConfirmed,
    required String presenceReason,
  }) async {
    _validateProgress(progress);
    if (!sasConfirmed || !_isSixDigitSas(displayedSas)) {
      throw const DeviceManagementException('sas_not_confirmed');
    }
    if (progress.side != DeviceJoinSide.admin ||
        progress.phase != DeviceJoinPhase.responseVerified ||
        progress.sas != displayedSas) {
      throw const DeviceManagementException('join_not_ready_for_approval');
    }
    if (!_approvalSessionsInFlight.add(progress.joinSessionId)) {
      throw const DeviceManagementException('approval_already_in_progress');
    }
    try {
      final prompt = await _core.prepareDeviceJoinApproval(
        selector: _required(selector, 'selector'),
        joinSessionId: progress.joinSessionId,
        sasConfirmed: true,
      );
      if (prompt.joinSessionId != progress.joinSessionId ||
          prompt.sas != displayedSas ||
          !_isSixDigitSas(prompt.sas)) {
        throw const DeviceManagementException('approval_prompt_mismatch');
      }

      final confirmed = await _userPresence.confirm(
        reason: _required(presenceReason, 'presenceReason'),
      );
      if (!confirmed) {
        try {
          await _core.confirmDeviceJoinApproval(
            approvalHandle: _required(prompt.approvalHandle, 'approvalHandle'),
            userPresenceConfirmed: false,
          );
        } on Object {
          // The handle is fail-closed in Core. Do not surface an implementation
          // error in place of the user's explicit rejection.
        }
        throw const DeviceManagementException('user_presence_denied');
      }
      final result = await _core.confirmDeviceJoinApproval(
        approvalHandle: _required(prompt.approvalHandle, 'approvalHandle'),
        userPresenceConfirmed: true,
      );
      _validateProgress(result);
      return result;
    } finally {
      _approvalSessionsInFlight.remove(progress.joinSessionId);
    }
  }

  Future<DeviceJoinProgress> rejectJoin({
    required String selector,
    required String joinSessionId,
    required DeviceJoinRejectReason reason,
  }) async {
    final progress = await _core.rejectDeviceJoin(
      selector: _required(selector, 'selector'),
      joinSessionId: _requiredJoinSessionId(joinSessionId),
      reason: reason,
    );
    _validateProgress(progress);
    if (progress.side != DeviceJoinSide.admin ||
        progress.remoteState != DeviceJoinRemoteState.rejected) {
      throw const DeviceManagementException('invalid_reject_result');
    }
    return progress;
  }
}

void _validateProgress(DeviceJoinProgress progress) {
  _requiredJoinSessionId(progress.joinSessionId);
  _required(progress.did, 'did');
  _required(progress.protocolDeviceId, 'protocolDeviceId');
  final authorized = progress.authorizedDevice;
  if (authorized != null &&
      authorized.protocolDeviceId != progress.protocolDeviceId) {
    throw const DeviceManagementException(
      'invalid_authorized_device_projection',
    );
  }
  final sas = progress.sas;
  if (sas != null && !_isSixDigitSas(sas)) {
    throw const DeviceManagementException('invalid_sas_projection');
  }
}

void _validateRequest(DeviceJoinRequestNotice request) {
  _required(request.eventId, 'eventId');
  _requiredJoinSessionId(request.joinSessionId);
  _required(request.did, 'did');
  _required(request.protocolDeviceId, 'protocolDeviceId');
  _required(request.candidateKeyFingerprint, 'candidateKeyFingerprint');
  if (!request.expiresAt.isAfter(request.issuedAt)) {
    throw const DeviceManagementException('invalid_join_request_time');
  }
}

bool _isSixDigitSas(String value) {
  if (value.length != 6) {
    return false;
  }
  return value.codeUnits.every((codeUnit) => codeUnit >= 48 && codeUnit <= 57);
}

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw DeviceManagementException('invalid_$field');
  }
  return normalized;
}

String _requiredJoinSessionId(String value) {
  if (!isCanonicalDeviceJoinSessionId(value)) {
    throw const DeviceManagementException('invalid_joinSessionId');
  }
  return value;
}
