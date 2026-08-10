class SessionAccountBinding {
  const SessionAccountBinding({
    required this.ownerIdentityId,
    required this.accountId,
    required this.currentDid,
    required this.protocolDeviceId,
    required this.identityGeneration,
    required this.deviceAuthGeneration,
  });

  final String ownerIdentityId;
  final String accountId;
  final String currentDid;
  final String protocolDeviceId;
  final String identityGeneration;
  final String deviceAuthGeneration;
}

class SessionIdentity {
  const SessionIdentity({
    required this.did,
    required this.credentialName,
    required this.displayName,
    this.identityId,
    this.handle,
    this.jwtToken,
    this.accountBinding,
  });

  final String did;

  /// Stable Core identity identifier. Legacy hosts may omit it, in which case
  /// exact local operations fall back to the current DID before the alias.
  final String? identityId;
  final String credentialName;
  final String displayName;
  final String? handle;
  final String? jwtToken;

  /// Present only after Core has selected the identity and returned its typed
  /// active sync binding. Local identity inventory rows remain unbound.
  final SessionAccountBinding? accountBinding;

  String? get ownerIdentityId => accountBinding?.ownerIdentityId;

  String? get accountId => accountBinding?.accountId;

  String? get protocolDeviceId => accountBinding?.protocolDeviceId;

  String get localIdentitySelector {
    final stableId = identityId?.trim();
    if (stableId != null && stableId.isNotEmpty) {
      return stableId;
    }
    final currentDid = did.trim();
    if (currentDid.isNotEmpty) {
      return currentDid;
    }
    return credentialName.trim();
  }
}
