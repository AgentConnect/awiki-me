// [INPUT]: Secret-free group encryption readiness returned by IM Core.
// [OUTPUT]: Product-safe readiness states for one local device in one group.
// [POS]: Domain projection; MLS Leaf identifiers, keys, epochs, and private state stay in Core.

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
