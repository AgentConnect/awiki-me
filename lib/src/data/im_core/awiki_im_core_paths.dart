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
    required this.identityRootDir,
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
  }) {
    final appSupportImCoreRoot = _joinAll(<String>[
      appSupportRoot,
      'awiki-me',
      'im-core',
    ]);
    final identityRoot = _joinAll(<String>[appSupportImCoreRoot, 'identities']);
    return AwikiImCorePathLayout(
      identityRootDir: identityRoot,
      registryPath: _joinAll(<String>[identityRoot, 'registry.json']),
      defaultIdentityPath: _joinAll(<String>[identityRoot, 'default']),
      sqlitePath: _joinAll(<String>[
        appSupportImCoreRoot,
        'state',
        'im_core.sqlite',
      ]),
      cacheDir: _joinAll(<String>[cacheRoot, 'awiki-me', 'im-core']),
      tempDir: _joinAll(<String>[tempRoot, 'awiki-me', 'im-core']),
    );
  }

  static Future<AwikiImCorePathLayout> fromPlatform() async {
    final e2eRoot = _e2eAppStateRoot();
    if (e2eRoot != null) {
      return AwikiImCorePathLayout.fromRoots(
        appSupportRoot: _joinAll(<String>[e2eRoot, 'support']),
        cacheRoot: _joinAll(<String>[e2eRoot, 'cache']),
        tempRoot: _joinAll(<String>[e2eRoot, 'tmp']),
      );
    }
    final appSupport = await getApplicationSupportDirectory();
    final cache = await getApplicationCacheDirectory();
    final temp = await getTemporaryDirectory();
    return AwikiImCorePathLayout.fromRoots(
      appSupportRoot: appSupport.path,
      cacheRoot: cache.path,
      tempRoot: temp.path,
    );
  }

  final String identityRootDir;
  final String registryPath;
  final String defaultIdentityPath;
  final String sqlitePath;
  final String cacheDir;
  final String tempDir;

  Future<void> ensureDirectories() async {
    await Future.wait(<Future<Directory>>[
      Directory(identityRootDir).create(recursive: true),
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
  return root.isEmpty ? null : root;
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
