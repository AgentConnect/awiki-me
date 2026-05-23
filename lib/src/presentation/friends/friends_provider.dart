import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/relationship_summary.dart';

class FriendsState {
  const FriendsState({
    this.followers = const <RelationshipSummary>[],
    this.following = const <RelationshipSummary>[],
    this.isLoading = false,
  });

  final List<RelationshipSummary> followers;
  final List<RelationshipSummary> following;
  final bool isLoading;

  FriendsState copyWith({
    List<RelationshipSummary>? followers,
    List<RelationshipSummary>? following,
    bool? isLoading,
  }) {
    return FriendsState(
      followers: followers ?? this.followers,
      following: following ?? this.following,
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
    }
  }

  Future<void> follow(String didOrHandle) async {
    await ref.read(relationshipApplicationServiceProvider).follow(didOrHandle);
    await refresh();
  }

  Future<void> unfollow(String didOrHandle) async {
    await ref
        .read(relationshipApplicationServiceProvider)
        .unfollow(didOrHandle);
    await refresh();
  }

  Future<RelationshipSummary?> checkRelationship(String didOrHandle) async {
    return ref.read(relationshipApplicationServiceProvider).status(didOrHandle);
  }

  void clear() {
    state = const FriendsState();
  }
}

final friendsProvider = StateNotifierProvider<FriendsController, FriendsState>(
  (ref) => FriendsController(ref),
);
