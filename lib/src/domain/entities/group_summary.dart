class GroupSummary {
  const GroupSummary({
    required this.groupId,
    String? displayName,
    String? name,
    required this.description,
    required this.memberCount,
    required this.lastMessageAt,
    this.avatarUri,
    this.myRole,
    this.membershipStatus,
  }) : displayName = displayName ?? name ?? groupId;

  final String groupId;
  final String displayName;
  final String description;
  final int memberCount;
  final DateTime? lastMessageAt;
  final String? avatarUri;
  final String? myRole;
  final String? membershipStatus;

  String get name => displayName;
}
