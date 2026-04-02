import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';

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
    final groups = await ref.read(awikiGatewayProvider).listGroups();
    state = state.copyWith(groups: groups, isLoading: false);
  }

  Future<List<GroupMemberSummary>> loadGroupMembers(String groupId) async {
    final members =
        await ref.read(awikiGatewayProvider).listGroupMembers(groupId);
    state = state.copyWith(
      membersByGroup: <String, List<GroupMemberSummary>>{
        ...state.membersByGroup,
        groupId: members,
      },
    );
    return members;
  }

  Future<GroupSummary> refreshGroup(String groupId) async {
    final group = await ref.read(awikiGatewayProvider).getGroup(groupId);
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
    String? groupMode,
  }) async {
    final created = await ref.read(awikiGatewayProvider).createGroup(
          name: name,
          slug: slug,
          description: description,
          goal: goal,
          rules: rules,
          messagePrompt: messagePrompt,
          groupMode: groupMode,
        );
    upsertGroup(created);
    return created;
  }

  Future<GroupSummary> joinGroup(String joinCode) async {
    final joined = await ref.read(awikiGatewayProvider).joinGroup(joinCode);
    upsertGroup(joined);
    return joined;
  }

  Future<String?> getJoinCode(String groupId) async {
    final joinCode =
        await ref.read(awikiGatewayProvider).getGroupJoinCode(groupId);
    final refreshed = await ref.read(awikiGatewayProvider).getGroup(groupId);
    upsertGroup(refreshed);
    return joinCode;
  }

  Future<String?> refreshJoinCode(String groupId) async {
    final joinCode =
        await ref.read(awikiGatewayProvider).refreshGroupJoinCode(groupId);
    final refreshed = await ref.read(awikiGatewayProvider).getGroup(groupId);
    upsertGroup(refreshed);
    return joinCode;
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
  }

  void clear() {
    state = const GroupState();
  }
}

final groupProvider = StateNotifierProvider<GroupController, GroupState>(
  (ref) => GroupController(ref),
);

final groupMembersProvider =
    Provider.family<List<GroupMemberSummary>, String>((ref, groupId) {
  return ref.watch(groupProvider).membersByGroup[groupId] ??
      const <GroupMemberSummary>[];
});
