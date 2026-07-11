import '../../domain/entities/user_profile.dart';

class DirectoryPeerResolution {
  const DirectoryPeerResolution({
    required this.input,
    required this.did,
    this.handle,
    this.conversationId,
    this.profile,
    this.warnings = const <String>[],
  });

  final String input;
  final String did;
  final String? handle;
  final String? conversationId;
  final UserProfile? profile;
  final List<String> warnings;
}

abstract interface class DirectoryCorePort {
  Future<DirectoryPeerResolution> resolvePeer(String peer);

  Future<DirectoryPeerResolution> lookupHandle(String handle);
}
