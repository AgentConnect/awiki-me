import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/relationship_summary.dart';
import 'friends_provider.dart';

enum FriendsWorkspaceDetail { directory, groups, profile }

@immutable
class FriendsWorkspaceNavigationState {
  const FriendsWorkspaceNavigationState({
    this.detail = FriendsWorkspaceDetail.directory,
    this.relationshipType = FriendsRelationshipListType.following,
    this.selectedDid,
  });

  final FriendsWorkspaceDetail detail;
  final FriendsRelationshipListType relationshipType;
  final String? selectedDid;

  bool get showsCompactDetail =>
      detail == FriendsWorkspaceDetail.groups ||
      detail == FriendsWorkspaceDetail.profile;

  FriendsWorkspaceNavigationState copyWith({
    FriendsWorkspaceDetail? detail,
    FriendsRelationshipListType? relationshipType,
    String? selectedDid,
    bool clearSelectedDid = false,
  }) {
    return FriendsWorkspaceNavigationState(
      detail: detail ?? this.detail,
      relationshipType: relationshipType ?? this.relationshipType,
      selectedDid: clearSelectedDid ? null : selectedDid ?? this.selectedDid,
    );
  }
}

class FriendsWorkspaceNavigationController
    extends StateNotifier<FriendsWorkspaceNavigationState> {
  FriendsWorkspaceNavigationController()
    : super(const FriendsWorkspaceNavigationState());

  void showDirectory(FriendsRelationshipListType type) {
    state = FriendsWorkspaceNavigationState(relationshipType: type);
  }

  void showGroups() {
    state = state.copyWith(
      detail: FriendsWorkspaceDetail.groups,
      clearSelectedDid: true,
    );
  }

  void showProfile(RelationshipSummary contact) {
    showProfileDid(contact.did);
  }

  void showProfileDid(String did) {
    final normalized = did.trim();
    if (normalized.isEmpty) {
      return;
    }
    state = state.copyWith(
      detail: FriendsWorkspaceDetail.profile,
      selectedDid: normalized,
    );
  }

  void closeDetail() {
    state = state.copyWith(
      detail: FriendsWorkspaceDetail.directory,
      clearSelectedDid: true,
    );
  }

  void reset() {
    state = const FriendsWorkspaceNavigationState();
  }
}

final friendsWorkspaceNavigationProvider =
    StateNotifierProvider<
      FriendsWorkspaceNavigationController,
      FriendsWorkspaceNavigationState
    >((ref) => FriendsWorkspaceNavigationController());
