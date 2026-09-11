// [INPUT]: One E2E target, isolated runtime/artifact roots, a reusable role build root, bundle identity, and stable Dart defines.
// [OUTPUT]: An isolated Debug macOS or Linux App bundle plus a machine-readable artifact manifest.
// [POS]: Reusable incremental build boundary for E2E modes that need concurrently runnable App processes.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../tests/e2e/app_artifact_spec.dart';
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
    this.consumerSuites = const <String>[],
    this.pinnedCompileKeys = const <String>{},
    this.preserveScratch = false,
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
  final List<String> consumerSuites;
  final Set<String> pinnedCompileKeys;
  final bool preserveScratch;

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
    final dartDefines = canonicalDartDefines(
      values['dart-define'] ?? const <String>[],
    );
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

  IsolatedE2eAppBuildPlan toPlan({String? processArchitecture}) {
    final buildDirectory = Directory('${workRoot.path}/flutter-build');
    final flutterConfigDirectory = Directory('${workRoot.path}/flutter-config');
    final overrideConfig = File('${workRoot.path}/AppPair.xcconfig');
    final sourceApp = switch (platform) {
      IsolatedE2eAppPlatform.macos => Directory(
        '${buildDirectory.path}/macos/Build/Products/Debug/AWikiMe.app',
      ),
      IsolatedE2eAppPlatform.linux => Directory(
        '${buildDirectory.path}/linux/'
        '${_flutterLinuxArchitecture(processArchitecture ?? 'x86_64')}/'
        'debug/bundle',
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
    required this.projectRelativeAppPath,
    required this.executableRelativePath,
    required this.consumerSuites,
    required this.compileKeyPayload,
    required this.provenance,
    required this.cachePrunedEntries,
    required this.cachePrunedBytes,
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
  final String projectRelativeAppPath;
  final String executableRelativePath;
  final List<String> consumerSuites;
  final Map<String, Object?> compileKeyPayload;
  final Map<String, Object?> provenance;
  final int cachePrunedEntries;
  final int cachePrunedBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'name': name,
    'target': target,
    'bundleId': bundleId,
    'projectRelativeAppPath': projectRelativeAppPath,
    'executableRelativePath': executableRelativePath,
    'consumerSuites': consumerSuites,
    'dryRun': dryRun,
    'hostPlatform': hostPlatform.toJson(),
    'compileKeySchemaVersion': 1,
    'compileKey': fingerprint,
    'fingerprint': fingerprint,
    'cacheHit': cacheHit,
    'artifactSha256': artifactSha256,
    'compileKeyPayload': compileKeyPayload,
    'provenance': provenance,
    'evidenceEligible': provenance['worktreeDirty'] == false,
    'cachePrunedEntries': cachePrunedEntries,
    'cachePrunedBytes': cachePrunedBytes,
  };
}

class IsolatedE2eAppBuilder {
  Future<IsolatedE2eAppArtifact> build(
    IsolatedE2eAppBuildRequest request, {
    IsolatedE2eAppBuildIdentity? precomputedIdentity,
  }) async {
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
    final plan = request.toPlan(
      processArchitecture: hostPlatform.processArchitecture,
    );
    if (request.dryRun) {
      return _isolatedArtifact(
        request: request,
        plan: plan,
        hostPlatform: hostPlatform,
        fingerprint: 'dry-run',
        cacheHit: false,
        artifactSha256: '',
        compileKeyPayload: const <String, Object?>{},
        provenance: const <String, Object?>{},
        cachePruneReport: const E2eAppCachePruneReport(
          prunedEntries: 0,
          prunedBytes: 0,
        ),
      );
    }

    final identity =
        precomputedIdentity ??
        await isolatedBuildIdentity(
          request: request,
          hostPlatform: hostPlatform,
        );
    final fingerprint = identity.compileKey;
    await recoverStaleIsolatedArtifactTemps(request.projectRoot);
    final cached = await _restoreIsolatedArtifactCache(
      request: request,
      plan: plan,
      fingerprint: fingerprint,
      hostPlatform: hostPlatform,
    );
    if (cached != null) {
      request.artifactRoot.createSync(recursive: true);
      final artifact = _isolatedArtifact(
        request: request,
        plan: plan,
        hostPlatform: hostPlatform,
        fingerprint: fingerprint,
        cacheHit: true,
        artifactSha256: cached.digest,
        appDirectory: cached.appDirectory,
        compileKeyPayload: identity.compileKeyPayload,
        provenance: identity.provenance,
        cachePruneReport: const E2eAppCachePruneReport(
          prunedEntries: 0,
          prunedBytes: 0,
        ),
      );
      plan.manifest.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(artifact.toJson()),
        flush: true,
      );
      return artifact;
    }

    final cachePruneReport = await requireE2eBuildDiskBudget(
      request.projectRoot,
      pinnedCompileKeys: <String>{...request.pinnedCompileKeys, fingerprint},
    );

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

    final linuxNativeAssetsLink = prepareIsolatedLinuxNativeAssetsCompatibility(
      projectRoot: request.projectRoot,
      buildDirectory: plan.buildDirectory,
      platform: request.platform,
    );
    late final ProcessResult build;
    try {
      build = await Process.run(
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
    } finally {
      removeIsolatedLinuxNativeAssetsCompatibility(
        linuxNativeAssetsLink,
        buildDirectory: plan.buildDirectory,
      );
    }
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
    final cachedApp = await _storeIsolatedArtifactCache(
      request: request,
      plan: plan,
      fingerprint: fingerprint,
      artifactSha256: artifactSha256,
      hostPlatform: hostPlatform,
    );
    if (plan.artifactApp.existsSync()) {
      plan.artifactApp.deleteSync(recursive: true);
    }
    if (!request.preserveScratch) _deleteBuildScratch(plan);
    final artifact = _isolatedArtifact(
      request: request,
      plan: plan,
      hostPlatform: hostPlatform,
      fingerprint: fingerprint,
      cacheHit: false,
      artifactSha256: artifactSha256,
      appDirectory: cachedApp,
      compileKeyPayload: identity.compileKeyPayload,
      provenance: identity.provenance,
      cachePruneReport: cachePruneReport,
    );
    plan.manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(artifact.toJson()),
      flush: true,
    );
    return artifact;
  }
}

int e2eBuildRequiredFreeBytes({
  required int minFreeAfterJob,
  required int estimatedPeakBytes,
}) => minFreeAfterJob + estimatedPeakBytes;

final class E2eAppCachePruneReport {
  const E2eAppCachePruneReport({
    required this.prunedEntries,
    required this.prunedBytes,
  });

  final int prunedEntries;
  final int prunedBytes;
}

Future<E2eAppCachePruneReport> requireE2eBuildDiskBudget(
  Directory projectRoot, {
  Set<String> pinnedCompileKeys = const <String>{},
}) async {
  const gibibyte = 1024 * 1024 * 1024;
  const minFreeAfterJob = 4 * gibibyte;
  const conservativeFirstBuildPeak = 4 * gibibyte;
  final required = e2eBuildRequiredFreeBytes(
    minFreeAfterJob: minFreeAfterJob,
    estimatedPeakBytes: conservativeFirstBuildPeak,
  );
  var availableBytes = await e2eBuildAvailableDiskBytes(projectRoot);
  var pruneReport = const E2eAppCachePruneReport(
    prunedEntries: 0,
    prunedBytes: 0,
  );
  if (availableBytes < required) {
    pruneReport = await pruneIsolatedArtifactCache(
      projectRoot: projectRoot,
      pinnedCompileKeys: pinnedCompileKeys,
      bytesToFree: required - availableBytes,
    );
    availableBytes = await e2eBuildAvailableDiskBytes(projectRoot);
  }
  if (availableBytes < required) {
    throw const IsolatedE2eAppBuildException(
      'The next App build does not satisfy minFreeAfterJob + estimatedPeakBytes.',
    );
  }
  return pruneReport;
}

Future<int> e2eBuildAvailableDiskBytes(Directory projectRoot) async {
  final result = await Process.run('df', <String>['-Pk', projectRoot.path]);
  if (result.exitCode != 0) {
    throw const IsolatedE2eAppBuildException(
      'Available disk space could not be measured before the App build.',
    );
  }
  final lines = const LineSplitter()
      .convert(result.stdout.toString().trim())
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) {
    throw const IsolatedE2eAppBuildException(
      'Available disk space report is invalid.',
    );
  }
  final fields = lines.last.trim().split(RegExp(r'\s+'));
  final availableKiB = fields.length >= 4 ? int.tryParse(fields[3]) : null;
  if (availableKiB == null) {
    throw const IsolatedE2eAppBuildException(
      'Available disk space report is invalid.',
    );
  }
  return availableKiB * 1024;
}

Future<int> isolatedArtifactCacheBytes(Directory projectRoot) async {
  var bytes = 0;
  for (final directory in _isolatedArtifactCacheEntries(projectRoot)) {
    bytes += await _directoryBytes(directory);
  }
  return bytes;
}

Future<E2eAppCachePruneReport> pruneIsolatedArtifactCache({
  required Directory projectRoot,
  required Set<String> pinnedCompileKeys,
  required int bytesToFree,
}) async {
  if (bytesToFree <= 0) {
    return const E2eAppCachePruneReport(prunedEntries: 0, prunedBytes: 0);
  }
  final candidates = <({Directory directory, DateTime lastUsed, int bytes})>[];
  for (final directory in _isolatedArtifactCacheEntries(projectRoot)) {
    final compileKey = directory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    if (pinnedCompileKeys.contains(compileKey)) {
      continue;
    }
    final manifest = File('${directory.path}/manifest.json');
    if (!manifest.existsSync()) {
      continue;
    }
    candidates.add((
      directory: directory,
      lastUsed: manifest.lastModifiedSync(),
      bytes: await _directoryBytes(directory),
    ));
  }
  candidates.sort((left, right) => left.lastUsed.compareTo(right.lastUsed));
  var prunedEntries = 0;
  var prunedBytes = 0;
  for (final candidate in candidates) {
    if (prunedBytes >= bytesToFree) {
      break;
    }
    candidate.directory.deleteSync(recursive: true);
    prunedEntries += 1;
    prunedBytes += candidate.bytes;
  }
  return E2eAppCachePruneReport(
    prunedEntries: prunedEntries,
    prunedBytes: prunedBytes,
  );
}

Future<void> recoverStaleIsolatedArtifactTemps(Directory projectRoot) async {
  final cache = Directory('${projectRoot.absolute.path}/.e2e/build-cache/v2');
  if (!cache.existsSync()) {
    return;
  }
  await for (final entity in cache.list(recursive: true, followLinks: false)) {
    if (entity is! Directory) {
      continue;
    }
    final name = entity.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    final match = RegExp(r'^\.[0-9a-f]{64}\.([0-9]+)\.tmp$').firstMatch(name);
    if (match == null) {
      continue;
    }
    final ownerPid = int.parse(match.group(1)!);
    if (ownerPid == pid || await _processExists(ownerPid)) {
      continue;
    }
    entity.deleteSync(recursive: true);
  }
}

Iterable<Directory> _isolatedArtifactCacheEntries(Directory projectRoot) sync* {
  final cache = Directory('${projectRoot.absolute.path}/.e2e/build-cache/v2');
  if (!cache.existsSync()) {
    return;
  }
  final keyPattern = RegExp(r'^[0-9a-f]{64}$');
  for (final platform
      in cache.listSync(followLinks: false).whereType<Directory>()) {
    if (!const <String>{'linux', 'macos'}.contains(
      platform.uri.pathSegments.where((segment) => segment.isNotEmpty).last,
    )) {
      continue;
    }
    for (final architecture
        in platform.listSync(followLinks: false).whereType<Directory>()) {
      for (final entry
          in architecture.listSync(followLinks: false).whereType<Directory>()) {
        final name = entry.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last;
        if (keyPattern.hasMatch(name)) {
          yield entry;
        }
      }
    }
  }
}

Future<int> _directoryBytes(Directory directory) async {
  var bytes = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) {
      bytes += await entity.length();
    }
  }
  return bytes;
}

Future<bool> _processExists(int processId) async {
  final result = await Process.run('/bin/kill', <String>['-0', '$processId']);
  return result.exitCode == 0;
}

IsolatedE2eAppArtifact _isolatedArtifact({
  required IsolatedE2eAppBuildRequest request,
  required IsolatedE2eAppBuildPlan plan,
  required E2eHostPlatform hostPlatform,
  required String fingerprint,
  required bool cacheHit,
  required String artifactSha256,
  Directory? appDirectory,
  required Map<String, Object?> compileKeyPayload,
  required Map<String, Object?> provenance,
  required E2eAppCachePruneReport cachePruneReport,
}) {
  final selectedApp = appDirectory ?? plan.artifactApp;
  final executable = File(
    request.platform == IsolatedE2eAppPlatform.macos
        ? '${selectedApp.path}/Contents/MacOS/AWikiMe'
        : '${selectedApp.path}/awiki_me',
  );
  return IsolatedE2eAppArtifact(
    name: request.name,
    target: request.target,
    bundleId: request.bundleId,
    appPath: selectedApp.path,
    executablePath: executable.path,
    stateRoot: request.stateRoot.path,
    buildDirectory: plan.buildDirectory.path,
    dryRun: request.dryRun,
    hostPlatform: hostPlatform,
    fingerprint: fingerprint,
    cacheHit: cacheHit,
    artifactSha256: artifactSha256,
    projectRelativeAppPath: _projectRelativePath(
      root: request.projectRoot,
      entityPath: selectedApp.path,
      label: 'App bundle',
    ),
    executableRelativePath: request.platform == IsolatedE2eAppPlatform.macos
        ? 'Contents/MacOS/AWikiMe'
        : 'awiki_me',
    consumerSuites: List<String>.unmodifiable(request.consumerSuites),
    compileKeyPayload: Map<String, Object?>.unmodifiable(compileKeyPayload),
    provenance: Map<String, Object?>.unmodifiable(provenance),
    cachePrunedEntries: cachePruneReport.prunedEntries,
    cachePrunedBytes: cachePruneReport.prunedBytes,
  );
}

Future<String> isolatedBuildFingerprint({
  required IsolatedE2eAppBuildRequest request,
  required E2eHostPlatform hostPlatform,
}) async => (await isolatedBuildIdentity(
  request: request,
  hostPlatform: hostPlatform,
)).compileKey;

typedef IsolatedE2eAppBuildIdentity = ({
  String compileKey,
  Map<String, Object?> compileKeyPayload,
  Map<String, Object?> provenance,
});

Future<IsolatedE2eAppBuildIdentity> isolatedBuildIdentity({
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
    target: request.target,
  );
  String nativeCoreSha256 = '';
  String nativeCoreProvenanceSha256 = '';
  if (request.platform == IsolatedE2eAppPlatform.linux) {
    final layout = await LinuxImCoreLayout.resolve(request.projectRoot);
    nativeCoreSha256 = await fileSha256(layout.artifact);
    nativeCoreProvenanceSha256 = await fileSha256(layout.manifest);
  } else if (request.platform == IsolatedE2eAppPlatform.macos) {
    final nativeLibraries =
        Directory(
              '${request.projectRoot.parent.path}/awiki-cli-rs2/'
              'packages/awiki_im_core/macos/Frameworks/AwikiImCore.xcframework',
            )
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('/libawiki_im_core.a'))
            .toList();
    if (nativeLibraries.length != 1) {
      throw const IsolatedE2eAppBuildException(
        'The macOS IM Core native artifact is unavailable or ambiguous.',
      );
    }
    nativeCoreSha256 = await fileSha256(nativeLibraries.single);
  }
  final rustc = await Process.run('rustc', const <String>['--version']);
  if (rustc.exitCode != 0 || rustc.stdout.toString().trim().isEmpty) {
    throw const IsolatedE2eAppBuildException(
      'Rust toolchain identity is unavailable.',
    );
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
  final overrides = File('${request.projectRoot.path}/pubspec_overrides.yaml');
  final payload = isolatedCompileKeyPayload(
    request: request,
    hostPlatform: hostPlatform,
    sourceDigest: sourceDigest,
    pubspecLockSha256: await fileSha256(
      File('${request.projectRoot.path}/pubspec.lock'),
    ),
    pubspecOverridesSha256: overrides.existsSync()
        ? await fileSha256(overrides)
        : '',
    pathDependencySha256: await pathDependencyBuildInputsSha256(
      request.projectRoot,
    ),
    nativeCoreSha256: nativeCoreSha256,
    nativeCoreProvenanceSha256: nativeCoreProvenanceSha256,
    flutterIdentity: flutterIdentity,
    rustcVersion: rustc.stdout.toString().trim(),
  );
  final sourceRef = await _gitOutput(request.projectRoot, const <String>[
    'rev-parse',
    'HEAD',
  ], label: 'Git source revision');
  final worktreeStatus = await _gitOutput(
    request.projectRoot,
    const <String>['status', '--porcelain=v1', '--untracked-files=normal'],
    label: 'Git worktree status',
    allowEmpty: true,
  );
  return (
    compileKey: sha256.convert(utf8.encode(jsonEncode(payload))).toString(),
    compileKeyPayload: Map<String, Object?>.unmodifiable(payload),
    provenance: <String, Object?>{
      'sourceRef': sourceRef,
      'worktreeDirty': worktreeStatus.isNotEmpty,
      'sourceDigest': sourceDigest,
      'toolchains': <String, Object?>{
        'flutter': flutterIdentity,
        'rustc': rustc.stdout.toString().trim(),
      },
      'nativeCore': <String, String>{
        'sha256': nativeCoreSha256,
        'provenanceSha256': nativeCoreProvenanceSha256,
      },
    },
  );
}

Map<String, Object?> isolatedCompileKeyPayload({
  required IsolatedE2eAppBuildRequest request,
  required E2eHostPlatform hostPlatform,
  required String sourceDigest,
  required String pubspecLockSha256,
  required String pubspecOverridesSha256,
  required String pathDependencySha256,
  required String nativeCoreSha256,
  required String nativeCoreProvenanceSha256,
  required Map<String, String> flutterIdentity,
  required String rustcVersion,
}) => <String, Object?>{
  'schemaVersion': 1,
  'cacheContractVersion': 4,
  'target': request.target,
  'bundleId': request.bundleId,
  'platform': request.platform.name,
  'dartDefines': request.dartDefines,
  'sourceDigest': sourceDigest,
  'pubspecLockSha256': pubspecLockSha256,
  'pubspecOverridesSha256': pubspecOverridesSha256,
  'pathDependencySha256': pathDependencySha256,
  'nativeCoreSha256': nativeCoreSha256,
  'nativeCoreProvenanceSha256': nativeCoreProvenanceSha256,
  'host': <String, Object?>{
    'os': hostPlatform.operatingSystem,
    'processArchitecture': hostPlatform.processArchitecture,
    'hardwareArchitecture': hostPlatform.hardwareArchitecture,
    'translated': hostPlatform.translated,
  },
  'flutter': flutterIdentity,
  'rustc': rustcVersion,
};

List<String> canonicalDartDefines(Iterable<String> values) {
  try {
    return canonicalCompileTimeDartDefines(values);
  } on FormatException catch (error) {
    throw IsolatedE2eAppBuildException(error.message);
  }
}

String _flutterLinuxArchitecture(String processArchitecture) =>
    switch (processArchitecture.trim()) {
      'x86_64' => 'x64',
      'aarch64' => 'arm64',
      _ => throw IsolatedE2eAppBuildException(
        'Unsupported Linux process architecture: $processArchitecture',
      ),
    };

String _projectRelativePath({
  required Directory root,
  required String entityPath,
  required String label,
}) {
  final rootPath = root.absolute.path;
  final absolute = entityPath.startsWith('/')
      ? entityPath
      : '${Directory.current.absolute.path}/$entityPath';
  if (!absolute.startsWith('$rootPath/')) {
    throw IsolatedE2eAppBuildException(
      '$label must remain inside the App project root.',
    );
  }
  final relative = absolute.substring(rootPath.length + 1);
  if (relative.isEmpty || relative.split('/').contains('..')) {
    throw IsolatedE2eAppBuildException('$label relative path is invalid.');
  }
  return relative;
}

Future<String> _gitOutput(
  Directory root,
  List<String> arguments, {
  required String label,
  bool allowEmpty = false,
}) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  final output = result.stdout.toString().trim();
  if (result.exitCode != 0 || (!allowEmpty && output.isEmpty)) {
    throw IsolatedE2eAppBuildException('$label is unavailable.');
  }
  return output;
}

Future<String> trackedBuildInputsSha256(
  Directory projectRoot, {
  required IsolatedE2eAppPlatform platform,
  required String target,
}) async {
  final targetInputs = await transitiveLocalDartInputsSha256Paths(
    projectRoot,
    target,
  );
  final listed = await Process.run('git', <String>[
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
    '--',
    'lib',
    ...targetInputs,
    'test_driver',
    'assets',
    platform.name,
    'pubspec.yaml',
    'pubspec.lock',
    'pubspec_overrides.yaml',
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

Future<List<String>> transitiveLocalDartInputsSha256Paths(
  Directory projectRoot,
  String target,
) async {
  final root = projectRoot.absolute.path;
  final pending = <String>[target];
  final visited = <String>{};
  final directive = RegExp(
    r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  while (pending.isNotEmpty) {
    final relative = pending.removeLast();
    if (!visited.add(relative)) continue;
    final file = File('$root/$relative');
    if (!file.existsSync()) {
      throw IsolatedE2eAppBuildException(
        'App target dependency is unavailable: $relative',
      );
    }
    final source = await file.readAsString();
    for (final match in directive.allMatches(source)) {
      final reference = match.group(1)!;
      if (reference.startsWith('dart:') || reference.startsWith('package:')) {
        continue;
      }
      final resolved = File.fromUri(file.uri.resolve(reference)).absolute.path;
      if (resolved != root && !resolved.startsWith('$root/')) {
        throw const IsolatedE2eAppBuildException(
          'App target dependency escapes the project root.',
        );
      }
      final dependency = resolved.substring(root.length + 1);
      if (!visited.contains(dependency)) pending.add(dependency);
    }
  }
  final result = visited.toList()..sort();
  return result;
}

Future<String> pathDependencyBuildInputsSha256(Directory projectRoot) async {
  final dependencyRoot = Directory(
    '${projectRoot.parent.path}/awiki-cli-rs2/packages/awiki_im_core',
  );
  if (!dependencyRoot.existsSync()) {
    throw const IsolatedE2eAppBuildException(
      'The awiki_im_core path dependency is unavailable.',
    );
  }
  final listed = await Process.run('git', <String>[
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
    '-z',
    '--',
    'packages/awiki_im_core/lib',
    'packages/awiki_im_core/linux',
    'packages/awiki_im_core/macos',
    'packages/awiki_im_core/pubspec.yaml',
    'packages/awiki_im_core/pubspec.lock',
  ], workingDirectory: dependencyRoot.parent.parent.path);
  if (listed.exitCode != 0) {
    throw const IsolatedE2eAppBuildException(
      'The awiki_im_core build input inventory is unavailable.',
    );
  }
  final paths =
      listed.stdout
          .toString()
          .split('\u0000')
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort();
  Digest? digest;
  final input = sha256.startChunkedConversion(
    _DigestSink((value) => digest = value),
  );
  for (final relative in paths) {
    input.add(utf8.encode('$relative\u0000'));
    final file = File('${dependencyRoot.parent.parent.path}/$relative');
    if (file.existsSync()) {
      await for (final chunk in file.openRead()) {
        input.add(chunk);
      }
    } else {
      input.add(const <int>[0xff]);
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

Future<({String digest, Directory appDirectory})?>
_restoreIsolatedArtifactCache({
  required IsolatedE2eAppBuildRequest request,
  required IsolatedE2eAppBuildPlan plan,
  required String fingerprint,
  required E2eHostPlatform hostPlatform,
}) async {
  final cacheRoot = _isolatedArtifactCacheEntry(
    request: request,
    hostPlatform: hostPlatform,
    fingerprint: fingerprint,
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
  final cachedExecutable = File(
    request.platform == IsolatedE2eAppPlatform.macos
        ? '${cachedApp.path}/Contents/MacOS/AWikiMe'
        : '${cachedApp.path}/awiki_me',
  );
  if (!cachedExecutable.existsSync() ||
      await directorySha256(cachedApp) != expectedDigest) {
    throw const IsolatedE2eAppBuildException(
      'The restored isolated App artifact is invalid.',
    );
  }
  manifest.setLastModifiedSync(DateTime.now().toUtc());
  return (digest: expectedDigest, appDirectory: cachedApp);
}

Future<Directory> _storeIsolatedArtifactCache({
  required IsolatedE2eAppBuildRequest request,
  required IsolatedE2eAppBuildPlan plan,
  required String fingerprint,
  required String artifactSha256,
  required E2eHostPlatform hostPlatform,
}) async {
  final cacheRoot = _isolatedArtifactCacheEntry(
    request: request,
    hostPlatform: hostPlatform,
    fingerprint: fingerprint,
  );
  final parent = cacheRoot.parent..createSync(recursive: true);
  if (cacheRoot.existsSync()) {
    throw const IsolatedE2eAppBuildException(
      'The isolated App cache entry already exists.',
    );
  }
  final temporary = Directory('${parent.path}/.$fingerprint.$pid.tmp');
  if (temporary.existsSync()) {
    temporary.deleteSync(recursive: true);
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
    return Directory('${cacheRoot.path}/app');
  } on Object {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    rethrow;
  }
}

Directory _isolatedArtifactCacheEntry({
  required IsolatedE2eAppBuildRequest request,
  required E2eHostPlatform hostPlatform,
  required String fingerprint,
}) => isolatedArtifactCacheDirectory(
  projectRoot: request.projectRoot,
  platform: request.platform,
  processArchitecture: hostPlatform.processArchitecture,
  compileKey: fingerprint,
);

Directory isolatedArtifactCacheDirectory({
  required Directory projectRoot,
  required IsolatedE2eAppPlatform platform,
  required String processArchitecture,
  required String compileKey,
}) => Directory(
  '${projectRoot.absolute.path}/.e2e/build-cache/v2/'
  '${platform.name}/$processArchitecture/$compileKey',
);

void _deleteBuildScratch(IsolatedE2eAppBuildPlan plan) {
  for (final directory in <Directory>[
    plan.buildDirectory,
    plan.flutterConfigDirectory,
  ]) {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
  if (plan.overrideConfig.existsSync()) plan.overrideConfig.deleteSync();
}

Future<void> _copyAppDirectory({
  required Directory source,
  required Directory destination,
  required IsolatedE2eAppPlatform platform,
}) async {
  destination.parent.createSync(recursive: true);
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

final class IsolatedLinuxNativeAssetsCompatibility {
  const IsolatedLinuxNativeAssetsCompatibility({
    required this.linuxLink,
    required this.nativeAssetsLink,
    required this.nativeAssetsBackup,
  });

  final Link linuxLink;
  final Link nativeAssetsLink;
  final Directory? nativeAssetsBackup;
}

IsolatedLinuxNativeAssetsCompatibility?
prepareIsolatedLinuxNativeAssetsCompatibility({
  required Directory projectRoot,
  required Directory buildDirectory,
  required IsolatedE2eAppPlatform platform,
}) {
  if (platform != IsolatedE2eAppPlatform.linux) return null;
  recoverStaleIsolatedLinuxNativeAssetsCompatibility(
    projectRoot: projectRoot,
    buildDirectory: buildDirectory,
  );
  final target = Directory('${buildDirectory.path}/linux')
    ..createSync(recursive: true);
  final link = Link('${projectRoot.path}/build/linux');
  final nativeAssetsTarget = Directory('${buildDirectory.path}/native_assets');
  Directory('${nativeAssetsTarget.path}/linux').createSync(recursive: true);
  final nativeAssetsLink = Link('${projectRoot.path}/build/native_assets');
  final type = FileSystemEntity.typeSync(link.path, followLinks: false);
  if (type != FileSystemEntityType.notFound) {
    if (type != FileSystemEntityType.link ||
        link.targetSync() != target.absolute.path) {
      throw IsolatedE2eAppBuildException(
        'Isolated App native-assets compatibility refuses to replace '
        '${link.path}.',
      );
    }
  }
  final nativeAssetsType = FileSystemEntity.typeSync(
    nativeAssetsLink.path,
    followLinks: false,
  );
  if (nativeAssetsType != FileSystemEntityType.notFound &&
      nativeAssetsType != FileSystemEntityType.link &&
      nativeAssetsType != FileSystemEntityType.directory) {
    throw IsolatedE2eAppBuildException(
      'Isolated App native-assets compatibility refuses to replace '
      '${nativeAssetsLink.path}.',
    );
  }
  if (nativeAssetsType == FileSystemEntityType.link &&
      nativeAssetsLink.targetSync() != nativeAssetsTarget.absolute.path) {
    throw IsolatedE2eAppBuildException(
      'Isolated App native-assets compatibility refuses to replace '
      '${nativeAssetsLink.path}.',
    );
  }
  link.parent.createSync(recursive: true);
  Directory? nativeAssetsBackup;
  if (nativeAssetsType == FileSystemEntityType.directory) {
    nativeAssetsBackup = Directory(
      '${nativeAssetsLink.path}.awiki-isolated-backup-$pid',
    );
    if (nativeAssetsBackup.existsSync()) {
      throw const IsolatedE2eAppBuildException(
        'Isolated App native-assets backup already exists.',
      );
    }
    Directory(nativeAssetsLink.path).renameSync(nativeAssetsBackup.path);
  }
  if (type == FileSystemEntityType.notFound) {
    link.createSync(target.absolute.path);
  }
  if (nativeAssetsType != FileSystemEntityType.link) {
    nativeAssetsLink.createSync(nativeAssetsTarget.absolute.path);
  }
  return IsolatedLinuxNativeAssetsCompatibility(
    linuxLink: link,
    nativeAssetsLink: nativeAssetsLink,
    nativeAssetsBackup: nativeAssetsBackup,
  );
}

void recoverStaleIsolatedLinuxNativeAssetsCompatibility({
  required Directory projectRoot,
  required Directory buildDirectory,
}) {
  final linuxLink = Link('${projectRoot.path}/build/linux');
  final expectedLinuxTarget = Directory(
    '${buildDirectory.path}/linux',
  ).absolute.path;
  if (FileSystemEntity.typeSync(linuxLink.path, followLinks: false) !=
          FileSystemEntityType.link ||
      linuxLink.targetSync() == expectedLinuxTarget) {
    return;
  }
  final staleTarget = linuxLink.targetSync();
  final cachePrefix = '${projectRoot.absolute.path}/.e2e/build-cache/';
  if (!staleTarget.startsWith(cachePrefix)) {
    throw const IsolatedE2eAppBuildException(
      'Isolated App recovery refuses an unrelated Linux build link.',
    );
  }
  final buildRoot = Directory('${projectRoot.path}/build');
  final backups = buildRoot
      .listSync(followLinks: false)
      .whereType<Directory>()
      .where(
        (directory) =>
            directory.path.contains('/native_assets.awiki-isolated-backup-'),
      )
      .toList();
  if (backups.length != 1) {
    throw const IsolatedE2eAppBuildException(
      'Interrupted isolated App build has no unique native-assets backup.',
    );
  }
  final ownerPid = int.tryParse(backups.single.path.split('-').last);
  if (ownerPid == null || Directory('/proc/$ownerPid').existsSync()) {
    throw const IsolatedE2eAppBuildException(
      'Interrupted isolated App build owner is invalid or still running.',
    );
  }
  final nativeAssetsLink = Link('${buildRoot.path}/native_assets');
  if (FileSystemEntity.typeSync(nativeAssetsLink.path, followLinks: false) !=
          FileSystemEntityType.link ||
      !nativeAssetsLink.targetSync().startsWith(cachePrefix)) {
    throw const IsolatedE2eAppBuildException(
      'Interrupted isolated App native-assets link is not recoverable.',
    );
  }
  linuxLink.deleteSync();
  nativeAssetsLink.deleteSync();
  backups.single.renameSync(nativeAssetsLink.path);
}

void removeIsolatedLinuxNativeAssetsCompatibility(
  IsolatedLinuxNativeAssetsCompatibility? compatibility, {
  required Directory buildDirectory,
}) {
  if (compatibility == null) return;
  final link = compatibility.linuxLink;
  if (FileSystemEntity.typeSync(link.path, followLinks: false) !=
      FileSystemEntityType.link) {
    throw const IsolatedE2eAppBuildException(
      'Isolated App Linux compatibility link changed during the build.',
    );
  } else if (link.targetSync() ==
      Directory('${buildDirectory.path}/linux').absolute.path) {
    link.deleteSync();
  }
  final nativeAssetsLink = compatibility.nativeAssetsLink;
  if (FileSystemEntity.typeSync(nativeAssetsLink.path, followLinks: false) ==
          FileSystemEntityType.link &&
      nativeAssetsLink.targetSync() ==
          Directory('${buildDirectory.path}/native_assets').absolute.path) {
    nativeAssetsLink.deleteSync();
  } else {
    throw const IsolatedE2eAppBuildException(
      'Isolated App native-assets compatibility link changed during the build.',
    );
  }
  final backup = compatibility.nativeAssetsBackup;
  if (backup != null) {
    if (!backup.existsSync() || nativeAssetsLink.existsSync()) {
      throw const IsolatedE2eAppBuildException(
        'Isolated App native-assets backup cannot be restored safely.',
      );
    }
    backup.renameSync(nativeAssetsLink.path);
  }
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
