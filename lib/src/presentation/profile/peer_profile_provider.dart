import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';
import '../friends/friends_provider.dart';
import 'profile_provider.dart';
import '../../domain/entities/user_profile.dart';

final peerPublicProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, String>((ref, did) {
      return ref
          .watch(profileApplicationServiceProvider)
          .loadPublicProfile(did)
          .timeout(const Duration(seconds: 12));
    });

class PeerProfileState {
  const PeerProfileState({
    this.profile,
    this.relationship = 'none',
    this.isLoading = true,
    this.isActionBusy = false,
    this.error,
  });

  final UserProfile? profile;
  final String relationship;
  final bool isLoading;
  final bool isActionBusy;
  final Object? error;

  bool get hasError => error != null;

  PeerProfileState copyWith({
    UserProfile? profile,
    String? relationship,
    bool? isLoading,
    bool? isActionBusy,
    Object? error,
    bool clearError = false,
  }) {
    return PeerProfileState(
      profile: profile ?? this.profile,
      relationship: relationship ?? this.relationship,
      isLoading: isLoading ?? this.isLoading,
      isActionBusy: isActionBusy ?? this.isActionBusy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PeerProfileController extends StateNotifier<PeerProfileState> {
  PeerProfileController(this.ref, this.did) : super(const PeerProfileState()) {
    unawaited(load());
  }

  final Ref ref;
  final String did;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final UserProfile profile;
    try {
      profile = await ref.read(peerPublicProfileProvider(did).future);
    } catch (error) {
      if (!mounted) {
        return;
      }
      state = state.copyWith(isLoading: false, error: error);
      return;
    }
    if (!mounted) {
      return;
    }
    state = state.copyWith(profile: profile, clearError: true);

    try {
      final relationship = await ref
          .read(friendsProvider.notifier)
          .checkRelationship(did);
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        relationship: relationship?.relationship ?? 'none',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
    }

    final homepageUrl = ref
        .read(profileHomepageResolverProvider)
        .homepageUrl(profile);
    if (homepageUrl.isNotEmpty) {
      try {
        final markdown = await ref.read(homepageMarkdownLoaderProvider)(
          homepageUrl,
        );
        if (!mounted) {
          return;
        }
        if (markdown != null && markdown.trim().isNotEmpty) {
          state = state.copyWith(
            profile: profile.copyWith(profileMarkdown: markdown),
          );
        }
      } catch (_) {
        if (!mounted) {
          return;
        }
      }
    }
    state = state.copyWith(isLoading: false, clearError: true);
  }

  Future<void> unfollow() async {
    state = state.copyWith(isActionBusy: true);
    try {
      await ref.read(friendsProvider.notifier).unfollow(did);
      if (mounted) {
        state = state.copyWith(relationship: 'none');
      }
    } finally {
      if (mounted) {
        state = state.copyWith(isActionBusy: false);
      }
    }
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
