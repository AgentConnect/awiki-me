enum LegacyIdentityUpgradePhase { idle, running, retryRequired, completed }

class LegacyIdentityUpgradeStatus {
  const LegacyIdentityUpgradeStatus._({required this.phase, this.identityId});

  const LegacyIdentityUpgradeStatus.idle()
    : this._(phase: LegacyIdentityUpgradePhase.idle);

  const LegacyIdentityUpgradeStatus.running()
    : this._(phase: LegacyIdentityUpgradePhase.running);

  const LegacyIdentityUpgradeStatus.retryRequired({required String identityId})
    : this._(
        phase: LegacyIdentityUpgradePhase.retryRequired,
        identityId: identityId,
      );

  const LegacyIdentityUpgradeStatus.completed()
    : this._(phase: LegacyIdentityUpgradePhase.completed);

  final LegacyIdentityUpgradePhase phase;
  final String? identityId;
}

abstract interface class LegacyIdentityUpgradePort {
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  );

  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  );
}
