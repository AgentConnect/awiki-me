class PeerDisplayProfile {
  const PeerDisplayProfile({
    required this.did,
    this.peerPersonaId,
    this.displayName,
    this.handle,
    this.avatarUri,
  });

  final String did;
  final String? peerPersonaId;
  final String? displayName;
  final String? handle;
  final String? avatarUri;
}
