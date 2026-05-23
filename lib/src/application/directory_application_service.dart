import 'ports/directory_core_port.dart';

abstract interface class DirectoryApplicationService {
  Future<DirectoryPeerResolution> resolvePeer(String peer);

  Future<DirectoryPeerResolution> lookupHandle(String handle);
}

class ImCoreDirectoryApplicationService implements DirectoryApplicationService {
  const ImCoreDirectoryApplicationService({
    required DirectoryCorePort directory,
  }) : _directory = directory;

  final DirectoryCorePort _directory;

  @override
  Future<DirectoryPeerResolution> lookupHandle(String handle) {
    return _directory.lookupHandle(handle.trim().toLowerCase());
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) {
    return _directory.resolvePeer(peer.trim());
  }
}
