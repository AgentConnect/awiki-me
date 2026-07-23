// [INPUT]: Secret-free Device Registry, Join, and revoke projections from IM Core.
// [OUTPUT]: Device roles, readiness, Join progress, safe root-transfer receipts, and revoke results.
// [POS]: Domain truth used by AWiki Me's multi-device application and presentation layers.

enum DeviceRole { member, admin }

enum DeviceStatus { active, revoked }

enum DeviceRevokeStatus { revoked }

enum DeviceManagementReadiness { adminAwaitingRoot, importing, ready, failed }

enum RootKeyTransferStatus {
  pendingDelivery,
  awaitingImport,
  importing,
  failed,
  completed,
}

enum DeviceJoinSide { newDevice, admin }

enum DeviceJoinPhase {
  pending,
  challengePrepared,
  responsePrepared,
  responseVerified,
  approvalPrepared,
  authorized,
  cancelled,
  expired,
}

enum DeviceJoinRemoteState {
  pending,
  challengeSent,
  responseVerified,
  consumed,
  cancelled,
  rejected,
  expired,
}

enum DeviceJoinRejectReason { userRejected, sasMismatch }

class DeviceSummary {
  const DeviceSummary({
    required this.protocolDeviceId,
    required this.signingKeyId,
    required this.e2eeKeyId,
    required this.status,
    required this.role,
    required this.managementReady,
    required this.isCurrent,
  });

  final String protocolDeviceId;
  final String signingKeyId;
  final String e2eeKeyId;
  final DeviceStatus status;
  final DeviceRole role;
  final bool managementReady;
  final bool isCurrent;

  bool get canManageDevices =>
      status == DeviceStatus.active &&
      role == DeviceRole.admin &&
      managementReady;
}

/// Secret-free result of permanently revoking one AWiki device.
class DeviceRevokeResult {
  const DeviceRevokeResult({
    required this.did,
    required this.targetDeviceId,
    required this.status,
  });

  final String did;
  final String targetDeviceId;
  final DeviceRevokeStatus status;
}

/// Secret-free delivery acceptance returned by IM Core.
///
/// Acceptance does not mean that the receiving device has imported the root
/// key. [DeviceSummary.managementReady] remains the durable readiness truth.
class RootKeyTransferReceipt {
  const RootKeyTransferReceipt({
    required this.did,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.messageId,
    required this.acceptedAt,
  });

  final String did;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String messageId;
  final DateTime acceptedAt;
}

/// Secret-free, restart-safe projection of one Core-owned root transfer.
///
/// [status] is progress only. A completed transfer never grants management
/// authority; [DeviceSummary.managementReady] remains authoritative.
class RootKeyTransferSummary {
  const RootKeyTransferSummary({
    required this.did,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.messageId,
    required this.status,
    required this.createdAt,
    required this.retryable,
    this.acceptedAt,
    this.completedAt,
  });

  final String did;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String messageId;
  final RootKeyTransferStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final bool retryable;
}

class DeviceJoinRequestNotice {
  const DeviceJoinRequestNotice({
    required this.eventId,
    required this.joinSessionId,
    required this.did,
    required this.protocolDeviceId,
    required this.candidateKeyFingerprint,
    required this.issuedAt,
    required this.expiresAt,
    required this.state,
    required this.claimedByCurrentDevice,
    required this.canStartVerification,
  });

  final String eventId;
  final String joinSessionId;
  final String did;
  final String protocolDeviceId;
  final String candidateKeyFingerprint;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DeviceJoinRemoteState state;
  final bool claimedByCurrentDevice;
  final bool canStartVerification;

  bool get isTerminal =>
      state == DeviceJoinRemoteState.consumed ||
      state == DeviceJoinRemoteState.cancelled ||
      state == DeviceJoinRemoteState.rejected ||
      state == DeviceJoinRemoteState.expired;

  bool get claimedByOther =>
      !claimedByCurrentDevice &&
      (state == DeviceJoinRemoteState.challengeSent ||
          state == DeviceJoinRemoteState.responseVerified);
}

class DeviceRegistrySnapshot {
  const DeviceRegistrySnapshot({required this.did, this.devices = const []});

  final String did;
  final List<DeviceSummary> devices;

  DeviceSummary? get currentDevice {
    for (final device in devices) {
      if (device.isCurrent) {
        return device;
      }
    }
    return null;
  }
}

class DeviceJoinProgress {
  const DeviceJoinProgress({
    required this.joinSessionId,
    required this.did,
    required this.protocolDeviceId,
    required this.side,
    required this.phase,
    required this.remoteState,
    required this.expiresAt,
    this.sas,
    this.authorizedDevice,
  });

  final String joinSessionId;
  final String did;
  final String protocolDeviceId;
  final DeviceJoinSide side;
  final DeviceJoinPhase phase;
  final DeviceJoinRemoteState remoteState;
  final DateTime expiresAt;

  /// Short-lived display-only SAS. It must never be persisted or logged.
  final String? sas;
  final DeviceSummary? authorizedDevice;

  bool get isTerminal =>
      phase == DeviceJoinPhase.authorized ||
      phase == DeviceJoinPhase.cancelled ||
      phase == DeviceJoinPhase.expired;

  bool get canCompareSas =>
      sas != null &&
      (phase == DeviceJoinPhase.responsePrepared ||
          phase == DeviceJoinPhase.responseVerified ||
          phase == DeviceJoinPhase.approvalPrepared);
}

class DeviceJoinApprovalPrompt {
  const DeviceJoinApprovalPrompt({
    required this.approvalHandle,
    required this.joinSessionId,
    required this.sas,
    required this.expiresAt,
  });

  final String approvalHandle;
  final String joinSessionId;

  /// Short-lived display-only SAS. It must never be persisted or logged.
  final String sas;
  final DateTime expiresAt;
}
