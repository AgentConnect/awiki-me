enum GroupIdentityMode { handle, didOnly }

String? groupHandleForDid({required String? handle, required String did}) {
  final normalizedHandle = handle?.trim().toLowerCase();
  if (normalizedHandle == null || normalizedHandle.isEmpty) {
    return null;
  }
  if (normalizedHandle.contains('.')) {
    return normalizedHandle;
  }
  final parts = did.trim().split(':');
  if (parts.length < 3 || parts[0] != 'did' || parts[1] != 'wba') {
    return null;
  }
  final providerDomain = parts[2].trim().toLowerCase();
  if (providerDomain.isEmpty || !providerDomain.contains('.')) {
    return null;
  }
  return '$normalizedHandle.$providerDomain';
}

class GroupIdentitySelection {
  const GroupIdentitySelection.didOnly()
    : mode = GroupIdentityMode.didOnly,
      handle = null;

  factory GroupIdentitySelection.handle(String handle) {
    final normalized = handle.trim().toLowerCase();
    if (normalized.isEmpty || !normalized.contains('.')) {
      throw ArgumentError.value(
        handle,
        'handle',
        'must be a domain-qualified Handle',
      );
    }
    return GroupIdentitySelection._(
      mode: GroupIdentityMode.handle,
      handle: normalized,
    );
  }

  const GroupIdentitySelection._({required this.mode, required this.handle});

  final GroupIdentityMode mode;
  final String? handle;
}

class GroupRebindRecoveryItem {
  const GroupRebindRecoveryItem({
    required this.groupDid,
    required this.layer,
    required this.phase,
    required this.blocked,
  });

  final String groupDid;
  final String layer;
  final String phase;
  final bool blocked;
}

class GroupRebindRecoverySummary {
  const GroupRebindRecoverySummary({
    required this.processed,
    required this.completed,
    required this.pending,
    required this.blocked,
    this.sendPausedGroupDids = const <String>[],
    this.items = const <GroupRebindRecoveryItem>[],
    this.warnings = const <String>[],
  });

  static const empty = GroupRebindRecoverySummary(
    processed: 0,
    completed: 0,
    pending: 0,
    blocked: 0,
  );

  final int processed;
  final int completed;
  final int pending;
  final int blocked;
  final List<String> sendPausedGroupDids;
  final List<GroupRebindRecoveryItem> items;
  final List<String> warnings;

  bool get hasPending => pending > 0 || sendPausedGroupDids.isNotEmpty;
  bool get hasBlocked => blocked > 0 || items.any((item) => item.blocked);
}
