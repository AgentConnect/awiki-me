class PeerDisplayProfile {
  const PeerDisplayProfile({
    required this.did,
    this.peerPersonaId,
    this.displayName,
    this.handle,
    this.avatarUri,
    this.isStale = false,
    this.legacyFallback = false,
  });

  final String did;
  final String? peerPersonaId;
  final String? displayName;
  final String? handle;
  final String? avatarUri;
  final bool isStale;
  final bool legacyFallback;
}
