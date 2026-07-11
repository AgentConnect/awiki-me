import '../../application/active_session_store.dart';
import '../../application/tenant/app_tenant.dart';
import 'app_key_value_store.dart';

class KeyValueActiveSessionStore implements ActiveSessionStore {
  KeyValueActiveSessionStore({
    required AppKeyValueStore storage,
    required StorageScopeId scopeId,
  }) : _storage = storage,
       _key = 'awiki_me_active_identity.scope.${scopeId.value}';

  final AppKeyValueStore _storage;
  final String _key;

  @override
  Future<String?> readActiveIdentityId() async {
    final value = (await _storage.read(key: _key))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> writeActiveIdentityId(String identityId) async {
    final trimmed = identityId.trim();
    if (trimmed.isEmpty) {
      await clearActiveIdentityId();
      return;
    }
    await _storage.write(key: _key, value: trimmed);
  }

  @override
  Future<void> clearActiveIdentityId() {
    return _storage.delete(key: _key);
  }
}
