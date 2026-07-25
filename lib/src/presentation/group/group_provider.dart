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

class _GroupRecoveryOperation {
  const _GroupRecoveryOperation({required this.owner, required this.operation});

  final _GroupOwnerOperation owner;
  final Future<GroupRebindRecoverySummary> operation;
}

class GroupController extends StateNotifier<GroupState> {
  GroupController(this.ref) : super(const GroupState());

  final Ref ref;
  final Map<String, _GroupMemberLoadOperation> _initialMemberLoads =
      <String, _GroupMemberLoadOperation>{};
  int _memberLoadGeneration = 0;
  _GroupRecoveryOperation? _recoveryOperation;

  Future<void> refresh() async {
    final ownerOperation = _captureOwnerOperation();
    state = state.copyWith(isLoading: true);
    try {
      final groups = await ref
          .read(groupApplicationServiceProvider)
          .listGroups();
      if (!_isGroupOwnerOperationCurrent(ownerOperation)) {
        return;
      }
      final merged = _mergeGroupList(
        local: state.groups,
        incoming: groups,
        keepLocalOnly: false,
      );
      state = state.copyWith(groups: merged, isLoading: false);
    } catch (_) {
      if (_isGroupOwnerOperationCurrent(ownerOperation)) {
        state = state.copyWith(isLoading: false);
      }
      rethrow;
    }
  }

  Future<List<GroupMemberSummary>> loadGroupMembers(String groupId) async {
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
      return Future<List<GroupMemberSummary>>.value(cached);
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
  }) async {
    _requireCurrentOwnerOperation(ownerOperation);
    final members = await ref
        .read(groupApplicationServiceProvider)
        .listMembers(groupId);
    _requireCurrentOwnerOperation(ownerOperation);
    _publishGroupMembers(groupId, members);
    if (!hydrateProfiles) {
      return members;
    }
    final hydratedMembers = await _hydrateMemberProfiles(
      members,
      ownerOperation: ownerOperation,
    );
    _requireCurrentOwnerOperation(ownerOperation);
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
    _memberLoadGeneration += 1;
    _initialMemberLoads.clear();
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
