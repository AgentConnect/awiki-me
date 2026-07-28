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
    this.handle,
    this.jwtToken,
    this.accountBinding,
  });

  final String did;
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
}
