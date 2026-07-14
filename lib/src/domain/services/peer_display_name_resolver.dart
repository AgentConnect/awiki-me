class PeerDisplayNameResolver {
  const PeerDisplayNameResolver();

  String resolve({
    String? localNote,
    String? nickname,
    String? fullHandle,
    String? senderNameSnapshot,
    String? did,
    String unknownLabel = '',
  }) {
    final normalizedDid = did?.trim() ?? '';
    final compact = compactDid(normalizedDid);
    for (final candidate in <String?>[localNote, nickname]) {
      final value = _humanName(candidate, normalizedDid, compact);
      if (value.isNotEmpty) {
        return value;
      }
    }
    final handle = cleanHandle(fullHandle);
    if (handle.isNotEmpty && handle != normalizedDid) {
      return handle;
    }
    final snapshot = _humanName(senderNameSnapshot, normalizedDid, compact);
    if (snapshot.isNotEmpty) {
      return snapshot;
    }
    if (compact.isNotEmpty) {
      return compact;
    }
    return unknownLabel.trim();
  }

  static String cleanHandle(String? source) {
    var value = source?.trim() ?? '';
    while (value.startsWith('@')) {
      value = value.substring(1).trimLeft();
    }
    return value;
  }

  static String compactDid(String source) {
    final did = source.trim();
    if (did.isEmpty) {
      return '';
    }
    final userMatch = RegExp(r':(?:user:)?([^:]+):e1_').firstMatch(did);
    if (userMatch != null) {
      return userMatch.group(1)!;
    }
    final tailMatch = RegExp(r':([^:]+)$').firstMatch(did);
    return tailMatch?.group(1) ?? did;
  }

  static String _humanName(String? source, String did, String compactDid) {
    final value = source?.trim() ?? '';
    if (value.isEmpty ||
        value.startsWith('did:') ||
        value == did ||
        value == compactDid) {
      return '';
    }
    return value;
  }
}
