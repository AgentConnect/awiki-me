import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/profile_homepage_resolver.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/ports/profile_core_port.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';

UserProfile profile(
  String version, {
  String? uri = 'https://example.com/avatar.jpg',
}) => UserProfile(
  did: 'did:example:alice',
  displayName: 'Alice',
  bio: '',
  tags: const [],
  profileMarkdown: '',
  avatarUri: uri,
  avatarThumbnailUri: uri == null ? null : 'https://example.com/thumb.jpg',
  profileVersion: version,
  avatarUploadEnabled: true,
);

class Avatars implements ProfileApplicationService, AvatarCorePort {
  UserProfile current = profile('1');
  Completer<UserProfile>? mutation;
  final requests = <(String, String, Uint8List?)>[];
  @override
  Future<UserProfile> loadMyProfile() async => current;
  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async => current;
  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async => current;
  @override
  Future<UserProfile> setAvatar({
    required String requestId,
    required String expectedProfileVersion,
    required Uint8List jpeg,
  }) {
    requests.add((requestId, expectedProfileVersion, jpeg));
    return mutation!.future;
  }

  @override
  Future<UserProfile> clearAvatar({
    required String requestId,
    required String expectedProfileVersion,
  }) {
    requests.add((requestId, expectedProfileVersion, null));
    return mutation!.future;
  }
}

void main() {
  late ProviderContainer container;
  late Avatars avatars;
  setUp(() {
    avatars = Avatars();
    container = ProviderContainer(
      overrides: [
        profileApplicationServiceProvider.overrideWithValue(avatars),
        profileHomepageResolverProvider.overrideWithValue(
          ProfileHomepageResolver(
            environment: AwikiEnvironmentConfig(baseUrl: 'https://example.com'),
          ),
        ),
      ],
    );
    container
        .read(sessionProvider.notifier)
        .activateSession(
          const SessionIdentity(
            did: 'did:example:alice',
            credentialName: 'alice',
            displayName: 'Alice',
          ),
        );
  });
  tearDown(() => container.dispose());

  test(
    'clear removes both variants and stale reconciliation cannot resurrect them',
    () async {
      final controller = container.read(profileProvider.notifier);
      await controller.loadAvatarProfile();
      avatars.mutation = Completer<UserProfile>();
      final save = controller.mutateAvatar(
        requestId: 'request-1',
        expectedVersion: '1',
      );
      avatars.mutation!.complete(profile('2', uri: null));
      await save;
      expect(container.read(profileProvider).profile!.avatarUri, isNull);
      expect(
        container.read(profileProvider).profile!.avatarThumbnailUri,
        isNull,
      );
      await controller.loadAvatarProfile(); // Slow/old version 1 response.
      expect(container.read(profileProvider).profile!.profileVersion, '2');
      expect(container.read(profileProvider).profile!.avatarUri, isNull);
      expect(container.read(profileProvider).isSaving, isFalse);
    },
  );

  test(
    'old owner completion is fenced and failed requests release saving state',
    () async {
      final controller = container.read(profileProvider.notifier);
      await controller.loadAvatarProfile();
      avatars.mutation = Completer<UserProfile>();
      final save = controller.mutateAvatar(
        requestId: 'request-2',
        expectedVersion: '1',
      );
      final assertion = expectLater(save, throwsStateError);
      container
          .read(sessionProvider.notifier)
          .activateSession(
            const SessionIdentity(
              did: 'did:example:bob',
              credentialName: 'bob',
              displayName: 'Bob',
            ),
          );
      controller.clear();
      avatars.mutation!.complete(profile('2'));
      await assertion;
      expect(container.read(profileProvider).profile, isNull);
      expect(container.read(profileProvider).isSaving, isFalse);
    },
  );

  test(
    'retry preserves operation bytes/version and saving recovers after transport failure',
    () async {
      final controller = container.read(profileProvider.notifier);
      await controller.loadAvatarProfile();
      final bytes = Uint8List.fromList([255, 216, 255, 217]);
      avatars.mutation = Completer<UserProfile>();
      final first = controller.mutateAvatar(
        requestId: 'request-3',
        expectedVersion: '1',
        jpeg: bytes,
      );
      final assertion = expectLater(first, throwsStateError);
      avatars.mutation!.completeError(StateError('network'));
      await assertion;
      expect(container.read(profileProvider).isSaving, isFalse);
      avatars.mutation = Completer<UserProfile>();
      final retry = controller.mutateAvatar(
        requestId: 'request-3',
        expectedVersion: '1',
        jpeg: bytes,
      );
      avatars.mutation!.complete(profile('2'));
      await retry;
      expect(avatars.requests[0], avatars.requests[1]);
    },
  );
}
