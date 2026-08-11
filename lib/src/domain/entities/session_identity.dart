// [INPUT]: Secret-free identity/session projections from application services.
// [OUTPUT]: UI-facing local identity, account-binding, and credential metadata.
// [POS]: Domain session projection; exact Core identity IDs remain distinct from local aliases.

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
    this.localIdentityId,
    this.handle,
    this.jwtToken,
    this.accountBinding,
  });

  final String did;

  final String credentialName;
  final String displayName;

  /// Exact Core local identity ID. Unlike [credentialName], this is never a
  /// user-facing local alias and is safe for stable-owner operation lookup.
  final String? localIdentityId;
  final String? handle;
  final String? jwtToken;

  /// Present only after Core has selected the identity and returned its typed
  /// active sync binding. Local identity inventory rows remain unbound.
  final SessionAccountBinding? accountBinding;

  String? get ownerIdentityId => accountBinding?.ownerIdentityId;

  String? get accountId => accountBinding?.accountId;

  String? get protocolDeviceId => accountBinding?.protocolDeviceId;

  String get localIdentitySelector {
    final stableId = localIdentityId?.trim();
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
