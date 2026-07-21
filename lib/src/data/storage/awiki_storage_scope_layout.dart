import 'dart:io';

import 'package:path/path.dart' as p;

import '../../application/tenant/app_tenant.dart';
import 'awiki_storage_roots.dart';

class AwikiStorageScopeLayout {
  factory AwikiStorageScopeLayout.fromRoots({
    required String appSupportRoot,
    required String cacheRoot,
    required String tempRoot,
    required StorageScopeId scopeId,
    p.Context? pathContext,
  }) {
    final context =
        pathContext ??
        awikiPathContextFor(<String?>[appSupportRoot, cacheRoot, tempRoot]);
    return AwikiStorageScopeLayout._(
      supportRoot: context.normalize(context.absolute(appSupportRoot)),
      cacheRoot: context.normalize(context.absolute(cacheRoot)),
      tempRoot: context.normalize(context.absolute(tempRoot)),
      scopeId: scopeId,
      pathContext: context,
    );
  }

  AwikiStorageScopeLayout._({
    required this.supportRoot,
    required this.cacheRoot,
    required this.tempRoot,
    required this.scopeId,
    required p.Context pathContext,
  }) : _path = pathContext {
    _assertContained(supportRoot, scopeRoot);
    _assertContained(cacheRoot, cacheScopeRoot);
    _assertContained(tempRoot, tempScopeRoot);
  }

  final String supportRoot;
  final String cacheRoot;
  final String tempRoot;
  final StorageScopeId scopeId;
  final p.Context _path;

  p.Context get pathContext => _path;

  String get awikiRoot => _path.join(supportRoot, 'awiki-me');
  String get controlRoot => _path.join(awikiRoot, 'control');
  String get registryPath => _path.join(controlRoot, 'tenant-registry.json');
  String get scopesRoot => _path.join(awikiRoot, 'storage-scopes');
  String get scopeRoot => _path.join(scopesRoot, scopeId.value);
  String get manifestPath => _path.join(scopeRoot, 'scope-manifest.json');
  String get imCoreRoot => _path.join(scopeRoot, 'im-core');
  String get identitiesRoot => _path.join(imCoreRoot, 'identities');
  String get identityRegistryPath =>
      _path.join(identitiesRoot, 'registry.json');
  String get defaultIdentityPath => _path.join(identitiesRoot, 'default');
  String get identityVaultRoot => _path.join(imCoreRoot, 'identity-vault');
  String get vaultWorkspaceId => 'awiki-me.scope.v1.${scopeId.value}';
  String get vaultContextDeviceId =>
      'awiki-me.scope-device.v1.${scopeId.value}';
  String get imCoreStateRoot => _path.join(imCoreRoot, 'state');
  String get imCoreSqlitePath => _path.join(imCoreStateRoot, 'im_core.sqlite');
  String get productRoot => _path.join(scopeRoot, 'product');
  String get productDatabasePath =>
      _path.join(productRoot, 'awiki_me_product_store.db');
  String get attachmentsRoot => _path.join(scopeRoot, 'attachments');
  String get cacheScopeRoot =>
      _path.join(cacheRoot, 'awiki-me', 'storage-scopes', scopeId.value);
  String get cacheImCoreRoot => _path.join(cacheScopeRoot, 'im-core');
  String get tempScopeRoot =>
      _path.join(tempRoot, 'awiki-me', 'storage-scopes', scopeId.value);
  String get tempImCoreRoot => _path.join(tempScopeRoot, 'im-core');

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

  void _assertContained(String parent, String child) {
    if (!_path.isWithin(parent, child)) {
      throw const FormatException('storage_scope_path_escape');
    }
  }

  Future<void> _assertNoLinksBetween(String trustedRoot, String target) async {
    final normalizedRoot = _path.normalize(_path.absolute(trustedRoot));
    var current = _path.normalize(_path.absolute(target));
    if (!_path.equals(current, normalizedRoot) &&
        !_path.isWithin(normalizedRoot, current)) {
      throw const FormatException('storage_scope_path_escape');
    }
    while (!_path.equals(current, normalizedRoot)) {
      await _rejectSymlink(Directory(current));
      final parent = _path.dirname(current);
      if (_path.equals(parent, current)) {
        throw const FormatException('storage_scope_path_escape');
      }
      current = parent;
    }
  }
}

Future<void> _rejectSymlink(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw const FileSystemException('storage_scope_symlink_forbidden');
  }
}
