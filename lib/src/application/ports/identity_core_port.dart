import '../models/app_session.dart';
import '../models/daemon_subkey_authorization_revoke_result.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/device_management.dart';
import '../../domain/entities/session_identity.dart';

enum IdentityRegistrationStatus { registered, joinRequired }

class IdentityRegistrationResult {
  const IdentityRegistrationResult({
    required this.status,
    this.identity,
    this.joinProgress,
    this.warnings = const <String>[],
  });

  final IdentityRegistrationStatus status;
  final AppSession? identity;
  final DeviceJoinProgress? joinProgress;
  final List<String> warnings;
}

abstract interface class IdentityCorePort {
  Future<List<AppSession>> listLocalIdentities();

  Future<AppSession?> defaultIdentity();

  Future<AppSession> resolveIdentity(String identityIdOrAlias);

  Future<SessionAccountBinding> activeSyncAccountBinding();

  Future<UserSubkeyPackage> loadDaemonSubkeyPackage(String identityIdOrAlias);

  Future<UserSubkeyPackage> ensureDaemonSubkeyPackage(String identityIdOrAlias);

  Future<DaemonSubkeyAuthorizationRevokeResult> revokeDaemonSubkeyAuthorization(
    String identityIdOrAlias,
  );

  Future<AppSession> deleteLocalIdentity(String identityIdOrAlias);

  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? displayName,
  });

  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? displayName,
  });

  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String handle,
    String? inviteCode,
    String? displayName,
  });
}
