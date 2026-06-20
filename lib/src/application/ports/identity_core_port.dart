import '../models/app_session.dart';
import '../models/daemon_subkey_authorization_revoke_result.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';

abstract interface class IdentityCorePort {
  Future<List<AppSession>> listLocalIdentities();

  Future<AppSession?> defaultIdentity();

  Future<AppSession> resolveIdentity(String identityIdOrAlias);

  Future<UserSubkeyPackage> loadDaemonSubkeyPackage(String identityIdOrAlias);

  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage(String identityIdOrAlias);

  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
    String identityIdOrAlias,
  );

  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias);

  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  });

  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  });

  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  });
}
