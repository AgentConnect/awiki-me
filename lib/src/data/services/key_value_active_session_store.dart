import '../../application/active_session_store.dart';
import 'app_key_value_store.dart';

class KeyValueActiveSessionStore implements ActiveSessionStore {
  KeyValueActiveSessionStore({
    required AppKeyValueStore storage,
    required String stateNamespace,
  }) : _storage = storage,
       _key = 'awiki_me_active_identity.${_normalizeNamespace(stateNamespace)}';

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

String _normalizeNamespace(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return normalized.isEmpty ? 'default' : normalized;
}
