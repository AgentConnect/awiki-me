import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/app_services.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';
import 'profile_markdown.dart';

typedef HomepageMarkdownLoader = Future<String?> Function(String url);

final homepageMarkdownLoaderProvider = Provider<HomepageMarkdownLoader>((ref) {
  return (String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        return null;
      }
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('text/html')) {
        return null;
      }
      final body = response.body.trim();
      return body;
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
    this.homepageUrl,
    this.homepageMarkdown,
    this.homepageMarkdownLoaded = false,
  });

  final UserProfile? profile;
  final bool isLoading;
  final bool isSaving;
  final String? homepageUrl;
  final String? homepageMarkdown;
  final bool homepageMarkdownLoaded;

  ProfileState copyWith({
    UserProfile? profile,
    bool? isLoading,
    bool? isSaving,
    String? homepageUrl,
    String? homepageMarkdown,
    bool? homepageMarkdownLoaded,
    bool clearProfile = false,
    bool clearHomepageMarkdown = false,
  }) {
    return ProfileState(
      profile: clearProfile ? null : (profile ?? this.profile),
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      homepageUrl: clearHomepageMarkdown
          ? null
          : (homepageUrl ?? this.homepageUrl),
      homepageMarkdown: clearHomepageMarkdown
          ? null
          : (homepageMarkdown ?? this.homepageMarkdown),
      homepageMarkdownLoaded: clearHomepageMarkdown
          ? false
          : (homepageMarkdownLoaded ?? this.homepageMarkdownLoaded),
    );
  }
}

class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this.ref) : super(const ProfileState());

  final Ref ref;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final profile = await ref
        .read(profileApplicationServiceProvider)
        .loadMyProfile();
    state = _profileStateAfterRefresh(profile, isLoading: false);
  }

  Future<void> refreshWithHomepage(String url) async {
    await refresh();
    await loadHomepageMarkdown(url);
  }

  Future<void> loadHomepageMarkdown(String url) async {
    final homepageUrl = url.trim();
    if (state.profile == null || homepageUrl.isEmpty) {
      return;
    }
    final markdown = await ref.read(homepageMarkdownLoaderProvider)(
      homepageUrl,
    );
    if (markdown == null) {
      return;
    }
    final normalizedMarkdown = markdown.trim();
    if (looksLikeHtmlDocument(normalizedMarkdown)) {
      return;
    }
    final current = state.profile;
    if (current == null ||
        ref.read(profileHomepageResolverProvider).homepageUrl(current) !=
            homepageUrl) {
      return;
    }
    state = state.copyWith(
      homepageUrl: homepageUrl,
      homepageMarkdown: normalizedMarkdown,
      homepageMarkdownLoaded: true,
    );
  }

  Future<void> updateProfile(ProfilePatch patch) async {
    state = state.copyWith(isSaving: true);
    final profile = await ref
        .read(profileApplicationServiceProvider)
        .updateProfile(patch);
    state = _profileStateAfterRefresh(profile, isSaving: false);
    ref.read(uiFeedbackProvider.notifier).showInfo(AppMessage.profileUpdated());
  }

  void clear() {
    state = state.copyWith(clearProfile: true, clearHomepageMarkdown: true);
  }

  ProfileState _profileStateAfterRefresh(
    UserProfile profile, {
    bool? isLoading,
    bool? isSaving,
  }) {
    final homepageUrl = ref
        .read(profileHomepageResolverProvider)
        .homepageUrl(profile);
    final shouldKeepHomepageMarkdown =
        state.homepageMarkdownLoaded && state.homepageUrl == homepageUrl;
    return state.copyWith(
      profile: profile,
      isLoading: isLoading,
      isSaving: isSaving,
      clearHomepageMarkdown: !shouldKeepHomepageMarkdown,
    );
  }

  String visibleProfileContent() {
    if (state.homepageMarkdownLoaded) {
      return state.homepageMarkdown?.trim() ?? '';
    }
    final profile = state.profile;
    if (profile == null) {
      return '';
    }
    final markdown = profile.profileMarkdown.trim();
    if (markdown.isNotEmpty) {
      return markdown;
    }
    return profile.bio.trim();
  }
}

final profileProvider = StateNotifierProvider<ProfileController, ProfileState>(
  (ref) => ProfileController(ref),
);
