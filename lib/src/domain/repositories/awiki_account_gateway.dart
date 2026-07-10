import '../entities/session_identity.dart';

enum HandleRegistrationStatus { registered, notRegistered }

class HandleAvailability {
  const HandleAvailability({
    required this.handle,
    required this.available,
    this.domain,
    this.fullHandle,
    this.reason,
    this.message,
  });

  final String handle;
  final String? domain;
  final String? fullHandle;
  final bool available;
  final String? reason;
  final String? message;
}

abstract class AwikiAccountGateway {
  Future<SessionIdentity?> restoreSession();

  Future<SessionIdentity?> currentSession();

  Future<SessionIdentity?> refreshSession();

  Future<Object> currentAnpSession({bool requireSigning = false});

  Future<void> logout();

  Future<List<SessionIdentity>> listLocalCredentials();

  Future<SessionIdentity> loginWithLocalCredential(String credentialName);

  Future<void> deleteLocalCredential(String credentialName);

  Future<String?> exportCurrentCredentialAsZip();

  Future<SessionIdentity?> importCredentialFromZip();

  Future<void> sendOtp({required String phone});

  Future<void> sendEmailVerification({
    required String email,
    required String handle,
  });

  Future<bool> checkEmailVerified({
    required String email,
    required String handle,
  });

  Future<HandleRegistrationStatus> lookupHandleRegistration({
    required String handle,
  });

  Future<SessionIdentity> registerHandle({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  });

  Future<SessionIdentity> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  });

  Future<SessionIdentity> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  });
}
