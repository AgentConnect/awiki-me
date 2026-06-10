class RelationshipSummary {
  const RelationshipSummary({
    required this.did,
    required this.displayName,
    required this.relationship,
    this.handle,
  });

  final String did;
  final String displayName;
  final String relationship;
  final String? handle;
}
