import 'common.dart';

class ImGroupDto {
  const ImGroupDto({
    required this.groupId,
    this.groupDid,
    required this.name,
    required this.description,
    this.slug,
    this.goal,
    this.rules,
    this.messagePrompt,
    this.docUrl,
    required this.policy,
    this.myRole,
    this.membershipStatus,
    required this.memberCount,
    this.lastMessageAt,
    this.metadata = const <String, Object?>{},
  });

  final String groupId;
  final String? groupDid;
  final String name;
  final String description;
  final String? slug;
  final String? goal;
  final String? rules;
  final String? messagePrompt;
  final String? docUrl;
  final ImGroupPolicyDto policy;
  final String? myRole;
  final String? membershipStatus;
  final int memberCount;
  final DateTime? lastMessageAt;
  final Map<String, Object?> metadata;
}

class ImGroupPolicyDto {
  const ImGroupPolicyDto({
    required this.discoverability,
    required this.admissionMode,
    required this.messageSecurityProfile,
    this.attachmentsAllowed,
    this.maxMembers,
    this.memberMaxMessages,
    this.memberMaxTotalChars,
  });

  final String discoverability;
  final String admissionMode;
  final ImSecurityMode messageSecurityProfile;
  final bool? attachmentsAllowed;
  final int? maxMembers;
  final int? memberMaxMessages;
  final int? memberMaxTotalChars;
}

class ImGroupMemberDto {
  const ImGroupMemberDto({
    this.userId,
    required this.did,
    this.handle,
    required this.role,
    required this.status,
    this.profileUrl,
  });

  final String? userId;
  final String did;
  final String? handle;
  final String role;
  final String status;
  final String? profileUrl;
}
