class DaemonSubkeyAuthorizationRevokeResult {
  const DaemonSubkeyAuthorizationRevokeResult({
    required this.userDid,
    required this.verificationMethod,
    required this.updated,
  });

  final String userDid;
  final String verificationMethod;
  final bool updated;
}
