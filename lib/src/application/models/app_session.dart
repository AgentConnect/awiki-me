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
    this.accountBinding,
  });

  final String did;
  final String identityId;
  final String displayName;
  final String? handle;
  final String? localAlias;
  final bool authenticated;
  final DateTime? expiresAt;
  final String? jwtToken;

  /// Filled from `AwikiImClient.activeSyncAccountBinding()` after switch.
  /// Never derive this value from the fields above.
  final SessionAccountBinding? accountBinding;

  String? get ownerIdentityId => accountBinding?.ownerIdentityId;

  String? get accountId => accountBinding?.accountId;

  String? get protocolDeviceId => accountBinding?.protocolDeviceId;

  AppSession copyWith({
    String? did,
    String? identityId,
    String? displayName,
    String? handle,
    String? localAlias,
    bool? authenticated,
    DateTime? expiresAt,
    String? jwtToken,
    SessionAccountBinding? accountBinding,
    bool clearExpiresAt = false,
    bool clearJwtToken = false,
  }) {
    return AppSession(
      did: did ?? this.did,
      identityId: identityId ?? this.identityId,
      displayName: displayName ?? this.displayName,
      handle: handle ?? this.handle,
      localAlias: localAlias ?? this.localAlias,
      authenticated: authenticated ?? this.authenticated,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      jwtToken: clearJwtToken ? null : (jwtToken ?? this.jwtToken),
      accountBinding: accountBinding ?? this.accountBinding,
    );
  }
}

extension AppSessionLegacyIdentity on AppSession {
  SessionIdentity toLegacySessionIdentity() {
    return SessionIdentity(
      did: did,
      identityId: identityId,
      credentialName: localAlias ?? identityId,
      displayName: displayName,
      handle: handle,
      jwtToken: jwtToken,
      accountBinding: accountBinding,
    );
  }
}
