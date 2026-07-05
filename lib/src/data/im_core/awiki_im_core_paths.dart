import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:path_provider/path_provider.dart';

const int identityOwnedLocalStateSchemaVersion = 17;
const bool _awikiE2eEnabled = bool.fromEnvironment('AWIKI_E2E');
const String _awikiE2eAppStateRoot = String.fromEnvironment(
  'AWIKI_E2E_APP_STATE_ROOT',
);
const String _sqliteHeader = 'SQLite format 3\u0000';
const List<String> _sqliteSidecarSuffixes = <String>[
  '-wal',
  '-shm',
  '-journal',
];

class AwikiImCorePathLayout {
  const AwikiImCorePathLayout({
    required this.stateNamespace,
    required this.identityRootDir,
    required this.vaultDir,
    required this.vaultWorkspaceId,
    required this.registryPath,
    required this.defaultIdentityPath,
    required this.sqlitePath,
    required this.cacheDir,
    required this.tempDir,
  });

  factory AwikiImCorePathLayout.fromRoots({
    required String appSupportRoot,
    required String cacheRoot,
    required String tempRoot,
    String? stateNamespace,
  }) {
    final namespace = normalizeAwikiStateNamespace(stateNamespace);
    final appSupportImCoreRoot = _joinAll(<String>[
      appSupportRoot,
      'awiki-me',
      'environments',
      namespace,
      'im-core',
    ]);
    final identityRoot = _joinAll(<String>[appSupportImCoreRoot, 'identities']);
    return AwikiImCorePathLayout(
      stateNamespace: namespace,
      identityRootDir: identityRoot,
      vaultDir: _joinAll(<String>[appSupportImCoreRoot, 'identity-vault']),
      vaultWorkspaceId: 'awiki-me-$namespace',
      registryPath: _joinAll(<String>[identityRoot, 'registry.json']),
      defaultIdentityPath: _joinAll(<String>[identityRoot, 'default']),
      sqlitePath: _joinAll(<String>[
        appSupportImCoreRoot,
        'state',
        'im_core.sqlite',
      ]),
      cacheDir: _joinAll(<String>[
        cacheRoot,
        'awiki-me',
        'environments',
        namespace,
        'im-core',
      ]),
      tempDir: _joinAll(<String>[
        tempRoot,
        'awiki-me',
        'environments',
        namespace,
        'im-core',
      ]),
    );
  }

  static Future<AwikiImCorePathLayout> fromPlatform({
    String? appStateRoot,
    String? stateNamespace,
  }) async {
    final stateRoot = _firstNonEmpty(appStateRoot, _e2eAppStateRoot());
    if (stateRoot != null) {
      return AwikiImCorePathLayout.fromRoots(
        appSupportRoot: _joinAll(<String>[stateRoot, 'support']),
        cacheRoot: _joinAll(<String>[stateRoot, 'cache']),
        tempRoot: _joinAll(<String>[stateRoot, 'tmp']),
        stateNamespace: stateNamespace,
      );
    }
    final appSupport = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final temp = await getTemporaryDirectory();
    return AwikiImCorePathLayout.fromRoots(
      appSupportRoot: appSupport.path,
      cacheRoot: cache.path,
      tempRoot: temp.path,
      stateNamespace: stateNamespace,
    );
  }

  final String stateNamespace;
  final String identityRootDir;
  final String vaultDir;
  final String vaultWorkspaceId;
  final String registryPath;
  final String defaultIdentityPath;
  final String sqlitePath;
  final String cacheDir;
  final String tempDir;

  Future<void> ensureDirectories() async {
    await Future.wait(<Future<Directory>>[
      Directory(identityRootDir).create(recursive: true),
      Directory(vaultDir).create(recursive: true),
      Directory(_dirname(sqlitePath)).create(recursive: true),
      Directory(cacheDir).create(recursive: true),
      Directory(tempDir).create(recursive: true),
    ]);
  }

  Future<ArchivedLocalState?> archiveIncompatibleLocalStateIfNeeded({
    int minimumSchemaVersion = identityOwnedLocalStateSchemaVersion,
    DateTime Function()? clock,
  }) async {
    final sqliteFile = File(sqlitePath);
    if (!await sqliteFile.exists()) {
      return null;
    }

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
    final archivedPaths = <String>[];

    archivedPaths.add(
      await _archiveFile(
        sqliteFile,
        _joinAll(<String>[
          archiveDir.path,
          '$baseName.schema$schemaVersion.$timestamp',
        ]),
      ),
    );

    for (final suffix in _sqliteSidecarSuffixes) {
      final sidecar = File('$sqlitePath$suffix');
      if (!await sidecar.exists()) {
        continue;
      }
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

  core.AwikiImCorePaths toCorePaths() {
    return core.AwikiImCorePaths(
      identityRootDir: identityRootDir,
      registryPath: registryPath,
      defaultIdentityPath: defaultIdentityPath,
      sqlitePath: sqlitePath,
      cacheDir: cacheDir,
      tempDir: tempDir,
    );
  }
}

String? awikiE2eAppStateRoot() => _e2eAppStateRoot();

String? _e2eAppStateRoot() {
  if (!_awikiE2eEnabled) {
    return null;
  }
  final root = _awikiE2eAppStateRoot.trim();
  return root.isEmpty ? null : normalizeAwikiE2eAppStateRootForLaunch(root);
}

String? _firstNonEmpty(String? first, String? second) {
  final firstTrimmed = first?.trim();
  if (firstTrimmed != null && firstTrimmed.isNotEmpty) {
    return firstTrimmed;
  }
  final secondTrimmed = second?.trim();
  if (secondTrimmed != null && secondTrimmed.isNotEmpty) {
    return secondTrimmed;
  }
  return null;
}

String normalizeAwikiStateNamespace(String? value) {
  final raw = value?.trim().toLowerCase();
  if (raw == null || raw.isEmpty) {
    return 'default';
  }
  final safe = raw
      .replaceAll(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'[/\\:*?"<>|#?&=%]+'), '-')
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return safe.isEmpty ? 'default' : safe;
}

String normalizeAwikiE2eAppStateRootForLaunch(
  String root, {
  String? currentDirectory,
  String? homeDirectory,
  bool? isMacOS,
  String? temporaryDirectory,
}) {
  final trimmed = root.trim();
  if (trimmed.isEmpty || _isAbsolutePath(trimmed)) {
    return trimmed;
  }

  final expandedHome = _expandHomeRelativePath(trimmed, homeDirectory);
  if (expandedHome != null) {
    return expandedHome;
  }

  final cwd = (currentDirectory ?? Directory.current.path).trim();
  if (_canAnchorRelativeE2eRootToCurrentDirectory(cwd)) {
    return _joinAll(<String>[cwd, trimmed]);
  }

  final appSupportFallback = _appSupportFallbackRoot(
    homeDirectory ?? Platform.environment['HOME'],
    isMacOS: isMacOS ?? Platform.isMacOS,
  );
  if (appSupportFallback != null) {
    return _joinAll(<String>[appSupportFallback, trimmed]);
  }

  final temp = (temporaryDirectory ?? Directory.systemTemp.path).trim();
  return _joinAll(<String>[temp, 'ai.awiki.awikiMe', trimmed]);
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

bool _isAbsolutePath(String path) {
  return path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String? _expandHomeRelativePath(String path, String? homeDirectory) {
  if (path != '~' && !path.startsWith('~/')) {
    return null;
  }
  final home = homeDirectory?.trim() ?? Platform.environment['HOME']?.trim();
  if (home == null || home.isEmpty) {
    return null;
  }
  if (path == '~') {
    return home;
  }
  return _joinAll(<String>[home, path.substring(2)]);
}

bool _canAnchorRelativeE2eRootToCurrentDirectory(String currentDirectory) {
  if (currentDirectory.isEmpty ||
      currentDirectory == '/' ||
      currentDirectory == r'\') {
    return false;
  }
  final lower = currentDirectory.toLowerCase();
  return !lower.contains('.app/contents');
}

String? _appSupportFallbackRoot(
  String? homeDirectory, {
  required bool isMacOS,
}) {
  final home = homeDirectory?.trim();
  if (home == null || home.isEmpty) {
    return null;
  }
  if (isMacOS) {
    return _joinAll(<String>[
      home,
      'Library',
      'Application Support',
      'ai.awiki.awikiMe',
    ]);
  }
  return _joinAll(<String>[home, '.awiki-me']);
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
