// [INPUT]: One E2E target, isolated runtime/artifact roots, a reusable role build root, bundle identity, and stable Dart defines.
// [OUTPUT]: An isolated Debug macOS or Linux App bundle plus a machine-readable artifact manifest.
// [POS]: Reusable incremental build boundary for E2E modes that need concurrently runnable App processes.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../tests/e2e/host_platform.dart';
import 'ensure_linux_im_core.dart';

enum IsolatedE2eAppPlatform {
  macos,
  linux;

  static IsolatedE2eAppPlatform parse(String value) => switch (value) {
    'macos' => IsolatedE2eAppPlatform.macos,
    'linux' => IsolatedE2eAppPlatform.linux,
    _ => throw const IsolatedE2eAppBuildException(
      'The isolated App platform must be macos or linux.',
    ),
  };

  static IsolatedE2eAppPlatform fromHost() {
    if (Platform.isMacOS) return IsolatedE2eAppPlatform.macos;
    if (Platform.isLinux) return IsolatedE2eAppPlatform.linux;
    throw const IsolatedE2eAppBuildException(
      'Isolated E2E App builds require macOS or Linux.',
    );
  }
}

Future<void> main(List<String> args) async {
  try {
    final request = IsolatedE2eAppBuildRequest.parse(
      args,
      projectRoot: Directory.current,
    );
    final artifact = await IsolatedE2eAppBuilder().build(request);
    stdout.writeln(jsonEncode(artifact.toJson()));
  } on IsolatedE2eAppBuildException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}

class IsolatedE2eAppBuildRequest {
  const IsolatedE2eAppBuildRequest({
    required this.projectRoot,
    required this.name,
    required this.target,
    required this.stateRoot,
    required this.workRoot,
    required this.artifactRoot,
    required this.bundleId,
    required this.platform,
    required this.flutterBin,
    required this.dartDefines,
    required this.dryRun,
  });

  final Directory projectRoot;
  final String name;
  final String target;
  final Directory stateRoot;
  final Directory workRoot;
  final Directory artifactRoot;
  final String bundleId;
  final IsolatedE2eAppPlatform platform;
  final String flutterBin;
  final List<String> dartDefines;
  final bool dryRun;

  factory IsolatedE2eAppBuildRequest.parse(
    List<String> args, {
    required Directory projectRoot,
  }) {
    final values = <String, List<String>>{};
    var dryRun = false;
    for (final argument in args) {
      if (argument == '--dry-run') {
        dryRun = true;
        continue;
      }
      final separator = argument.indexOf('=');
      if (!argument.startsWith('--') || separator <= 2) {
        throw const IsolatedE2eAppBuildException(
          'Arguments must use --name=value form.',
        );
      }
      final key = argument.substring(2, separator);
      final value = argument.substring(separator + 1).trim();
      if (!const <String>{
        'name',
        'target',
        'state-root',
        'work-root',
        'artifact-root',
        'bundle-id',
        'platform',
        'flutter-bin',
        'dart-define',
      }.contains(key)) {
        throw IsolatedE2eAppBuildException('Unknown argument: --$key');
      }
      values.putIfAbsent(key, () => <String>[]).add(value);
    }

    String requiredValue(String key) {
      final matches = values[key] ?? const <String>[];
      if (matches.length != 1 || matches.single.isEmpty) {
        throw IsolatedE2eAppBuildException(
          'Exactly one non-empty --$key value is required.',
        );
      }
      return matches.single;
    }

    final name = requiredValue('name').toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9-]{0,31}$').hasMatch(name)) {
      throw const IsolatedE2eAppBuildException(
        'The isolated App name is invalid.',
      );
    }
    final target = requiredValue('target');
    if (!target.startsWith('integration_test/') ||
        !target.endsWith('_test.dart') ||
        target.contains('..')) {
      throw const IsolatedE2eAppBuildException(
        'The target must be an integration_test/*_test.dart entrypoint.',
      );
    }
    final bundleId = requiredValue('bundle-id').toLowerCase();
    if (!RegExp(
      r'^[a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+$',
    ).hasMatch(bundleId)) {
      throw const IsolatedE2eAppBuildException(
        'The bundle identifier is invalid.',
      );
    }
    final platformValues = values['platform'] ?? const <String>[];
    if (platformValues.length > 1) {
      throw const IsolatedE2eAppBuildException(
        'At most one --platform value is allowed.',
      );
    }
    final platform = platformValues.isEmpty
        ? IsolatedE2eAppPlatform.fromHost()
        : IsolatedE2eAppPlatform.parse(platformValues.single);
    final flutterValues = values['flutter-bin'] ?? const <String>[];
    if (flutterValues.length > 1) {
      throw const IsolatedE2eAppBuildException(
        'At most one --flutter-bin value is allowed.',
      );
    }
    final flutterBin =
        flutterValues.singleOrNull ??
        Platform.environment['AWIKI_E2E_FLUTTER_BIN']?.trim() ??
        'flutter';
    if (flutterBin.trim().isEmpty) {
      throw const IsolatedE2eAppBuildException(
        'The Flutter executable is empty.',
      );
    }
    final dartDefines = List<String>.unmodifiable(
      values['dart-define'] ?? const <String>[],
    );
    for (final define in dartDefines) {
      final separator = define.indexOf('=');
      if (separator <= 0 || separator == define.length - 1) {
        throw const IsolatedE2eAppBuildException(
          'Each --dart-define must contain KEY=VALUE.',
        );
      }
    }
    final stateRoot = _validatedRoot(
      requiredValue('state-root'),
      projectRoot: projectRoot,
      label: 'state-root',
    );
    final workRoot = _validatedRoot(
      requiredValue('work-root'),
      projectRoot: projectRoot,
      label: 'work-root',
    );
    final artifactRoot = _validatedRoot(
      requiredValue('artifact-root'),
      projectRoot: projectRoot,
      label: 'artifact-root',
    );
    if (_pathsOverlap(stateRoot.path, workRoot.path) ||
        _pathsOverlap(stateRoot.path, artifactRoot.path) ||
        _pathsOverlap(workRoot.path, artifactRoot.path)) {
      throw const IsolatedE2eAppBuildException(
        'State, work, and artifact roots must not overlap.',
      );
    }
    return IsolatedE2eAppBuildRequest(
      projectRoot: projectRoot.absolute,
      name: name,
      target: target,
      stateRoot: stateRoot,
      workRoot: workRoot,
      artifactRoot: artifactRoot,
      bundleId: bundleId,
      platform: platform,
      flutterBin: flutterBin,
      dartDefines: dartDefines,
      dryRun: dryRun,
    );
  }

  IsolatedE2eAppBuildPlan toPlan() {
    final buildDirectory = platform == IsolatedE2eAppPlatform.linux
        ? Directory('${projectRoot.path}/build')
        : Directory('${workRoot.path}/flutter-build');
    final flutterConfigDirectory = Directory('${workRoot.path}/flutter-config');
    final overrideConfig = File('${workRoot.path}/AppPair.xcconfig');
    final sourceApp = switch (platform) {
      IsolatedE2eAppPlatform.macos => Directory(
        '${buildDirectory.path}/macos/Build/Products/Debug/AWikiMe.app',
      ),
      IsolatedE2eAppPlatform.linux => Directory(
        '${buildDirectory.path}/linux/x64/debug/bundle',
      ),
    };
    final artifactApp = switch (platform) {
      IsolatedE2eAppPlatform.macos => Directory(
        '${artifactRoot.path}/AWikiMe-$name.app',
      ),
      IsolatedE2eAppPlatform.linux => Directory(
        '${artifactRoot.path}/AWikiMe-$name-linux',
      ),
    };
    return IsolatedE2eAppBuildPlan(
      buildDirectory: buildDirectory,
      flutterBuildDirectorySetting: buildDirectory.path.substring(
        projectRoot.path.length + 1,
      ),
      flutterConfigDirectory: flutterConfigDirectory,
      flutterSettingsFile: File('${flutterConfigDirectory.path}/settings'),
      overrideConfig: overrideConfig,
      sourceApp: sourceApp,
      artifactApp: artifactApp,
      executable: File(
        platform == IsolatedE2eAppPlatform.macos
            ? '${artifactApp.path}/Contents/MacOS/AWikiMe'
            : '${artifactApp.path}/awiki_me',
      ),
      manifest: File('${artifactRoot.path}/$name.json'),
      flutterArguments: <String>[
        'build',
        platform.name,
        '--debug',
        '--no-pub',
        '--target=$target',
        '--dart-define=AWIKI_E2E=true',
        for (final define in dartDefines) '--dart-define=$define',
      ],
    );
  }
}

class IsolatedE2eAppBuildPlan {
  const IsolatedE2eAppBuildPlan({
    required this.buildDirectory,
    required this.flutterBuildDirectorySetting,
    required this.flutterConfigDirectory,
    required this.flutterSettingsFile,
    required this.overrideConfig,
    required this.sourceApp,
    required this.artifactApp,
    required this.executable,
    required this.manifest,
    required this.flutterArguments,
  });

  final Directory buildDirectory;
  final String flutterBuildDirectorySetting;
  final Directory flutterConfigDirectory;
  final File flutterSettingsFile;
  final File overrideConfig;
  final Directory sourceApp;
  final Directory artifactApp;
  final File executable;
  final File manifest;
  final List<String> flutterArguments;
}

class IsolatedE2eAppArtifact {
  const IsolatedE2eAppArtifact({
    required this.name,
    required this.target,
    required this.bundleId,
    required this.appPath,
    required this.executablePath,
    required this.stateRoot,
    required this.buildDirectory,
    required this.dryRun,
    required this.hostPlatform,
    required this.fingerprint,
    required this.cacheHit,
    required this.artifactSha256,
  });

  final String name;
  final String target;
  final String bundleId;
  final String appPath;
  final String executablePath;
  final String stateRoot;
  final String buildDirectory;
  final bool dryRun;
  final E2eHostPlatform hostPlatform;
  final String fingerprint;
  final bool cacheHit;
  final String artifactSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'name': name,
    'target': target,
    'bundleId': bundleId,
    'appPath': appPath,
    'executablePath': executablePath,
    'stateRoot': stateRoot,
    'buildDirectory': buildDirectory,
    'dryRun': dryRun,
    'hostPlatform': hostPlatform.toJson(),
    'fingerprint': fingerprint,
    'cacheHit': cacheHit,
    'artifactSha256': artifactSha256,
  };
}

class IsolatedE2eAppBuilder {
  Future<IsolatedE2eAppArtifact> build(
    IsolatedE2eAppBuildRequest request,
  ) async {
    final hostPlatform = await E2eHostPlatform.detect();
    if (!request.dryRun) {
      try {
        hostPlatform.requireOperatingSystem(request.platform.name);
        if (request.platform == IsolatedE2eAppPlatform.macos) {
          hostPlatform.requireNativeMacToolchain();
        }
      } on StateError catch (error) {
        throw IsolatedE2eAppBuildException(error.message);
      }
    }
    final plan = request.toPlan();
    if (request.dryRun) {
      return _isolatedArtifact(
        request: request,
        plan: plan,
        hostPlatform: hostPlatform,
        fingerprint: 'dry-run',
        cacheHit: false,
        artifactSha256: '',
      );
    }

    final fingerprint = await _isolatedBuildFingerprint(
      request: request,
      hostPlatform: hostPlatform,
    );
    final cachedDigest = await _restoreIsolatedArtifactCache(
      request: request,
      plan: plan,
      fingerprint: fingerprint,
    );
    if (cachedDigest != null) {
      final artifact = _isolatedArtifact(
        request: request,
        plan: plan,
        hostPlatform: hostPlatform,
        fingerprint: fingerprint,
        cacheHit: true,
        artifactSha256: cachedDigest,
      );
      plan.manifest.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(artifact.toJson()),
        flush: true,
      );
      return artifact;
    }

    request.stateRoot.createSync(recursive: true);
    request.workRoot.createSync(recursive: true);
    request.artifactRoot.createSync(recursive: true);
    plan.flutterConfigDirectory.createSync(recursive: true);
    plan.flutterSettingsFile.writeAsStringSync(
      jsonEncode(<String, Object?>{
        'build-dir': plan.flutterBuildDirectorySetting,
        if (request.platform == IsolatedE2eAppPlatform.macos)
          'enable-macos-desktop': true,
        if (request.platform == IsolatedE2eAppPlatform.linux)
          'enable-linux-desktop': true,
      }),
      flush: true,
    );
    if (request.platform == IsolatedE2eAppPlatform.macos) {
      plan.overrideConfig.writeAsStringSync(
        'AWIKI_MACOS_DEV_BUNDLE_ID = ${request.bundleId}\n'
        'AWIKI_APP_DISPLAY_NAME = AWikiMe E2E ${request.name}\n',
        flush: true,
      );
    }

    final build = await Process.run(
      request.flutterBin,
      plan.flutterArguments,
      workingDirectory: request.projectRoot.path,
      environment: <String, String>{
        ...Platform.environment,
        'LANG': request.platform == IsolatedE2eAppPlatform.macos
            ? 'en_US.UTF-8'
            : 'C.UTF-8',
        'LC_ALL': request.platform == IsolatedE2eAppPlatform.macos
            ? 'en_US.UTF-8'
            : 'C.UTF-8',
        'XDG_CONFIG_HOME': plan.flutterConfigDirectory.path,
        if (request.platform == IsolatedE2eAppPlatform.macos)
          'XCODE_XCCONFIG_FILE': plan.overrideConfig.path,
      },
      runInShell: false,
    );
    if (build.exitCode != 0 || !plan.sourceApp.existsSync()) {
      throw IsolatedE2eAppBuildException(
        'The isolated Debug App build failed for ${request.name}.'
        '${_commandFailureTail(build)}',
      );
    }
    if (plan.artifactApp.existsSync()) {
      plan.artifactApp.deleteSync(recursive: true);
    }
    final copy = request.platform == IsolatedE2eAppPlatform.macos
        ? await Process.run('/usr/bin/ditto', <String>[
            plan.sourceApp.path,
            plan.artifactApp.path,
          ])
        : await Process.run('/bin/cp', <String>[
            '-a',
            plan.sourceApp.path,
            plan.artifactApp.path,
          ]);
    if (copy.exitCode != 0 || !plan.executable.existsSync()) {
      throw IsolatedE2eAppBuildException(
        'The isolated App artifact copy failed for ${request.name}.',
      );
    }
    if (request.platform == IsolatedE2eAppPlatform.linux) {
      final layout = await LinuxImCoreLayout.resolve(request.projectRoot);
      final bundledCore = File(
        '${plan.artifactApp.path}/lib/libawiki_im_core.so',
      );
      if (!bundledCore.existsSync() ||
          await fileSha256(bundledCore) != await fileSha256(layout.artifact)) {
        throw const IsolatedE2eAppBuildException(
          'The isolated Linux App contains a stale IM Core shared library.',
        );
      }
    }
    if (request.platform == IsolatedE2eAppPlatform.macos) {
      final bundle = await Process.run('/usr/libexec/PlistBuddy', <String>[
        '-c',
        'Print :CFBundleIdentifier',
        '${plan.artifactApp.path}/Contents/Info.plist',
      ]);
      if (bundle.exitCode != 0 ||
          bundle.stdout.toString().trim() != request.bundleId) {
        throw const IsolatedE2eAppBuildException(
          'The isolated App bundle identifier did not match the request.',
        );
      }
      final signature = await Process.run('/usr/bin/codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        plan.artifactApp.path,
      ]);
      if (signature.exitCode != 0) {
        throw const IsolatedE2eAppBuildException(
          'The isolated App signature verification failed.',
        );
      }
      final architectures = await Process.run('/usr/bin/lipo', <String>[
        '-archs',
        plan.executable.path,
      ]);
      if (architectures.exitCode != 0 ||
          !architectures.stdout
              .toString()
              .trim()
              .split(RegExp(r'\s+'))
              .contains(hostPlatform.hardwareArchitecture)) {
        throw IsolatedE2eAppBuildException(
          'The isolated Debug App does not contain the detected host '
          'architecture ${hostPlatform.hardwareArchitecture}.',
        );
      }
    }
    final artifactSha256 = await directorySha256(plan.artifactApp);
    await _storeIsolatedArtifactCache(
      request: request,
      plan: plan,
      fingerprint: fingerprint,
      artifactSha256: artifactSha256,
    );
    final artifact = _isolatedArtifact(
      request: request,
      plan: plan,
      hostPlatform: hostPlatform,
      fingerprint: fingerprint,
      cacheHit: false,
      artifactSha256: artifactSha256,
    );
    plan.manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(artifact.toJson()),
      flush: true,
    );
    return artifact;
  }
}

IsolatedE2eAppArtifact _isolatedArtifact({
  required IsolatedE2eAppBuildRequest request,
  required IsolatedE2eAppBuildPlan plan,
  required E2eHostPlatform hostPlatform,
  required String fingerprint,
  required bool cacheHit,
  required String artifactSha256,
}) => IsolatedE2eAppArtifact(
  name: request.name,
  target: request.target,
  bundleId: request.bundleId,
  appPath: plan.artifactApp.path,
  executablePath: plan.executable.path,
  stateRoot: request.stateRoot.path,
  buildDirectory: plan.buildDirectory.path,
  dryRun: request.dryRun,
  hostPlatform: hostPlatform,
  fingerprint: fingerprint,
  cacheHit: cacheHit,
  artifactSha256: artifactSha256,
);

Future<String> _isolatedBuildFingerprint({
  required IsolatedE2eAppBuildRequest request,
  required E2eHostPlatform hostPlatform,
}) async {
  final flutter = await Process.run(request.flutterBin, const <String>[
    '--version',
    '--machine',
  ], workingDirectory: request.projectRoot.path);
  if (flutter.exitCode != 0) {
    throw const IsolatedE2eAppBuildException(
      'Flutter toolchain identity is unavailable.',
    );
  }
  final flutterJson = jsonDecode(flutter.stdout.toString());
  if (flutterJson is! Map) {
    throw const IsolatedE2eAppBuildException(
      'Flutter toolchain identity is invalid.',
    );
  }
  final sourceDigest = await trackedBuildInputsSha256(
    request.projectRoot,
    platform: request.platform,
  );
  String nativeCoreSha256 = '';
  String nativeCoreProvenanceSha256 = '';
  if (request.platform == IsolatedE2eAppPlatform.linux) {
    final layout = await LinuxImCoreLayout.resolve(request.projectRoot);
    nativeCoreSha256 = await fileSha256(layout.artifact);
    nativeCoreProvenanceSha256 = await fileSha256(layout.manifest);
  }
  final flutterIdentity = <String, String>{
    for (final key in const <String>[
      'frameworkVersion',
      'frameworkRevision',
      'engineRevision',
      'dartSdkVersion',
    ])
      key: flutterJson[key]?.toString() ?? '',
  };
  if (flutterIdentity.values.any((value) => value.isEmpty)) {
    throw const IsolatedE2eAppBuildException(
      'Flutter toolchain identity omitted a required field.',
    );
  }
  final payload = <String, Object?>{
    'schemaVersion': 1,
    'cacheContractVersion': 2,
    'name': request.name,
    'target': request.target,
    'bundleId': request.bundleId,
    'platform': request.platform.name,
    'dartDefines': request.dartDefines,
    'sourceDigest': sourceDigest,
    'pubspecLockSha256': await fileSha256(
      File('${request.projectRoot.path}/pubspec.lock'),
    ),
    'nativeCoreSha256': nativeCoreSha256,
    'nativeCoreProvenanceSha256': nativeCoreProvenanceSha256,
    'host': <String, Object?>{
      'os': hostPlatform.operatingSystem,
      'hardwareArchitecture': hostPlatform.hardwareArchitecture,
      'translated': hostPlatform.translated,
    },
    'flutter': flutterIdentity,
  };
  return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
}

Future<String> trackedBuildInputsSha256(
  Directory projectRoot, {
  required IsolatedE2eAppPlatform platform,
}) async {
  final listed = await Process.run('git', <String>[
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
    '--',
    'lib',
    'integration_test',
    platform.name,
    'pubspec.yaml',
    'pubspec.lock',
  ], workingDirectory: projectRoot.path);
  if (listed.exitCode != 0) {
    throw const IsolatedE2eAppBuildException(
      'App build input inventory is unavailable.',
    );
  }
  final paths =
      listed.stdout
          .toString()
          .split('\u0000')
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort();
  if (paths.isEmpty) {
    throw const IsolatedE2eAppBuildException('App build inputs are empty.');
  }
  Digest? digest;
  final input = sha256.startChunkedConversion(
    _DigestSink((value) => digest = value),
  );
  for (final relative in paths) {
    input.add(utf8.encode('$relative\u0000'));
    final file = File('${projectRoot.path}/$relative');
    if (!file.existsSync()) {
      input.add(const <int>[0xff]);
      continue;
    }
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.add(const <int>[0]);
  }
  input.close();
  return digest!.toString();
}

Future<String> directorySha256(Directory directory) async {
  if (!directory.existsSync()) {
    throw const IsolatedE2eAppBuildException('App artifact is missing.');
  }
  final entities = directory.listSync(recursive: true, followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  Digest? digest;
  final input = sha256.startChunkedConversion(
    _DigestSink((value) => digest = value),
  );
  for (final entity in entities) {
    final relative = entity.path.substring(directory.path.length + 1);
    input.add(utf8.encode('$relative\u0000'));
    input.add(utf8.encode('${entity.statSync().mode & 0x1ff}\u0000'));
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      input.add(const <int>[1]);
      await for (final chunk in File(entity.path).openRead()) {
        input.add(chunk);
      }
    } else if (type == FileSystemEntityType.link) {
      input.add(const <int>[2]);
      input.add(utf8.encode(Link(entity.path).targetSync()));
    } else if (type == FileSystemEntityType.directory) {
      input.add(const <int>[3]);
    }
    input.add(const <int>[0]);
  }
  input.close();
  return digest!.toString();
}

Future<String?> _restoreIsolatedArtifactCache({
  required IsolatedE2eAppBuildRequest request,
  required IsolatedE2eAppBuildPlan plan,
  required String fingerprint,
}) async {
  final cacheRoot = Directory(
    '${request.workRoot.path}/artifact-cache/$fingerprint',
  );
  if (!cacheRoot.existsSync()) return null;
  final manifest = File('${cacheRoot.path}/manifest.json');
  final cachedApp = Directory('${cacheRoot.path}/app');
  if (!manifest.existsSync() || !cachedApp.existsSync()) {
    throw const IsolatedE2eAppBuildException(
      'The isolated App cache entry is incomplete.',
    );
  }
  final decoded = jsonDecode(await manifest.readAsString());
  if (decoded is! Map ||
      decoded['schemaVersion'] != 1 ||
      decoded['fingerprint'] != fingerprint ||
      decoded['bundleId'] != request.bundleId ||
      decoded['artifactSha256'] is! String) {
    throw const IsolatedE2eAppBuildException(
      'The isolated App cache manifest is invalid.',
    );
  }
  final expectedDigest = decoded['artifactSha256'] as String;
  if (await directorySha256(cachedApp) != expectedDigest) {
    throw const IsolatedE2eAppBuildException(
      'The isolated App cache artifact hash changed.',
    );
  }
  if (plan.artifactApp.existsSync()) {
    plan.artifactApp.deleteSync(recursive: true);
  }
  await _copyAppDirectory(
    source: cachedApp,
    destination: plan.artifactApp,
    platform: request.platform,
  );
  if (!plan.executable.existsSync() ||
      await directorySha256(plan.artifactApp) != expectedDigest) {
    throw const IsolatedE2eAppBuildException(
      'The restored isolated App artifact is invalid.',
    );
  }
  return expectedDigest;
}

Future<void> _storeIsolatedArtifactCache({
  required IsolatedE2eAppBuildRequest request,
  required IsolatedE2eAppBuildPlan plan,
  required String fingerprint,
  required String artifactSha256,
}) async {
  final parent = Directory('${request.workRoot.path}/artifact-cache')
    ..createSync(recursive: true);
  final cacheRoot = Directory('${parent.path}/$fingerprint');
  if (cacheRoot.existsSync()) {
    throw const IsolatedE2eAppBuildException(
      'The isolated App cache entry already exists.',
    );
  }
  final temporary = Directory('${parent.path}/.$fingerprint.tmp');
  if (temporary.existsSync()) {
    throw const IsolatedE2eAppBuildException(
      'The isolated App cache temporary entry already exists.',
    );
  }
  temporary.createSync();
  final cachedApp = Directory('${temporary.path}/app');
  try {
    await _copyAppDirectory(
      source: plan.artifactApp,
      destination: cachedApp,
      platform: request.platform,
    );
    if (await directorySha256(cachedApp) != artifactSha256) {
      throw const IsolatedE2eAppBuildException(
        'The isolated App cache copy hash changed.',
      );
    }
    File('${temporary.path}/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'fingerprint': fingerprint,
        'bundleId': request.bundleId,
        'artifactSha256': artifactSha256,
      }),
      flush: true,
    );
    temporary.renameSync(cacheRoot.path);
  } on Object {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    rethrow;
  }
}

Future<void> _copyAppDirectory({
  required Directory source,
  required Directory destination,
  required IsolatedE2eAppPlatform platform,
}) async {
  final copy = platform == IsolatedE2eAppPlatform.macos
      ? await Process.run('/usr/bin/ditto', <String>[
          source.path,
          destination.path,
        ])
      : await Process.run('/bin/cp', <String>[
          '-a',
          source.path,
          destination.path,
        ]);
  if (copy.exitCode != 0 || !destination.existsSync()) {
    throw const IsolatedE2eAppBuildException(
      'The isolated App directory copy failed.',
    );
  }
}

class _DigestSink implements Sink<Digest> {
  _DigestSink(this.onDigest);

  final void Function(Digest) onDigest;

  @override
  void add(Digest data) => onDigest(data);

  @override
  void close() {}
}

class IsolatedE2eAppBuildException implements Exception {
  const IsolatedE2eAppBuildException(this.message);

  final String message;
}

Directory _validatedRoot(
  String value, {
  required Directory projectRoot,
  required String label,
}) {
  if (value.replaceAll('\\', '/').split('/').contains('..')) {
    throw IsolatedE2eAppBuildException('--$label must not contain "..".');
  }
  final root = projectRoot.absolute.path;
  final directory = Directory(value).absolute;
  if (directory.path == root || !directory.path.startsWith('$root/')) {
    throw IsolatedE2eAppBuildException(
      '--$label must be inside the project root.',
    );
  }
  return directory;
}

bool _pathsOverlap(String first, String second) =>
    first == second ||
    first.startsWith('$second/') ||
    second.startsWith('$first/');

String _commandFailureTail(ProcessResult result) {
  final combined = '${result.stdout}\n${result.stderr}'.trim();
  if (combined.isEmpty) {
    return '';
  }
  final lines = const LineSplitter().convert(combined);
  final tail = lines.skip(lines.length > 12 ? lines.length - 12 : 0).join('\n');
  return '\n$tail';
}

extension<T> on List<T> {
  T? get singleOrNull => length == 1 ? single : null;
}
