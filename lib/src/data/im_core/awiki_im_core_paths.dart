import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:path_provider/path_provider.dart';

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
