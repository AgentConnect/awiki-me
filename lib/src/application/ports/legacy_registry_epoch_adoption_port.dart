// [INPUT]: Exact local identity selector for the active Core identity.
// [OUTPUT]: Optional secret-free proof for one-time pre-v5 Registry epoch adoption.
// [POS]: Identity/account binding capability; not a Handle Recovery operation.

import '../models/product_local_models.dart';

abstract interface class LegacyRegistryEpochAdoptionPort {
  /// Returns null unless Core proves its active local checkpoint and account
  /// binding match exactly and no Recovery transition marker exists.
  Future<LegacyRegistryEpochAdoptionAuthority?>
  legacyRegistryEpochAdoptionAuthority(String identitySelector);
}
