import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/profile_homepage_resolver.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import '../test_support.dart';
import 'avatar_profile_controller_test.dart' as fixture;

const _session = SessionIdentity(
  did: 'did:example:alice',
  credentialName: 'alice',
  displayName: 'Alice',
  localIdentityId: 'owner',
  accountBinding: SessionAccountBinding(
    ownerIdentityId: 'owner',
    accountId: 'account',
    currentDid: 'did:example:alice',
    protocolDeviceId: 'device',
    identityGeneration: '1',
    deviceAuthGeneration: '1',
  ),
);

class _DelayedProjection extends FakeIdentityCorePort {
  _DelayedProjection()
    : super(
        defaultSession: const AppSession(
          did: 'did:example:alice',
          identityId: 'owner',
          displayName: 'Alice',
          localAlias: 'alice',
        ),
      );
  final started = Completer<void>();
  final completion = Completer<AppSession>();
  @override
  Future<AppSession> updateDisplayNameProjection({
    required String identityId,
    String? displayName,
  }) {
    started.complete();
    return completion.future;
  }

  void finish() => completion.complete(
    const AppSession(
      did: 'did:example:alice',
      identityId: 'owner',
      displayName: 'Alice',
      localAlias: 'alice',
    ),
  );
}

ProviderContainer _container(
  fixture.Avatars avatars,
  _DelayedProjection identities,
) {
  final container = ProviderContainer(
    overrides: [
      profileApplicationServiceProvider.overrideWithValue(avatars),
      identityCorePortProvider.overrideWithValue(identities),
      profileHomepageResolverProvider.overrideWithValue(
        ProfileHomepageResolver(
          environment: AwikiEnvironmentConfig(baseUrl: 'https://example.com'),
        ),
      ),
    ],
  );
  container.read(sessionProvider.notifier).activateSession(_session);
  return container;
}

ProductProfileSnapshot _snapshot({String version = '1', String? uri}) =>
    ProductProfileSnapshot(
      binding: const ProductAccountBinding(
        ownerIdentityId: 'owner',
        accountId: 'account',
      ),
      domainVersion: version,
      refreshedAt: DateTime.utc(2026, 11, 5),
      payloadJson: uri == null
          ? '{"nick_name":"Alice"}'
          : '{"nick_name":"Alice","avatar_url":"$uri"}',
    );
void main() {
  for (final enabled in [true, false]) {
    test(
      'late account snapshot preserves the latest explicit avatar capability: $enabled',
      () async {
        final avatars = fixture.Avatars()
          ..current = fixture
              .profile('1', uri: null)
              .copyWith(avatarUploadEnabled: !enabled);
        final identities = _DelayedProjection();
        final container = _container(avatars, identities);
        addTearDown(container.dispose);
        final controller = container.read(profileProvider.notifier);
        await controller.loadAvatarProfile();
        final snapshot = controller.applyAccountStateSnapshot(
          _snapshot(),
          session: _session,
        );
        await identities.started.future;
        avatars.current = avatars.current.copyWith(
          avatarUploadEnabled: enabled,
        );
        await controller.loadAvatarProfile();
        expect(
          container.read(profileProvider).profile!.avatarUploadEnabled,
          enabled,
        );
        identities.finish();
        await snapshot;
        expect(
          container.read(profileProvider).profile!.avatarUploadEnabled,
          enabled,
        );
      },
    );
  }
  test(
    'late account snapshot preserves a matching thumbnail loaded during projection',
    () async {
      final avatars = fixture.Avatars();
      final identities = _DelayedProjection();
      final container = _container(avatars, identities);
      addTearDown(container.dispose);
      final controller = container.read(profileProvider.notifier);
      await controller.loadAvatarProfile();
      const uri = 'https://example.com/new-avatar.jpg';
      final snapshot = controller.applyAccountStateSnapshot(
        _snapshot(version: '2', uri: uri),
        session: _session,
      );
      await identities.started.future;
      avatars.current = fixture.profile('2', uri: uri);
      await controller.loadAvatarProfile();
      identities.finish();
      await snapshot;
      expect(
        container.read(profileProvider).profile!.avatarThumbnailUri,
        'https://example.com/thumb.jpg',
      );
    },
  );
  test(
    'an old owner snapshot cannot inherit or overwrite the new owner metadata',
    () async {
      final avatars = fixture.Avatars();
      final identities = _DelayedProjection();
      final container = _container(avatars, identities);
      addTearDown(container.dispose);
      final controller = container.read(profileProvider.notifier);
      await controller.loadAvatarProfile();
      final snapshot = controller.applyAccountStateSnapshot(
        _snapshot(),
        session: _session,
      );
      await identities.started.future;
      container
          .read(sessionProvider.notifier)
          .activateSession(
            const SessionIdentity(
              did: 'did:example:bob',
              credentialName: 'bob',
              displayName: 'Bob',
              localIdentityId: 'owner-b',
              accountBinding: SessionAccountBinding(
                ownerIdentityId: 'owner-b',
                accountId: 'account-b',
                currentDid: 'did:example:bob',
                protocolDeviceId: 'device-b',
                identityGeneration: '1',
                deviceAuthGeneration: '1',
              ),
            ),
          );
      controller.clear();
      avatars.current = const UserProfile(
        did: 'did:example:bob',
        displayName: 'Bob',
        bio: '',
        tags: [],
        profileMarkdown: '',
        avatarUploadEnabled: false,
        profileVersion: '1',
      );
      await controller.loadAvatarProfile();
      identities.finish();
      await snapshot;
      expect(container.read(profileProvider).profile!.did, 'did:example:bob');
      expect(
        container.read(profileProvider).profile!.avatarUploadEnabled,
        isFalse,
      );
    },
  );
}
