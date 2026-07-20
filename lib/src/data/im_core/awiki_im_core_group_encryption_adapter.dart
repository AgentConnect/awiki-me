// [INPUT]: IM Core's public group secure status/repair facade for the current identity.
// [OUTPUT]: Redacted product readiness without MLS Leaf or private-state details.
// [POS]: Thin adapter; P6 lifecycle orchestration remains entirely inside IM Core.

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/group_encryption_core_port.dart';
import '../../domain/entities/group_encryption_status.dart';
import 'awiki_im_core_runtime.dart';

typedef AwikiImCoreGroupSecureStatus =
    Future<core.GroupSecureStatus> Function(String groupDid);
typedef AwikiImCoreGroupSecureRepair =
    Future<core.GroupSecureRepairResult> Function(String groupDid);

class AwikiImCoreGroupEncryptionAdapter implements GroupEncryptionCorePort {
  AwikiImCoreGroupEncryptionAdapter({required AwikiImCoreRuntime runtime})
    : this.withCalls(
        status: (groupDid) => runtime.withCurrentClient(
          (client) => client.secure.group(groupDid).status(),
        ),
        repair: (groupDid) => runtime.withCurrentClient(
          (client) => client.secure.group(groupDid).repair(),
        ),
      );

  AwikiImCoreGroupEncryptionAdapter.withCalls({
    required AwikiImCoreGroupSecureStatus status,
    required AwikiImCoreGroupSecureRepair repair,
  }) : _status = status,
       _repair = repair;

  final AwikiImCoreGroupSecureStatus _status;
  final AwikiImCoreGroupSecureRepair _repair;

  @override
  Future<GroupEncryptionStatus> status(String groupDid) async {
    final normalizedGroupDid = _normalizedGroupDid(groupDid);
    return _forExpectedGroup(
      normalizedGroupDid,
      mapCoreGroupEncryptionStatus(await _status(normalizedGroupDid)),
    );
  }

  @override
  Future<GroupEncryptionStatus> retry(String groupDid) async {
    final normalizedGroupDid = _normalizedGroupDid(groupDid);
    await _repair(normalizedGroupDid);
    return _forExpectedGroup(
      normalizedGroupDid,
      mapCoreGroupEncryptionStatus(await _status(normalizedGroupDid)),
    );
  }
}

GroupEncryptionStatus mapCoreGroupEncryptionStatus(
  core.GroupSecureStatus value,
) {
  final readiness = switch (value.state) {
    core.GroupSecureState.ready when value.canSendSecure =>
      GroupEncryptionReadiness.ready,
    core.GroupSecureState.syncing ||
    core.GroupSecureState.waitingForMembershipUpdate =>
      GroupEncryptionReadiness.preparing,
    core.GroupSecureState.needsRepair ||
    core.GroupSecureState.missingLocalState ||
    core.GroupSecureState.unknown ||
    core.GroupSecureState.ready => GroupEncryptionReadiness.needsRetry,
    core.GroupSecureState.unavailable =>
      value.problem?.retryable == true
          ? GroupEncryptionReadiness.needsRetry
          : GroupEncryptionReadiness.unavailable,
  };
  return GroupEncryptionStatus(
    groupDid: value.group,
    readiness: readiness,
    canSendSecure:
        readiness == GroupEncryptionReadiness.ready && value.canSendSecure,
    retryable:
        readiness == GroupEncryptionReadiness.needsRetry &&
        (value.problem?.retryable ?? true),
  );
}

String _normalizedGroupDid(String value) {
  final groupDid = value.trim();
  if (groupDid.isEmpty) {
    throw const FormatException('invalid_group_did');
  }
  return groupDid;
}

GroupEncryptionStatus _forExpectedGroup(
  String expectedGroupDid,
  GroupEncryptionStatus status,
) {
  if (status.groupDid.trim() != expectedGroupDid) {
    throw StateError('group_encryption_binding_mismatch');
  }
  return status;
}
