import '../../application/ports/relationship_core_port.dart';
import '../../domain/entities/relationship_summary.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreRelationshipAdapter implements RelationshipCorePort {
  AwikiImCoreRelationshipAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<RelationshipSummary> status(String peer) async {
    final status = await _runtime.withCurrentClient(
      (client) => client.directory.relationStatus(peer),
    );
    return _mappers.relationshipFromCore(status);
  }

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) async {
    final offset = _offsetFromCursor(cursor);
    final page = await _runtime.withCurrentClient(
      (client) => client.directory.listFollowers(
        limit: limit,
        offset: offset,
        hydrateProfiles: true,
      ),
    );
    return _mappers.relationshipPageFromCore(
      page,
      fallbackCursorOffset: offset,
    );
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) async {
    final offset = _offsetFromCursor(cursor);
    final page = await _runtime.withCurrentClient(
      (client) => client.directory.listFollowing(
        limit: limit,
        offset: offset,
        hydrateProfiles: true,
      ),
    );
    return _mappers.relationshipPageFromCore(
      page,
      fallbackCursorOffset: offset,
    );
  }

  @override
  Future<void> follow(String peer) async {
    await _runtime.withCurrentClient((client) => client.directory.follow(peer));
  }

  @override
  Future<void> unfollow(String peer) async {
    await _runtime.withCurrentClient(
      (client) => client.directory.unfollow(peer),
    );
  }
}

int _offsetFromCursor(String? cursor) {
  if (cursor == null || cursor.trim().isEmpty) {
    return 0;
  }
  final offset = int.tryParse(cursor.trim());
  if (offset == null || offset < 0) {
    throw ArgumentError.value(
      cursor,
      'cursor',
      'must be a non-negative offset',
    );
  }
  return offset;
}
