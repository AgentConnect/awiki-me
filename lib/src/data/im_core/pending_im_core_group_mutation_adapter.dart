import '../../application/ports/group_core_port.dart';
import '../../domain/entities/group_summary.dart';

class PendingImCoreGroupMutationAdapter {
  const PendingImCoreGroupMutationAdapter();

  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberDid,
    String role = 'member',
  }) {
    throw UnsupportedError('IM Core group addMember is not available yet');
  }

  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberDid,
  }) {
    throw UnsupportedError('IM Core group removeMember is not available yet');
  }
}

mixin PendingImCoreGroupMutations on GroupCorePort {
  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberDid,
    String role = 'member',
  }) {
    throw UnsupportedError('IM Core group addMember is not available yet');
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberDid,
  }) {
    throw UnsupportedError('IM Core group removeMember is not available yet');
  }
}
