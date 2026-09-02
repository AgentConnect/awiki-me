import '../models/app_thread_ref.dart';

abstract interface class ImCoreRuntimePort {
  bool get isOpen;

  Future<void> open();

  Future<List<String>> validate();

  Future<void> ensureIdentityVault(String identityIdOrAlias);

  Future<void> switchIdentity(String identityIdOrAlias);

  /// Releases only the selected identity client while keeping Core available
  /// for signed-out registration and Join/Recovery continuation.
  Future<void> clearIdentity();

  Future<void> dispose();
}

abstract interface class ImCoreThreadCodecPort {
  Object toCoreThreadRef(AppThreadRef thread);

  Object toCoreMessageTarget(AppThreadRef thread);
}
