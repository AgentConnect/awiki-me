import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/group_core_port.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_identity.dart';
import '../../domain/entities/group_summary.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreGroupAdapter implements GroupCorePort {
  AwikiImCoreGroupAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<GroupSummary> createGroup({
    required String name,
    required String slug,
    required String description,
    required String goal,
    required String rules,
    String? messagePrompt,
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) async {
    if ((_runtime.config.anpServiceDid ?? '').trim().isEmpty) {
      throw StateError('Group creation requires an ANP service DID.');
    }
    final result = await _runtime.withCurrentClient(
      (client) => client.groups.createGroup(
        mapCoreCreateGroupRequest(
          name: name,
          slug: slug,
          description: description,
          goal: goal,
          rules: rules,
          messagePrompt: messagePrompt,
          identity: identity,
          secureRequired: _runtime.multiDeviceGroupE2eeEnabled,
        ),
      ),
    );
    return _groupFromResult(result);
  }

  @override
  Future<GroupSummary> joinGroup(
    String groupDid, {
    GroupIdentitySelection identity = const GroupIdentitySelection.didOnly(),
  }) async {
    final result = await _runtime.withCurrentClient(
      (client) => client.groups.joinGroupWithIdentity(
        mapCoreJoinGroupRequest(groupDid, identity),
      ),
    );
    return _groupFromResult(result);
  }

  @override
  Future<GroupRebindRecoverySummary> resumeRebindRecovery({
    int limit = 100,
  }) async {
    final result = await _runtime.withCurrentClient(
      (client) => client.groups.resumeRebindRecovery(limit: limit),
    );
    return GroupRebindRecoverySummary(
      processed: result.processed,
      completed: result.completed,
      pending: result.pending,
      blocked: result.blocked,
      sendPausedGroupDids: result.sendPausedGroupDids,
      items: result.items
          .map(
            (item) => GroupRebindRecoveryItem(
              groupDid: item.groupDid,
              layer: item.layer,
              phase: item.phase,
              blocked: item.blocked,
            ),
          )
          .toList(growable: false),
      warnings: result.warnings,
    );
  }

  @override
  Future<GroupSummary> getGroup(String groupDid) async {
    final result = await _runtime.withCurrentClient(
      (client) => client.groups.getGroup(groupDid),
    );
    return _groupFromResult(result);
  }

  @override
  Future<List<GroupSummary>> listGroups({int limit = 100}) async {
    final result = await _runtime.withCurrentClient(
      (client) => client.groups.listGroups(limit: limit),
    );
    return result.groups.map(_mappers.groupFromCoreSummary).toList();
  }

  @override
  Future<List<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
  }) async {
    final result = await _runtime.withCurrentClient(
      (client) => client.groups.listMembers(groupDid, limit: limit),
    );
    return result.members.map(_mappers.groupMemberFromCore).toList();
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) async {
    return _runtime.withCurrentClient((client) async {
      final ownerDid = (await client.identity.current()).did;
      final result = await client.groups.listMessages(
        groupDid,
        limit: limit,
        cursor: cursor,
      );
      return result.messages.items
          .map(
            (message) =>
                _mappers.chatMessageFromCore(message, ownerDid: ownerDid),
          )
          .where((message) => message.hasRenderableContent)
          .toList();
    });
  }

  @override
  Future<void> leaveGroup(String groupDid) async {
    await _runtime.withCurrentClient(
      (client) => client.groups.leaveGroup(groupDid),
    );
  }

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) async {
    await _runtime.withCurrentClient(
      (client) =>
          client.groups.addMember(groupDid, memberRef: memberRef, role: role),
    );
    return getGroup(groupDid);
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberRef,
  }) async {
    await _runtime.withCurrentClient(
      (client) => client.groups.removeMember(groupDid, memberRef: memberRef),
    );
    return getGroup(groupDid);
  }

  GroupSummary _groupFromResult(core.GroupReadResult result) {
    final snapshot = result.group;
    if (snapshot != null) {
      return _mappers.groupFromCoreSnapshot(snapshot);
    }
    if (result.groups.isNotEmpty) {
      return _mappers.groupFromCoreSummary(result.groups.first);
    }
    throw StateError('IM Core group response did not include a group.');
  }
}

core.CreateGroupRequest mapCoreCreateGroupRequest({
  required String name,
  required String slug,
  required String description,
  required String goal,
  required String rules,
  required String? messagePrompt,
  required GroupIdentitySelection identity,
  required bool secureRequired,
}) {
  return core.CreateGroupRequest(
    name: name,
    identityMode: _coreIdentityMode(identity.mode),
    identityHandle: identity.handle,
    slug: slug,
    description: description,
    goal: goal,
    rules: rules,
    messagePrompt: messagePrompt,
    messageSecurityProfile: secureRequired
        ? core.GroupMessageSecurityProfile.groupE2ee
        : null,
    e2ee: secureRequired,
    attachmentsAllowed: secureRequired ? true : null,
  );
}

core.JoinGroupRequest mapCoreJoinGroupRequest(
  String groupDid,
  GroupIdentitySelection identity,
) {
  return core.JoinGroupRequest(
    groupDid: groupDid,
    identityMode: _coreIdentityMode(identity.mode),
    identityHandle: identity.handle,
  );
}

core.GroupIdentityMode _coreIdentityMode(GroupIdentityMode mode) {
  return switch (mode) {
    GroupIdentityMode.handle => core.GroupIdentityMode.handle,
    GroupIdentityMode.didOnly => core.GroupIdentityMode.didOnly,
  };
}
