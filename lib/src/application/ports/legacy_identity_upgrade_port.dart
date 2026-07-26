enum LegacyIdentityUpgradePhase { idle, running, retryRequired, completed }

class LegacyIdentityUpgradeStatus {
  const LegacyIdentityUpgradeStatus._({
    required this.phase,
    this.identityId,
    this.failureCode,
  });

  const LegacyIdentityUpgradeStatus.idle()
    : this._(phase: LegacyIdentityUpgradePhase.idle);

  const LegacyIdentityUpgradeStatus.running()
    : this._(phase: LegacyIdentityUpgradePhase.running);

  const LegacyIdentityUpgradeStatus.retryRequired({
    required String identityId,
    String failureCode = 'legacy_upgrade_failed',
  }) : this._(
         phase: LegacyIdentityUpgradePhase.retryRequired,
         identityId: identityId,
         failureCode: failureCode,
       );

  const LegacyIdentityUpgradeStatus.completed()
    : this._(phase: LegacyIdentityUpgradePhase.completed);

  final LegacyIdentityUpgradePhase phase;
  final String? identityId;
  final String? failureCode;
}

abstract interface class LegacyIdentityUpgradePort {
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  );

  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  );
}
