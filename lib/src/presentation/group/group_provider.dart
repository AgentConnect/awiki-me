import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../conversation_list/conversation_provider.dart';

class GroupState {
  const GroupState({
    this.groups = const <GroupSummary>[],
    this.membersByGroup = const <String, List<GroupMemberSummary>>{},
    this.isLoading = false,
  });

  final List<GroupSummary> groups;
  final Map<String, List<GroupMemberSummary>> membersByGroup;
  final bool isLoading;

  GroupState copyWith({
    List<GroupSummary>? groups,
    Map<String, List<GroupMemberSummary>>? membersByGroup,
    bool? isLoading,
  }) {
    return GroupState(
      groups: groups ?? this.groups,
      membersByGroup: membersByGroup ?? this.membersByGroup,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class GroupController extends StateNotifier<GroupState> {
  GroupController(this.ref) : super(const GroupState());

  final Ref ref;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final groups = await ref.read(groupApplicationServiceProvider).listGroups();
    state = state.copyWith(groups: groups, isLoading: false);
    _applyGroupsToConversations(groups);
  }

  Future<List<GroupMemberSummary>> loadGroupMembers(String groupId) async {
    final members = await ref
        .read(groupApplicationServiceProvider)
        .listMembers(groupId);
    state = state.copyWith(
      membersByGroup: <String, List<GroupMemberSummary>>{
        ...state.membersByGroup,
        groupId: members,
      },
    );
    return members;
  }

  Future<GroupSummary> refreshGroup(String groupId) async {
    final group = await ref
        .read(groupApplicationServiceProvider)
        .getGroup(groupId);
    upsertGroup(group);
    await loadGroupMembers(groupId);
    return group;
  }

  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
  }) async {
    final created = await ref
        .read(groupApplicationServiceProvider)
        .createGroup(
          name: name,
          slug: slug,
          description: description,
          goal: goal,
          rules: rules,
          messagePrompt: messagePrompt,
        );
    upsertGroup(created);
    return created;
  }

  Future<GroupSummary> joinGroup(String groupDid) async {
    final joined = await ref
        .read(groupApplicationServiceProvider)
        .joinGroup(groupDid);
    upsertGroup(joined);
    return joined;
  }

  Future<GroupSummary> addGroupMember({
    required String groupId,
    required String memberDid,
    String role = 'member',
  }) async {
    final updated = await ref
        .read(groupApplicationServiceProvider)
        .addMember(groupDid: groupId, memberDid: memberDid, role: role);
    upsertGroup(updated);
    await loadGroupMembers(groupId);
    return updated;
  }

  void upsertGroup(GroupSummary group) {
    final byGroupId = <String, GroupSummary>{
      for (final item in state.groups) item.groupId: item,
    };
    byGroupId[group.groupId] = group;
    final merged = byGroupId.values.toList()
      ..sort(
        (a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ),
      );
    state = state.copyWith(groups: merged);
    _applyGroupsToConversations(merged);
  }

  void _applyGroupsToConversations(List<GroupSummary> groups) {
    ref.read(conversationListProvider.notifier).applyGroupNames(groups);
    ref.read(selectedConversationProvider.notifier).applyGroupNames(groups);
  }

  void clear() {
    state = const GroupState();
  }
}

final groupProvider = StateNotifierProvider<GroupController, GroupState>(
  (ref) => GroupController(ref),
);

final groupMembersProvider = Provider.family<List<GroupMemberSummary>, String>((
  ref,
  groupId,
) {
  return ref.watch(groupProvider).membersByGroup[groupId] ??
      const <GroupMemberSummary>[];
});
