import '../models/app_thread_ref.dart';

abstract interface class ImCoreRuntimePort {
  bool get isOpen;

  Future<void> open();

  Future<List<String>> validate();

  Future<void> ensureIdentityVault(String identityIdOrAlias);

  Future<void> switchIdentity(String identityIdOrAlias);

  Future<void> dispose();
}

abstract interface class ImCoreThreadCodecPort {
  Object toCoreThreadRef(AppThreadRef thread);

  Object toCoreMessageTarget(AppThreadRef thread);
}
