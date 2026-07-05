// Presentation compatibility for group display thread ids only.
// Direct conversation identity is owned by im-core and must not be re-derived
// in AWiki Me.
String canonicalGroupThreadId(String groupDid) {
  final group = groupDid.trim();
  if (group.isEmpty) {
    return '';
  }
  return group.startsWith('group:') ? group : 'group:$group';
}
