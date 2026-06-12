class RelationshipSummary {
  const RelationshipSummary({
    required this.did,
    required this.displayName,
    required this.relationship,
    this.avatarUri,
    this.handle,
  });

  final String did;
  final String displayName;
  final String relationship;
  final String? avatarUri;
  final String? handle;
}
