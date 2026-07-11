import 'dart:io';

import 'package:path/path.dart' as p;

import '../../application/tenant/app_tenant.dart';

class AwikiStorageScopeLayout {
  AwikiStorageScopeLayout.fromRoots({
    required String appSupportRoot,
    required String cacheRoot,
    required String tempRoot,
    required this.scopeId,
  }) : supportRoot = p.normalize(p.absolute(appSupportRoot)),
       cacheRoot = p.normalize(p.absolute(cacheRoot)),
       tempRoot = p.normalize(p.absolute(tempRoot)) {
    _assertContained(supportRoot, scopeRoot);
    _assertContained(cacheRoot, cacheScopeRoot);
    _assertContained(tempRoot, tempScopeRoot);
  }

  final String supportRoot;
  final String cacheRoot;
  final String tempRoot;
  final StorageScopeId scopeId;

  String get awikiRoot => p.join(supportRoot, 'awiki-me');
  String get controlRoot => p.join(awikiRoot, 'control');
  String get registryPath => p.join(controlRoot, 'tenant-registry.json');
  String get scopesRoot => p.join(awikiRoot, 'storage-scopes');
  String get scopeRoot => p.join(scopesRoot, scopeId.value);
  String get manifestPath => p.join(scopeRoot, 'scope-manifest.json');
  String get imCoreRoot => p.join(scopeRoot, 'im-core');
  String get identitiesRoot => p.join(imCoreRoot, 'identities');
  String get identityRegistryPath => p.join(identitiesRoot, 'registry.json');
  String get defaultIdentityPath => p.join(identitiesRoot, 'default');
  String get identityVaultRoot => p.join(imCoreRoot, 'identity-vault');
  String get vaultWorkspaceId => 'awiki-me.scope.v1.${scopeId.value}';
  String get vaultContextDeviceId =>
      'awiki-me.scope-device.v1.${scopeId.value}';
  String get imCoreStateRoot => p.join(imCoreRoot, 'state');
  String get imCoreSqlitePath => p.join(imCoreStateRoot, 'im_core.sqlite');
  String get productRoot => p.join(scopeRoot, 'product');
  String get productDatabasePath =>
      p.join(productRoot, 'awiki_me_product_store.db');
  String get attachmentsRoot => p.join(scopeRoot, 'attachments');
  String get cacheScopeRoot =>
      p.join(cacheRoot, 'awiki-me', 'storage-scopes', scopeId.value);
  String get cacheImCoreRoot => p.join(cacheScopeRoot, 'im-core');
  String get tempScopeRoot =>
      p.join(tempRoot, 'awiki-me', 'storage-scopes', scopeId.value);
  String get tempImCoreRoot => p.join(tempScopeRoot, 'im-core');

  Future<void> createScopeRootExclusive() async {
    await _assertNoLinksBetween(supportRoot, scopesRoot);
    await Directory(scopesRoot).create(recursive: true);
    await _assertNoLinksBetween(supportRoot, scopesRoot);
    final existing = await FileSystemEntity.type(scopeRoot, followLinks: false);
    if (existing != FileSystemEntityType.notFound) {
      throw const FileSystemException('storage_scope_already_exists');
    }
    try {
      await Directory(scopeRoot).create(recursive: false);
    } on FileSystemException {
      final raced = await FileSystemEntity.type(scopeRoot, followLinks: false);
      if (raced != FileSystemEntityType.notFound) {
        throw const FileSystemException('storage_scope_already_exists');
      }
      rethrow;
    }
  }

  Future<void> ensureDataDirectories() async {
    await assertSafeExistingScope();
    for (final path in <String>[
      identitiesRoot,
      identityVaultRoot,
      imCoreStateRoot,
      productRoot,
      attachmentsRoot,
    ]) {
      await _assertNoLinksBetween(scopeRoot, path);
      await Directory(path).create(recursive: true);
    }
    for (final (root, path) in <(String, String)>[
      (cacheRoot, cacheImCoreRoot),
      (tempRoot, tempImCoreRoot),
    ]) {
      await _assertNoLinksBetween(root, path);
      await Directory(path).create(recursive: true);
    }
  }

  Future<void> assertSafeExistingScope() async {
    _assertContained(scopesRoot, scopeRoot);
    await _assertNoLinksBetween(supportRoot, scopeRoot);
    final type = await FileSystemEntity.type(scopeRoot, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('storage_scope_root_invalid');
    }
  }
}

void _assertContained(String parent, String child) {
  if (!p.isWithin(parent, child)) {
    throw const FormatException('storage_scope_path_escape');
  }
}

Future<void> _rejectSymlink(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw const FileSystemException('storage_scope_symlink_forbidden');
  }
}

Future<void> _assertNoLinksBetween(String trustedRoot, String target) async {
  final normalizedRoot = p.normalize(p.absolute(trustedRoot));
  var current = p.normalize(p.absolute(target));
  if (current != normalizedRoot && !p.isWithin(normalizedRoot, current)) {
    throw const FormatException('storage_scope_path_escape');
  }
  while (current != normalizedRoot) {
    await _rejectSymlink(Directory(current));
    final parent = p.dirname(current);
    if (parent == current) {
      throw const FormatException('storage_scope_path_escape');
    }
    current = parent;
  }
}
