class GroupMemberSummary {
  const GroupMemberSummary({
    required this.userId,
    required this.did,
    required this.handle,
    required this.role,
    this.profileUrl,
  });

  final String userId;
  final String did;
  final String handle;
  final String role;
  final String? profileUrl;
}
