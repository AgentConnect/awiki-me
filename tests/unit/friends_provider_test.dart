import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/presentation/friends/friends_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('follow returns before slow relationship list reconciliation', () async {
    final service = _RelationshipService();
    final followers = Completer<CoreRelationshipPage>();
    final following = Completer<CoreRelationshipPage>();
    service.followersResult = followers.future;
    service.followingResult = following.future;
    final container = _container(
      service,
      refreshTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(container.dispose);

    await container
        .read(friendsProvider.notifier)
        .follow('did:wba:awiki.ai:alice');

    expect(service.followCalls, 1);
    expect(service.listFollowersCalls, 1);
    expect(service.listFollowingCalls, 1);
    expect(
      container.read(friendsProvider).isFollowing('did:wba:awiki.ai:alice'),
      isTrue,
    );
    expect(container.read(friendsProvider).isLoading, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(friendsProvider).isLoading, isFalse);
  });

  test(
    'stale following refresh does not roll back optimistic follow',
    () async {
      final service = _RelationshipService();
      final container = _container(service);
      addTearDown(container.dispose);

      await container
          .read(friendsProvider.notifier)
          .follow('did:wba:awiki.ai:alice');
      await Future<void>.delayed(Duration.zero);

      final state = container.read(friendsProvider);
      expect(state.following, isEmpty);
      expect(state.isFollowing('did:wba:awiki.ai:alice'), isTrue);
    },
  );

  test(
    'stale following refresh does not roll back optimistic unfollow',
    () async {
      const peer = 'did:wba:awiki.ai:alice';
      final service = _RelationshipService(
        following: const <RelationshipSummary>[
          RelationshipSummary(
            did: peer,
            displayName: 'Alice',
            relationship: 'following',
          ),
        ],
      );
      final container = _container(service);
      addTearDown(container.dispose);
      final controller = container.read(friendsProvider.notifier);
      await controller.refresh();

      await controller.unfollow(peer);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(friendsProvider).following, isNotEmpty);
      expect(container.read(friendsProvider).isFollowing(peer), isFalse);
    },
  );

  test(
    'hung follow times out and late success reconciles without busy wait',
    () async {
      const peer = 'did:wba:awiki.ai:alice';
      final operation = Completer<void>();
      final service = _RelationshipService()..followResult = operation.future;
      final container = _container(
        service,
        mutationTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(container.dispose);
      final controller = container.read(friendsProvider.notifier);

      await expectLater(
        controller.follow(peer),
        throwsA(isA<TimeoutException>()),
      );
      expect(container.read(friendsProvider).isFollowing(peer), isFalse);

      operation.complete();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(friendsProvider).isFollowing(peer), isTrue);
    },
  );

  test('failed follow does not create an optimistic relationship', () async {
    const peer = 'did:wba:awiki.ai:alice';
    final service = _RelationshipService()
      ..followResult = Future<void>.error(StateError('follow failed'));
    final container = _container(service);
    addTearDown(container.dispose);

    await expectLater(
      container.read(friendsProvider.notifier).follow(peer),
      throwsStateError,
    );

    expect(container.read(friendsProvider).isFollowing(peer), isFalse);
    expect(service.listFollowersCalls, 0);
    expect(service.listFollowingCalls, 0);
  });

  test('unsupported relationship lists release loading state', () async {
    final service = _RelationshipService()
      ..followersResult = Future<CoreRelationshipPage>.error(
        UnsupportedError('relationship list unavailable'),
      );
    final container = _container(service);
    addTearDown(container.dispose);

    await container.read(friendsProvider.notifier).refresh();

    expect(container.read(friendsProvider).isLoading, isFalse);
    expect(service.listFollowersCalls, 1);
    expect(service.listFollowingCalls, 1);
  });

  test(
    'handle follow uses overlay without inventing a DID relationship row',
    () async {
      const handle = 'alice.awiki.ai';
      final service = _RelationshipService();
      final container = _container(service);
      addTearDown(container.dispose);

      await container.read(friendsProvider.notifier).follow(handle);

      final state = container.read(friendsProvider);
      expect(state.following, isEmpty);
      expect(state.isFollowing(handle), isTrue);
    },
  );

  test(
    'blank relationship aliases do not mutate presentation overlays',
    () async {
      final service = _RelationshipService();
      final container = _container(service);
      addTearDown(container.dispose);
      final controller = container.read(friendsProvider.notifier);

      await controller.follow('   ');
      await controller.unfollow('');

      final state = container.read(friendsProvider);
      expect(state.following, isEmpty);
      expect(state.followingAliases, isEmpty);
      expect(state.notFollowingAliases, isEmpty);
    },
  );
}

ProviderContainer _container(
  _RelationshipService service, {
  Duration mutationTimeout = const Duration(seconds: 1),
  Duration refreshTimeout = const Duration(seconds: 1),
}) {
  return ProviderContainer(
    overrides: <Override>[
      relationshipApplicationServiceProvider.overrideWithValue(service),
      friendsProvider.overrideWith(
        (ref) => FriendsController(
          ref,
          mutationTimeout: mutationTimeout,
          refreshTimeout: refreshTimeout,
        ),
      ),
    ],
  );
}

class _RelationshipService implements RelationshipApplicationService {
  _RelationshipService({
    List<RelationshipSummary> followers = const <RelationshipSummary>[],
    List<RelationshipSummary> following = const <RelationshipSummary>[],
  }) : followersResult = Future<CoreRelationshipPage>.value(
         CoreRelationshipPage(items: followers, hasMore: false),
       ),
       followingResult = Future<CoreRelationshipPage>.value(
         CoreRelationshipPage(items: following, hasMore: false),
       );

  Future<void> followResult = Future<void>.value();
  Future<void> unfollowResult = Future<void>.value();
  late Future<CoreRelationshipPage> followersResult;
  late Future<CoreRelationshipPage> followingResult;
  int followCalls = 0;
  int listFollowersCalls = 0;
  int listFollowingCalls = 0;

  @override
  Future<void> follow(String peer) {
    followCalls += 1;
    return followResult;
  }

  @override
  Future<CoreRelationshipPage> listFollowers({
    int limit = 100,
    String? cursor,
  }) {
    listFollowersCalls += 1;
    return followersResult;
  }

  @override
  Future<CoreRelationshipPage> listFollowing({
    int limit = 100,
    String? cursor,
  }) {
    listFollowingCalls += 1;
    return followingResult;
  }

  @override
  Future<RelationshipSummary> status(String peer) async {
    return RelationshipSummary(
      did: peer,
      displayName: peer,
      relationship: 'none',
    );
  }

  @override
  Future<void> unfollow(String peer) => unfollowResult;
}
