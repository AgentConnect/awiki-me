// [INPUT]: Product artifact spec names, host platform, and one project-local export root.
// [OUTPUT]: One verified manifest per unique requested App build spec.
// [POS]: Account/OTP/provider-free prepare entrypoint used by the profile orchestrator.

import 'dart:convert';
import 'dart:io';

import '../tests/e2e/app_artifact_spec.dart';
import '../tests/e2e/host_platform.dart';
import 'isolated_e2e_app_builder.dart';

Future<void> main(List<String> arguments) async {
  try {
    final options = _PrepareOptions.parse(arguments);
    final root = Directory.current.absolute;
    final manifest = E2eAppArtifactSpecManifest.load(
      File('${root.path}/tests/e2e/app_artifact_specs.json'),
    );
    final hostPlatform = await E2eHostPlatform.detect();
    hostPlatform.requireOperatingSystem(options.platform.name);
    final freeBytesBefore = await e2eBuildAvailableDiskBytes(root);
    final cacheBytesBefore = await isolatedArtifactCacheBytes(root);
    final sharedWorkRoot = Directory(
      '${root.path}/.e2e/build-cache/v2/work/${options.platform.name}/shared',
    );
    final dagFile = File(
      '${root.path}/.e2e/build-cache/v2/dags/'
      '${options.platform.name}-${hostPlatform.processArchitecture}-last-successful.json',
    );
    final previousCompileKeys = _loadPreviousCompileKeys(
      dagFile,
      platform: options.platform.name,
      processArchitecture: hostPlatform.processArchitecture,
    );
    final requests = <IsolatedE2eAppBuildRequest>[];
    final identities = <IsolatedE2eAppBuildIdentity>[];
    for (final name in options.names) {
      final spec = manifest.requireSpec(name);
      if (!spec.supportedPlatforms.contains(options.platform.name)) {
        throw FormatException(
          'App artifact $name does not support ${options.platform.name}.',
        );
      }
      final request = IsolatedE2eAppBuildRequest(
        projectRoot: root,
        name: spec.name,
        target: spec.target,
        stateRoot: Directory(
          '${root.path}/.e2e/build-cache/v2/prepare-state/${spec.name}',
        ),
        workRoot: sharedWorkRoot,
        artifactRoot: options.artifactRoot,
        bundleId: spec.bundleId,
        platform: options.platform,
        flutterBin: options.flutterBin,
        dartDefines: spec.dartDefines,
        dryRun: false,
        consumerSuites: spec.consumerSuites,
        preserveScratch: true,
      );
      requests.add(request);
      identities.add(
        await isolatedBuildIdentity(
          request: request,
          hostPlatform: hostPlatform,
        ),
      );
    }
    final currentCompileKeys = identities
        .map((identity) => identity.compileKey)
        .toSet();
    final pinnedCompileKeys = <String>{
      ...previousCompileKeys,
      ...currentCompileKeys,
    };
    final artifacts = <Map<String, Object?>>[];
    for (var index = 0; index < requests.length; index += 1) {
      final request = requests[index];
      final artifact = await IsolatedE2eAppBuilder().build(
        IsolatedE2eAppBuildRequest(
          projectRoot: request.projectRoot,
          name: request.name,
          target: request.target,
          stateRoot: request.stateRoot,
          workRoot: request.workRoot,
          artifactRoot: request.artifactRoot,
          bundleId: request.bundleId,
          platform: request.platform,
          flutterBin: request.flutterBin,
          dartDefines: request.dartDefines,
          dryRun: request.dryRun,
          consumerSuites: request.consumerSuites,
          pinnedCompileKeys: pinnedCompileKeys,
          preserveScratch: request.preserveScratch,
        ),
        precomputedIdentity: identities[index],
      );
      artifacts.add(artifact.toJson());
    }
    if (sharedWorkRoot.existsSync()) {
      sharedWorkRoot.deleteSync(recursive: true);
    }
    _writeSuccessfulDag(
      dagFile,
      platform: options.platform.name,
      processArchitecture: hostPlatform.processArchitecture,
      compileKeys: currentCompileKeys,
    );
    final freeBytesAfter = await e2eBuildAvailableDiskBytes(root);
    final cacheBytesAfter = await isolatedArtifactCacheBytes(root);
    stdout.writeln(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'status': 'prepared',
        'platform': options.platform.name,
        'artifactCount': artifacts.length,
        'requestedArtifactCount': requests.length,
        'uniqueBuildSpecCount': currentCompileKeys.length,
        'cacheHits': artifacts
            .where((value) => value['cacheHit'] == true)
            .length,
        'cacheMisses': artifacts
            .where((value) => value['cacheHit'] == false)
            .length,
        'prunedEntries': artifacts.fold<int>(
          0,
          (sum, value) => sum + (value['cachePrunedEntries'] as int? ?? 0),
        ),
        'prunedBytes': artifacts.fold<int>(
          0,
          (sum, value) => sum + (value['cachePrunedBytes'] as int? ?? 0),
        ),
        'cacheBytesBefore': cacheBytesBefore,
        'cacheBytesAfter': cacheBytesAfter,
        'freeBytesBefore': freeBytesBefore,
        'freeBytesAfter': freeBytesAfter,
        'artifacts': artifacts,
      }),
    );
  } on Object catch (error) {
    stderr.writeln(
      error is IsolatedE2eAppBuildException
          ? error.message
          : error is FormatException
          ? error.message
          : error is FileSystemException
          ? '${error.runtimeType}: ${error.message}: ${error.path ?? '<unknown>'}'
          : 'App artifact prepare failed: ${error.runtimeType}',
    );
    exitCode = 2;
  }
}

Set<String> _loadPreviousCompileKeys(
  File file, {
  required String platform,
  required String processArchitecture,
}) {
  if (!file.existsSync()) {
    return const <String>{};
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map ||
      decoded['schemaVersion'] != 1 ||
      decoded['platform'] != platform ||
      decoded['processArchitecture'] != processArchitecture ||
      decoded['compileKeys'] is! List) {
    throw const FormatException('Previous App artifact DAG is invalid.');
  }
  final values = (decoded['compileKeys'] as List).cast<Object?>();
  if (values.any(
        (value) =>
            value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value),
      ) ||
      values.toSet().length != values.length) {
    throw const FormatException('Previous App artifact DAG keys are invalid.');
  }
  return values.cast<String>().toSet();
}

void _writeSuccessfulDag(
  File file, {
  required String platform,
  required String processArchitecture,
  required Set<String> compileKeys,
}) {
  file.parent.createSync(recursive: true);
  final temporary = File('${file.path}.tmp');
  final sortedKeys = compileKeys.toList()..sort();
  temporary.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schemaVersion': 1,
      'platform': platform,
      'processArchitecture': processArchitecture,
      'compileKeys': sortedKeys,
    }),
    flush: true,
  );
  if (file.existsSync()) {
    file.deleteSync();
  }
  temporary.renameSync(file.path);
}

final class _PrepareOptions {
  const _PrepareOptions({
    required this.names,
    required this.artifactRoot,
    required this.platform,
    required this.flutterBin,
  });

  final List<String> names;
  final Directory artifactRoot;
  final IsolatedE2eAppPlatform platform;
  final String flutterBin;

  factory _PrepareOptions.parse(List<String> arguments) {
    final values = <String, String>{};
    for (final argument in arguments) {
      final separator = argument.indexOf('=');
      if (!argument.startsWith('--') || separator <= 2) {
        throw const FormatException('Prepare arguments must use --name=value.');
      }
      final key = argument.substring(2, separator);
      final value = argument.substring(separator + 1).trim();
      if (!const <String>{
        'names',
        'artifact-root',
        'platform',
        'flutter-bin',
      }.contains(key)) {
        throw FormatException('Unknown App artifact prepare option: --$key');
      }
      if (value.isEmpty || values.containsKey(key)) {
        throw FormatException('App artifact prepare option --$key is invalid.');
      }
      values[key] = value;
    }
    final names = (values['names'] ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (names.isEmpty || names.length != names.toSet().length) {
      throw const FormatException(
        'App artifact prepare names must be non-empty and unique.',
      );
    }
    names.sort();
    final artifactRoot = values['artifact-root'];
    if (artifactRoot == null) {
      throw const FormatException('App artifact prepare root is required.');
    }
    return _PrepareOptions(
      names: List<String>.unmodifiable(names),
      artifactRoot: Directory(artifactRoot).absolute,
      platform: IsolatedE2eAppPlatform.parse(values['platform'] ?? ''),
      flutterBin: values['flutter-bin'] ?? 'flutter',
    );
  }
}
