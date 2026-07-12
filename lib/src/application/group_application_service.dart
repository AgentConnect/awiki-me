import '../domain/entities/chat_message.dart';
import '../domain/entities/group_member_summary.dart';
import '../domain/entities/group_identity.dart';
import '../domain/entities/group_summary.dart';
import 'ports/group_core_port.dart';

abstract interface class GroupApplicationService {
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  });

  Future<GroupSummary> joinGroup(
    String groupDid, {
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  });

  Future<GroupRebindRecoverySummary> resumeRebindRecovery({int limit = 100});

  Future<GroupSummary> getGroup(String groupDid);

  Future<List<GroupSummary>> listGroups({int limit = 100});

  Future<List<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
  });

  Future<List<ChatMessage>> listMessages(
    String groupDid, {
    int limit = 100,
    String? cursor,
  });

  Future<void> leaveGroup(String groupDid);

  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  });

  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberRef,
  });
}

class ImCoreGroupApplicationService implements GroupApplicationService {
  const ImCoreGroupApplicationService({required GroupCorePort groups})
    : _groups = groups;

  final GroupCorePort _groups;

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) {
    return _groups.createGroup(
      name: name,
      slug: slug,
      description: description,
      goal: goal,
      rules: rules,
      messagePrompt: messagePrompt,
      identity: identity,
    );
  }

  @override
  Future<GroupSummary> joinGroup(
    String groupDid, {
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) => _groups.joinGroup(groupDid, identity: identity);

  @override
  Future<GroupRebindRecoverySummary> resumeRebindRecovery({int limit = 100}) =>
      _groups.resumeRebindRecovery(limit: limit);

  @override
  Future<GroupSummary> getGroup(String groupDid) => _groups.getGroup(groupDid);

  @override
  Future<List<GroupSummary>> listGroups({int limit = 100}) {
    return _groups.listGroups(limit: limit);
  }

  @override
  Future<List<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
  }) {
    return _groups.listMembers(groupDid, limit: limit);
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) {
    return _groups.listMessages(groupDid, limit: limit, cursor: cursor);
  }

  @override
  Future<void> leaveGroup(String groupDid) => _groups.leaveGroup(groupDid);

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) {
    return _groups.addMember(
      groupDid: groupDid,
      memberRef: memberRef,
      role: role,
    );
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberRef,
  }) {
    return _groups.removeMember(groupDid: groupDid, memberRef: memberRef);
  }
}
