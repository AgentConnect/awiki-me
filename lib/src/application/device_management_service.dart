import '../domain/entities/device_management.dart';
import 'directory_application_service.dart';
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
    required DirectoryApplicationService directory,
    required UserPresencePort userPresence,
  }) : _core = core,
       _directory = directory,
       _userPresence = userPresence;

  final DeviceManagementCorePort _core;
  final DirectoryApplicationService _directory;
  final UserPresencePort _userPresence;
  final Set<String> _approvalSessionsInFlight = <String>{};

  Future<void> sendJoinSmsOtp(String phone) {
    return _core.sendJoinSmsOtp(_required(phone, 'phone'));
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

  Future<DeviceJoinProgress> beginNewDeviceJoinWithSms({
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
    int ttlSeconds = 600,
  }) async {
    final normalizedHandle = _required(handle, 'handle').toLowerCase();
    final resolution = await _directory.lookupHandle(normalizedHandle);
    final progress = await _core.beginDeviceJoinWithSms(
      did: _required(resolution.did, 'did'),
      handle: normalizedHandle,
      phone: _required(phone, 'phone'),
      otp: _required(otp, 'otp'),
      operationId: _required(operationId, 'operationId'),
      ttlSeconds: ttlSeconds,
    );
    _validateProgress(progress);
    return progress;
  }

  Future<DeviceJoinProgress> claim({
    required String selector,
    required String joinSessionId,
    required String operationId,
    int challengeTtlSeconds = 300,
  }) async {
    final result = await _core.claimDeviceJoin(
      selector: _required(selector, 'selector'),
      joinSessionId: _required(joinSessionId, 'joinSessionId'),
      operationId: _required(operationId, 'operationId'),
      challengeTtlSeconds: challengeTtlSeconds,
    );
    _validateProgress(result);
    return result;
  }

  Future<DeviceJoinProgress> poll({
    required String selector,
    required DeviceJoinProgress progress,
  }) async {
    _validateProgress(progress);
    final result = switch (progress.side) {
      DeviceJoinSide.newDevice => _core.pollNewDeviceJoin(
        progress.joinSessionId,
      ),
      DeviceJoinSide.admin => _core.pollAdminDeviceJoin(
        selector: _required(selector, 'selector'),
        joinSessionId: progress.joinSessionId,
      ),
    };
    final next = await result;
    _validateProgress(next);
    return next;
  }

  Future<DeviceJoinProgress> cancel({
    required String selector,
    required DeviceJoinProgress progress,
  }) async {
    _validateProgress(progress);
    final result = switch (progress.side) {
      DeviceJoinSide.newDevice => _core.cancelNewDeviceJoin(
        progress.joinSessionId,
      ),
      DeviceJoinSide.admin => _core.cancelAdminDeviceJoin(
        selector: _required(selector, 'selector'),
        joinSessionId: progress.joinSessionId,
      ),
    };
    final next = await result;
    _validateProgress(next);
    return next;
  }

  Future<DeviceJoinProgress> approve({
    required String selector,
    required DeviceJoinProgress progress,
    required String displayedSas,
    required DeviceRole role,
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
        role: role,
        sasConfirmed: true,
      );
      if (prompt.joinSessionId != progress.joinSessionId ||
          prompt.role != role ||
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
}

void _validateProgress(DeviceJoinProgress progress) {
  _required(progress.joinSessionId, 'joinSessionId');
  _required(progress.did, 'did');
  _required(progress.protocolDeviceId, 'protocolDeviceId');
  final sas = progress.sas;
  if (sas != null && !_isSixDigitSas(sas)) {
    throw const DeviceManagementException('invalid_sas_projection');
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
