import '../../domain/entities/relationship_summary.dart';

class CoreRelationshipPage {
  const CoreRelationshipPage({
    required this.items,
    this.nextCursor,
    required this.hasMore,
  });

  final List<RelationshipSummary> items;
  final String? nextCursor;
  final bool hasMore;
}

abstract interface class RelationshipCorePort {
  Future<CoreRelationshipPage> listFollowers({int limit = 100, String? cursor});

  Future<CoreRelationshipPage> listFollowing({int limit = 100, String? cursor});

  Future<RelationshipSummary> status(String peer);

  Future<void> follow(String peer);

  Future<void> unfollow(String peer);
}
