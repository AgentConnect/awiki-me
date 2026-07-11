import 'dart:io';

import '../../application/tenant/app_tenant.dart';
import 'awiki_storage_scope_layout.dart';
import 'scope_manifest.dart';
import 'scope_secret_repository.dart';

enum StorageScopeProvisionPoint {
  rootCreated,
  manifestWritten,
  secretCreated,
  directoriesCreated,
  manifestReady,
}

typedef StorageScopeFaultInjector =
    Future<void> Function(StorageScopeProvisionPoint point);
typedef ScopeSecretRecordFactory =
    ScopeSecretRecord Function(StorageScopeId scopeId);

class StorageScopeProvisioner {
  StorageScopeProvisioner({
    required this.secrets,
    required this.manifests,
    required this.secretFactory,
    this.faultInjector,
  });

  final ScopeSecretRepository secrets;
  final StorageScopeManifestStore manifests;
  final ScopeSecretRecordFactory secretFactory;
  final StorageScopeFaultInjector? faultInjector;

  Future<StorageScopeManifest> provision({
    required AwikiStorageScopeLayout layout,
    required AppTenantProfile owner,
    DateTime? now,
  }) async {
    if (layout.scopeId != owner.storageScopeId) {
      throw const FormatException('scope_owner_mismatch');
    }
    final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
    await layout.createScopeRootExclusive();
    await _fault(StorageScopeProvisionPoint.rootCreated);
    var manifest = StorageScopeManifest(
      storageScopeId: owner.storageScopeId,
      ownerTenantProfileId: owner.tenantProfileId,
      lifecycle: StorageScopeLifecycle.provisioning,
      remoteRealmId: owner.remoteRealmId,
      didHostAtCreation: owner.didHost,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await manifests.writeAtomic(layout.manifestPath, manifest);
    await _fault(StorageScopeProvisionPoint.manifestWritten);
    await secrets.createExclusive(secretFactory(owner.storageScopeId));
    await _fault(StorageScopeProvisionPoint.secretCreated);
    await layout.ensureDataDirectories();
    await _fault(StorageScopeProvisionPoint.directoriesCreated);
    manifest = manifest.copyWith(
      lifecycle: StorageScopeLifecycle.ready,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await manifests.writeAtomic(layout.manifestPath, manifest);
    await _fault(StorageScopeProvisionPoint.manifestReady);
    return manifest;
  }

  Future<StorageScopeManifest?> recover({
    required AwikiStorageScopeLayout layout,
    required TenantProfileId expectedOwner,
  }) async {
    await layout.assertSafeExistingScope();
    final manifest = await manifests.readExisting(layout.manifestPath);
    _validateBinding(layout, expectedOwner, manifest);
    final secret = await secrets.readExisting(layout.scopeId);
    if (secret.status == ScopeSecretReadStatus.accessDenied) {
      return _block(layout, manifest);
    }
    if (manifest.lifecycle == StorageScopeLifecycle.ready) {
      if (secret.status != ScopeSecretReadStatus.present) {
        return _block(layout, manifest);
      }
      return manifest;
    }
    if (manifest.lifecycle != StorageScopeLifecycle.provisioning) {
      return manifest;
    }
    if (secret.status == ScopeSecretReadStatus.present) {
      await layout.ensureDataDirectories();
      final ready = manifest.copyWith(
        lifecycle: StorageScopeLifecycle.ready,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await manifests.writeAtomic(layout.manifestPath, ready);
      return ready;
    }
    if (secret.status != ScopeSecretReadStatus.missing ||
        !await _isPristine(layout)) {
      return _block(layout, manifest);
    }
    await Directory(layout.scopeRoot).delete(recursive: true);
    return null;
  }

  Future<StorageScopeManifest?> recoverOrphan({
    required AwikiStorageScopeLayout layout,
  }) async {
    await layout.assertSafeExistingScope();
    if (!await File(layout.manifestPath).exists()) {
      if (!await _isPristine(layout)) {
        throw const FileSystemException('orphan_scope_unverified');
      }
      await Directory(layout.scopeRoot).delete(recursive: true);
      return null;
    }
    final manifest = await manifests.readExisting(layout.manifestPath);
    return recover(
      layout: layout,
      expectedOwner: manifest.ownerTenantProfileId,
    );
  }

  Future<StorageScopeManifest> beginDeletion({
    required AwikiStorageScopeLayout layout,
    required TenantProfileId expectedOwner,
  }) async {
    final manifest = await manifests.readExisting(layout.manifestPath);
    _validateBinding(layout, expectedOwner, manifest);
    final deleting = manifest.copyWith(
      lifecycle: StorageScopeLifecycle.deleting,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await manifests.writeAtomic(layout.manifestPath, deleting);
    return deleting;
  }

  void _validateBinding(
    AwikiStorageScopeLayout layout,
    TenantProfileId expectedOwner,
    StorageScopeManifest manifest,
  ) {
    if (manifest.storageScopeId != layout.scopeId ||
        manifest.ownerTenantProfileId != expectedOwner) {
      throw const FormatException('scope_manifest_mismatch');
    }
  }

  Future<StorageScopeManifest> _block(
    AwikiStorageScopeLayout layout,
    StorageScopeManifest manifest,
  ) async {
    final blocked = manifest.copyWith(
      lifecycle: StorageScopeLifecycle.blocked,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await manifests.writeAtomic(layout.manifestPath, blocked);
    return blocked;
  }

  Future<bool> _isPristine(AwikiStorageScopeLayout layout) async {
    await for (final entity in Directory(
      layout.scopeRoot,
    ).list(followLinks: false)) {
      if (entity.path == layout.manifestPath) continue;
      if (entity is Directory) {
        await for (final nested in entity.list(
          recursive: true,
          followLinks: false,
        )) {
          if (nested is File && await nested.length() > 0) return false;
          if (nested is Link) return false;
        }
        continue;
      }
      return false;
    }
    return true;
  }

  Future<void> _fault(StorageScopeProvisionPoint point) async {
    await faultInjector?.call(point);
  }
}

class StorageScopeProcessLock {
  StorageScopeProcessLock(this.path);
  final String path;

  Future<T> synchronized<T>(Future<T> Function() action) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.exclusive);
      return await action();
    } finally {
      await handle.unlock();
      await handle.close();
    }
  }
}
