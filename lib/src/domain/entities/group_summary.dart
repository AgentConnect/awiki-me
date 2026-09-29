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
