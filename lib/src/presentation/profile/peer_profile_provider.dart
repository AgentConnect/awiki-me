import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';
import '../friends/friends_provider.dart';
import '../app_shell/providers/session_provider.dart';
import 'peer_display_profile_provider.dart';
import 'profile_provider.dart';
import '../../domain/entities/user_profile.dart';

class PeerPublicProfileRequest {
  const PeerPublicProfileRequest({required this.did, required this.epoch});

  final String did;
  final SessionEpoch? epoch;

  @override
  bool operator ==(Object other) {
    return other is PeerPublicProfileRequest &&
        other.did == did &&
        other.epoch == epoch;
  }

  @override
  int get hashCode => Object.hash(did, epoch);
}

final peerPublicProfileProvider = FutureProvider.autoDispose
    .family<UserProfile, PeerPublicProfileRequest>((ref, request) {
      return ref
          .watch(profileApplicationServiceProvider)
          .loadPublicProfile(request.did)
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

final class _PeerProfileOperation {
  const _PeerProfileOperation({required this.epoch, required this.generation});

  final SessionEpoch? epoch;
  final int generation;
}

class PeerProfileController extends StateNotifier<PeerProfileState> {
  PeerProfileController(this.ref, this.did)
    : _ownerEpoch = ref.read(sessionProvider).activeEpoch,
      super(const PeerProfileState()) {
    unawaited(load());
  }

  final Ref ref;
  final String did;
  final SessionEpoch? _ownerEpoch;
  int _loadGeneration = 0;
  int _actionGeneration = 0;

  Future<void> load() async {
    final operation = _PeerProfileOperation(
      epoch: _ownerEpoch,
      generation: ++_loadGeneration,
    );
    if (!_isLoadOperationCurrent(operation)) {
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    final UserProfile profile;
    try {
      profile = await ref.read(
        peerPublicProfileProvider(
          PeerPublicProfileRequest(did: did, epoch: operation.epoch),
        ).future,
      );
    } catch (error) {
      if (!_isLoadOperationCurrent(operation)) {
        return;
      }
      state = state.copyWith(isLoading: false, error: error);
      return;
    }
    if (!_isLoadOperationCurrent(operation)) {
      return;
    }
    final ownerDid = operation.epoch?.ownerDid ?? '';
    ref
        .read(peerDisplayProfileProvider.notifier)
        .updateFromRemote(
          ownerDid: ownerDid,
          profile: profile,
          expectedEpoch: operation.epoch,
        );
    state = state.copyWith(profile: profile, clearError: true);

    try {
      final relationship = await ref
          .read(friendsProvider.notifier)
          .checkRelationship(did);
      if (!_isLoadOperationCurrent(operation)) {
        return;
      }
      state = state.copyWith(
        relationship: relationship?.relationship ?? 'none',
      );
    } catch (_) {
      if (!_isLoadOperationCurrent(operation)) {
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
        if (!_isLoadOperationCurrent(operation)) {
          return;
        }
        if (markdown != null && markdown.trim().isNotEmpty) {
          state = state.copyWith(
            profile: profile.copyWith(profileMarkdown: markdown),
          );
        }
      } catch (_) {
        if (!_isLoadOperationCurrent(operation)) {
          return;
        }
      }
    }
    if (!_isLoadOperationCurrent(operation)) {
      return;
    }
    state = state.copyWith(isLoading: false, clearError: true);
  }

  Future<void> unfollow() async {
    final operation = _PeerProfileOperation(
      epoch: _ownerEpoch,
      generation: ++_actionGeneration,
    );
    if (!_isActionOperationCurrent(operation)) {
      return;
    }
    state = state.copyWith(isActionBusy: true);
    try {
      await ref.read(friendsProvider.notifier).unfollow(did);
      if (_isActionOperationCurrent(operation)) {
        state = state.copyWith(relationship: 'none');
      }
    } catch (error) {
      if (!isSessionEpochChangedError(error)) {
        rethrow;
      }
    } finally {
      if (_isActionOperationCurrent(operation)) {
        state = state.copyWith(isActionBusy: false);
      }
    }
  }

  bool _isLoadOperationCurrent(_PeerProfileOperation operation) {
    return mounted &&
        operation.generation == _loadGeneration &&
        operation.epoch == ref.read(sessionProvider).activeEpoch;
  }

  bool _isActionOperationCurrent(_PeerProfileOperation operation) {
    return mounted &&
        operation.generation == _actionGeneration &&
        operation.epoch == ref.read(sessionProvider).activeEpoch;
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
