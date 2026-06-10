class RelationshipSummary {
  const RelationshipSummary({
    required this.did,
    required this.displayName,
    required this.relationship,
    this.avatarUri,
  });

  final String did;
  final String displayName;
  final String relationship;
  final String? avatarUri;
}
