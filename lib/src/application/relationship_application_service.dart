import '../domain/entities/relationship_summary.dart';
import 'ports/relationship_core_port.dart';

abstract interface class RelationshipApplicationService {
  Future<CoreRelationshipPage> listFollowers({int limit = 100, String? cursor});

  Future<CoreRelationshipPage> listFollowing({int limit = 100, String? cursor});

  Future<RelationshipSummary> status(String peer);

  Future<void> follow(String peer);

  Future<void> unfollow(String peer);
}

class ImCoreRelationshipApplicationService
    implements RelationshipApplicationService {
  const ImCoreRelationshipApplicationService({
    required RelationshipCorePort relationships,
  }) : _relationships = relationships;

  final RelationshipCorePort _relationships;

  @override
  Future<void> follow(String peer) => _relationships.follow(peer.trim());

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) {
    return _relationships.listFollowers(limit: limit, cursor: cursor);
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) {
    return _relationships.listFollowing(limit: limit, cursor: cursor);
  }

  @override
  Future<RelationshipSummary> status(String peer) {
    return _relationships.status(peer.trim());
  }

  @override
  Future<void> unfollow(String peer) => _relationships.unfollow(peer.trim());
}
