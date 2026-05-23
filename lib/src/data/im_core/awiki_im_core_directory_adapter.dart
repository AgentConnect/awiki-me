import '../../application/ports/directory_core_port.dart';
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
  Future<DirectoryPeerResolution> lookupHandle(String handle) async {
    final resolution = await (await _runtime.currentClient()).directory
        .lookupHandle(handle);
    return DirectoryPeerResolution(
      input: resolution.input,
      did: resolution.did,
      handle: resolution.handle,
      profile: resolution.profile == null
          ? null
          : _mappers.userProfileFromCore(resolution.profile!),
      warnings: resolution.warnings,
    );
  }

  @override
  Future<DirectoryPeerResolution> resolvePeer(String peer) async {
    final resolution = await (await _runtime.currentClient()).directory
        .resolvePeer(peer);
    return DirectoryPeerResolution(
      input: resolution.input,
      did: resolution.did,
      handle: resolution.handle,
      profile: resolution.profile == null
          ? null
          : _mappers.userProfileFromCore(resolution.profile!),
      warnings: resolution.warnings,
    );
  }
}
