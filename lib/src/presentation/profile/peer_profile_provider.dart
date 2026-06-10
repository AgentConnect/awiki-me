import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';
import '../shared/formatters/display_formatters.dart';
import '../friends/friends_provider.dart';
import 'profile_provider.dart';
import '../../domain/entities/user_profile.dart';

class PeerProfileState {
  const PeerProfileState({
    this.profile,
    this.relationship = 'none',
    this.isLoading = true,
    this.isActionBusy = false,
  });

  final UserProfile? profile;
  final String relationship;
  final bool isLoading;
  final bool isActionBusy;

  PeerProfileState copyWith({
    UserProfile? profile,
    String? relationship,
    bool? isLoading,
    bool? isActionBusy,
  }) {
    return PeerProfileState(
      profile: profile ?? this.profile,
      relationship: relationship ?? this.relationship,
      isLoading: isLoading ?? this.isLoading,
      isActionBusy: isActionBusy ?? this.isActionBusy,
    );
  }
}

class PeerProfileController extends StateNotifier<PeerProfileState> {
  PeerProfileController(this.ref, this.did) : super(const PeerProfileState()) {
    load();
  }

  final Ref ref;
  final String did;

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    final profile = await ref
        .read(profileApplicationServiceProvider)
        .loadPublicProfile(did);
    final relationship = await ref
        .read(friendsProvider.notifier)
        .checkRelationship(did);
    UserProfile resolved = profile;
    final homepageUrl = DidDisplayFormatter.homepageUrl(profile);
    if (homepageUrl.isNotEmpty) {
      final markdown = await ref.read(homepageMarkdownLoaderProvider)(
        homepageUrl,
      );
      if (markdown != null && markdown.trim().isNotEmpty) {
        resolved = profile.copyWith(profileMarkdown: markdown);
      }
    }
    state = state.copyWith(
      profile: resolved,
      relationship: relationship?.relationship ?? 'none',
      isLoading: false,
    );
  }

  Future<void> unfollow() async {
    state = state.copyWith(isActionBusy: true);
    await ref.read(friendsProvider.notifier).unfollow(did);
    state = state.copyWith(relationship: 'none', isActionBusy: false);
  }

  void showLinkOpenError(Object error) {
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.linkOpenFailed('$error'));
  }
}

final peerProfileProvider =
    StateNotifierProvider.family<
      PeerProfileController,
      PeerProfileState,
      String
    >((ref, did) => PeerProfileController(ref, did));
