class PeerDisplayProfile {
  const PeerDisplayProfile({
    required this.did,
    this.displayName,
    this.handle,
    this.avatarUri,
  });

  final String did;
  final String? displayName;
  final String? handle;
  final String? avatarUri;
}
