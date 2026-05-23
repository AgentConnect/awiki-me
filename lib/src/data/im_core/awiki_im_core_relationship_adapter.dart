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
    final status = await (await _runtime.currentClient()).directory
        .relationStatus(peer);
    return _mappers.relationshipFromCore(status);
  }

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) {
    // TODO(im-core): enable when SDK exposes listFollowers.
    throw UnsupportedError('IM Core listFollowers is not available yet');
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) {
    // TODO(im-core): enable when SDK exposes listFollowing.
    throw UnsupportedError('IM Core listFollowing is not available yet');
  }

  @override
  Future<void> follow(String peer) {
    // TODO(im-core): enable when SDK follow facade is implemented/public.
    throw UnsupportedError('IM Core follow is not available yet');
  }

  @override
  Future<void> unfollow(String peer) {
    // TODO(im-core): enable when SDK unfollow facade is implemented/public.
    throw UnsupportedError('IM Core unfollow is not available yet');
  }
}
