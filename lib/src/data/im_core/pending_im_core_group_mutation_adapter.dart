import '../../application/ports/group_core_port.dart';
import '../../domain/entities/group_summary.dart';

class PendingImCoreGroupMutationAdapter {
  const PendingImCoreGroupMutationAdapter();

  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) {
    throw UnsupportedError('Group addMember is not configured');
  }

  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberRef,
  }) {
    throw UnsupportedError('Group removeMember is not configured');
  }
}

mixin PendingImCoreGroupMutations on GroupCorePort {
  @override
  Future<GroupSummary> addMember({
    required String groupDid,
    required String memberRef,
    String role = 'member',
  }) {
    throw UnsupportedError('Group addMember is not configured');
  }

  @override
  Future<GroupSummary> removeMember({
    required String groupDid,
    required String memberRef,
  }) {
    throw UnsupportedError('Group removeMember is not configured');
  }
}
