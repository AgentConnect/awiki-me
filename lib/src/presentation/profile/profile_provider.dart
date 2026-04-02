import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/app_services.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';

typedef HomepageMarkdownLoader = Future<String?> Function(String url);

final homepageMarkdownLoaderProvider = Provider<HomepageMarkdownLoader>((ref) {
  return (String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return null;
      }
      final body = response.body.trim();
      return body.isEmpty ? null : body;
    } catch (_) {
      return null;
    }
  };
});

class ProfileState {
  const ProfileState({
    this.profile,
    this.isLoading = false,
    this.isSaving = false,
  });

  final UserProfile? profile;
  final bool isLoading;
  final bool isSaving;

  ProfileState copyWith({
    UserProfile? profile,
    bool? isLoading,
    bool? isSaving,
    bool clearProfile = false,
  }) {
    return ProfileState(
      profile: clearProfile ? null : (profile ?? this.profile),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this.ref) : super(const ProfileState());

  final Ref ref;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final profile = await ref.read(awikiGatewayProvider).loadMyProfile();
    state = state.copyWith(profile: profile, isLoading: false);
  }

  Future<void> refreshWithHomepage(String url) async {
    await refresh();
    final current = state.profile;
    if (current == null) {
      return;
    }
    final markdown = await ref.read(homepageMarkdownLoaderProvider)(url);
    if (markdown == null || markdown.trim().isEmpty) {
      return;
    }
    state =
        state.copyWith(profile: current.copyWith(profileMarkdown: markdown));
  }

  Future<void> updateProfile(ProfilePatch patch) async {
    state = state.copyWith(isSaving: true);
    final profile = await ref.read(awikiGatewayProvider).updateProfile(patch);
    state = state.copyWith(profile: profile, isSaving: false);
    ref.read(uiFeedbackProvider.notifier).showInfo(AppMessage.profileUpdated());
  }

  void clear() {
    state = state.copyWith(clearProfile: true);
  }
}

final profileProvider = StateNotifierProvider<ProfileController, ProfileState>(
  (ref) => ProfileController(ref),
);
