import '../../data/awiki_sdk/awiki_anp_session.dart';
import '../entities/session_identity.dart';

abstract class AwikiAccountGateway {
  Future<SessionIdentity?> restoreSession();

  Future<SessionIdentity?> currentSession();

  Future<SessionIdentity?> refreshSession();

  Future<AwikiAnpSession> currentAnpSession({bool requireSigning = false});

  Future<void> logout();

  Future<List<SessionIdentity>> listLocalCredentials();

  Future<SessionIdentity> loginWithLocalCredential(String credentialName);

  Future<void> deleteLocalCredential(String credentialName);

  Future<String?> exportCurrentCredentialAsZip();

  Future<SessionIdentity?> importCredentialFromZip();

  Future<void> sendOtp({required String phone});

  Future<void> sendEmailVerification({required String email});

  Future<bool> checkEmailVerified({required String email});

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
