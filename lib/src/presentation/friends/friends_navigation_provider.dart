import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/relationship_summary.dart';
import 'friends_provider.dart';

enum FriendsWorkspaceDetail {
  overview,
  relationships,
  groups,
  groupChat,
  profile,
}

enum FriendsProfileParent { overview, relationships }

@immutable
class FriendsWorkspaceNavigationState {
  const FriendsWorkspaceNavigationState({
    this.detail = FriendsWorkspaceDetail.overview,
    this.relationshipType = FriendsRelationshipListType.following,
    this.profileParent = FriendsProfileParent.overview,
    this.selectedDid,
    this.selectedGroupConversation,
  });

  final FriendsWorkspaceDetail detail;
  final FriendsRelationshipListType relationshipType;
  final FriendsProfileParent profileParent;
  final String? selectedDid;
  final ConversationSummary? selectedGroupConversation;

  bool get showsCompactDetail => detail != FriendsWorkspaceDetail.overview;

  bool get keepsRelationshipPageInCompactStack =>
      detail == FriendsWorkspaceDetail.relationships ||
      (detail == FriendsWorkspaceDetail.profile &&
          profileParent == FriendsProfileParent.relationships);

  FriendsWorkspaceNavigationState copyWith({
    FriendsWorkspaceDetail? detail,
    FriendsRelationshipListType? relationshipType,
    FriendsProfileParent? profileParent,
    String? selectedDid,
    bool clearSelectedDid = false,
    ConversationSummary? selectedGroupConversation,
    bool clearSelectedGroupConversation = false,
  }) {
    return FriendsWorkspaceNavigationState(
      detail: detail ?? this.detail,
      relationshipType: relationshipType ?? this.relationshipType,
      profileParent: profileParent ?? this.profileParent,
      selectedDid: clearSelectedDid ? null : selectedDid ?? this.selectedDid,
      selectedGroupConversation: clearSelectedGroupConversation
          ? null
          : selectedGroupConversation ?? this.selectedGroupConversation,
    );
  }
}

class FriendsWorkspaceNavigationController
    extends StateNotifier<FriendsWorkspaceNavigationState> {
  FriendsWorkspaceNavigationController()
    : super(const FriendsWorkspaceNavigationState());

  void showRelationships(FriendsRelationshipListType type) {
    state = FriendsWorkspaceNavigationState(
      detail: FriendsWorkspaceDetail.relationships,
      relationshipType: type,
    );
  }

  void showGroups() {
    state = state.copyWith(
      detail: FriendsWorkspaceDetail.groups,
      profileParent: FriendsProfileParent.overview,
      clearSelectedDid: true,
      clearSelectedGroupConversation: true,
    );
  }

  void showGroupChat(ConversationSummary conversation) {
    state = state.copyWith(
      detail: FriendsWorkspaceDetail.groupChat,
      selectedGroupConversation: conversation,
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
    final profileParent = state.detail == FriendsWorkspaceDetail.relationships
        ? FriendsProfileParent.relationships
        : FriendsProfileParent.overview;
    state = state.copyWith(
      detail: FriendsWorkspaceDetail.profile,
      profileParent: profileParent,
      selectedDid: normalized,
      clearSelectedGroupConversation: true,
    );
  }

  void closeDetail() {
    if (state.detail == FriendsWorkspaceDetail.overview) {
      return;
    }
    final destination = switch (state.detail) {
      FriendsWorkspaceDetail.profile =>
        state.profileParent == FriendsProfileParent.relationships
            ? FriendsWorkspaceDetail.relationships
            : FriendsWorkspaceDetail.overview,
      FriendsWorkspaceDetail.relationships ||
      FriendsWorkspaceDetail.groups ||
      FriendsWorkspaceDetail.groupChat => FriendsWorkspaceDetail.overview,
      FriendsWorkspaceDetail.overview => FriendsWorkspaceDetail.overview,
    };
    state = state.copyWith(
      detail: destination,
      clearSelectedDid: true,
      clearSelectedGroupConversation: true,
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
