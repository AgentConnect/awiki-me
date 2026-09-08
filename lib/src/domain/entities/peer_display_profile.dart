class PeerDisplayProfile {
  const PeerDisplayProfile({
    required this.did,
    this.peerPersonaId,
    this.displayName,
    this.handle,
    this.avatarUri,
    this.profileUri,
    this.subjectType,
    this.isStale = false,
    this.legacyFallback = false,
  });

  final String did;
  final String? peerPersonaId;
  final String? displayName;
  final String? handle;
  final String? avatarUri;
  final String? profileUri;
  final String? subjectType;
  final bool isStale;
  final bool legacyFallback;
}
