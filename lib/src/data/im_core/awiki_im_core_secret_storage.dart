import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/tenant/app_tenant.dart';
import '../storage/scope_secret_repository.dart';

class AwikiImCoreVaultSecrets {
  const AwikiImCoreVaultSecrets({required this.rootKey});

  final core.DeviceVaultRootKey rootKey;
}

abstract interface class AwikiImCoreVaultSecretProvider {
  Future<AwikiImCoreVaultSecrets> openExisting(StorageScopeId scopeId);
}

/// Runtime adapter over the typed scope repository. It never provisions,
/// migrates, upserts, or falls back to another secret backend.
class ScopeAwikiImCoreVaultSecretProvider
    implements AwikiImCoreVaultSecretProvider {
  const ScopeAwikiImCoreVaultSecretProvider({required this.repository});

  final ScopeSecretRepository repository;

  @override
  Future<AwikiImCoreVaultSecrets> openExisting(StorageScopeId scopeId) async {
    final result = await repository.readExisting(scopeId);
    final record = switch (result.status) {
      ScopeSecretReadStatus.present => result.record,
      ScopeSecretReadStatus.missing => throw const AwikiVaultOpenException(
        'vault_key_missing',
      ),
      ScopeSecretReadStatus.accessDenied => throw const AwikiVaultOpenException(
        'vault_key_access_denied',
      ),
      ScopeSecretReadStatus.corrupt => throw const AwikiVaultOpenException(
        'vault_key_bundle_corrupt',
      ),
      ScopeSecretReadStatus.scopeMismatch =>
        throw const AwikiVaultOpenException('vault_key_scope_mismatch'),
      ScopeSecretReadStatus.schemaUnsupported =>
        throw const AwikiVaultOpenException('vault_key_schema_unsupported'),
      ScopeSecretReadStatus.providerUnavailable =>
        throw const AwikiVaultOpenException('vault_key_provider_unavailable'),
      ScopeSecretReadStatus.unsupported => throw const AwikiVaultOpenException(
        'vault_key_platform_unsupported',
      ),
    };
    if (record == null || record.scopeId != scopeId) {
      throw const AwikiVaultOpenException('vault_key_bundle_corrupt');
    }
    final material = record.envelope.identityVaultRoot.copyMaterial();
    try {
      return AwikiImCoreVaultSecrets(
        rootKey: core.DeviceVaultRootKey.fromList(material),
      );
    } finally {
      material.fillRange(0, material.length, 0);
    }
  }
}

class AwikiVaultOpenException implements Exception {
  const AwikiVaultOpenException(this.code);

  final String code;

  @override
  String toString() => code;
}
