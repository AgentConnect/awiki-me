// [INPUT]: Builder manifests, verified App bundles, role roots, and exclusive desktop lease.
// [OUTPUT]: Validated artifacts plus bounded App/driver process lifecycle helpers.
// [POS]: App artifact/runtime support shared by prepared and App-pair scenarios.

part of '../runner.dart';

class _IsolatedAppArtifact {
  const _IsolatedAppArtifact({
    required this.role,
    required this.target,
    required this.bundleId,
    required this.appDirectory,
    required this.executable,
    required this.fingerprint,
    required this.cacheHit,
    required this.artifactSha256,
  });

  final String role;
  final String target;
  final String bundleId;
  final Directory appDirectory;
  final File executable;
  final String fingerprint;
  final bool cacheHit;
  final String artifactSha256;

  static _IsolatedAppArtifact fromBuilderOutput(String output) {
    Object? decoded;
    try {
      decoded = jsonDecode(output.trim());
    } on Object {
      throw E2eFailure(
        'The isolated App builder returned an invalid artifact manifest.',
      );
    }
    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      throw E2eFailure(
        'The isolated App builder returned an unsupported artifact manifest.',
      );
    }
    final role = decoded['name'];
    final target = decoded['target'];
    final bundleId = decoded['bundleId'];
    final appPath = decoded['appPath'];
    final executablePath = decoded['executablePath'];
    final fingerprint = decoded['fingerprint'];
    final cacheHit = decoded['cacheHit'];
    final artifactSha256 = decoded['artifactSha256'];
    if (role is! String ||
        !RegExp(r'^[a-z][a-z0-9-]{0,31}$').hasMatch(role) ||
        target is! String ||
        !target.startsWith('integration_test/') ||
        !target.endsWith('_test.dart') ||
        target.contains('..') ||
        bundleId is! String ||
        !RegExp(
          r'^[a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+$',
        ).hasMatch(bundleId) ||
        appPath is! String ||
        appPath.trim().isEmpty ||
        executablePath is! String ||
        executablePath.trim().isEmpty ||
        fingerprint is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint) ||
        cacheHit is! bool ||
        artifactSha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactSha256)) {
      throw E2eFailure('The isolated App artifact manifest is incomplete.');
    }
    final executable = File(executablePath);
    if (!executable.existsSync()) {
      throw E2eFailure('The isolated App executable was not produced.');
    }
    return _IsolatedAppArtifact(
      role: role,
      target: target,
      bundleId: bundleId,
      appDirectory: Directory(appPath),
      executable: executable,
      fingerprint: fingerprint,
      cacheHit: cacheHit,
      artifactSha256: artifactSha256,
    );
  }
}

class _RunningIsolatedApp {
  _RunningIsolatedApp._({
    required this.role,
    required this.vmServiceUri,
    required this.process,
    required this.stdoutSubscription,
    required this.stderrSubscription,
  });

  final String role;
  final Uri vmServiceUri;
  final Process process;
  final StreamSubscription<String> stdoutSubscription;
  final StreamSubscription<String> stderrSubscription;

  static Future<_RunningIsolatedApp> start({
    required String role,
    required _IsolatedAppArtifact artifact,
    required Map<String, String> environment,
    required DesktopE2ePlatform platform,
  }) async {
    if (artifact.role != role) {
      throw E2eFailure('The isolated App role does not match its artifact.');
    }
    final executable = platform == DesktopE2ePlatform.linux
        ? 'xvfb-run'
        : artifact.executable.path;
    final arguments = platform == DesktopE2ePlatform.linux
        ? <String>[
            '-a',
            '--server-args=-screen 0 1280x720x24 -nolisten tcp',
            artifact.executable.path,
            '--enable-vm-service=0',
          ]
        : const <String>['--enable-vm-service=0'];
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    final service = Completer<Uri>();

    void inspect(String line) {
      if (service.isCompleted) {
        return;
      }
      final match = RegExp(r'http://[^\s]+').firstMatch(line);
      final uri = match == null ? null : Uri.tryParse(match.group(0)!);
      if (uri != null &&
          uri.scheme == 'http' &&
          (uri.host == InternetAddress.loopbackIPv4.address ||
              uri.host == 'localhost') &&
          uri.hasPort) {
        service.complete(uri);
      }
    }

    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(inspect);
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(inspect);
    unawaited(
      process.exitCode.then((code) {
        if (!service.isCompleted) {
          service.completeError(
            E2eFailure(
              'The isolated $role App exited before publishing a VM service.',
            ),
          );
        }
      }),
    );

    try {
      final vmServiceUri = await service.future.timeout(
        const Duration(seconds: 45),
      );
      return _RunningIsolatedApp._(
        role: role,
        vmServiceUri: vmServiceUri,
        process: process,
        stdoutSubscription: stdoutSubscription,
        stderrSubscription: stderrSubscription,
      );
    } on Object {
      process.kill(ProcessSignal.sigkill);
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      rethrow;
    }
  }

  Future<void> close(DesktopCommandRunner commands) async {
    await commands.terminateProcessTree(process);
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}

class _RunningAppPairDriver {
  _RunningAppPairDriver._({
    required this.process,
    required this.stdoutSubscription,
    required this.stderrSubscription,
    required List<String> diagnosticLines,
  }) : _diagnosticLines = diagnosticLines;

  static const int _maximumDiagnosticLines = 80;

  final Process process;
  final StreamSubscription<String> stdoutSubscription;
  final StreamSubscription<String> stderrSubscription;
  final List<String> _diagnosticLines;

  Future<int> get exitCode => process.exitCode;

  String get diagnosticTail => _diagnosticLines.isEmpty
      ? 'No sanitized driver output.'
      : _diagnosticLines.join('\n');

  static Future<_RunningAppPairDriver> start({
    required String role,
    required String flutterBin,
    required Uri vmServiceUri,
    required Directory root,
    required Directory flutterConfigDirectory,
    required String locale,
    required DesktopE2ePlatform platform,
    required DesktopSecretRedactor redactor,
  }) async {
    if (!appPairRoles.contains(role)) {
      throw E2eFailure('The App-pair driver role is invalid.');
    }
    final flutterArguments = <String>[
      'drive',
      '--use-existing-app=$vmServiceUri',
      '--driver=test_driver/integration_test.dart',
      '--target=$_multiDeviceAppPairTarget',
      '-d',
      platform.name,
      '--no-build',
      '--no-pub',
      '--no-keep-app-running',
    ];
    final executable = platform == DesktopE2ePlatform.linux
        ? 'xvfb-run'
        : flutterBin;
    final arguments = platform == DesktopE2ePlatform.linux
        ? <String>[
            '-a',
            '--server-args=-screen 0 1280x720x24 -nolisten tcp',
            flutterBin,
            ...flutterArguments,
          ]
        : flutterArguments;
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: root.path,
      environment: <String, String>{
        'LANG': locale,
        'LC_ALL': locale,
        'XDG_CONFIG_HOME': flutterConfigDirectory.path,
      },
      includeParentEnvironment: true,
      runInShell: false,
    );
    final diagnosticLines = <String>[];
    void record(String stream, String line) {
      final sanitized = sanitizeAppPairDriverDiagnostic(line, redactor).trim();
      if (sanitized.isEmpty) {
        return;
      }
      diagnosticLines.add('$stream: $sanitized');
      if (diagnosticLines.length > _maximumDiagnosticLines) {
        diagnosticLines.removeRange(
          0,
          diagnosticLines.length - _maximumDiagnosticLines,
        );
      }
    }

    return _RunningAppPairDriver._(
      process: process,
      stdoutSubscription: process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => record('stdout', line)),
      stderrSubscription: process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => record('stderr', line)),
      diagnosticLines: diagnosticLines,
    );
  }

  Future<void> close(DesktopCommandRunner commands) async {
    await commands.terminateProcessTree(process);
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();
  }
}

String _newAppPairToken() {
  final random = Random.secure();
  return List<int>.generate(
    32,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

Future<void> _deleteDirectoryBestEffort(Directory directory) async {
  try {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  } on FileSystemException {
    // Remote identities are not deleted here; this only removes isolated
    // local App state after both product processes have stopped.
  }
}

void resetAppPairRuntimeDirectories({
  required bool functional,
  bool contentSync = false,
  required Directory adminStateRoot,
  required Directory joinerStateRoot,
  required Directory daemonStateRoot,
  required Directory cliWorkspace,
  required Directory cliHome,
}) {
  final directories = <Directory>[
    adminStateRoot,
    joinerStateRoot,
    if (functional) daemonStateRoot,
    if (functional || contentSync) ...<Directory>[cliWorkspace, cliHome],
  ];
  for (final directory in directories) {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    directory.createSync(recursive: true);
  }
}

Future<List<int>> competingFlutterIntegrationTestPids() async {
  if (Platform.isWindows) {
    return const <int>[];
  }
  final result = await Process.run('ps', const <String>[
    '-axo',
    'pid=,command=',
  ]);
  if (result.exitCode != 0) {
    return const <int>[];
  }
  return competingFlutterIntegrationTestPidsFromPs(result.stdout.toString());
}

List<int> competingFlutterIntegrationTestPidsFromPs(String output) {
  final pids = <int>[];
  for (final line in const LineSplitter().convert(output)) {
    final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
    if (match == null) {
      continue;
    }
    final command = match.group(2)!;
    if (!command.contains('flutter_tools.snapshot') ||
        !command.contains(' test ') ||
        !command.contains('integration_test/')) {
      continue;
    }
    final candidatePid = int.tryParse(match.group(1)!);
    if (candidatePid != null && candidatePid != pid) {
      pids.add(candidatePid);
    }
  }
  return pids;
}

Future<T> _withFlutterExecutionLease<T>(
  DesktopE2ePlatform platform,
  String runId,
  Future<T> Function() action,
) async {
  final lockFile = File(
    '${Directory.systemTemp.path}/awiki-me-e2e-${platform.name}.lock',
  );
  await lockFile.parent.create(recursive: true);
  final handle = await lockFile.open(mode: FileMode.append);
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var acquired = false;
  try {
    while (!acquired && DateTime.now().isBefore(deadline)) {
      try {
        await handle.lock(FileLock.exclusive);
        acquired = true;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    if (!acquired) {
      throw E2eFailure(
        'Timed out waiting for the exclusive Flutter desktop E2E lease '
        'for ${platform.name}.',
      );
    }
    await handle.setPosition(0);
    await handle.truncate(0);
    await handle.writeFrom(
      utf8.encode(
        'pid=$pid\nrunId=$runId\nstartedAt=${DateTime.now().toUtc().toIso8601String()}\n',
      ),
    );
    await handle.flush();
    return await action();
  } finally {
    if (acquired) {
      await handle.unlock();
    }
    await handle.close();
  }
}
