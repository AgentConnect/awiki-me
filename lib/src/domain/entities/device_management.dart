enum DeviceRole { member, admin }

enum DeviceStatus { active, revoked }

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
  notObserved,
  pending,
  claimed,
  challengeSent,
  responseVerified,
  consumed,
  expired,
}

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
}

class PendingDeviceJoinSummary {
  const PendingDeviceJoinSummary({
    required this.joinSessionId,
    required this.protocolDeviceId,
    required this.signingKeyId,
    required this.e2eeKeyId,
    required this.requestedRole,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String joinSessionId;
  final String protocolDeviceId;
  final String signingKeyId;
  final String e2eeKeyId;
  final DeviceRole requestedRole;
  final DateTime issuedAt;
  final DateTime expiresAt;
}

class DeviceRegistrySnapshot {
  const DeviceRegistrySnapshot({
    required this.did,
    this.devices = const <DeviceSummary>[],
    this.pendingJoins = const <PendingDeviceJoinSummary>[],
  });

  final String did;
  final List<DeviceSummary> devices;
  final List<PendingDeviceJoinSummary> pendingJoins;

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
    required this.role,
    required this.sas,
    required this.expiresAt,
  });

  final String approvalHandle;
  final String joinSessionId;
  final DeviceRole role;

  /// Short-lived display-only SAS. It must never be persisted or logged.
  final String sas;
  final DateTime expiresAt;
}
