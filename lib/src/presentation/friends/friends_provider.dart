import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/ports/relationship_core_port.dart';
import '../../domain/entities/relationship_summary.dart';

enum FriendsRelationshipListType { following, followers }

class FriendsState {
  const FriendsState({
    this.followers = const <RelationshipSummary>[],
    this.following = const <RelationshipSummary>[],
    this.followingAliases = const <String>{},
    this.isLoading = false,
  });

  final List<RelationshipSummary> followers;
  final List<RelationshipSummary> following;
  final Set<String> followingAliases;
  final bool isLoading;

  bool isFollowing(String did) {
    final target = _normalizeIdentity(did);
    return target.isNotEmpty &&
        (followingAliases.contains(target) ||
            following.any((item) => _normalizeIdentity(item.did) == target));
  }

  FriendsState copyWith({
    List<RelationshipSummary>? followers,
    List<RelationshipSummary>? following,
    Set<String>? followingAliases,
    bool? isLoading,
  }) {
    return FriendsState(
      followers: followers ?? this.followers,
      following: following ?? this.following,
      followingAliases: followingAliases ?? this.followingAliases,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class FriendsController extends StateNotifier<FriendsState> {
  FriendsController(this.ref) : super(const FriendsState());

  final Ref ref;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final relationships = ref.read(relationshipApplicationServiceProvider);
      final followers = await relationships.listFollowers();
      final following = await relationships.listFollowing();
      state = state.copyWith(
        followers: followers.items,
        following: following.items,
        isLoading: false,
      );
    } on UnsupportedError {
      // TODO(im-core): show an explicit unavailable state once relationship
      // list APIs land in the SDK. For now, don't let optional contacts data
      // block profile/conversation/group refresh on macOS.
      state = state.copyWith(isLoading: false);
    } catch (_) {
      // Relationship previews are optional sidebar data. A transient list
      // refresh failure must not leave the contacts page stuck in a loading
      // state or roll back a successful follow/unfollow action.
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> follow(String didOrHandle) async {
    final relationships = ref.read(relationshipApplicationServiceProvider);
    await relationships.follow(didOrHandle);
    _markFollowing(didOrHandle);
    await refresh();
    _invalidateRelationshipLists();
  }

  Future<void> unfollow(String didOrHandle) async {
    await ref
        .read(relationshipApplicationServiceProvider)
        .unfollow(didOrHandle);
    _markNotFollowing(didOrHandle);
    await refresh();
    _invalidateRelationshipLists();
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
    );
  }

  Future<RelationshipSummary?> checkRelationship(String didOrHandle) async {
    return ref.read(relationshipApplicationServiceProvider).status(didOrHandle);
  }

  void clear() {
    state = const FriendsState();
    _invalidateRelationshipLists();
  }

  void _invalidateRelationshipLists() {
    ref.invalidate(
      relationshipListProvider(FriendsRelationshipListType.following),
    );
    ref.invalidate(
      relationshipListProvider(FriendsRelationshipListType.followers),
    );
  }
}

final friendsProvider = StateNotifierProvider<FriendsController, FriendsState>(
  (ref) => FriendsController(ref),
);

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
  RelationshipListController(this.ref, this.type)
    : super(const RelationshipListState()) {
    unawaited(refresh());
  }

  static const int pageSize = 30;

  final Ref ref;
  final FriendsRelationshipListType type;

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
        return relationships.listFollowing(limit: pageSize, cursor: cursor);
      case FriendsRelationshipListType.followers:
        return relationships.listFollowers(limit: pageSize, cursor: cursor);
    }
  }
}

final relationshipListProvider =
    StateNotifierProvider.family<
      RelationshipListController,
      RelationshipListState,
      FriendsRelationshipListType
    >((ref, type) => RelationshipListController(ref, type));

String _normalizeIdentity(String value) => value.trim();
