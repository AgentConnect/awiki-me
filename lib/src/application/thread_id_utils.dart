// Deprecated migration adapter for pre-conversationId paths.
//
// TODO(message-arch Step 14): remove this as a correctness mechanism after
// list/timeline/read/send/sync providers consume im-core ConversationIdentity
// and AppConversationReadRef. Until then, callers must treat these helpers as
// compatibility fallbacks only.
String canonicalDirectThreadId(String ownerDid, String peerDid) {
  final owner = ownerDid.trim();
  final peer = peerDid.trim();
  if (owner.isEmpty) {
    return peer;
  }
  if (peer.isEmpty) {
    return owner;
  }
  final participants = <String>[owner, peer]..sort();
  return 'dm:${participants[0]}:${participants[1]}';
}

String canonicalGroupThreadId(String groupDid) {
  final group = groupDid.trim();
  if (group.isEmpty) {
    return '';
  }
  return group.startsWith('group:') ? group : 'group:$group';
}

String canonicalThreadId({
  required String ownerDid,
  required bool isGroup,
  String? peerDid,
  String? groupId,
  String? fallbackThreadId,
}) {
  final fallback = fallbackThreadId?.trim() ?? '';
  if (isGroup) {
    final groupThreadId = canonicalGroupThreadId(
      _firstNonEmpty([groupId, _stripPrefix(fallback, 'group:')]) ?? '',
    );
    return groupThreadId.isNotEmpty ? groupThreadId : fallback;
  }

  final peer = _firstNonEmpty([peerDid]);
  if (peer != null) {
    final directThreadId = canonicalDirectThreadId(ownerDid, peer);
    if (directThreadId.isNotEmpty) {
      return directThreadId;
    }
  }
  return fallback;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

String? _stripPrefix(String value, String prefix) {
  if (value.isEmpty) {
    return null;
  }
  return value.startsWith(prefix) ? value.substring(prefix.length) : value;
}
