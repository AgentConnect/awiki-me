import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:path_provider/path_provider.dart';

import '../../application/tenant/app_tenant.dart';
import '../storage/awiki_storage_roots.dart';
import '../storage/awiki_storage_scope_layout.dart';

export '../storage/awiki_storage_roots.dart'
    show awikiE2eAppStateRoot, normalizeAwikiE2eAppStateRootForLaunch;

const int identityOwnedLocalStateSchemaVersion = 17;
const String _sqliteHeader = 'SQLite format 3\u0000';
const List<String> _sqliteSidecarSuffixes = <String>[
  '-wal',
  '-shm',
  '-journal',
];

/// im-core view over the single authoritative Storage Scope layout.
class AwikiImCorePathLayout {
  const AwikiImCorePathLayout._(this.scopeLayout);

  factory AwikiImCorePathLayout.fromStorageScope(
    AwikiStorageScopeLayout scopeLayout,
  ) => AwikiImCorePathLayout._(scopeLayout);

  factory AwikiImCorePathLayout.fromRoots({
    required String appSupportRoot,
    required String cacheRoot,
    required String tempRoot,
    required StorageScopeId scopeId,
  }) => AwikiImCorePathLayout.fromStorageScope(
    AwikiStorageScopeLayout.fromRoots(
      appSupportRoot: appSupportRoot,
      cacheRoot: cacheRoot,
      tempRoot: tempRoot,
      scopeId: scopeId,
    ),
  );

  static Future<AwikiImCorePathLayout> fromPlatform({
    required StorageScopeId scopeId,
    String? appStateRoot,
  }) async {
    final stateRoot = explicitAwikiAppStateRoot(appStateRoot);
    if (stateRoot != null) {
      return AwikiImCorePathLayout.fromRoots(
        appSupportRoot: _joinAll(<String>[stateRoot, 'support']),
        cacheRoot: _joinAll(<String>[stateRoot, 'cache']),
        tempRoot: _joinAll(<String>[stateRoot, 'tmp']),
        scopeId: scopeId,
      );
    }
    final appSupport = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final temp = await getTemporaryDirectory();
    return AwikiImCorePathLayout.fromRoots(
      appSupportRoot: appSupport.path,
      cacheRoot: cache.path,
      tempRoot: temp.path,
      scopeId: scopeId,
    );
  }

  final AwikiStorageScopeLayout scopeLayout;

  StorageScopeId get scopeId => scopeLayout.scopeId;
  String get identityRootDir => scopeLayout.identitiesRoot;
  String get vaultDir => scopeLayout.identityVaultRoot;
  String get vaultWorkspaceId => scopeLayout.vaultWorkspaceId;
  String get vaultContextDeviceId => scopeLayout.vaultContextDeviceId;
  String get registryPath => scopeLayout.identityRegistryPath;
  String get defaultIdentityPath => scopeLayout.defaultIdentityPath;
  String get sqlitePath => scopeLayout.imCoreSqlitePath;
  String get cacheDir => scopeLayout.cacheImCoreRoot;
  String get tempDir => scopeLayout.tempImCoreRoot;

  Future<void> ensureDirectories() => scopeLayout.ensureDataDirectories();

  Future<ArchivedLocalState?> archiveIncompatibleLocalStateIfNeeded({
    int minimumSchemaVersion = identityOwnedLocalStateSchemaVersion,
    DateTime Function()? clock,
  }) async {
    final sqliteFile = File(sqlitePath);
    if (!await sqliteFile.exists()) return null;
    final schemaVersion = await _readSqliteUserVersion(sqliteFile);
    if (schemaVersion == null ||
        schemaVersion == 0 ||
        schemaVersion >= minimumSchemaVersion) {
      return null;
    }
    final archiveDir = Directory(
      _joinAll(<String>[_dirname(sqlitePath), 'legacy-state']),
    );
    await archiveDir.create(recursive: true);
    final timestamp = _archiveTimestamp((clock ?? DateTime.now).call());
    final baseName = _basename(sqlitePath);
    final archivedPaths = <String>[
      await _archiveFile(
        sqliteFile,
        _joinAll(<String>[
          archiveDir.path,
          '$baseName.schema$schemaVersion.$timestamp',
        ]),
      ),
    ];
    for (final suffix in _sqliteSidecarSuffixes) {
      final sidecar = File('$sqlitePath$suffix');
      if (!await sidecar.exists()) continue;
      archivedPaths.add(
        await _archiveFile(
          sidecar,
          _joinAll(<String>[
            archiveDir.path,
            '$baseName$suffix.schema$schemaVersion.$timestamp',
          ]),
        ),
      );
    }
    return ArchivedLocalState(
      schemaVersion: schemaVersion,
      minimumSchemaVersion: minimumSchemaVersion,
      archivedPaths: archivedPaths,
    );
  }

  core.AwikiImCorePaths toCorePaths() => core.AwikiImCorePaths(
    identityRootDir: identityRootDir,
    registryPath: registryPath,
    defaultIdentityPath: defaultIdentityPath,
    sqlitePath: sqlitePath,
    cacheDir: cacheDir,
    tempDir: tempDir,
  );
}

class ArchivedLocalState {
  const ArchivedLocalState({
    required this.schemaVersion,
    required this.minimumSchemaVersion,
    required this.archivedPaths,
  });

  final int schemaVersion;
  final int minimumSchemaVersion;
  final List<String> archivedPaths;
}

String _joinAll(List<String> parts) {
  final normalized = parts
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .map((part) => part.replaceAll(RegExp(r'/+$'), ''))
      .toList();
  if (normalized.isEmpty) {
    return '';
  }
  final first = normalized.first;
  final rest = normalized
      .skip(1)
      .map((part) => part.replaceAll(RegExp(r'^/+'), ''));
  return <String>[first, ...rest].join('/');
}

String _dirname(String path) {
  final index = path.lastIndexOf('/');
  if (index <= 0) {
    return '.';
  }
  return path.substring(0, index);
}

String _basename(String path) {
  final index = path.lastIndexOf('/');
  if (index < 0) {
    return path;
  }
  return path.substring(index + 1);
}

Future<int?> _readSqliteUserVersion(File file) async {
  final length = await file.length();
  if (length < 64) {
    return null;
  }

  final handle = await file.open();
  try {
    final header = await handle.read(64);
    if (header.length < 64) {
      return null;
    }
    final marker = String.fromCharCodes(header.sublist(0, 16));
    if (marker != _sqliteHeader) {
      return null;
    }
    return ByteData.sublistView(Uint8List.fromList(header), 60, 64).getInt32(0);
  } finally {
    await handle.close();
  }
}

Future<String> _archiveFile(File source, String desiredPath) async {
  final target = await _availableArchivePath(desiredPath);
  final archived = await source.rename(target);
  return archived.path;
}

Future<String> _availableArchivePath(String desiredPath) async {
  if (!await File(desiredPath).exists()) {
    return desiredPath;
  }
  for (var index = 1; index < 1000; index++) {
    final candidate = '$desiredPath.$index';
    if (!await File(candidate).exists()) {
      return candidate;
    }
  }
  throw FileSystemException('No available archive path', desiredPath);
}

String _archiveTimestamp(DateTime value) {
  final utc = value.toUtc();
  String two(int input) => input.toString().padLeft(2, '0');
  return '${utc.year}${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
}
