import '../../domain/entities/chat_message.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_identity.dart';
import '../../domain/entities/group_summary.dart';

abstract interface class GroupCorePort {
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
