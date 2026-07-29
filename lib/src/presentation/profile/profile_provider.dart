import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../app/app_services.dart';
import '../../application/account_state_sync_request_bus.dart';
import '../../application/models/product_local_models.dart';
import '../../application/profile_application_service.dart';
import '../../domain/entities/profile_patch.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../app/ui_feedback.dart';
import '../app_shell/providers/session_provider.dart';
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
  int _stateGeneration = 0;

  Future<void> refresh() async {
    final generation = _stateGeneration;
    final epoch = ref.read(sessionProvider).activeEpoch;
    final accountStateRequests = ref.read(accountStateSyncRequestBusProvider);
    if (accountStateRequests.hasHandler &&
        ref.read(sessionProvider).session?.accountBinding != null) {
      await accountStateRequests.request('profile_manual_refresh', force: true);
      return;
    }
    state = state.copyWith(isLoading: true);
    final profile = await ref
        .read(profileApplicationServiceProvider)
        .loadMyProfile();
    if (!_isOperationCurrent(generation, epoch)) {
      return;
    }
    state = _profileStateAfterRefresh(profile, isLoading: false);
  }

  Future<void> refreshWithHomepage(String url) async {
    final generation = _stateGeneration;
    final epoch = ref.read(sessionProvider).activeEpoch;
    await refresh();
    if (!_isOperationCurrent(generation, epoch)) {
      return;
    }
    await loadHomepageMarkdown(url);
  }

  Future<void> loadHomepageMarkdown(String url) async {
    final generation = _stateGeneration;
    final epoch = ref.read(sessionProvider).activeEpoch;
    final homepageUrl = url.trim();
    if (state.profile == null || homepageUrl.isEmpty) {
      return;
    }
    final String? markdown;
    try {
      markdown = await ref.read(homepageMarkdownLoaderProvider)(homepageUrl);
    } catch (_) {
      return;
    }
    if (markdown == null) {
      return;
    }
    if (!_isOperationCurrent(generation, epoch)) {
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
    final generation = _stateGeneration;
    final epoch = ref.read(sessionProvider).activeEpoch;
    final sessionBefore = ref.read(sessionProvider);
    state = state.copyWith(isSaving: true);
    final profiles = ref.read(profileApplicationServiceProvider);
    final UserProfile profile;
    final String? profileVersion;
    if (profiles is VersionedProfileApplicationService) {
      final mutation = await (profiles as VersionedProfileApplicationService)
          .updateProfileVersioned(patch);
      profile = mutation.profile;
      profileVersion = mutation.profileVersion;
    } else {
      profile = await profiles.updateProfile(patch);
      profileVersion = profile.profileVersion;
    }
    if (!_isOperationCurrent(generation, epoch) ||
        !_sameProfileProviderSession(
          sessionBefore,
          ref.read(sessionProvider),
        )) {
      return;
    }
    state = _profileStateAfterRefresh(profile, isSaving: false);
    await ref
        .read(accountStateSyncRequestBusProvider)
        .request(
          'profile_updated',
          force: true,
          minimumVersion:
              profileVersion == null ||
                  !isCanonicalProductDecimal(profileVersion)
              ? null
              : AccountStateVersionFloor(
                  domain: ProductAccountDomain.profile,
                  version: profileVersion,
                ),
        );
    if (!_isOperationCurrent(generation, epoch) ||
        !_sameProfileProviderSession(
          sessionBefore,
          ref.read(sessionProvider),
        )) {
      return;
    }
    ref.read(uiFeedbackProvider.notifier).showInfo(AppMessage.profileUpdated());
  }

  void applyAccountStateSnapshot(
    ProductProfileSnapshot snapshot, {
    required SessionIdentity session,
  }) {
    final current = ref.read(sessionProvider).session;
    if (!mounted || current == null || current.did != session.did) {
      return;
    }
    final payload = snapshot.payloadJson == null
        ? const <String, Object?>{}
        : _readJsonObject(snapshot.payloadJson!);
    final profile = UserProfile(
      did: session.did,
      displayName: _optionalString(payload['nick_name']) ?? '',
      bio: _optionalString(payload['bio']) ?? '',
      tags: _stringList(payload['tags']),
      profileMarkdown: _optionalString(payload['profile_md']) ?? '',
      handle: session.handle,
      avatarUri: _optionalString(payload['avatar_url']),
      profileVersion: snapshot.domainVersion,
    );
    state = _profileStateAfterRefresh(
      profile,
      isLoading: false,
      isSaving: false,
    );
  }

  void clear() {
    _stateGeneration += 1;
    state = const ProfileState();
  }

  bool _isOperationCurrent(int generation, SessionEpoch? epoch) {
    return mounted &&
        generation == _stateGeneration &&
        ref.read(sessionProvider).activeEpoch == epoch;
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

bool _sameProfileProviderSession(SessionState before, SessionState after) {
  final beforeSession = before.session;
  final afterSession = after.session;
  final beforeBinding = beforeSession?.accountBinding;
  final afterBinding = afterSession?.accountBinding;
  return before.generation == after.generation &&
      beforeSession != null &&
      afterSession != null &&
      beforeSession.did == afterSession.did &&
      beforeBinding?.ownerIdentityId == afterBinding?.ownerIdentityId &&
      beforeBinding?.accountId == afterBinding?.accountId &&
      beforeBinding?.currentDid == afterBinding?.currentDid &&
      beforeBinding?.protocolDeviceId == afterBinding?.protocolDeviceId &&
      beforeBinding?.identityGeneration == afterBinding?.identityGeneration &&
      beforeBinding?.deviceAuthGeneration == afterBinding?.deviceAuthGeneration;
}

final profileProvider = StateNotifierProvider<ProfileController, ProfileState>(
  (ref) => ProfileController(ref),
);

Map<String, Object?> _readJsonObject(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('account_profile_payload_not_object');
  }
  return decoded.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
