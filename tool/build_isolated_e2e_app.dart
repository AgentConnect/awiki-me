// [INPUT]: One E2E target, isolated runtime/artifact roots, a reusable role build root, bundle identity, and stable Dart defines.
// [OUTPUT]: A signed Debug macOS App bundle plus a machine-readable artifact manifest.
// [POS]: Reusable incremental build boundary for E2E modes that need concurrently runnable App processes.

import 'dart:convert';
import 'dart:io';

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
      flutterBin: flutterBin,
      dartDefines: dartDefines,
      dryRun: dryRun,
    );
  }

  IsolatedE2eAppBuildPlan toPlan() {
    final buildDirectory = Directory('${workRoot.path}/flutter-build');
    final flutterConfigDirectory = Directory('${workRoot.path}/flutter-config');
    final overrideConfig = File('${workRoot.path}/AppPair.xcconfig');
    final sourceApp = Directory(
      '${buildDirectory.path}/macos/Build/Products/Debug/AWikiMe.app',
    );
    final artifactApp = Directory('${artifactRoot.path}/AWikiMe-$name.app');
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
      executable: File('${artifactApp.path}/Contents/MacOS/AWikiMe'),
      manifest: File('${artifactRoot.path}/$name.json'),
      flutterArguments: <String>[
        'build',
        'macos',
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
  });

  final String name;
  final String target;
  final String bundleId;
  final String appPath;
  final String executablePath;
  final String stateRoot;
  final String buildDirectory;
  final bool dryRun;

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
  };
}

class IsolatedE2eAppBuilder {
  Future<IsolatedE2eAppArtifact> build(
    IsolatedE2eAppBuildRequest request,
  ) async {
    if (!Platform.isMacOS && !request.dryRun) {
      throw const IsolatedE2eAppBuildException(
        'Isolated E2E App builds currently require macOS.',
      );
    }
    final plan = request.toPlan();
    final artifact = IsolatedE2eAppArtifact(
      name: request.name,
      target: request.target,
      bundleId: request.bundleId,
      appPath: plan.artifactApp.path,
      executablePath: plan.executable.path,
      stateRoot: request.stateRoot.path,
      buildDirectory: plan.buildDirectory.path,
      dryRun: request.dryRun,
    );
    if (request.dryRun) {
      return artifact;
    }

    request.stateRoot.createSync(recursive: true);
    request.workRoot.createSync(recursive: true);
    request.artifactRoot.createSync(recursive: true);
    plan.flutterConfigDirectory.createSync(recursive: true);
    plan.flutterSettingsFile.writeAsStringSync(
      jsonEncode(<String, Object?>{
        'build-dir': plan.flutterBuildDirectorySetting,
        'enable-macos-desktop': true,
      }),
      flush: true,
    );
    plan.overrideConfig.writeAsStringSync(
      'AWIKI_MACOS_DEV_BUNDLE_ID = ${request.bundleId}\n'
      'AWIKI_APP_DISPLAY_NAME = AWikiMe E2E ${request.name}\n',
      flush: true,
    );

    final build = await Process.run(
      request.flutterBin,
      plan.flutterArguments,
      workingDirectory: request.projectRoot.path,
      environment: <String, String>{
        ...Platform.environment,
        'LANG': 'en_US.UTF-8',
        'LC_ALL': 'en_US.UTF-8',
        'XDG_CONFIG_HOME': plan.flutterConfigDirectory.path,
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
    final copy = await Process.run('/usr/bin/ditto', <String>[
      plan.sourceApp.path,
      plan.artifactApp.path,
    ]);
    if (copy.exitCode != 0 || !plan.executable.existsSync()) {
      throw IsolatedE2eAppBuildException(
        'The isolated App artifact copy failed for ${request.name}.',
      );
    }
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
        architectures.stdout.toString().trim() != 'x86_64') {
      throw const IsolatedE2eAppBuildException(
        'The isolated Debug App must contain only x86_64 on this host.',
      );
    }
    plan.manifest.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(artifact.toJson()),
      flush: true,
    );
    return artifact;
  }
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
