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
    final followers = await ref.read(awikiGatewayProvider).listFollowers();
    final following = await ref.read(awikiGatewayProvider).listFollowing();
    state = state.copyWith(
      followers: followers,
      following: following,
      isLoading: false,
    );
  }

  Future<void> follow(String didOrHandle) async {
    await ref.read(awikiGatewayProvider).follow(didOrHandle);
    await refresh();
  }

  Future<void> unfollow(String didOrHandle) async {
    await ref.read(awikiGatewayProvider).unfollow(didOrHandle);
    await refresh();
  }

  Future<RelationshipSummary?> checkRelationship(String didOrHandle) async {
    return ref.read(awikiGatewayProvider).getRelationshipStatus(didOrHandle);
  }

  void clear() {
    state = const FriendsState();
  }
}

final friendsProvider = StateNotifierProvider<FriendsController, FriendsState>(
  (ref) => FriendsController(ref),
);
