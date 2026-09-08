import '../models/app_session.dart';
import '../models/daemon_subkey_authorization_revoke_result.dart';
import '../../domain/entities/agent/agent_bootstrap.dart';
import '../../domain/entities/device_management.dart';
import '../../domain/entities/session_identity.dart';

enum IdentityRegistrationStatus { registered, joinRequired, recoveryRequired }

enum ExistingHandleJoinMode { ordinary, handleRecoveryRebind }

class IdentityRegistrationResult {
  const IdentityRegistrationResult({
    required this.status,
    this.identity,
    this.existingHandleContinuationId,
    this.existingHandleJoinMode,
    this.existingHandleJoinRequiresUserPresence = false,
    this.warnings = const <String>[],
  });

  final IdentityRegistrationStatus status;
  final AppSession? identity;
  final String? existingHandleContinuationId;
  final ExistingHandleJoinMode? existingHandleJoinMode;
  final bool existingHandleJoinRequiresUserPresence;
  final List<String> warnings;
}

abstract interface class IdentityCorePort {
  Future<List<AppSession>> listLocalIdentities();

  Future<AppSession?> defaultIdentity();

  Future<AppSession> resolveIdentity(String identityIdOrAlias);

  Future<AppSession> updateDisplayNameProjection({
    required String identityId,
    String? displayName,
  });

  Future<SessionAccountBinding> activeSyncAccountBinding();

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

abstract interface class DaemonSubkeyAuthorizationCorePort {
  Future<UserSubkeyPackage> authorizeDaemonSubkey(
    String identityIdOrAlias,
    UserSubkeyPackage proposal,
  );
}

class LocalIdentityDeletionTicket {
  const LocalIdentityDeletionTicket({
    required this.deletionId,
    required this.ownerIdentityId,
    required this.currentDid,
  });

  final String deletionId;
  final String ownerIdentityId;
  final String currentDid;
}

abstract interface class LocalIdentityDataDeletionPort {
  Future<AppSession> deleteLocalIdentityData(String identityIdOrAlias);

  Future<LocalIdentityDeletionTicket> prepareLocalIdentityDataDeletion(
    String identityIdOrAlias,
  );

  Future<AppSession> completeLocalIdentityDataDeletion(String deletionId);

  Future<List<LocalIdentityDeletionTicket>> pendingLocalIdentityDataDeletions();
}

abstract interface class ExistingHandleContinuationPort {
  Future<DeviceJoinProgress> beginExistingHandleDeviceJoin(
    String continuationId, {
    required bool userPresenceConfirmed,
  });

  Future<void> discardExistingHandleContinuation(String continuationId);
}
