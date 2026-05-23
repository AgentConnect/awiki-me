class AppSession {
  const AppSession({
    required this.did,
    required this.identityId,
    required this.displayName,
    this.handle,
    this.localAlias,
    this.authenticated = false,
    this.expiresAt,
  });

  final String did;
  final String identityId;
  final String displayName;
  final String? handle;
  final String? localAlias;
  final bool authenticated;
  final DateTime? expiresAt;

  AppSession copyWith({
    String? did,
    String? identityId,
    String? displayName,
    String? handle,
    String? localAlias,
    bool? authenticated,
    DateTime? expiresAt,
  }) {
    return AppSession(
      did: did ?? this.did,
      identityId: identityId ?? this.identityId,
      displayName: displayName ?? this.displayName,
      handle: handle ?? this.handle,
      localAlias: localAlias ?? this.localAlias,
      authenticated: authenticated ?? this.authenticated,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
