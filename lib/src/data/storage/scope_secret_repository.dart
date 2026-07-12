import '../../application/tenant/app_tenant.dart';
import 'scope_secret_envelope.dart';

enum ScopeSecretReadStatus {
  present,
  missing,
  accessDenied,
  corrupt,
  scopeMismatch,
  schemaUnsupported,
  providerUnavailable,
  unsupported,
}

enum ScopeSecretFailure {
  alreadyExists('scope_secret_already_exists'),
  revisionConflict('scope_secret_revision_conflict'),
  accessDenied('scope_secret_access_denied'),
  corrupt('scope_secret_corrupt'),
  providerUnavailable('scope_secret_provider_unavailable'),
  unsupported('scope_secret_platform_unsupported'),
  operationFailed('scope_secret_operation_failed');

  const ScopeSecretFailure(this.code);
  final String code;
}

class ScopeSecretRecord {
  const ScopeSecretRecord({required this.envelope});

  final ScopeSecretEnvelope envelope;
  StorageScopeId get scopeId => envelope.scopeId;

  @override
  String toString() =>
      'ScopeSecretRecord(scopeId: ${scopeId.value}, revision: ${envelope.revision}, value: <redacted>)';
}

class ScopeSecretReadResult {
  const ScopeSecretReadResult(this.status, {this.record});

  final ScopeSecretReadStatus status;
  final ScopeSecretRecord? record;
}

abstract interface class ScopeSecretRepository {
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId);
  Future<void> createExclusive(ScopeSecretRecord record);
  Future<void> compareAndReplace({
    required ScopeSecretRecord record,
    required int expectedRevision,
  });
  Future<void> delete(StorageScopeId scopeId);
}

class UnavailableScopeSecretRepository implements ScopeSecretRepository {
  const UnavailableScopeSecretRepository();

  @override
  Future<void> createExclusive(ScopeSecretRecord record) =>
      _unavailable<void>();

  @override
  Future<void> compareAndReplace({
    required ScopeSecretRecord record,
    required int expectedRevision,
  }) => _unavailable<void>();

  @override
  Future<void> delete(StorageScopeId scopeId) => _unavailable<void>();

  @override
  Future<ScopeSecretReadResult> readExisting(StorageScopeId scopeId) async =>
      const ScopeSecretReadResult(ScopeSecretReadStatus.providerUnavailable);

  Future<T> _unavailable<T>() => Future<T>.error(
    const ScopeSecretException(ScopeSecretFailure.providerUnavailable),
  );
}

class ScopeSecretException implements Exception {
  const ScopeSecretException(this.failure);

  final ScopeSecretFailure failure;
  String get code => failure.code;

  @override
  String toString() => code;
}

/// Deterministic test adapter. Production code must use a platform provider or
/// the explicitly selected E2E file provider.
class FakeScopeSecretRepository implements ScopeSecretRepository {
  final Map<StorageScopeId, ScopeSecretRecord> _records = {};
  final Set<StorageScopeId> deniedScopes = {};

  @override
  Future<void> createExclusive(ScopeSecretRecord record) async {
    _checkAccess(record.scopeId);
    if (_records.containsKey(record.scopeId)) {
      throw const ScopeSecretException(ScopeSecretFailure.alreadyExists);
    }
    _records[record.scopeId] = record;
  }

  @override
  Future<void> compareAndReplace({
    required ScopeSecretRecord record,
    required int expectedRevision,
  }) async {
    _checkAccess(record.scopeId);
    final current = _records[record.scopeId];
    if (current == null ||
        current.envelope.revision != expectedRevision ||
        record.envelope.revision != expectedRevision + 1) {
      throw const ScopeSecretException(ScopeSecretFailure.revisionConflict);
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
    _checkAccess(scopeId);
    _records.remove(scopeId);
  }

  void _checkAccess(StorageScopeId scopeId) {
    if (deniedScopes.contains(scopeId)) {
      throw const ScopeSecretException(ScopeSecretFailure.accessDenied);
    }
  }
}
