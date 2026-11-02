import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A build snapshot, never a second Git checkout. Ignored fixture/config files
/// are excluded by Git's own inventory and the developer source is read-only.
Future<Directory> prepareWindowsE2eWorkspace({
  required Directory projectRoot,
  required Directory destination,
  required String bundleId,
  required String name,
}) async {
  await resetWindowsE2eSnapshot(
    projectRoot: projectRoot,
    destination: destination,
  );
  final source = Directory(p.normalize(projectRoot.absolute.path));
  final output = Directory(p.normalize(destination.absolute.path));
  return _materializeWindowsE2eWorkspace(source, output, bundleId, name);
}

/// Refreshes generated source while retaining the native build cache for the
/// same role. Flutter still rebuilds and validates every new source fingerprint.
Future<void> resetWindowsE2eSnapshot({
  required Directory projectRoot,
  required Directory destination,
}) async {
  final source = Directory(p.normalize(projectRoot.absolute.path));
  final output = Directory(p.normalize(destination.absolute.path));
  final normalizedSource = source.path.replaceAll('\\', '/').toLowerCase();
  final normalizedOutput = output.path.replaceAll('\\', '/').toLowerCase();
  if (!normalizedOutput.startsWith('$normalizedSource/.e2e/')) {
    throw StateError('Windows E2E build snapshots must stay under .e2e/.');
  }
  final canonicalRoot = source
      .resolveSymbolicLinksSync()
      .replaceAll('\\', '/')
      .toLowerCase();
  var existingParent = output;
  while (!existingParent.existsSync()) {
    if (FileSystemEntity.typeSync(existingParent.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError(
        'Windows E2E build snapshots cannot traverse broken links.',
      );
    }
    existingParent = existingParent.parent;
  }
  final canonicalParent = existingParent
      .resolveSymbolicLinksSync()
      .replaceAll('\\', '/')
      .toLowerCase();
  if (canonicalParent != canonicalRoot &&
      canonicalParent != '$canonicalRoot/.e2e' &&
      !canonicalParent.startsWith('$canonicalRoot/.e2e/')) {
    throw StateError(
      'Windows E2E build snapshots cannot escape through links.',
    );
  }
  if (output.existsSync()) {
    // Only this deterministic, project-local generated snapshot is replaced.
    if (FileSystemEntity.typeSync(output.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Windows E2E build snapshot cannot be a symbolic link.');
    }
    final build = Directory(p.join(output.path, 'build'));
    final buildType = FileSystemEntity.typeSync(build.path, followLinks: false);
    if (buildType != FileSystemEntityType.notFound &&
        buildType != FileSystemEntityType.directory) {
      throw StateError(
        'Windows native build cache must be a regular directory.',
      );
    }
    for (final entry in output.listSync(followLinks: false)) {
      if (p.basename(entry.path) == 'build') continue;
      if (entry is Directory) {
        await entry.delete(recursive: true);
      } else {
        await entry.delete();
      }
    }
  }
  await output.create(recursive: true);
}

Future<Directory> _materializeWindowsE2eWorkspace(
  Directory source,
  Directory output,
  String bundleId,
  String name,
) async {
  final paths = await windowsE2eSourceInventory(source);
  for (final relative in paths) {
    if (relative.startsWith('/') || relative.split('/').contains('..')) {
      throw StateError('Windows source inventory contains an unsafe path.');
    }
    final path = '${source.path}/$relative';
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.file) {
      throw StateError('Windows source inventory must contain regular files.');
    }
    final target = File('${output.path}/$relative');
    await target.parent.create(recursive: true);
    await File(path).copy(target.path);
  }
  return _configureWindowsE2eWorkspace(source, output, bundleId, name);
}

Future<List<String>> windowsE2eSourceInventory(Directory source) async {
  final inventory = await Process.run('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
    '--',
    'lib',
    'assets',
    'windows',
    'integration_test',
    'tests/e2e',
    'tests/unit',
    'test_driver',
    'pubspec.yaml',
    'pubspec.lock',
    'l10n.yaml',
    'analysis_options.yaml',
  ], workingDirectory: source.path);
  if (inventory.exitCode != 0) {
    throw StateError('Windows source inventory failed.');
  }
  return inventory.stdout
      .toString()
      .split('\u0000')
      .where((path) => path.isNotEmpty)
      .toSet()
      .toList();
}

Future<Directory> _configureWindowsE2eWorkspace(
  Directory source,
  Directory output,
  String bundleId,
  String name,
) async {
  final pubspec =
      loadYaml(File('${source.path}/pubspec.yaml').readAsStringSync()) as Map;
  final overridesFile = File('${source.path}/pubspec_overrides.yaml');
  final overrides = overridesFile.existsSync()
      ? Map<String, dynamic>.from(
          loadYaml(overridesFile.readAsStringSync()) as Map,
        )
      : <String, dynamic>{};
  final dependencies = <String, dynamic>{
    ...?overrides['dependency_overrides'] as Map?,
  };
  for (final section in [
    'dependency_overrides',
    'dependencies',
    'dev_dependencies',
  ]) {
    final entries = pubspec[section];
    if (entries is! Map) continue;
    for (final entry in entries.entries) {
      final value = entry.value;
      if (!dependencies.containsKey(entry.key) &&
          value is Map &&
          value['path'] is String) {
        dependencies[entry.key.toString()] = {'path': value['path']};
      }
    }
  }
  for (final entry in dependencies.entries.toList()) {
    if (entry.value is! Map || entry.value['path'] is! String) continue;
    final path = entry.value['path'] as String;
    dependencies[entry.key] = {
      'path': p
          .normalize(p.isAbsolute(path) ? path : p.join(source.path, path))
          .replaceAll('\\', '/'),
    };
  }
  overrides['dependency_overrides'] = dependencies;
  await File(
    '${output.path}/pubspec_overrides.yaml',
  ).writeAsString('${jsonEncode(overrides)}\n');
  final lockFile = File('${output.path}/pubspec.lock');
  final lock =
      jsonDecode(jsonEncode(loadYaml(lockFile.readAsStringSync()))) as Map;
  final hosted =
      Platform.environment['PUB_HOSTED_URL'] ??
      'https://mirrors.tuna.tsinghua.edu.cn/dart-pub';
  final hostedUri = Uri.parse(hosted);
  if (hostedUri.scheme != 'https' || hostedUri.userInfo.isNotEmpty) {
    throw StateError(
      'Windows E2E hosted packages require a credential-free HTTPS origin.',
    );
  }
  final hostedUrl = hosted.endsWith('/') ? hosted : '$hosted/';
  for (final entry in (lock['packages'] as Map).entries) {
    final package = entry.value as Map;
    final description = package['description'];
    if (package['source'] == 'hosted' &&
        description is Map &&
        const [
          'https://pub.dev',
          'https://pub.dev/',
        ].contains(description['url'])) {
      description['url'] = hostedUrl;
    }
    if (package['source'] == 'path' &&
        dependencies[entry.key] is Map &&
        dependencies[entry.key]['path'] is String) {
      package['description'] = {
        'path': dependencies[entry.key]['path'],
        'relative': false,
      };
    }
  }
  await lockFile.writeAsString('${jsonEncode(lock)}\n');
  applyWindowsE2eIdentity(output, bundleId: bundleId, name: name);
  return output;
}

/// A relocated build may change path descriptions or use a hosted mirror. It
/// must retain every selected version and hosted archive checksum.
void verifyWindowsSnapshotDependencies(
  Directory projectRoot,
  Directory snapshot,
) {
  final original =
      loadYaml(File('${projectRoot.path}/pubspec.lock').readAsStringSync())
          as Map;
  final generated =
      loadYaml(File('${snapshot.path}/pubspec.lock').readAsStringSync()) as Map;
  final expected = original['packages'] as Map;
  final actual = generated['packages'] as Map;
  if (expected.length != actual.length) {
    throw StateError('Windows E2E dependency graph changed during relocation.');
  }
  for (final entry in expected.entries) {
    final before = entry.value as Map;
    final after = actual[entry.key];
    if (after is! Map ||
        after['version'] != before['version'] ||
        after['source'] != before['source']) {
      throw StateError(
        'Windows E2E dependency version/source changed: ${entry.key}.',
      );
    }
    if (before['source'] == 'hosted' &&
        after['description']['sha256'] != before['description']['sha256']) {
      throw StateError(
        'Windows E2E dependency checksum changed: ${entry.key}.',
      );
    }
  }
}

/// Windows identities are compile-time native constants. Override only the
/// generated build snapshot so parallel roles cannot activate the normal App,
/// share a mutex, read its path-provider roots, or use its dev secret namespace.
void applyWindowsE2eIdentity(
  Directory root, {
  required String bundleId,
  required String name,
}) {
  if (!RegExp(r'^[a-z][a-z0-9-]{0,31}$').hasMatch(name) ||
      !RegExp(
        r'^[a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+$',
      ).hasMatch(bundleId)) {
    throw ArgumentError('Invalid Windows E2E application identity.');
  }
  final hash = sha256.convert(utf8.encode(bundleId)).toString();
  final token = hash.substring(0, 16);
  final product = 'AWikiMeE2E$token';
  final appId = 'AWiki.AWikiMe.E2E.$token';
  final service = 'ai.awiki.awikime.dev.e2e.$token.scope-secrets';
  final guid =
      '${hash.substring(0, 8)}-${hash.substring(8, 12)}-'
      '${hash.substring(12, 16)}-${hash.substring(16, 20)}-${hash.substring(20, 32)}';
  void replace(String relative, String before, String after) {
    final file = File('${root.path}/$relative');
    final text = file.readAsStringSync();
    if (!text.contains(before)) {
      throw StateError('Windows E2E identity contract changed in $relative.');
    }
    file.writeAsStringSync(text.replaceAll(before, after));
  }

  const header = 'windows/runner/app_constants.h';
  replace(header, 'AI_AWIKI_AWIKIME_FLUTTER_WINDOW', 'AWIKI_E2E_$token');
  replace(
    header,
    'ai.awiki.awikime.single-instance',
    '$bundleId.single-instance',
  );
  replace(header, 'ai.awiki.awikime.activate.v1', '$bundleId.activate.v1');
  replace(
    header,
    'ai.awiki.awikime.shutdown-for-update.v1',
    '$bundleId.shutdown-for-update.v1',
  );
  replace(header, 'L"AWiki Me"', 'L"AWiki Me E2E $name"');
  replace(header, 'AWiki.AWikiMe', appId);
  replace(header, '42f66431-9bea-46c4-ac14-475b9044a2be', guid);
  replace('windows/runner/Runner.rc', '"AWiki Me"', '"$product"');
  replace('windows/runner/desktop_shell.cpp', 'L"AWikiMe"', 'L"$product"');
  replace(
    'windows/runner/desktop_shell.cpp',
    'L"AWiki Me"',
    'L"AWiki Me E2E $name"',
  );
  replace('windows/runner/window_placement.cpp', 'AWikiMeDevelopment', product);
  for (final path in [
    'windows/runner/scope_secret_store.cpp',
    'lib/src/data/storage/platform_scope_secret_repository.dart',
  ]) {
    replace(path, 'ai.awiki.awikime.dev.scope-secrets', service);
  }
  const notifications = 'lib/src/data/services/app_notification_facade.dart';
  replace(notifications, 'AWiki.AWikiMe', appId);
  replace(notifications, '42f66431-9bea-46c4-ac14-475b9044a2be', guid);
}
