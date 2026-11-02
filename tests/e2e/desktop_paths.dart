import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Windows SQLite backup names need room beyond the App's private state root.
/// Reports keep their descriptive suite/run paths independently of runtime data.
Directory desktopRuntimeStateRoot({
  required Directory projectRoot,
  required String suiteScope,
  required String runId,
  required String operatingSystem,
  Directory? systemTemporaryDirectory,
}) {
  if (operatingSystem != 'windows') {
    return Directory('${projectRoot.path}/.e2e/$suiteScope/$runId');
  }
  final digest = sha256
      .convert(utf8.encode('${projectRoot.absolute.path}\n$suiteScope\n$runId'))
      .toString()
      .substring(0, 16);
  final candidates = <Directory>[
    Directory(p.join(projectRoot.absolute.path, '.e2e', 'ws', digest)),
    Directory(
      p.join(
        (systemTemporaryDirectory ?? Directory.systemTemp).absolute.path,
        'aw-e2e-$digest',
      ),
    ),
  ];
  for (final candidate in candidates) {
    if (candidate.absolute.path.length <= 74) return candidate;
  }
  throw StateError(
    'Windows E2E requires a shorter workspace or private TEMP directory so '
    'SQLite backup paths stay below the Windows path limit.',
  );
}

String normalizeDesktopPath(String path) =>
    p.normalize(path).replaceAll('\\', '/');
bool desktopPathIsWithin(String parent, String child) {
  var root = normalizeDesktopPath(parent), target = normalizeDesktopPath(child);
  if (Platform.isWindows) {
    root = root.toLowerCase();
    target = target.toLowerCase();
  }
  return target.startsWith('$root/');
}

String resolveDesktopConfigPath(Directory root, String path) {
  final value = path.trim();
  if (value.isEmpty || value.startsWith('/') || p.windows.isAbsolute(value)) {
    return value;
  }
  return '${root.path}/$value';
}
