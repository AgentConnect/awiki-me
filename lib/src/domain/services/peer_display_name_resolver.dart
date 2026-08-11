class PeerDisplayNameResolver {
  const PeerDisplayNameResolver();

  String resolve({
    String? nickname,
    String? fullHandle,
    String? senderNameSnapshot,
    String? did,
    String unknownLabel = '',
    bool compactQualifiedHandle = false,
  }) {
    final normalizedDid = did?.trim() ?? '';
    final compact = compactDid(normalizedDid);
    final handle = cleanHandle(fullHandle);
    final name = _visibleName(
      nickname,
      fullHandle: handle,
      did: normalizedDid,
      compactDid: compact,
      compactQualifiedHandle: compactQualifiedHandle,
    );
    if (name.isNotEmpty) {
      return name;
    }
    if (handle.isNotEmpty && handle != normalizedDid) {
      return compactQualifiedHandle ? compactHandle(handle) : handle;
    }
    final snapshot = _visibleName(
      senderNameSnapshot,
      fullHandle: handle,
      did: normalizedDid,
      compactDid: compact,
      compactQualifiedHandle: compactQualifiedHandle,
    );
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

  /// Returns the user-facing local part of a domain-qualified Handle while
  /// leaving the complete Handle available to identity and routing surfaces.
  static String compactHandle(String? source) {
    final handle = cleanHandle(source);
    final separator = handle.indexOf('.');
    if (separator <= 0) {
      return handle;
    }
    return handle.substring(0, separator);
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

  static String _visibleName(
    String? source, {
    required String fullHandle,
    required String did,
    required String compactDid,
    required bool compactQualifiedHandle,
  }) {
    final value = _humanName(source, did, compactDid);
    if (value.isEmpty) {
      return '';
    }
    final cleaned = cleanHandle(value);
    final representsKnownHandle =
        fullHandle.isNotEmpty &&
        cleaned.toLowerCase() == fullHandle.toLowerCase();
    if (compactQualifiedHandle &&
        (representsKnownHandle ||
            (fullHandle.isEmpty && _looksLikeQualifiedHandle(cleaned)))) {
      return compactHandle(cleaned);
    }
    return value;
  }

  static bool _looksLikeQualifiedHandle(String value) {
    return RegExp(
      r'^[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
      caseSensitive: false,
    ).hasMatch(value);
  }
}
