import 'package:awiki_me/src/application/models/product_local_models.dart';

// Test-only observation after runtime activation: a valid new-epoch refresh
// must not be confused with persistence of the retired registry snapshot.
bool handleRecoveryRegistryResetObserved({
  required ProductDeviceRegistryEpochResetAuthorization expected,
  required ProductDeviceRegistryEpoch? epoch,
  required ProductDeviceRegistryEpochResetReceipt? receipt,
  required ProductDeviceRegistrySnapshot? snapshot,
}) {
  final target = expected.reference.targetEpoch;
  return receipt?.authorization.matches(expected) == true &&
      epoch?.matches(target) == true &&
      (snapshot == null ||
          (snapshot.binding.ownerIdentityId ==
                  expected.reference.ownerIdentityId &&
              snapshot.binding.accountId == expected.reference.accountUserId &&
              snapshot.epoch.matches(target)));
}
