import '../../application/ports/relationship_core_port.dart';
import '../../domain/entities/relationship_summary.dart';

class PendingImCoreRelationshipAdapter implements RelationshipCorePort {
  const PendingImCoreRelationshipAdapter();

  @override
  Future<void> follow(String peer) {
    throw UnsupportedError('IM Core follow is not available yet');
  }

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) {
    throw UnsupportedError('IM Core listFollowers is not available yet');
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) {
    throw UnsupportedError('IM Core listFollowing is not available yet');
  }

  @override
  Future<RelationshipSummary> status(String peer) {
    throw UnsupportedError('IM Core relationship status is not available yet');
  }

  @override
  Future<void> unfollow(String peer) {
    throw UnsupportedError('IM Core unfollow is not available yet');
  }
}
