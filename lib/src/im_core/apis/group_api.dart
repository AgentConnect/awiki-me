import '../models/common.dart';
import '../models/group_models.dart';
import '../models/message_models.dart';

abstract class ImGroupApi {
  Future<ImGroupDto> create(ImCreateGroupRequest request);
  Future<ImGroupDto> get(String groupId);
  Future<ImGroupDto> join(ImJoinGroupRequest request);
  Future<ImGroupDto> addMember(ImGroupMemberMutationRequest request);
  Future<ImGroupDto> removeMember(ImGroupMemberMutationRequest request);
  Future<ImGroupDto> leave(ImLeaveGroupRequest request);
  Future<ImGroupDto> update(ImUpdateGroupRequest request);
  Future<ImPage<ImGroupMemberDto>> listMembers(
    ImListGroupMembersRequest request,
  );
  Future<ImPage<ImMessageDto>> listMessages(ImListGroupMessagesRequest request);
}

class ImCreateGroupRequest {
  const ImCreateGroupRequest({
    required this.name,
    this.description = '',
    this.slug,
    this.goal,
    this.rules,
    this.messagePrompt,
    this.policy = const ImGroupPolicyDto(
      discoverability: 'private',
      admissionMode: 'open-join',
      messageSecurityProfile: ImSecurityMode.transportProtected,
      attachmentsAllowed: true,
    ),
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final String description;
  final String? slug;
  final String? goal;
  final String? rules;
  final String? messagePrompt;
  final ImGroupPolicyDto policy;
  final Map<String, Object?> metadata;
}

class ImJoinGroupRequest {
  const ImJoinGroupRequest({required this.groupId, this.reason});

  final String groupId;
  final String? reason;
}

class ImGroupMemberMutationRequest {
  const ImGroupMemberMutationRequest({
    required this.groupId,
    required this.memberDidOrHandle,
    this.role = 'member',
    this.reason,
  });

  final String groupId;
  final String memberDidOrHandle;
  final String role;
  final String? reason;
}

class ImLeaveGroupRequest {
  const ImLeaveGroupRequest({required this.groupId, this.reason});

  final String groupId;
  final String? reason;
}

class ImUpdateGroupRequest {
  const ImUpdateGroupRequest({
    required this.groupId,
    this.name,
    this.description,
    this.slug,
    this.goal,
    this.rules,
    this.messagePrompt,
    this.docUrl,
    this.policy,
    this.metadata = const <String, Object?>{},
  });

  final String groupId;
  final String? name;
  final String? description;
  final String? slug;
  final String? goal;
  final String? rules;
  final String? messagePrompt;
  final String? docUrl;
  final ImGroupPolicyDto? policy;
  final Map<String, Object?> metadata;
}

class ImListGroupMembersRequest {
  const ImListGroupMembersRequest({required this.groupId, this.limit = 100});

  final String groupId;
  final int limit;
}

class ImListGroupMessagesRequest {
  const ImListGroupMessagesRequest({
    required this.groupId,
    this.limit = 50,
    this.cursor,
  });

  final String groupId;
  final int limit;
  final String? cursor;
}
