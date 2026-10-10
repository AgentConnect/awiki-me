class GroupSummary {
  const GroupSummary({
    required this.conversationId,
    required this.groupId,
    String? displayName,
    String? name,
    required this.description,
    required this.memberCount,
    required this.lastMessageAt,
    this.avatarUri,
    this.avatarMembers,
    this.groupStateVersion,
    this.myRole,
    this.membershipStatus,
    this.encrypted,
    this.canSendSecure,
    this.secureState,
    this.operation,
    this.secureProblem,
    this.secureRetryable,
  }) : displayName = displayName ?? name ?? groupId;

  final String conversationId;
  final String groupId;
  final String displayName;
  final String description;
  final int memberCount;
  final DateTime? lastMessageAt;
  final String? avatarUri;
  final List<GroupAvatarMember>? avatarMembers;
  final String? groupStateVersion;
  final String? myRole;
  final String? membershipStatus;

  final bool? encrypted;
  final bool? canSendSecure;
  final String? secureState;
  final GroupOperationSummary? operation;
  final String? secureProblem;
  final bool? secureRetryable;

  GroupSummary withSecurity({
    bool? encrypted,
    bool? canSendSecure,
    String? secureState,
    GroupOperationSummary? operation,
    String? secureProblem,
    bool? secureRetryable,
  }) => GroupSummary(
    conversationId: conversationId,
    groupId: groupId,
    displayName: displayName,
    description: description,
    memberCount: memberCount,
    lastMessageAt: lastMessageAt,
    avatarUri: avatarUri,
    avatarMembers: avatarMembers,
    groupStateVersion: groupStateVersion,
    myRole: myRole,
    membershipStatus: membershipStatus,
    encrypted: encrypted ?? this.encrypted,
    canSendSecure: canSendSecure ?? this.canSendSecure,
    secureState: secureState ?? this.secureState,
    operation: operation ?? this.operation,
    secureProblem: secureProblem ?? this.secureProblem,
    secureRetryable: secureRetryable ?? this.secureRetryable,
  );

  String get name => displayName;
}

class GroupAvatarMember {
  const GroupAvatarMember({
    required this.memberKey,
    required this.did,
    this.handle,
  });
  final String memberKey;
  final String did;
  final String? handle;
}

class GroupOperationSummary {
  const GroupOperationSummary({
    required this.businessCommitted,
    required this.encryptionReady,
    required this.phase,
    this.reason,
  });
  final bool businessCommitted;
  final bool encryptionReady;
  final String phase;
  final String? reason;
}
