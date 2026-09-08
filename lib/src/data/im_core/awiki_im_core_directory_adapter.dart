import '../../application/ports/directory_core_port.dart';
import '../../domain/entities/peer_display_profile.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

class AwikiImCoreDirectoryAdapter implements DirectoryCorePort {
  AwikiImCoreDirectoryAdapter({
    required AwikiImCoreRuntime runtime,
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : _runtime = runtime,
       _mappers = mappers;

  final AwikiImCoreRuntime _runtime;
  final AwikiImCoreMappers _mappers;

  @override
  Future<List<PeerDisplayProfile>> refreshDisplayProfiles(
    Iterable<String> dids, {
    bool force = false,
  }) async {
    final peers = dids
        .map((did) => did.trim())
        .where((did) => did.startsWith('did:'))
        .toSet()
        .toList();
    if (peers.isEmpty) return const [];
    // Bind every batch to the same client/owner, including during account switches.
    return _runtime.withCurrentClient((client) async {
      final results = <PeerDisplayProfile>[];
      for (var start = 0; start < peers.length; start += 100) {
        final batch = peers.skip(start).take(100).toList();
        final profiles = await client.directory.refreshDisplayProfiles(
          batch,
          force: force,
        );
        results.addAll(
          profiles
              .where((p) => p.cacheHit && p.did != null)
              .map(
                (p) => PeerDisplayProfile(
                  did: p.did!,
                  displayName: p.displayName,
                  handle: p.handle,
                  avatarUri: p.avatarUri ?? p.avatarUrl,
                  profileUri: p.profileUri,
                  subjectType: p.subjectType,
                  isStale: p.isStale,
                  legacyFallback: p.legacyFallback,
                ),
              ),
        );
      }
      return results;
    });
  }

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) async {
    final peers = dids
        .map((did) => did.trim())
        .where((did) => did.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (peers.isEmpty) {
      return const <PeerDisplayProfile>[];
    }
    final profiles = await _runtime.withCurrentClient(
      (client) => client.directory.hydrateDisplayProfiles(peers),
    );
    return profiles
        .where((profile) => profile.cacheHit && profile.did != null)
        .map(
          (profile) => PeerDisplayProfile(
            did: profile.did!,
            displayName: profile.displayName,
            handle: profile.handle,
            avatarUri: profile.avatarUri ?? profile.avatarUrl,
            profileUri: profile.profileUri,
            subjectType: profile.subjectType,
            isStale: profile.isStale,
            legacyFallback: profile.legacyFallback,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) async {
    final resolution = await _runtime.withCurrentClient(
      (client) => client.directory.lookupHandle(handle),
    );
    return DirectoryPeerResolution(
      input: resolution.input,
      did: resolution.did,
      handle: resolution.handle,
      conversationId: resolution.conversationId,
      profile: resolution.profile == null
          ? null
          : _mappers.userProfileFromCore(resolution.profile!),
      warnings: resolution.warnings,
    );
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) async {
    final resolution = await _runtime.withCurrentClient(
      (client) => client.directory.resolvePeer(peer),
    );
    return DirectoryPeerResolution(
      input: resolution.input,
      did: resolution.did,
      handle: resolution.handle,
      conversationId: resolution.conversationId,
      profile: resolution.profile == null
          ? null
          : _mappers.userProfileFromCore(resolution.profile!),
      warnings: resolution.warnings,
    );
  }
}
