import '../domain/entities/pin_recovery.dart';
import 'ports/pin_recovery_core_port.dart';
import 'ports/user_presence_port.dart';

/// Transient user intent only; never persists PIN, phone sessions, or progress.
class PinRecoveryService {
  PinRecoveryService({
    required PinRecoveryCorePort core,
    required UserPresencePort userPresence,
  }) : _core = core,
       _presence = userPresence;
  final PinRecoveryCorePort _core;
  final UserPresencePort _presence;
  bool get isAvailable => _core.tenantId != null;
  Future<bool> canBackup(String identityId) => _core.canBackup(identityId);
  Future<PinBackupStatus> backupStatus(String identityId) =>
      _core.backupStatus(identityId);
  Future<PinPhoneChallenge> requestPhoneCode(
    String phone, {
    String? resumeOperationId,
  }) {
    if (!isAvailable) throw const PinRecoveryFailure('not_configured');
    if (phone.trim().isEmpty) throw const PinRecoveryFailure('phone_required');
    return _core.requestPhoneCode(
      phone.trim(),
      resumeOperationId: resumeOperationId,
    );
  }

  Future<({String discoveryHandle, List<PinRecoveryTarget> targets})> verify({
    required String challengeHandle,
    required String code,
  }) async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const PinRecoveryFailure('otp_invalid');
    }
    final discovery = await _core.verifyPhoneCode(
      challengeHandle: challengeHandle,
      code: code,
    );
    return (
      discoveryHandle: discovery,
      targets: await _core.listTargets(discovery),
    );
  }

  Future<String> select(String discoveryHandle, PinRecoveryTarget target) =>
      _core.selectTarget(
        discoveryHandle: discoveryHandle,
        targetId: target.targetId,
      );
  Future<PinRecoveryProgress> beginEnable({
    required String sessionHandle,
    required String localIdentityId,
    required String presenceReason,
    bool Function()? isCurrent,
  }) async {
    if (!await _presence.confirm(reason: presenceReason)) {
      throw const PinRecoveryFailure('user_presence_required');
    }
    if (isCurrent?.call() == false) {
      throw const PinRecoveryFailure('action_not_allowed');
    }
    return _core.beginEnable(
      sessionHandle: sessionHandle,
      localIdentityId: localIdentityId,
      userPresenceConfirmed: true,
    );
  }

  Future<PinRecoveryProgress> beginRecover({
    required String sessionHandle,
    required String deviceLabel,
  }) {
    if (deviceLabel.trim().isEmpty) {
      throw const PinRecoveryFailure('device_label_required');
    }
    return _core.beginRecover(
      sessionHandle: sessionHandle,
      deviceLabel: deviceLabel.trim(),
    );
  }

  Future<PinRecoveryProgress> submitPin({
    required String operationId,
    required String pin,
    String? confirmation,
  }) {
    if (!RegExp(r'^[0-9]{4}$').hasMatch(pin)) {
      throw const PinRecoveryFailure('pin_format');
    }
    if (confirmation != null && confirmation != pin) {
      throw const PinRecoveryFailure('pin_mismatch');
    }
    return _core.submitPin(operationId: operationId, pin: pin);
  }

  Future<PinRecoveryProgress> confirmDevice(
    String operationId, {
    required String presenceReason,
    bool Function()? isCurrent,
  }) async {
    if (!await _presence.confirm(reason: presenceReason)) {
      throw const PinRecoveryFailure('user_presence_required');
    }
    if (isCurrent?.call() == false) {
      throw const PinRecoveryFailure('action_not_allowed');
    }
    return _core.confirmDevice(
      operationId: operationId,
      userPresenceConfirmed: true,
    );
  }

  Future<PinRecoveryProgress> status(String operationId) =>
      _core.status(operationId);
  Future<List<PinRecoveryProgress>> listPending() => _core.listPending();
  Future<PinRecoveryProgress> resume(
    String operationId, {
    String? sessionHandle,
  }) => _core.resume(operationId, sessionHandle: sessionHandle);
  Future<PinRecoveryProgress> cancel(String operationId) =>
      _core.cancel(operationId);
}
