import '../../application/tenant/app_tenant.dart';

enum ScopeSecretReadStatus { present, missing, accessDenied, corrupt }

class ScopeSecretRecord {
  const ScopeSecretRecord({required this.scopeId, required this.opaqueValue});
  final StorageScopeId scopeId;
  final Object opaqueValue;
}

class ScopeSecretReadResult {
  const ScopeSecretReadResult(this.status, {this.record});
  final ScopeSecretReadStatus status;
  final ScopeSecretRecord? record;
}

abstract interface class ScopeSecretRepository {
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId);
  Future<void> createExclusive(ScopeSecretRecord record);
  Future<void> delete(StorageScopeId scopeId);
}

class UnavailableScopeSecretRepository implements ScopeSecretRepository {
  const UnavailableScopeSecretRepository();

  @override
  Future<void> createExclusive(ScopeSecretRecord record) => Future<void>.error(
    const ScopeSecretException('scope_secret_provider_unavailable'),
  );

  @override
  Future<void> delete(StorageScopeId scopeId) => Future<void>.error(
    const ScopeSecretException('scope_secret_provider_unavailable'),
  );

  @override
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId) =>
      Future<ScopeSecretReadResult>.value(
        const ScopeSecretReadResult(ScopeSecretReadStatus.accessDenied),
      );
}

class ScopeSecretException implements Exception {
  const ScopeSecretException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Deterministic test adapter. It deliberately knows nothing about Keychain or
/// the Step 03 envelope schema.
class FakeScopeSecretRepository implements ScopeSecretRepository {
  final Map<StorageScopeId, ScopeSecretRecord> _records = {};
  final Set<StorageScopeId> deniedScopes = {};

  @override
  Future<void> createExclusive(ScopeSecretRecord record) async {
    if (deniedScopes.contains(record.scopeId)) {
      throw const ScopeSecretException('vault_key_access_denied');
    }
    if (_records.containsKey(record.scopeId)) {
      throw const ScopeSecretException('vault_key_already_exists');
    }
    _records[record.scopeId] = record;
  }

  @override
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId) async {
    if (deniedScopes.contains(scopeId)) {
      return const ScopeSecretReadResult(ScopeSecretReadStatus.accessDenied);
    }
    final record = _records[scopeId];
    return record == null
        ? const ScopeSecretReadResult(ScopeSecretReadStatus.missing)
        : ScopeSecretReadResult(ScopeSecretReadStatus.present, record: record);
  }

  @override
  Future<void> delete(StorageScopeId scopeId) async {
    if (deniedScopes.contains(scopeId)) {
      throw const ScopeSecretException('vault_key_access_denied');
    }
    _records.remove(scopeId);
  }
}
