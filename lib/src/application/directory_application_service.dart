import '../domain/entities/peer_display_profile.dart';
import 'ports/directory_core_port.dart';

abstract interface class DirectoryApplicationService {
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  );

  Future<DirectoryPeerResolution> resolvePeer(String peer);

  Future<DirectoryPeerResolution> lookupHandle(String handle);
}

class ImCoreDirectoryApplicationService implements DirectoryApplicationService {
  const ImCoreDirectoryApplicationService({
    required DirectoryCorePort directory,
  }) : _directory = directory;

  final DirectoryCorePort _directory;

  @override
  Future<List<PeerDisplayProfile>> loadCachedDisplayProfiles(
    Iterable<String> dids,
  ) {
    return _directory.loadCachedDisplayProfiles(dids);
  }

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) {
    return _directory.lookupHandle(handle.trim().toLowerCase());
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) {
    return _directory.resolvePeer(peer.trim());
  }
}
