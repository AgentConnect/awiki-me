import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/application/profile_application_service.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('本地 profile 投影按 owner 隔离且同一 DID 不重复读取', () async {
    final directory = _CachedDirectoryService();
    final container = ProviderContainer(
      overrides: <Override>[
        directoryApplicationServiceProvider.overrideWithValue(directory),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(peerDisplayProfileProvider.notifier);

    await controller.loadCached(
      ownerDid: 'did:test:owner-a',
      dids: const <String>['did:test:alice'],
    );
    await controller.loadCached(
      ownerDid: 'did:test:owner-a',
      dids: const <String>['did:test:alice'],
    );

    expect(directory.requests, <Set<String>>[
      <String>{'did:test:alice'},
    ]);
    expect(
      container
          .read(peerDisplayProfileProvider)
          .forDid('did:test:alice')
          ?.displayName,
      'Alice',
    );

    await controller.loadCached(
      ownerDid: 'did:test:owner-b',
      dids: const <String>['did:test:bob'],
    );
    final switched = container.read(peerDisplayProfileProvider);
    expect(switched.ownerDid, 'did:test:owner-b');
    expect(switched.forDid('did:test:alice'), isNull);
    expect(switched.forDid('did:test:bob')?.displayName, 'Bob');
  });

  test('远端 profile 不会按未经验证的旧 DID 复制展示别名', () {
    final container = ProviderContainer(
      overrides: <Override>[
        directoryApplicationServiceProvider.overrideWithValue(
          _EmptyCachedDirectoryService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(peerDisplayProfileProvider.notifier)
        .updateFromRemote(
          ownerDid: 'did:test:owner',
          peerPersonaId: 'persona:alice',
          profile: const UserProfile(
            did: 'did:test:alice',
            displayName: 'Alice New',
            bio: '',
            tags: <String>[],
            profileMarkdown: '',
            fullHandle: 'alice.awiki.ai',
          ),
        );

    final state = container.read(peerDisplayProfileProvider);
    expect(
      state
          .forPeer(peerPersonaId: 'persona:alice', did: 'did:test:alice')
          ?.displayName,
      'Alice New',
    );
    expect(state.forDid('did:test:alice')?.displayName, 'Alice New');
    expect(state.forDid('did:test:alice-old'), isNull);
  });

  test('远端 profile 没有昵称时保留 Handle 作为展示回退', () {
    final container = ProviderContainer(
      overrides: <Override>[
        directoryApplicationServiceProvider.overrideWithValue(
          _CachedDirectoryService(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container
        .read(peerDisplayProfileProvider.notifier)
        .updateFromRemote(
          ownerDid: 'did:test:owner',
          profile: const UserProfile(
            did: 'did:wba:awiki.ai:user:bob:e1_key',
            displayName: 'bob',
            bio: '',
            tags: <String>[],
            profileMarkdown: '',
            fullHandle: '@bob.awiki.ai',
          ),
        );

    expect(
      container.read(
        peerDisplayNameProvider(
          const PeerDisplayNameRequest(
            did: 'did:wba:awiki.ai:user:bob:e1_key',
            senderNameSnapshot: 'unknown',
          ),
        ),
      ),
      'bob.awiki.ai',
    );
  });

  test('同一 Persona 的已验证 DID 轮换共享一份展示资料', () {
    final container = ProviderContainer(
      overrides: <Override>[
        directoryApplicationServiceProvider.overrideWithValue(
          _EmptyCachedDirectoryService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(peerDisplayProfileProvider.notifier);

    controller.updateFromRemote(
      ownerDid: 'did:test:owner',
      peerPersonaId: 'persona:alice',
      profile: const UserProfile(
        did: 'did:test:alice-old',
        displayName: 'Alice Old',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
      ),
    );
    controller.updateFromRemote(
      ownerDid: 'did:test:owner',
      peerPersonaId: 'persona:alice',
      profile: const UserProfile(
        did: 'did:test:alice-new',
        displayName: 'Alice New',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
      ),
    );

    final state = container.read(peerDisplayProfileProvider);
    expect(state.profilesByPersonaId, hasLength(1));
    expect(state.forDid('did:test:alice-old')?.displayName, 'Alice New');
    expect(state.forDid('did:test:alice-new')?.displayName, 'Alice New');
  });

  test('后到的 Persona 路由会接管同 DID 的未解析 profile', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        directoryApplicationServiceProvider.overrideWithValue(
          _EmptyCachedDirectoryService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(peerDisplayProfileProvider.notifier);

    controller.updateFromRemote(
      ownerDid: 'did:test:owner',
      profile: const UserProfile(
        did: 'did:test:alice',
        displayName: 'Alice cached first',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        fullHandle: 'alice.awiki.info',
      ),
    );
    expect(
      container.read(peerDisplayProfileProvider).unresolvedProfilesByDid,
      contains('did:test:alice'),
    );

    await controller.loadCached(
      ownerDid: 'did:test:owner',
      dids: const <String>['did:test:alice'],
      peerPersonaIdsByDid: const <String, String>{
        'did:test:alice': 'persona:alice',
      },
    );

    final state = container.read(peerDisplayProfileProvider);
    expect(state.unresolvedProfilesByDid, isEmpty);
    expect(state.profilesByPersonaId, hasLength(1));
    expect(
      state
          .forPeer(peerPersonaId: 'persona:alice', did: 'did:test:alice')
          ?.displayName,
      'Alice cached first',
    );
  });

  test('统一 View Provider 在所有 DID 路由上优先使用 Persona 本地备注', () async {
    final container = ProviderContainer(
      overrides: <Override>[
        directoryApplicationServiceProvider.overrideWithValue(
          _CachedDirectoryService(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(peerDisplayProfileProvider.notifier);

    await controller.loadCached(
      ownerDid: 'did:test:owner-a',
      dids: const <String>['did:test:alice'],
      peerPersonaIdsByDid: const <String, String>{
        'did:test:alice': 'persona:alice',
      },
    );
    controller.registerLocalNotes(
      ownerDid: 'did:test:owner-a',
      localNotesByPersonaId: const <String, String>{
        'persona:alice': 'Alice local note',
      },
    );

    expect(
      container.read(
        peerDisplayNameProvider(
          const PeerDisplayNameRequest(
            did: 'did:test:alice',
            nickname: 'Different page nickname',
            fullHandle: 'alice.awiki.info',
          ),
        ),
      ),
      'Alice local note',
    );

    await controller.loadCached(
      ownerDid: 'did:test:owner-b',
      dids: const <String>['did:test:bob'],
    );
    expect(
      container.read(peerDisplayProfileProvider).localNotesByPersonaId,
      isEmpty,
    );
  });

  test('查看全部并发刷新本地缺失 profile 并缓存成功结果', () async {
    final profiles = _RemoteProfileService();
    final container = ProviderContainer(
      overrides: <Override>[
        directoryApplicationServiceProvider.overrideWithValue(
          _EmptyCachedDirectoryService(),
        ),
        profileApplicationServiceProvider.overrideWithValue(profiles),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(peerDisplayProfileProvider.notifier);

    await controller.refreshRemoteMissing(
      ownerDid: 'did:test:owner',
      dids: const <String>['did:test:alice', 'did:test:bob'],
    );
    await controller.refreshRemoteMissing(
      ownerDid: 'did:test:owner',
      dids: const <String>['did:test:alice', 'did:test:bob'],
    );

    expect(profiles.requests.toSet(), <String>{
      'did:test:alice',
      'did:test:bob',
    });
    expect(profiles.maxActiveRequests, 2);
    final state = container.read(peerDisplayProfileProvider);
    expect(state.forDid('did:test:alice')?.displayName, 'alice nickname');
    expect(state.forDid('did:test:bob')?.displayName, 'bob nickname');
  });
}

class _CachedDirectoryService implements DirectoryApplicationService {
  final List<Set<String>> requests = <Set<String>>[];

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async {
    final requested = dids.toSet();
    requests.add(requested);
    return requested
        .map(
          (did) => PeerDisplayProfile(
            did: did,
            displayName: did.endsWith('alice') ? 'Alice' : 'Bob',
          ),
        )
        .toList();
  }

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) {
    throw UnimplementedError();
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) {
    throw UnimplementedError();
  }
}

class _RemoteProfileService implements ProfileApplicationService {
  final List<String> requests = <String>[];
  int activeRequests = 0;
  int maxActiveRequests = 0;

  @override
  Future<UserProfile> loadPublicProfile(String didOrHandle) async {
    requests.add(didOrHandle);
    activeRequests += 1;
    if (activeRequests > maxActiveRequests) {
      maxActiveRequests = activeRequests;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
    activeRequests -= 1;
    final name = didOrHandle.split(':').last;
    return UserProfile(
      did: didOrHandle,
      displayName: '$name nickname',
      bio: '',
      tags: const <String>[],
      profileMarkdown: '',
      fullHandle: '$name.awiki.ai',
    );
  }

  @override
  Future<UserProfile> loadMyProfile() {
    throw UnimplementedError();
  }

  @override
  Future<UserProfile> updateProfile(ProfilePatch patch) {
    throw UnimplementedError();
  }
}

class _EmptyCachedDirectoryService implements DirectoryApplicationService {
  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async => const <PeerDisplayProfile>[];

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) {
    throw UnimplementedError();
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) {
    throw UnimplementedError();
  }
}
