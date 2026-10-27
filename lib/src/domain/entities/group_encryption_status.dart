// [INPUT]: Secret-free group encryption readiness returned by IM Core.
// [OUTPUT]: Product-safe readiness states for one local device in one group.
// [POS]: Domain projection; MLS Leaf identifiers, keys, epochs, and private state stay in Core.

import 'group_summary.dart';

enum GroupEncryptionReadiness { preparing, needsRetry, ready, unavailable }

class GroupEncryptionStatus {
  const GroupEncryptionStatus({
    required this.groupDid,
    required this.readiness,
    required this.canSendSecure,
    required this.retryable,
  });

  final String groupDid;
  final GroupEncryptionReadiness readiness;
  final bool canSendSecure;
  final bool retryable;
}

/// Apply only Core's readiness projection; group membership and role keep
/// their existing authoritative values until a group-state refresh.
GroupSummary applyGroupEncryptionStatus(
  GroupSummary group,
  GroupEncryptionStatus status,
) {
  if (group.groupId.trim() != status.groupDid.trim()) {
    throw StateError('group_encryption_binding_mismatch');
  }
  final ready =
      status.readiness == GroupEncryptionReadiness.ready &&
      status.canSendSecure &&
      group.membershipStatus != 'left' &&
      group.membershipStatus != 'removed';
  return group.withSecurity(
    canSendSecure: ready,
    secureState: switch (status.readiness) {
      GroupEncryptionReadiness.ready when ready => 'ready',
      GroupEncryptionReadiness.preparing =>
        group.secureState == 'waitingForMembershipUpdate'
            ? 'waitingForMembershipUpdate'
            : 'syncing',
      GroupEncryptionReadiness.needsRetry ||
      GroupEncryptionReadiness.ready => 'needsRepair',
      GroupEncryptionReadiness.unavailable => 'unavailable',
    },
    secureProblem: ready ? '' : group.secureProblem,
    secureRetryable: status.retryable,
  );
}
