class AwikiAnpSession {
  const AwikiAnpSession({
    required this.did,
    required this.jwtToken,
    this.didDocument,
    this.privateKeyPem,
  });

  final String did;
  final String jwtToken;
  final Map<String, Object?>? didDocument;
  final String? privateKeyPem;

  bool get canSign =>
      didDocument != null &&
      didDocument!.isNotEmpty &&
      privateKeyPem != null &&
      privateKeyPem!.trim().isNotEmpty;

  bool get isE1Did => did.trim().split(':').last.startsWith('e1_');
}
