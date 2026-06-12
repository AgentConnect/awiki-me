import '../../domain/entities/session_identity.dart';

class AppSession {
  const AppSession({
    required this.did,
    required this.identityId,
    required this.displayName,
    this.handle,
    this.localAlias,
    this.authenticated = false,
    this.expiresAt,
    this.jwtToken,
  });

  final String did;
  final String identityId;
  final String displayName;
  final String? handle;
  final String? localAlias;
  final bool authenticated;
  final DateTime? expiresAt;
  final String? jwtToken;

  AppSession copyWith({
    String? did,
    String? identityId,
    String? displayName,
    String? handle,
    String? localAlias,
    bool? authenticated,
    DateTime? expiresAt,
    String? jwtToken,
  }) {
    return AppSession(
      did: did ?? this.did,
      identityId: identityId ?? this.identityId,
      displayName: displayName ?? this.displayName,
      handle: handle ?? this.handle,
      localAlias: localAlias ?? this.localAlias,
      authenticated: authenticated ?? this.authenticated,
      expiresAt: expiresAt ?? this.expiresAt,
      jwtToken: jwtToken ?? this.jwtToken,
    );
  }
}

extension AppSessionLegacyIdentity on AppSession {
  SessionIdentity toLegacySessionIdentity() {
    return SessionIdentity(
      did: did,
      credentialName: localAlias ?? identityId,
      displayName: displayName,
      handle: handle,
      jwtToken: jwtToken,
    );
  }
}
