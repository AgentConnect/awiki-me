import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/models/group_collection_page.dart';
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
    this.groupsHasMore = false,
    this.groupsNextCursor,
    this.memberPages = const <String, GroupMemberPageState>{},
    this.isLoading = false,
    this.isLoadingMoreGroups = false,
    this.isResumingRecovery = false,
    this.recoverySummary,
  });

  final List<GroupSummary> groups;
  final Map<String, List<GroupMemberSummary>> membersByGroup;
  final bool groupsHasMore;
  final String? groupsNextCursor;
  final Map<String, GroupMemberPageState> memberPages;
  final bool isLoading;
  final bool isLoadingMoreGroups;
  final bool isResumingRecovery;
  final GroupRebindRecoverySummary? recoverySummary;

  GroupState copyWith({
    List<GroupSummary>? groups,
    Map<String, List<GroupMemberSummary>>? membersByGroup,
    bool? groupsHasMore,
    String? groupsNextCursor,
    bool clearGroupsNextCursor = false,
    Map<String, GroupMemberPageState>? memberPages,
    bool? isLoading,
    bool? isLoadingMoreGroups,
    bool? isResumingRecovery,
    GroupRebindRecoverySummary? recoverySummary,
  }) {
    return GroupState(
      groups: groups ?? this.groups,
      membersByGroup: membersByGroup ?? this.membersByGroup,
      groupsHasMore: groupsHasMore ?? this.groupsHasMore,
      groupsNextCursor: clearGroupsNextCursor
          ? null
          : (groupsNextCursor ?? this.groupsNextCursor),
      memberPages: memberPages ?? this.memberPages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMoreGroups: isLoadingMoreGroups ?? this.isLoadingMoreGroups,
      isResumingRecovery: isResumingRecovery ?? this.isResumingRecovery,
      recoverySummary: recoverySummary ?? this.recoverySummary,
    );
  }
}

class _GroupOwnerOperation {
  const _GroupOwnerOperation({required this.generation, required this.epoch});

  final int generation;
  final SessionEpoch epoch;

  @override
  bool operator ==(Object other) {
    return other is _GroupOwnerOperation &&
        other.generation == generation &&
        other.epoch == epoch;
  }

  @override
  int get hashCode => Object.hash(generation, epoch);
}

class _GroupMemberLoadOperation {
  const _GroupMemberLoadOperation({
    required this.owner,
    required this.operation,
  });

  final _GroupOwnerOperation owner;
  final Future<List<GroupMemberSummary>> operation;
}

class _GroupMemberProfilePrewarmOperation {
  const _GroupMemberProfilePrewarmOperation({
    required this.owner,
    required this.rosterKey,
    required this.operation,
  });

  final _GroupOwnerOperation owner;
  final String rosterKey;
  final Future<void> operation;
}

class _GroupRecoveryOperation {
  const _GroupRecoveryOperation({required this.owner, required this.operation});

  final _GroupOwnerOperation owner;
  final Future<GroupRebindRecoverySummary> operation;
}

class GroupMemberPageState {
  const GroupMemberPageState({
    required this.hasMore,
    this.nextCursor,
    this.pageGroupDid,
    this.groupStateVersion,
    this.isLoadingMore = false,
  });

  final bool hasMore;
  final String? nextCursor;
  final String? pageGroupDid;
  final String? groupStateVersion;
  final bool isLoadingMore;

  GroupMemberPageState copyWith({bool? isLoadingMore}) => GroupMemberPageState(
    hasMore: hasMore,
    nextCursor: nextCursor,
    pageGroupDid: pageGroupDid,
    groupStateVersion: groupStateVersion,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
  );
}

class GroupController extends StateNotifier<GroupState> {
  GroupController(this.ref) : super(const GroupState());

  final Ref ref;
  final Map<String, _GroupMemberLoadOperation> _initialMemberLoads =
      <String, _GroupMemberLoadOperation>{};
  final Map<String, _GroupMemberProfilePrewarmOperation>
  _memberProfilePrewarms = <String, _GroupMemberProfilePrewarmOperation>{};
  final Map<String, String> _memberProfileReadyKeys = <String, String>{};
  int _memberLoadGeneration = 0;
  _GroupRecoveryOperation? _recoveryOperation;
  final Map<String, int> _memberLoadGenerations = <String, int>{};
  int _groupLoadGeneration = 0;

  Future<void> refresh({int limit = 100}) async {
    final ownerOperation = _captureOwnerOperation();
    final generation = ++_groupLoadGeneration;
    state = state.copyWith(isLoading: true, isLoadingMoreGroups: false);
    try {
      final groups = ref.read(groupApplicationServiceProvider);
      final recovery = await groups.resumeRebindRecovery(limit: limit);
      _requireCurrentOwnerOperation(ownerOperation);
      final page = await groups.listGroups(limit: limit);
      _validatePageCursor(page);
      if (!_isGroupOwnerOperationCurrent(ownerOperation) ||
          generation != _groupLoadGeneration) {
        return;
      }
      final merged = _mergeGroupList(
        local: state.groups,
        incoming: page.items,
        keepLocalOnly: false,
      );
      state = state.copyWith(
        groups: merged,
        groupsHasMore: page.hasMore,
        groupsNextCursor: page.nextCursor,
        clearGroupsNextCursor: page.nextCursor == null,
        isLoading: false,
        recoverySummary: _hasRecoveryWork(recovery) ? recovery : null,
      );
    } catch (_) {
      if (_isGroupOwnerOperationCurrent(ownerOperation) &&
          generation == _groupLoadGeneration) {
        state = state.copyWith(isLoading: false);
      }
      rethrow;
    }
  }

  Future<void> loadMoreGroups({int limit = 100}) async {
    final cursor = state.groupsNextCursor;
    if (!state.groupsHasMore || cursor == null || state.isLoadingMoreGroups) {
      return;
    }
    final ownerOperation = _captureOwnerOperation();
    final generation = _groupLoadGeneration;
    state = state.copyWith(isLoadingMoreGroups: true);
    try {
      final page = await ref
          .read(groupApplicationServiceProvider)
          .listGroups(limit: limit, cursor: cursor);
      _validatePageCursor(page, previousCursor: cursor);
      if (!_isGroupOwnerOperationCurrent(ownerOperation) ||
          generation != _groupLoadGeneration ||
          state.groupsNextCursor != cursor) {
        return;
      }
      state = state.copyWith(
        groups: _mergeGroupList(
          local: state.groups,
          incoming: page.items,
          keepLocalOnly: true,
        ),
        groupsHasMore: page.hasMore,
        groupsNextCursor: page.nextCursor,
        clearGroupsNextCursor: page.nextCursor == null,
        isLoadingMoreGroups: false,
      );
    } catch (_) {
      if (_isGroupOwnerOperationCurrent(ownerOperation) &&
          generation == _groupLoadGeneration) {
        state = state.copyWith(isLoadingMoreGroups: false);
      }
      rethrow;
    }
  }

  Future<List<GroupMemberSummary>> loadGroupMembers(
    String groupId, {
    int limit = 100,
  }) async {
    final ownerOperation = _captureOwnerOperation();
    final normalizedGroupId = groupId.trim();
    final initialLoad = _initialMemberLoads[normalizedGroupId];
    if (initialLoad != null && initialLoad.owner == ownerOperation) {
      try {
        await initialLoad.operation;
      } catch (_) {
        // An explicit refresh must still retry after an initial preload fails.
      }
    }
    _requireCurrentOwnerOperation(ownerOperation);
    return _loadGroupMembers(
      normalizedGroupId,
      ownerOperation: ownerOperation,
      hydrateProfiles: true,
      limit: limit,
    );
  }

  Future<List<GroupMemberSummary>> ensureGroupMembersLoaded(String groupId) {
    final ownerOperation = _captureOwnerOperation();
    return _ensureGroupMembersLoaded(
      groupId.trim(),
      ownerOperation: ownerOperation,
    );
  }

  Future<List<GroupMemberSummary>> _ensureGroupMembersLoaded(
    String normalizedGroupId, {
    required _GroupOwnerOperation ownerOperation,
  }) {
    _requireCurrentOwnerOperation(ownerOperation);
    final cached = state.membersByGroup[normalizedGroupId];
    if (cached != null) {
      return _ensureCachedMemberProfilesLoaded(
        normalizedGroupId,
        cached,
        ownerOperation: ownerOperation,
      ).then((_) {
        _requireCurrentOwnerOperation(ownerOperation);
        return state.membersByGroup[normalizedGroupId] ?? cached;
      });
    }
    final active = _initialMemberLoads[normalizedGroupId];
    if (active != null && active.owner == ownerOperation) {
      return active.operation;
    }
    late final Future<List<GroupMemberSummary>> load;
    load =
        _loadGroupMembers(
          normalizedGroupId,
          ownerOperation: ownerOperation,
          hydrateProfiles: false,
          limit: 100,
        ).whenComplete(() {
          if (identical(
            _initialMemberLoads[normalizedGroupId]?.operation,
            load,
          )) {
            _initialMemberLoads.remove(normalizedGroupId);
          }
        });
    _initialMemberLoads[normalizedGroupId] = _GroupMemberLoadOperation(
      owner: ownerOperation,
      operation: load,
    );
    return load;
  }

  Future<List<GroupMemberSummary>> _loadGroupMembers(
    String groupId, {
    required _GroupOwnerOperation ownerOperation,
    required bool hydrateProfiles,
    required int limit,
  }) async {
    _requireCurrentOwnerOperation(ownerOperation);
    final generation = (_memberLoadGenerations[groupId] ?? 0) + 1;
    _memberLoadGenerations[groupId] = generation;
    final currentPage = state.memberPages[groupId];
    if (currentPage?.isLoadingMore == true) {
      state = state.copyWith(
        memberPages: <String, GroupMemberPageState>{
          ...state.memberPages,
          groupId: currentPage!.copyWith(isLoadingMore: false),
        },
      );
    }
    final page = await ref
        .read(groupApplicationServiceProvider)
        .listMembers(groupId, limit: limit);
    _validatePageCursor(page);
    _requireCurrentOwnerOperation(ownerOperation);
    final members = page.items;
    if (generation != _memberLoadGenerations[groupId]) {
      return members;
    }
    if (page.pageGroupDid != groupId || page.groupStateVersion == null) {
      throw StateError('group_member_page_binding_mismatch');
    }
    _publishGroupMembers(groupId, members, page: page);
    await _ensureCachedMemberProfilesLoaded(
      groupId,
      members,
      ownerOperation: ownerOperation,
    );
    _requireCurrentOwnerOperation(ownerOperation);
    if (generation != _memberLoadGenerations[groupId]) {
      return members;
    }
    if (!hydrateProfiles) {
      return members;
    }
    final hydratedMembers = await _hydrateMemberProfiles(
      members,
      ownerOperation: ownerOperation,
    );
    _requireCurrentOwnerOperation(ownerOperation);
    if (generation != _memberLoadGenerations[groupId]) {
      return hydratedMembers;
    }
    _publishGroupMembers(groupId, hydratedMembers);
    return hydratedMembers;
  }

  void _publishGroupMembers(
    String groupId,
    List<GroupMemberSummary> members, {
    GroupCollectionPage<GroupMemberSummary>? page,
  }) {
    state = state.copyWith(
      membersByGroup: <String, List<GroupMemberSummary>>{
        ...state.membersByGroup,
        groupId: members,
      },
      memberPages: page == null
          ? state.memberPages
          : <String, GroupMemberPageState>{
              ...state.memberPages,
              groupId: GroupMemberPageState(
                hasMore: page.hasMore,
                nextCursor: page.nextCursor,
                pageGroupDid: page.pageGroupDid,
                groupStateVersion: page.groupStateVersion,
              ),
            },
    );
  }

  Future<void> loadMoreGroupMembers(String groupId) async {
    final normalizedGroupId = groupId.trim();
    final ownerOperation = _captureOwnerOperation();
    final metadata = state.memberPages[normalizedGroupId];
    final cursor = metadata?.nextCursor;
    if (metadata == null ||
        !metadata.hasMore ||
        cursor == null ||
        metadata.isLoadingMore) {
      return;
    }
    final generation = _memberLoadGenerations[normalizedGroupId] ?? 0;
    state = state.copyWith(
      memberPages: <String, GroupMemberPageState>{
        ...state.memberPages,
        normalizedGroupId: metadata.copyWith(isLoadingMore: true),
      },
    );
    try {
      final page = await ref
          .read(groupApplicationServiceProvider)
          .listMembers(normalizedGroupId, cursor: cursor);
      _validatePageCursor(page, previousCursor: cursor);
      if (!_isGroupOwnerOperationCurrent(ownerOperation) ||
          generation != _memberLoadGenerations[normalizedGroupId] ||
          state.memberPages[normalizedGroupId]?.nextCursor != cursor) {
        return;
      }
      if (page.pageGroupDid != normalizedGroupId ||
          page.groupStateVersion == null ||
          metadata.pageGroupDid != normalizedGroupId ||
          page.groupStateVersion != metadata.groupStateVersion) {
        _invalidateMemberPage(normalizedGroupId);
        throw StateError('group_member_page_binding_mismatch');
      }
      final combined = _deduplicateMembers(<GroupMemberSummary>[
        ...?state.membersByGroup[normalizedGroupId],
        ...page.items,
      ]);
      _publishGroupMembers(normalizedGroupId, combined, page: page);
      await _ensureCachedMemberProfilesLoaded(
        normalizedGroupId,
        combined,
        ownerOperation: ownerOperation,
      );
      if (!_isGroupOwnerOperationCurrent(ownerOperation) ||
          generation != _memberLoadGenerations[normalizedGroupId]) {
        return;
      }
      final hydrated = await _hydrateMemberProfiles(
        combined,
        ownerOperation: ownerOperation,
      );
      if (_isGroupOwnerOperationCurrent(ownerOperation) &&
          generation == _memberLoadGenerations[normalizedGroupId]) {
        _publishGroupMembers(normalizedGroupId, hydrated);
      }
    } catch (_) {
      final current = state.memberPages[normalizedGroupId];
      if (_isGroupOwnerOperationCurrent(ownerOperation) &&
          generation == _memberLoadGenerations[normalizedGroupId] &&
          current != null &&
          current.isLoadingMore) {
        state = state.copyWith(
          memberPages: <String, GroupMemberPageState>{
            ...state.memberPages,
            normalizedGroupId: current.copyWith(isLoadingMore: false),
          },
        );
      }
      rethrow;
    }
  }

  void _invalidateMemberPage(String groupId) {
    _memberProfilePrewarms.remove(groupId);
    _memberProfileReadyKeys.remove(groupId);
    final members = <String, List<GroupMemberSummary>>{...state.membersByGroup}
      ..remove(groupId);
    final pages = <String, GroupMemberPageState>{...state.memberPages}
      ..remove(groupId);
    state = state.copyWith(membersByGroup: members, memberPages: pages);
  }

  Future<void> _ensureCachedMemberProfilesLoaded(
    String groupId,
    List<GroupMemberSummary> members, {
    required _GroupOwnerOperation ownerOperation,
  }) {
    _requireCurrentOwnerOperation(ownerOperation);
    final rosterKey = _memberProfileRosterKey(groupId, members);
    if (_memberProfileReadyKeys[groupId] == rosterKey) {
      return Future<void>.value();
    }
    final active = _memberProfilePrewarms[groupId];
    if (active != null &&
        active.owner == ownerOperation &&
        active.rosterKey == rosterKey) {
      return active.operation;
    }
    late final Future<void> load;
    load =
        _prewarmCachedMemberProfiles(
          groupId,
          members,
          rosterKey: rosterKey,
          ownerOperation: ownerOperation,
        ).whenComplete(() {
          if (identical(_memberProfilePrewarms[groupId]?.operation, load)) {
            _memberProfilePrewarms.remove(groupId);
          }
        });
    _memberProfilePrewarms[groupId] = _GroupMemberProfilePrewarmOperation(
      owner: ownerOperation,
      rosterKey: rosterKey,
      operation: load,
    );
    return load;
  }

  Future<void> _prewarmCachedMemberProfiles(
    String groupId,
    List<GroupMemberSummary> members, {
    required String rosterKey,
    required _GroupOwnerOperation ownerOperation,
  }) async {
    try {
      await ref
          .read(peerDisplayProfileProvider.notifier)
          .loadCached(
            ownerDid: ownerOperation.epoch.ownerDid,
            dids: members.map((member) => member.did),
            peerPersonaIdsByDid: <String, String>{
              for (final member in members)
                if (member.did.trim().isNotEmpty &&
                    (member.peerPersonaId?.trim().isNotEmpty ?? false))
                  member.did.trim(): member.peerPersonaId!.trim(),
            },
            expectedEpoch: ownerOperation.epoch,
          );
    } catch (_) {
      // A local cache miss or legacy cache failure must not block mentions.
    }
    if (!_isGroupOwnerOperationCurrent(ownerOperation)) {
      return;
    }
    final currentMembers = state.membersByGroup[groupId];
    if (currentMembers != null &&
        _memberProfileRosterKey(groupId, currentMembers) == rosterKey) {
      _memberProfileReadyKeys[groupId] = rosterKey;
    }
  }

  String _memberProfileRosterKey(
    String groupId,
    List<GroupMemberSummary> members,
  ) {
    final version = state.memberPages[groupId]?.groupStateVersion?.trim() ?? '';
    final identities = members
        .map(
          (member) =>
              '${member.did.trim()}\u0001${member.peerPersonaId?.trim() ?? ''}',
        )
        .join('\u0002');
    return '$version\u0000$identities';
  }

  Future<List<GroupMemberSummary>> _hydrateMemberProfiles(
    List<GroupMemberSummary> members, {
    required _GroupOwnerOperation ownerOperation,
  }) async {
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
          if (!_isGroupOwnerOperationCurrent(ownerOperation)) {
            return member;
          }
          ref
              .read(peerDisplayProfileProvider.notifier)
              .updateFromRemote(
                ownerDid: ownerOperation.epoch.ownerDid,
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

  bool _isOwnerOperationCurrent(int generation, SessionEpoch epoch) {
    return mounted &&
        generation == _memberLoadGeneration &&
        ref.read(sessionProvider).activeEpoch == epoch;
  }

  Future<GroupSummary> refreshGroup(
    String groupId, {
    bool refreshMembers = true,
  }) async {
    final ownerOperation = _captureOwnerOperation();
    late GroupSummary group;
    Object? groupError;
    StackTrace? groupStackTrace;
    try {
      group = await ref.read(groupApplicationServiceProvider).getGroup(groupId);
    } catch (error, stackTrace) {
      groupError = error;
      groupStackTrace = stackTrace;
    }
    _requireCurrentOwnerOperation(ownerOperation);
    if (refreshMembers) {
      await _loadGroupMembers(
        groupId.trim(),
        ownerOperation: ownerOperation,
        hydrateProfiles: true,
        limit: 100,
      );
    } else {
      await _ensureGroupMembersLoaded(
        groupId.trim(),
        ownerOperation: ownerOperation,
      );
    }
    if (groupError != null) {
      Error.throwWithStackTrace(groupError, groupStackTrace!);
    }
    _requireCurrentOwnerOperation(ownerOperation);
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
    final ownerOperation = _captureOwnerOperation();
    _requireCurrentOwnerOperation(ownerOperation);
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
    _requireCurrentOwnerOperation(ownerOperation);
    upsertGroup(created);
    return created;
  }

  Future<GroupSummary> joinGroup(
    String groupDid, {
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) async {
    final ownerOperation = _captureOwnerOperation();
    _requireCurrentOwnerOperation(ownerOperation);
    final joined = await ref
        .read(groupApplicationServiceProvider)
        .joinGroup(groupDid, identity: identity);
    _requireCurrentOwnerOperation(ownerOperation);
    upsertGroup(joined);
    return joined;
  }

  Future<GroupRebindRecoverySummary> resumeRebindRecovery({int limit = 100}) {
    final ownerOperation = _captureOwnerOperation();
    final active = _recoveryOperation;
    if (active != null && active.owner == ownerOperation) {
      return active.operation;
    }
    late final Future<GroupRebindRecoverySummary> operation;
    operation = _runRebindRecovery(ownerOperation: ownerOperation, limit: limit)
        .whenComplete(() {
          if (identical(_recoveryOperation?.operation, operation)) {
            _recoveryOperation = null;
          }
        });
    _recoveryOperation = _GroupRecoveryOperation(
      owner: ownerOperation,
      operation: operation,
    );
    return operation;
  }

  Future<GroupRebindRecoverySummary> _runRebindRecovery({
    required _GroupOwnerOperation ownerOperation,
    required int limit,
  }) async {
    _requireCurrentOwnerOperation(ownerOperation);
    state = state.copyWith(isResumingRecovery: true);
    try {
      final summary = await ref
          .read(groupApplicationServiceProvider)
          .resumeRebindRecovery(limit: limit);
      _requireCurrentOwnerOperation(ownerOperation);
      state = state.copyWith(
        isResumingRecovery: false,
        recoverySummary: summary,
      );
      return summary;
    } catch (_) {
      if (_isGroupOwnerOperationCurrent(ownerOperation)) {
        state = state.copyWith(isResumingRecovery: false);
      }
      rethrow;
    }
  }

  Future<GroupSummary> addGroupMember({
    required String groupId,
    required String memberRef,
    String role = 'member',
  }) async {
    final ownerOperation = _captureOwnerOperation();
    _requireCurrentOwnerOperation(ownerOperation);
    final updated = await ref
        .read(groupApplicationServiceProvider)
        .addMember(groupDid: groupId, memberRef: memberRef, role: role);
    _requireCurrentOwnerOperation(ownerOperation);
    upsertGroup(updated);
    await _loadGroupMembers(
      groupId.trim(),
      ownerOperation: ownerOperation,
      hydrateProfiles: true,
      limit: 100,
    );
    return updated;
  }

  Future<GroupSummary> removeGroupMember({
    required String groupId,
    required String memberRef,
  }) async {
    final ownerOperation = _captureOwnerOperation();
    _requireCurrentOwnerOperation(ownerOperation);
    final updated = await ref
        .read(groupApplicationServiceProvider)
        .removeMember(groupDid: groupId, memberRef: memberRef);
    _requireCurrentOwnerOperation(ownerOperation);
    upsertGroup(updated);
    await _loadGroupMembers(
      groupId.trim(),
      ownerOperation: ownerOperation,
      hydrateProfiles: true,
      limit: 100,
    );
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
    _memberLoadGenerations.clear();
    _groupLoadGeneration += 1;
    _memberLoadGeneration += 1;
    _initialMemberLoads.clear();
    _memberProfilePrewarms.clear();
    _memberProfileReadyKeys.clear();
    _recoveryOperation = null;
    state = const GroupState();
  }

  _GroupOwnerOperation _captureOwnerOperation() {
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    return _GroupOwnerOperation(
      generation: _memberLoadGeneration,
      epoch: epoch,
    );
  }

  bool _isGroupOwnerOperationCurrent(_GroupOwnerOperation operation) {
    return _isOwnerOperationCurrent(operation.generation, operation.epoch);
  }

  void _requireCurrentOwnerOperation(_GroupOwnerOperation operation) {
    if (!_isGroupOwnerOperationCurrent(operation)) {
      throw sessionEpochChangedError();
    }
  }
}

List<GroupMemberSummary> _deduplicateMembers(List<GroupMemberSummary> members) {
  final byDid = <String, GroupMemberSummary>{};
  for (final member in members) {
    byDid[member.did] = member;
  }
  return byDid.values.toList(growable: false);
}

void _validatePageCursor<T>(
  GroupCollectionPage<T> page, {
  String? previousCursor,
}) {
  final nextCursor = page.nextCursor?.trim();
  if ((page.hasMore && (nextCursor == null || nextCursor.isEmpty)) ||
      (!page.hasMore && nextCursor != null) ||
      (page.hasMore && nextCursor == previousCursor)) {
    throw StateError('group_page_cursor_invalid');
  }
}

bool _hasRecoveryWork(GroupRebindRecoverySummary summary) {
  return summary.processed > 0 ||
      summary.completed > 0 ||
      summary.hasPending ||
      summary.hasBlocked ||
      summary.items.isNotEmpty;
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
