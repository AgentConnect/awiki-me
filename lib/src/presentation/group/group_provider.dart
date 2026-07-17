import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_identity.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/peer_display_profile_provider.dart';

class GroupState {
  const GroupState({
    this.groups = const <GroupSummary>[],
    this.membersByGroup = const <String, List<GroupMemberSummary>>{},
    this.isLoading = false,
    this.isResumingRecovery = false,
    this.recoverySummary,
  });

  final List<GroupSummary> groups;
  final Map<String, List<GroupMemberSummary>> membersByGroup;
  final bool isLoading;
  final bool isResumingRecovery;
  final GroupRebindRecoverySummary? recoverySummary;

  GroupState copyWith({
    List<GroupSummary>? groups,
    Map<String, List<GroupMemberSummary>>? membersByGroup,
    bool? isLoading,
    bool? isResumingRecovery,
    GroupRebindRecoverySummary? recoverySummary,
  }) {
    return GroupState(
      groups: groups ?? this.groups,
      membersByGroup: membersByGroup ?? this.membersByGroup,
      isLoading: isLoading ?? this.isLoading,
      isResumingRecovery: isResumingRecovery ?? this.isResumingRecovery,
      recoverySummary: recoverySummary ?? this.recoverySummary,
    );
  }
}

class GroupController extends StateNotifier<GroupState> {
  GroupController(this.ref) : super(const GroupState());

  final Ref ref;
  final Map<String, Future<List<GroupMemberSummary>>> _initialMemberLoads =
      <String, Future<List<GroupMemberSummary>>>{};
  int _memberLoadGeneration = 0;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final groups = await ref
          .read(groupApplicationServiceProvider)
          .listGroups();
      final merged = _mergeGroupList(
        local: state.groups,
        incoming: groups,
        keepLocalOnly: false,
      );
      state = state.copyWith(groups: merged, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<List<GroupMemberSummary>> loadGroupMembers(String groupId) async {
    final normalizedGroupId = groupId.trim();
    final initialLoad = _initialMemberLoads[normalizedGroupId];
    if (initialLoad != null) {
      try {
        await initialLoad;
      } catch (_) {
        // An explicit refresh must still retry after an initial preload fails.
      }
    }
    return _loadGroupMembers(normalizedGroupId, hydrateProfiles: true);
  }

  Future<List<GroupMemberSummary>> ensureGroupMembersLoaded(String groupId) {
    final normalizedGroupId = groupId.trim();
    final cached = state.membersByGroup[normalizedGroupId];
    if (cached != null) {
      return Future<List<GroupMemberSummary>>.value(cached);
    }
    final active = _initialMemberLoads[normalizedGroupId];
    if (active != null) {
      return active;
    }
    late final Future<List<GroupMemberSummary>> load;
    load = _loadGroupMembers(normalizedGroupId, hydrateProfiles: false)
        .whenComplete(() {
          if (identical(_initialMemberLoads[normalizedGroupId], load)) {
            _initialMemberLoads.remove(normalizedGroupId);
          }
        });
    _initialMemberLoads[normalizedGroupId] = load;
    return load;
  }

  Future<List<GroupMemberSummary>> _loadGroupMembers(
    String groupId, {
    required bool hydrateProfiles,
  }) async {
    final generation = _memberLoadGeneration;
    final members = await ref
        .read(groupApplicationServiceProvider)
        .listMembers(groupId);
    if (generation != _memberLoadGeneration) {
      return members;
    }
    _publishGroupMembers(groupId, members);
    if (!hydrateProfiles) {
      return members;
    }
    final hydratedMembers = await _hydrateMemberProfiles(members);
    if (generation != _memberLoadGeneration) {
      return hydratedMembers;
    }
    _publishGroupMembers(groupId, hydratedMembers);
    return hydratedMembers;
  }

  void _publishGroupMembers(String groupId, List<GroupMemberSummary> members) {
    state = state.copyWith(
      membersByGroup: <String, List<GroupMemberSummary>>{
        ...state.membersByGroup,
        groupId: members,
      },
    );
  }

  Future<List<GroupMemberSummary>> _hydrateMemberProfiles(
    List<GroupMemberSummary> members,
  ) async {
    if (members.isEmpty) {
      return members;
    }
    final profiles = ref.read(profileApplicationServiceProvider);
    return Future.wait<GroupMemberSummary>(
      members.map((member) async {
        final subject = _memberProfileSubject(member);
        if (subject == null) {
          return member;
        }
        try {
          final profile = await profiles.loadPublicProfile(subject);
          final ownerDid = ref.read(sessionProvider).session?.did ?? '';
          ref
              .read(peerDisplayProfileProvider.notifier)
              .updateFromRemote(
                ownerDid: ownerDid,
                profile: profile,
                peerPersonaId: member.peerPersonaId,
              );
          return _mergeMemberProfile(member, profile);
        } catch (_) {
          // Profile hydration is best-effort. The group membership snapshot is
          // still authoritative for DID/role/status, so keep the raw member if
          // a public profile is unavailable.
          return member;
        }
      }),
    );
  }

  Future<GroupSummary> refreshGroup(
    String groupId, {
    bool refreshMembers = true,
  }) async {
    late GroupSummary group;
    Object? groupError;
    StackTrace? groupStackTrace;
    try {
      group = await ref.read(groupApplicationServiceProvider).getGroup(groupId);
    } catch (error, stackTrace) {
      groupError = error;
      groupStackTrace = stackTrace;
    }
    if (refreshMembers) {
      await loadGroupMembers(groupId);
    } else {
      await ensureGroupMembersLoaded(groupId);
    }
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
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
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
          identity: identity,
        );
    upsertGroup(created);
    return created;
  }

  Future<GroupSummary> joinGroup(
    String groupDid, {
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) async {
    final joined = await ref
        .read(groupApplicationServiceProvider)
        .joinGroup(groupDid, identity: identity);
    upsertGroup(joined);
    return joined;
  }

  Future<GroupRebindRecoverySummary> resumeRebindRecovery({
    int limit = 100,
  }) async {
    if (state.isResumingRecovery) {
      return state.recoverySummary ?? GroupRebindRecoverySummary.empty;
    }
    state = state.copyWith(isResumingRecovery: true);
    try {
      final summary = await ref
          .read(groupApplicationServiceProvider)
          .resumeRebindRecovery(limit: limit);
      state = state.copyWith(
        isResumingRecovery: false,
        recoverySummary: summary,
      );
      return summary;
    } catch (_) {
      state = state.copyWith(isResumingRecovery: false);
      rethrow;
    }
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
  }

  void clear() {
    _memberLoadGeneration += 1;
    _initialMemberLoads.clear();
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
    conversationId: incoming.conversationId,
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

String? _memberProfileSubject(GroupMemberSummary member) {
  final did = _trimToNull(member.did);
  if (did != null) {
    return did;
  }
  return _trimToNull(member.handle);
}

GroupMemberSummary _mergeMemberProfile(
  GroupMemberSummary member,
  UserProfile profile,
) {
  final did = member.did.trim();
  final profileHandle =
      _trimToNull(profile.fullHandle) ?? _trimToNull(profile.handle);
  final memberHandle = _trimToNull(member.handle);
  final mergedHandle = memberHandle == null || memberHandle == did
      ? profileHandle ?? member.handle
      : member.handle;
  final subjectType = member.subjectType == GroupMemberSubjectType.unknown
      ? GroupMemberSubjectType.parse(profile.subjectType)
      : member.subjectType;
  return GroupMemberSummary(
    userId: member.userId,
    did: member.did,
    handle: mergedHandle,
    role: member.role,
    membershipId: member.membershipId,
    peerPersonaId: member.peerPersonaId,
    credentialDid: member.credentialDid,
    profileUrl: _preferNonEmptyOptional(member.profileUrl, profile.profileUri),
    displayName: _preferNonEmptyOptional(
      member.displayName,
      _profileDisplayName(profile),
    ),
    avatarUri: _preferNonEmptyOptional(member.avatarUri, profile.avatarUri),
    subjectType: subjectType,
    membershipStatus: member.membershipStatus,
  );
}

String? _profileDisplayName(UserProfile profile) {
  final displayName = _trimToNull(profile.displayName);
  final did = _trimToNull(profile.did);
  if (displayName == null || did == null) {
    return displayName;
  }
  if (displayName == did || displayName.startsWith('did:')) {
    return null;
  }
  if (did.length > 18) {
    final compactDid =
        '${did.substring(0, 10)}…${did.substring(did.length - 6)}';
    if (displayName == compactDid) {
      return null;
    }
  }
  return displayName;
}
