import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/group_core_port.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/group_member_summary.dart';
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
  }) async {
    if ((_runtime.config.anpServiceDid ?? '').trim().isEmpty) {
      throw StateError('Group creation requires AWIKI_ANP_SERVICE_DID');
    }
    final result = await (await _runtime.currentClient()).groups.createGroup(
      core.CreateGroupRequest(
        name: name,
        slug: slug,
        description: description,
        goal: goal,
        rules: rules,
        messagePrompt: messagePrompt,
      ),
    );
    return _groupFromResult(result);
  }

  @override
  Future<GroupSummary> joinGroup(String groupDid) async {
    final result = await (await _runtime.currentClient()).groups.joinGroup(
      groupDid,
    );
    return _groupFromResult(result);
  }

  @override
  Future<GroupSummary> getGroup(String groupDid) async {
    final result = await (await _runtime.currentClient()).groups.getGroup(
      groupDid,
    );
    return _groupFromResult(result);
  }

  @override
  Future<List<GroupSummary>> listGroups({int limit = 100}) async {
    final result = await (await _runtime.currentClient()).groups.listGroups(
      limit: limit,
    );
    return result.groups.map(_mappers.groupFromCoreSummary).toList();
  }

  @override
  Future<List<GroupMemberSummary>> listMembers(
    String groupDid, {
    int limit = 100,
  }) async {
    final result = await (await _runtime.currentClient()).groups.listMembers(
      groupDid,
      limit: limit,
    );
    return result.members.map(_mappers.groupMemberFromCore).toList();
  }

  @override
  Future<List<ChatMessage>> listMessages(
    String groupDid, {
    int limit = 100,
    String? cursor,
  }) async {
    final client = await _runtime.currentClient();
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
        .where((message) => message.hasDisplayableText)
        .toList();
  }

  @override
  Future<void> leaveGroup(String groupDid) async {
    await (await _runtime.currentClient()).groups.leaveGroup(groupDid);
  }

  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberDid,
    String role = 'member',
  }) {
    // TODO(im-core): enable when Dart group mutation facade exposes addMember.
    throw UnsupportedError('IM Core group addMember is not available yet');
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberDid,
  }) {
    // TODO(im-core): enable when Dart group mutation facade exposes removeMember.
    throw UnsupportedError('IM Core group removeMember is not available yet');
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
