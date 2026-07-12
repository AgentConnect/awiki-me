import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';

import '../../app/app_services.dart';
import '../../application/ports/relationship_core_port.dart';
import '../../domain/entities/relationship_summary.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/peer_display_profile_provider.dart';

enum FriendsRelationshipListType { following, followers }

class FriendsState {
  const FriendsState({
    this.followers = const <RelationshipSummary>[],
    this.following = const <RelationshipSummary>[],
    this.followingAliases = const <String>{},
    this.notFollowingAliases = const <String>{},
    this.isLoading = false,
    this.followersError,
    this.followingError,
  });

  final List<RelationshipSummary> followers;
  final List<RelationshipSummary> following;

  /// Short-lived optimistic aliases waiting for a relationship list refresh.
  final Set<String> followingAliases;
  final Set<String> notFollowingAliases;
  final bool isLoading;
  final Object? followersError;
  final Object? followingError;

  bool get hasRefreshError => followersError != null || followingError != null;

  bool isFollowing(String did) {
    final target = _normalizeIdentity(did);
    if (target.isEmpty || notFollowingAliases.contains(target)) {
      return false;
    }
    return followingAliases.contains(target) ||
        following.any((item) => _normalizeIdentity(item.did) == target);
  }

  FriendsState copyWith({
    List<RelationshipSummary>? followers,
    List<RelationshipSummary>? following,
    Set<String>? followingAliases,
    Set<String>? notFollowingAliases,
    bool? isLoading,
    Object? followersError,
    bool clearFollowersError = false,
    Object? followingError,
    bool clearFollowingError = false,
  }) {
    return FriendsState(
      followers: followers ?? this.followers,
      following: following ?? this.following,
      followingAliases: followingAliases ?? this.followingAliases,
      notFollowingAliases: notFollowingAliases ?? this.notFollowingAliases,
      isLoading: isLoading ?? this.isLoading,
      followersError: clearFollowersError
          ? null
          : (followersError ?? this.followersError),
      followingError: clearFollowingError
          ? null
          : (followingError ?? this.followingError),
    );
  }
}

class FriendsController extends StateNotifier<FriendsState> {
  FriendsController(
    this.ref, {
    this.mutationTimeout = const Duration(seconds: 15),
    this.refreshTimeout = const Duration(seconds: 12),
  }) : super(const FriendsState());

  final Ref ref;
  final Duration mutationTimeout;
  final Duration refreshTimeout;
  int _refreshGeneration = 0;

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    state = state.copyWith(
      isLoading: true,
      clearFollowersError: true,
      clearFollowingError: true,
    );
    final relationships = ref.read(relationshipApplicationServiceProvider);
    final results = await Future.wait<_RelationshipRefreshResult>(
      <Future<_RelationshipRefreshResult>>[
        _loadRelationshipPage(relationships.listFollowers()),
        _loadRelationshipPage(relationships.listFollowing()),
      ],
    );
    if (!mounted || generation != _refreshGeneration) {
      return;
    }
    final followersResult = results[0];
    final followingResult = results[1];
    await _loadCachedPeerProfiles(<RelationshipSummary>[
      ...?followersResult.page?.items,
      ...?followingResult.page?.items,
    ]);
    if (!mounted || generation != _refreshGeneration) {
      return;
    }
    final followingItems = followingResult.page?.items;
    var followingAliases = state.followingAliases;
    var notFollowingAliases = state.notFollowingAliases;
    if (followingItems != null) {
      final followingIdentities = followingItems
          .map((item) => _normalizeIdentity(item.did))
          .where((identity) => identity.isNotEmpty)
          .toSet();
      followingAliases = state.followingAliases
          .where((alias) => !followingIdentities.contains(alias))
          .toSet();
      notFollowingAliases = state.notFollowingAliases
          .where(followingIdentities.contains)
          .toSet();
    }
    state = FriendsState(
      followers: followersResult.page?.items ?? state.followers,
      following: followingItems ?? state.following,
      followingAliases: followingAliases,
      notFollowingAliases: notFollowingAliases,
      isLoading: false,
      followersError: followersResult.error,
      followingError: followingResult.error,
    );
    if (state.hasRefreshError) {
      debugPrint(
        '[awiki_me][friends] relationship_refresh_failed '
        'followers=${followersResult.error.runtimeType} '
        'following=${followingResult.error.runtimeType}',
      );
    }
  }

  Future<_RelationshipRefreshResult> _loadRelationshipPage(
    Future<CoreRelationshipPage> operation,
  ) async {
    try {
      return _RelationshipRefreshResult(
        page: await operation.timeout(refreshTimeout),
      );
    } catch (error) {
      return _RelationshipRefreshResult(error: error);
    }
  }

  Future<void> _loadCachedPeerProfiles(
    Iterable<RelationshipSummary> items,
  ) async {
    final ownerDid = ref.read(sessionProvider).session?.did ?? '';
    await ref
        .read(peerDisplayProfileProvider.notifier)
        .loadCached(ownerDid: ownerDid, dids: items.map((item) => item.did));
  }

  Future<void> follow(String didOrHandle) async {
    final relationships = ref.read(relationshipApplicationServiceProvider);
    await _runMutation(
      operation: relationships.follow(didOrHandle),
      applyOptimisticState: () => _markFollowing(didOrHandle),
    );
  }

  Future<void> unfollow(String didOrHandle) async {
    final relationships = ref.read(relationshipApplicationServiceProvider);
    await _runMutation(
      operation: relationships.unfollow(didOrHandle),
      applyOptimisticState: () => _markNotFollowing(didOrHandle),
    );
  }

  Future<void> _runMutation({
    required Future<void> operation,
    required void Function() applyOptimisticState,
  }) async {
    try {
      await operation.timeout(mutationTimeout);
    } on TimeoutException {
      // A Dart timeout cannot cancel the native request. If it later succeeds,
      // reconcile the presentation overlay without keeping the button busy.
      unawaited(
        operation.then<void>(
          (_) => _applyMutationResult(applyOptimisticState),
          onError: (_) {},
        ),
      );
      rethrow;
    }
    _applyMutationResult(applyOptimisticState);
  }

  void _applyMutationResult(void Function() applyOptimisticState) {
    if (!mounted) {
      return;
    }
    applyOptimisticState();
    _invalidateRelationshipLists();
    unawaited(refresh());
  }

  void _markFollowing(String didOrHandle) {
    final alias = _normalizeIdentity(didOrHandle);
    if (alias.isEmpty) {
      return;
    }
    final following =
        state.following.any((item) => _normalizeIdentity(item.did) == alias)
        ? state.following
        : alias.startsWith('did:')
        ? <RelationshipSummary>[
            ...state.following,
            RelationshipSummary(
              did: didOrHandle.trim(),
              displayName: didOrHandle.trim(),
              relationship: 'following',
            ),
          ]
        : state.following;
    state = state.copyWith(
      following: following,
      followingAliases: <String>{...state.followingAliases, alias},
      notFollowingAliases: state.notFollowingAliases
          .where((item) => item != alias)
          .toSet(),
    );
  }

  void _markNotFollowing(String didOrHandle) {
    final alias = _normalizeIdentity(didOrHandle);
    if (alias.isEmpty) {
      return;
    }
    state = state.copyWith(
      following: state.following
          .where((item) => _normalizeIdentity(item.did) != alias)
          .toList(),
      followingAliases: state.followingAliases
          .where((item) => item != alias)
          .toSet(),
      notFollowingAliases: <String>{...state.notFollowingAliases, alias},
    );
  }

  Future<RelationshipSummary?> checkRelationship(String didOrHandle) async {
    return ref.read(relationshipApplicationServiceProvider).status(didOrHandle);
  }

  void clear() {
    _refreshGeneration += 1;
    state = const FriendsState();
    _invalidateRelationshipLists();
  }

  void _invalidateRelationshipLists() {
    // Invalidate the family itself so only currently observed list instances
    // reload. Invalidating concrete, unobserved arguments constructs both
    // controllers and starts duplicate network requests.
    ref.invalidate(relationshipListProvider);
  }
}

final friendsProvider = StateNotifierProvider<FriendsController, FriendsState>(
  (ref) => FriendsController(ref),
);

class _RelationshipRefreshResult {
  const _RelationshipRefreshResult({this.page, this.error});

  final CoreRelationshipPage? page;
  final Object? error;
}

class RelationshipListState {
  const RelationshipListState({
    this.items = const <RelationshipSummary>[],
    this.nextCursor,
    this.hasMore = false,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<RelationshipSummary> items;
  final String? nextCursor;
  final bool hasMore;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  RelationshipListState copyWith({
    List<RelationshipSummary>? items,
    String? nextCursor,
    bool clearNextCursor = false,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
  }) {
    return RelationshipListState(
      items: items ?? this.items,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class RelationshipListController extends StateNotifier<RelationshipListState> {
  RelationshipListController(
    this.ref,
    this.type, {
    this.requestTimeout = const Duration(seconds: 12),
  }) : super(const RelationshipListState()) {
    unawaited(refresh());
  }

  static const int pageSize = 30;

  final Ref ref;
  final FriendsRelationshipListType type;
  final Duration requestTimeout;

  Future<void> refresh() async {
    if (state.isLoading) {
      return;
    }
    state = state.copyWith(
      isLoading: true,
      isLoadingMore: false,
      clearError: true,
      clearNextCursor: true,
    );
    try {
      final page = await _loadPage(cursor: null);
      await _loadCachedPeerProfiles(page.items);
      await _refreshMissingPeerProfiles(page.items);
      if (!mounted) {
        return;
      }
      state = RelationshipListState(
        items: page.items,
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) {
      return;
    }
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final page = await _loadPage(cursor: state.nextCursor);
      await _loadCachedPeerProfiles(page.items);
      await _refreshMissingPeerProfiles(page.items);
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        items: <RelationshipSummary>[...state.items, ...page.items],
        nextCursor: page.nextCursor,
        hasMore: page.hasMore,
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(isLoadingMore: false, error: error);
    }
  }

  Future<CoreRelationshipPage> _loadPage({required String? cursor}) {
    final relationships = ref.read(relationshipApplicationServiceProvider);
    switch (type) {
      case FriendsRelationshipListType.following:
        return relationships
            .listFollowing(limit: pageSize, cursor: cursor)
            .timeout(requestTimeout);
      case FriendsRelationshipListType.followers:
        return relationships
            .listFollowers(limit: pageSize, cursor: cursor)
            .timeout(requestTimeout);
    }
  }

  Future<void> _loadCachedPeerProfiles(
    Iterable<RelationshipSummary> items,
  ) async {
    final ownerDid = ref.read(sessionProvider).session?.did ?? '';
    await ref
        .read(peerDisplayProfileProvider.notifier)
        .loadCached(ownerDid: ownerDid, dids: items.map((item) => item.did));
  }

  Future<void> _refreshMissingPeerProfiles(
    Iterable<RelationshipSummary> items,
  ) async {
    final ownerDid = ref.read(sessionProvider).session?.did ?? '';
    await ref
        .read(peerDisplayProfileProvider.notifier)
        .refreshRemoteMissing(
          ownerDid: ownerDid,
          dids: items.map((item) => item.did),
        );
  }
}

final relationshipListProvider =
    StateNotifierProvider.family<
      RelationshipListController,
      RelationshipListState,
      FriendsRelationshipListType
    >((ref, type) => RelationshipListController(ref, type));

String _normalizeIdentity(String value) => value.trim();
