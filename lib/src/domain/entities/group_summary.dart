class GroupSummary {
  const GroupSummary({
    required this.groupId,
    required this.name,
    required this.description,
    required this.memberCount,
    required this.lastMessageAt,
    this.myRole,
    this.membershipStatus,
  });

  final String groupId;
  final String name;
  final String description;
  final int memberCount;
  final DateTime? lastMessageAt;
  final String? myRole;
  final String? membershipStatus;
}
