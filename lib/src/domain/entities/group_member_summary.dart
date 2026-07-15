enum GroupMemberSubjectType {
  human,
  agent,
  unknown;

  static GroupMemberSubjectType parse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'human' || 'person' || 'user' => GroupMemberSubjectType.human,
      'agent' || 'runtime_agent' || 'bot' => GroupMemberSubjectType.agent,
      _ => GroupMemberSubjectType.unknown,
    };
  }
}

enum GroupMemberMembershipStatus {
  active,
  inactive,
  unknown;

  static GroupMemberMembershipStatus parse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      null || '' || 'active' => GroupMemberMembershipStatus.active,
      'inactive' ||
      'removed' ||
      'left' ||
      'banned' ||
      'disabled' => GroupMemberMembershipStatus.inactive,
      _ => GroupMemberMembershipStatus.unknown,
    };
  }
}

class GroupMemberSummary {
  const GroupMemberSummary({
    required this.userId,
    required this.did,
    required this.handle,
    required this.role,
    this.membershipId,
    this.peerPersonaId,
    this.credentialDid,
    this.profileUrl,
    this.displayName,
    this.avatarUri,
    this.subjectType = GroupMemberSubjectType.unknown,
    this.membershipStatus = GroupMemberMembershipStatus.active,
  });

  final String userId;
  final String did;
  final String handle;
  final String role;
  final String? membershipId;
  final String? peerPersonaId;
  final String? credentialDid;
  final String? profileUrl;
  final String? displayName;
  final String? avatarUri;
  final GroupMemberSubjectType subjectType;
  final GroupMemberMembershipStatus membershipStatus;
}
