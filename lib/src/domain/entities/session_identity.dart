class SessionIdentity {
  const SessionIdentity({
    required this.did,
    required this.credentialName,
    required this.displayName,
    this.handle,
    this.jwtToken,
  });

  final String did;
  final String credentialName;
  final String displayName;
  final String? handle;
  final String? jwtToken;
}

