import '../storage/awiki_storage_scope_layout.dart';
import '../storage/scope_manifest.dart';
import '../storage/scope_secret_repository.dart';
import 'awiki_im_core_config.dart';
import 'awiki_im_core_paths.dart';
import 'awiki_im_core_runtime.dart';
import 'awiki_im_core_secret_storage.dart';

/// Provision/recovery gate that proves the newly created scope secret and
/// deterministic context can open a VaultRequired im-core before `ready`.
class StorageScopeImCoreValidator {
  const StorageScopeImCoreValidator({required this.repository});

  final ScopeSecretRepository repository;

  Future<void> call(
    AwikiStorageScopeLayout layout,
    StorageScopeManifest manifest,
  ) async {
    if (manifest.storageScopeId != layout.scopeId) {
      throw const FormatException('scope_manifest_mismatch');
    }
    final runtime = AwikiImCoreRuntime(
      config: AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://${manifest.didHostAtCreation}',
        didDomain: manifest.didHostAtCreation,
      ),
      paths: AwikiImCorePathLayout.fromStorageScope(layout),
      scopeId: layout.scopeId,
      vaultSecretProvider: ScopeAwikiImCoreVaultSecretProvider(
        repository: repository,
      ),
    );
    try {
      await runtime.openAndValidate();
    } finally {
      await runtime.dispose();
    }
  }
}
