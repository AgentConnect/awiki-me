import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../core/group_display_name.dart';
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
    final previousGroups = state.groups;
    state = state.copyWith(isLoading: true);
    try {
      final groups = await ref
          .read(groupApplicationServiceProvider)
          .listGroups();
      final merged = _mergeGroupList(
        local: previousGroups,
        incoming: groups,
        keepLocalOnly: false,
      );
      state = state.copyWith(groups: merged, isLoading: false);
      _applyGroupsToConversations(merged);
    } catch (_) {
      state = state.copyWith(groups: previousGroups, isLoading: false);
      rethrow;
    }
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
    late GroupSummary group;
    Object? groupError;
    StackTrace? groupStackTrace;
    try {
      group = await ref.read(groupApplicationServiceProvider).getGroup(groupId);
    } catch (error, stackTrace) {
      groupError = error;
      groupStackTrace = stackTrace;
    }
    await loadGroupMembers(groupId);
    if (groupError != null) {
      Error.throwWithStackTrace(groupError, groupStackTrace!);
    }
    upsertGroup(group);
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
    required String memberRef,
    String role = 'member',
  }) async {
    final updated = await ref
        .read(groupApplicationServiceProvider)
        .addMember(groupDid: groupId, memberRef: memberRef, role: role);
    upsertGroup(updated);
    await loadGroupMembers(groupId);
    return updated;
  }

  Future<GroupSummary> removeGroupMember({
    required String groupId,
    required String memberRef,
  }) async {
    final updated = await ref
        .read(groupApplicationServiceProvider)
        .removeMember(groupDid: groupId, memberRef: memberRef);
    upsertGroup(updated);
    await loadGroupMembers(groupId);
    return updated;
  }

  void upsertGroup(GroupSummary group) {
    final merged = _mergeGroupList(
      local: state.groups,
      incoming: <GroupSummary>[group],
      keepLocalOnly: true,
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

List<GroupSummary> _mergeGroupList({
  required List<GroupSummary> local,
  required List<GroupSummary> incoming,
  required bool keepLocalOnly,
}) {
  final localByGroupId = <String, GroupSummary>{
    for (final item in local) item.groupId: item,
  };
  final mergedByGroupId = <String, GroupSummary>{};
  for (final group in incoming) {
    mergedByGroupId[group.groupId] = _mergeGroupSummary(
      local: localByGroupId[group.groupId],
      incoming: group,
    );
  }
  if (keepLocalOnly) {
    for (final entry in localByGroupId.entries) {
      mergedByGroupId.putIfAbsent(entry.key, () => entry.value);
    }
  }
  return mergedByGroupId.values.toList()..sort(
    (a, b) => (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
  );
}

GroupSummary _mergeGroupSummary({
  required GroupSummary? local,
  required GroupSummary incoming,
}) {
  if (local == null) {
    return incoming;
  }
  return GroupSummary(
    groupId: incoming.groupId,
    name: _mergeGroupName(local: local, incoming: incoming),
    description: _preferNonEmpty(incoming.description, local.description) ?? '',
    memberCount: incoming.memberCount > 0
        ? incoming.memberCount
        : local.memberCount,
    lastMessageAt: incoming.lastMessageAt ?? local.lastMessageAt,
    myRole: _mergeRole(local: local, incoming: incoming),
    membershipStatus: _preferNonEmptyOptional(
      incoming.membershipStatus,
      local.membershipStatus,
    ),
  );
}

String _mergeGroupName({
  required GroupSummary local,
  required GroupSummary incoming,
}) {
  final incomingName = incoming.name.trim();
  if (incomingName.isEmpty) {
    return local.name;
  }
  final localName = local.name.trim();
  final incomingIsIdLike = GroupDisplayName.isIdLike(
    incomingName,
    incoming.groupId,
  );
  final localIsFriendly =
      localName.isNotEmpty &&
      !GroupDisplayName.isIdLike(localName, local.groupId);
  if (incomingIsIdLike && localIsFriendly) {
    return local.name;
  }
  return incoming.name;
}

String? _mergeRole({
  required GroupSummary local,
  required GroupSummary incoming,
}) {
  final incomingRole = _trimToNull(incoming.myRole);
  if (_isKnownGroupRole(incomingRole)) {
    return incomingRole;
  }
  final incomingStatus = _trimToNull(incoming.membershipStatus);
  if (incomingStatus != null && incomingStatus != 'active') {
    return incomingRole;
  }
  return local.myRole;
}

String? _preferNonEmpty(String? incoming, String? local) {
  final incomingText = incoming?.trim();
  if (incomingText != null && incomingText.isNotEmpty) {
    return incoming;
  }
  return local;
}

String? _preferNonEmptyOptional(String? incoming, String? local) {
  final value = _trimToNull(incoming);
  return value ?? _trimToNull(local);
}

String? _trimToNull(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

bool _isKnownGroupRole(String? role) {
  return role == 'owner' || role == 'admin' || role == 'member';
}
