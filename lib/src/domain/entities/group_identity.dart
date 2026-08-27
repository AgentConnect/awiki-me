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
