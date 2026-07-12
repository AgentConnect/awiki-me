import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/directory_application_service.dart';
import 'package:awiki_me/src/application/ports/directory_core_port.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
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

  test('头像触发的远端 profile 会立即更新展示投影', () {
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
          requestedDid: 'did:test:alice-old',
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
    expect(state.forDid('did:test:alice')?.displayName, 'Alice New');
    expect(state.forDid('did:test:alice-old')?.displayName, 'Alice New');
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

    final state = container.read(peerDisplayProfileProvider);
    expect(
      peerDisplayName(
        state,
        did: 'did:wba:awiki.ai:user:bob:e1_key',
        fallback: 'unknown',
      ),
      'bob.awiki.ai',
    );
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
