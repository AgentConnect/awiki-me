import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/account_state_sync_request_bus.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/ports/account_state_sync_port.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/application/profile_homepage_resolver.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('个人资料刷新后保留已加载的主页 markdown 作为可见内容', () async {
    const remoteMarkdown = '# Remote title\n\n# 如何与我通信\n\nRemote body';
    const serverProfile = UserProfile(
      did: 'did:test:bob',
      nickName: 'Bob',
      bio: 'Initial bio',
      tags: <String>[],
      profileMarkdown: '# Bob',
      handle: 'bob.awiki.ai',
    );
    final gateway = FakeAwikiGateway()..myProfile = serverProfile;
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        profileApplicationServiceProvider.overrideWithValue(
          FakeProfileApplicationService(gateway),
        ),
        profileHomepageResolverProvider.overrideWithValue(
          ProfileHomepageResolver(
            environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
          ),
        ),
        homepageMarkdownLoaderProvider.overrideWithValue(
          (_) async => remoteMarkdown,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileProvider.notifier);
    await controller.refresh();
    await controller.loadHomepageMarkdown('https://bob.awiki.ai');

    expect(container.read(profileProvider).profile?.profileMarkdown, '# Bob');
    expect(controller.visibleProfileContent(), remoteMarkdown);

    gateway.myProfile = serverProfile.copyWith(
      bio: 'Refreshed bio',
      profileMarkdown: '# Bob',
    );
    await controller.refresh();

    final refreshed = container.read(profileProvider).profile;
    expect(refreshed?.bio, 'Refreshed bio');
    expect(refreshed?.profileMarkdown, '# Bob');
    expect(controller.visibleProfileContent(), remoteMarkdown);
  });

  test('主页 markdown 慢请求返回后不会覆盖最新 profile 状态', () async {
    const remoteMarkdown = '# Remote title\n\n# 如何与我通信\n\nRemote body';
    const serverProfile = UserProfile(
      did: 'did:test:carol',
      nickName: 'Carol',
      bio: 'Initial bio',
      tags: <String>[],
      profileMarkdown: '# Carol',
      handle: 'carol.awiki.ai',
    );
    final homepageCompleter = Completer<String?>();
    final gateway = FakeAwikiGateway()..myProfile = serverProfile;
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        profileApplicationServiceProvider.overrideWithValue(
          FakeProfileApplicationService(gateway),
        ),
        profileHomepageResolverProvider.overrideWithValue(
          ProfileHomepageResolver(
            environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
          ),
        ),
        homepageMarkdownLoaderProvider.overrideWithValue(
          (_) => homepageCompleter.future,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileProvider.notifier);
    await controller.refresh();
    final homepageFuture = controller.loadHomepageMarkdown(
      'https://carol.awiki.ai',
    );

    gateway.myProfile = serverProfile.copyWith(
      nickName: 'Carol New',
      bio: 'Updated bio',
    );
    await controller.refresh();
    homepageCompleter.complete(remoteMarkdown);
    await homepageFuture;

    final profile = container.read(profileProvider).profile;
    expect(profile?.nickName, 'Carol New');
    expect(profile?.bio, 'Updated bio');
    expect(profile?.profileMarkdown, '# Carol');
    expect(controller.visibleProfileContent(), remoteMarkdown);
  });

  test('忽略主页 HTML 响应，避免覆盖已有 profile markdown', () async {
    const serverProfile = UserProfile(
      did: 'did:test:dana',
      nickName: 'Dana',
      bio: 'Initial bio',
      tags: <String>[],
      profileMarkdown: '# Dana\n\n# 如何与我通信\n\nKeep this copy',
      handle: 'dana.awiki.ai',
    );
    final gateway = FakeAwikiGateway()..myProfile = serverProfile;
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        profileApplicationServiceProvider.overrideWithValue(
          FakeProfileApplicationService(gateway),
        ),
        profileHomepageResolverProvider.overrideWithValue(
          ProfileHomepageResolver(
            environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
          ),
        ),
        homepageMarkdownLoaderProvider.overrideWithValue(
          (_) async => '<!doctype html><html><body></body></html>',
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileProvider.notifier);
    await controller.refresh();
    await controller.loadHomepageMarkdown('https://dana.awiki.ai');

    expect(
      container.read(profileProvider).profile?.profileMarkdown,
      serverProfile.profileMarkdown,
    );
    expect(controller.visibleProfileContent(), serverProfile.profileMarkdown);
  });

  test('旧身份资料慢请求不会覆盖新身份状态', () async {
    final profiles = _DelayedProfileService();
    final container = ProviderContainer(
      overrides: <Override>[
        profileApplicationServiceProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:owner:a',
            credentialName: 'owner-a',
            displayName: 'Owner A',
          ),
        );
    final controller = container.read(profileProvider.notifier);

    final refresh = controller.refresh();
    await profiles.started.future;
    container
        .read(sessionProvider.notifier)
        .setSession(
          const SessionIdentity(
            did: 'did:owner:b',
            credentialName: 'owner-b',
            displayName: 'Owner B',
          ),
        );
    controller.clear();
    profiles.result.complete(
      const UserProfile(
        did: 'did:owner:a',
        nickName: 'Owner A',
        bio: 'old owner profile',
        tags: <String>[],
        profileMarkdown: '# Owner A',
      ),
    );
    await refresh;

    final state = container.read(profileProvider);
    expect(state.profile, isNull);
    expect(state.isLoading, isFalse);
    expect(state.isSaving, isFalse);
  });

  test(
    'profile mutation forwards its independent version as a floor',
    () async {
      final profiles = _VersionedProfileService(
        result: const ProfileMutationResult(
          profile: UserProfile(
            did: 'did:test:alice',
            displayName: 'Alice 2',
            bio: 'Updated',
            tags: <String>[],
            profileMarkdown: '',
            profileVersion: '7',
          ),
          profileVersion: '7',
        ),
      );
      final identities = FakeIdentityCorePort(
        defaultSession: const AppSession(
          did: 'did:test:alice',
          identityId: 'owner-one',
          displayName: 'Alice',
          handle: 'alice.awiki.test',
          localAlias: 'one',
        ),
      );
      final container = ProviderContainer(
        overrides: <Override>[
          profileApplicationServiceProvider.overrideWithValue(profiles),
          identityCorePortProvider.overrideWithValue(identities),
        ],
      );
      addTearDown(container.dispose);
      container.read(sessionProvider.notifier).setSession(_boundSession('one'));
      AccountStateVersionFloor? observedFloor;
      container.read(accountStateSyncRequestBusProvider).attach((
        reason, {
        force = false,
        minimumVersion,
      }) async {
        expect(reason, 'profile_updated');
        expect(force, isTrue);
        observedFloor = minimumVersion;
      });

      await container
          .read(profileProvider.notifier)
          .updateProfile(const ProfilePatch(displayName: 'Alice 2'));

      expect(observedFloor?.domain, ProductAccountDomain.profile);
      expect(observedFloor?.version, '7');
      expect(container.read(profileProvider).profile?.profileVersion, '7');
      expect(identities.lastDisplayNameProjectionIdentityId, 'owner-one');
      expect(identities.lastDisplayNameProjection, 'Alice 2');
      expect(container.read(sessionProvider).session?.displayName, 'Alice 2');
    },
  );

  test(
    'account Profile is not published when identity projection fails',
    () async {
      final identities = _FailingDisplayProjectionIdentityCorePort(
        defaultSession: const AppSession(
          did: 'did:test:alice',
          identityId: 'owner-one',
          displayName: 'Alice',
          handle: 'alice.awiki.test',
          localAlias: 'one',
        ),
      );
      final container = ProviderContainer(
        overrides: <Override>[
          identityCorePortProvider.overrideWithValue(identities),
        ],
      );
      addTearDown(container.dispose);
      final session = _boundSession('one');
      container.read(sessionProvider.notifier).setSession(session);

      await expectLater(
        container
            .read(profileProvider.notifier)
            .applyAccountStateSnapshot(
              ProductProfileSnapshot(
                binding: const ProductAccountBinding(
                  ownerIdentityId: 'owner-one',
                  accountId: 'account-one',
                ),
                domainVersion: '2',
                refreshedAt: DateTime.utc(2026, 8, 11),
                payloadJson: '{"nick_name":"Alice New"}',
              ),
              session: session,
            ),
        throwsStateError,
      );

      expect(container.read(profileProvider).profile, isNull);
      expect(container.read(sessionProvider).session?.displayName, 'Alice');
    },
  );

  test('profile mutation response is fenced after a session switch', () async {
    final completer = Completer<ProfileMutationResult>();
    final profiles = _VersionedProfileService(completer: completer);
    final container = ProviderContainer(
      overrides: <Override>[
        profileApplicationServiceProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).setSession(_boundSession('one'));
    var requestCount = 0;
    container.read(accountStateSyncRequestBusProvider).attach((
      _, {
      force = false,
      minimumVersion,
    }) async {
      requestCount += 1;
    });

    final operation = container
        .read(profileProvider.notifier)
        .updateProfile(const ProfilePatch(displayName: 'Stale'));
    await profiles.started.future;
    container.read(sessionProvider.notifier).setSession(_boundSession('two'));
    completer.complete(
      const ProfileMutationResult(
        profile: UserProfile(
          did: 'did:test:alice',
          displayName: 'Stale',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          profileVersion: '8',
        ),
        profileVersion: '8',
      ),
    );
    await operation;

    expect(container.read(profileProvider).profile, isNull);
    expect(requestCount, 0);
  });

  test('unbound profile mutation keeps the legacy delegate path', () async {
    const updated = UserProfile(
      did: 'did:test:legacy',
      displayName: 'Legacy',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      profileVersion: '5',
    );
    final gateway = FakeAwikiGateway()..updatedProfile = updated;
    final service = AccountStateProfileApplicationService(
      delegate: FakeProfileApplicationService(gateway),
      mutations: _UnexpectedProfileMutationPort(),
      sessionProvider: () => null,
    );

    final result = await service.updateProfileVersioned(
      const ProfilePatch(displayName: 'Legacy'),
    );

    expect(result.profile, same(updated));
    expect(result.profileVersion, '5');
    expect(gateway.lastProfilePatch?.displayName, 'Legacy');
  });
}

class _DelayedProfileService implements ProfileApplicationService {
  final Completer<void> started = Completer<void>();
  final Completer<UserProfile> result = Completer<UserProfile>();

  @override
  Future<UserProfile> loadMyProfile() {
    started.complete();
    return result.future;
  }

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

SessionIdentity _boundSession(String accountId) {
  return SessionIdentity(
    did: 'did:test:alice',
    credentialName: accountId,
    localIdentityId: 'owner-$accountId',
    displayName: 'Alice',
    accountBinding: SessionAccountBinding(
      ownerIdentityId: 'owner-$accountId',
      accountId: 'account-$accountId',
      currentDid: 'did:test:alice',
      protocolDeviceId: 'device-$accountId',
      identityGeneration: '1',
      deviceAuthGeneration: '1',
    ),
  );
}

class _VersionedProfileService
    implements ProfileApplicationService, VersionedProfileApplicationService {
  _VersionedProfileService({this.result, this.completer});

  final ProfileMutationResult? result;
  final Completer<ProfileMutationResult>? completer;
  final Completer<void> started = Completer<void>();

  @override
  Future<UserProfile> loadMyProfile() => throw UnimplementedError();

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) =>
      throw UnimplementedError();

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) async =>
      (await updateProfileVersioned(patch)).profile;

  @override
  Future<ProfileMutationResult> updateProfileVersioned(ProfilePatch patch) {
    if (!started.isCompleted) {
      started.complete();
    }
    return completer?.future ?? Future<ProfileMutationResult>.value(result!);
  }
}

class _UnexpectedProfileMutationPort
    implements AccountStateProfileMutationPort {
  @override
  Future<AccountStateProfileMutationResult> updateAccountProfile(
    ProfilePatch patch,
  ) {
    throw StateError('account-state mutation must not run while unbound');
  }
}

class _FailingDisplayProjectionIdentityCorePort extends FakeIdentityCorePort {
  _FailingDisplayProjectionIdentityCorePort({required super.defaultSession});

  @override
  Future<AppSession> updateDisplayNameProjection({
    required String identityId,
    String? displayName,
  }) {
    throw StateError('projection failed');
  }
}
