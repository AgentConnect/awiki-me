import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  try {
    final options = DesktopE2eOptions.parse(args);
    if (options.help) {
      DesktopE2eOptions.printUsage();
      return;
    }

    final root = Directory.current;
    final platform = options.platform ?? DesktopE2ePlatform.fromHost();
    final config = DesktopE2eConfig.fromEnvironment(root, platform);
    final runner = DesktopE2eRunner(
      root: root,
      platform: platform,
      config: config,
      options: options,
    );
    await runner.run();
  } on DesktopE2eFailure catch (error) {
    stderr.writeln('\nDesktop E2E failed: ${error.message}');
    exitCode = 1;
  }
}

class DesktopE2eRunner {
  DesktopE2eRunner({
    required this.root,
    required this.platform,
    required this.config,
    required this.options,
  }) : commands = DesktopCommandRunner(dryRun: options.dryRun);

  final Directory root;
  final DesktopE2ePlatform platform;
  final DesktopE2eConfig config;
  final DesktopE2eOptions options;
  final DesktopCommandRunner commands;

  late final String runId;
  late final Directory reportDir;
  late final Directory cliWorkspaceDir;
  final List<DesktopE2eTimingEntry> _timings = <DesktopE2eTimingEntry>[];

  Future<void> run() async {
    if (!File('${root.path}/pubspec.yaml').existsSync()) {
      throw DesktopE2eFailure(
        'Run this tool from the awiki-me repository root.',
      );
    }

    runId = _newRunId();
    reportDir = Directory('${root.path}/.e2e/${platform.name}/reports/$runId')
      ..createSync(recursive: true);
    cliWorkspaceDir = Directory(
      '${root.path}/.e2e/${platform.name}/cli-workspaces/$runId',
    )..createSync(recursive: true);
    final totalStopwatch = Stopwatch()..start();
    var succeeded = false;

    try {
      _section('AWiki Me ${platform.label} E2E $runId');
      _line('app root: ${root.path}');
      _line('platform: ${platform.name}');
      _line('cli repo: ${config.cliRepo.path}');
      _line('base URL: ${config.baseUrl}');
      _line('DID domain: ${config.didDomain}');
      _line('Flutter: ${config.flutterExecutable}');
      _line('OTP: ${config.otpConfigured ? 'configured' : 'not configured'}');
      _line('reports: ${reportDir.path}');

      await _timed('Checking desktop tooling', _checkTooling);
      if (options.runPubGet) {
        await _timed('Flutter pub get', _flutterPubGet);
      }
      if (!options.skipCliBuild) {
        await _timed('Build awiki-cli-rs2 CLI', _buildCli);
      }
      await _timed('CLI isolated workspace smoke', _cliSmoke);
      if (!options.skipFlutterSmoke) {
        await _timed('Flutter ${platform.label} native smoke', _flutterSmoke);
      }

      _section('Desktop E2E completed');
      _line('runId: $runId');
      _line('cli workspace: ${cliWorkspaceDir.path}');
      succeeded = true;
    } finally {
      totalStopwatch.stop();
      _writeTimingReport(succeeded: succeeded, elapsed: totalStopwatch.elapsed);
      _printTimingSummary(
        succeeded: succeeded,
        elapsed: totalStopwatch.elapsed,
      );
    }
  }

  Future<void> _checkTooling() async {
    if (!Directory(config.cliRepo.path).existsSync()) {
      throw DesktopE2eFailure('CLI repo not found: ${config.cliRepo.path}');
    }
    await commands.run(
      config.flutterExecutable,
      const <String>['--version'],
      workingDirectory: root,
      logFile: File('${reportDir.path}/flutter-version.log'),
      timeout: const Duration(minutes: 1),
    );
    await commands.run(
      'cargo',
      const <String>['--version'],
      workingDirectory: config.cliRepo,
      logFile: File('${reportDir.path}/cargo-version.log'),
      timeout: const Duration(minutes: 1),
    );
    switch (platform) {
      case DesktopE2ePlatform.macos:
        await commands.run(
          'xcrun',
          const <String>['--version'],
          workingDirectory: root,
          logFile: File('${reportDir.path}/xcrun-version.log'),
          timeout: const Duration(minutes: 1),
        );
      case DesktopE2ePlatform.linux:
        for (final executable in const <String>[
          'xvfb-run',
          'clang',
          'cmake',
          'ninja',
          'pkg-config',
        ]) {
          await commands.run(
            'which',
            <String>[executable],
            workingDirectory: root,
            logFile: File('${reportDir.path}/which-$executable.log'),
            timeout: const Duration(minutes: 1),
          );
        }
    }
  }

  Future<void> _flutterPubGet() async {
    await commands.run(
      config.flutterExecutable,
      const <String>['pub', 'get'],
      workingDirectory: root,
      environment: <String, String>{'PUB_HOSTED_URL': config.pubHostedUrl},
      logFile: File('${reportDir.path}/flutter-pub-get.log'),
      timeout: const Duration(minutes: 10),
    );
  }

  Future<void> _buildCli() async {
    await commands.run(
      'cargo',
      const <String>['build', '-p', 'awiki-cli', '--bin', 'awiki-cli'],
      workingDirectory: config.cliRepo,
      logFile: File('${reportDir.path}/cli-build.log'),
      timeout: const Duration(minutes: 30),
    );
  }

  Future<void> _cliSmoke() async {
    final binary = File(config.cliBinaryPath);
    if (!options.dryRun && !binary.existsSync()) {
      throw DesktopE2eFailure(
        'CLI binary not found: ${binary.path}. Run without --skip-cli-build.',
      );
    }
    final env = <String, String>{
      'AWIKI_CLI_WORKSPACE_HOME_DIR': cliWorkspaceDir.path,
    };
    await commands.run(
      binary.path,
      const <String>['init'],
      workingDirectory: config.cliRepo,
      environment: env,
      logFile: File('${reportDir.path}/cli-init.log'),
      timeout: const Duration(minutes: 2),
    );
    if (options.dryRun) {
      _line(
        '[dry-run] would rewrite CLI config.yaml for ${config.baseUrl} / '
        '${config.didDomain}',
      );
    } else {
      _rewriteCliConfig();
    }
    await commands.run(
      binary.path,
      const <String>['config', 'show'],
      workingDirectory: config.cliRepo,
      environment: env,
      logFile: File('${reportDir.path}/cli-config-show.log'),
      timeout: const Duration(minutes: 2),
    );
    await commands.run(
      binary.path,
      const <String>['status'],
      workingDirectory: config.cliRepo,
      environment: env,
      logFile: File('${reportDir.path}/cli-status.log'),
      timeout: const Duration(minutes: 2),
    );
  }

  Future<void> _flutterSmoke() async {
    final flutterArgs = <String>[
      'test',
      'integration_test/im_core_open_smoke_test.dart',
      '-d',
      platform.flutterDevice,
      '--dart-define=AWIKI_BASE_URL=${config.baseUrl}',
      '--dart-define=AWIKI_SERVICE_BASE_URL=${config.baseUrl}',
      '--dart-define=AWIKI_DID_DOMAIN=${config.didDomain}',
      '--dart-define=AWIKI_ANP_SERVICE_URL=${config.anpServiceEndpoint}',
      '--dart-define=AWIKI_ANP_SERVICE_DID=${config.anpServiceDid}',
      '--dart-define=AWIKI_E2E=true',
    ];

    if (platform == DesktopE2ePlatform.linux) {
      await commands.run(
        'xvfb-run',
        <String>['-a', config.flutterExecutable, ...flutterArgs],
        workingDirectory: root,
        environment: <String, String>{'PUB_HOSTED_URL': config.pubHostedUrl},
        logFile: File('${reportDir.path}/flutter-linux-smoke.log'),
        timeout: const Duration(minutes: 20),
      );
      return;
    }

    await commands.run(
      config.flutterExecutable,
      flutterArgs,
      workingDirectory: root,
      environment: <String, String>{'PUB_HOSTED_URL': config.pubHostedUrl},
      logFile: File('${reportDir.path}/flutter-macos-smoke.log'),
      timeout: const Duration(minutes: 20),
    );
  }

  void _rewriteCliConfig() {
    final configFile = File('${cliWorkspaceDir.path}/config.yaml');
    if (!configFile.existsSync()) {
      throw DesktopE2eFailure(
        'CLI config file was not created: ${configFile.path}',
      );
    }
    var text = configFile.readAsStringSync();
    text = _replaceYamlValue(text, 'service_base_url', config.baseUrl);
    text = _replaceYamlValue(text, 'did_domain', config.didDomain);
    text = _replaceYamlValue(
      text,
      'anp_service_endpoint',
      config.anpServiceEndpoint,
    );
    text = _replaceYamlValue(text, 'anp_service_did', config.anpServiceDid);
    text = _replaceYamlValue(text, 'mail_service_url', config.baseUrl);
    configFile.writeAsStringSync(text);
  }

  Future<T> _timed<T>(String name, Future<T> Function() action) async {
    _section(name);
    final stopwatch = Stopwatch()..start();
    var succeeded = false;
    try {
      final result = await action();
      succeeded = true;
      return result;
    } finally {
      stopwatch.stop();
      _timings.add(
        DesktopE2eTimingEntry(
          name: name,
          elapsed: stopwatch.elapsed,
          succeeded: succeeded,
        ),
      );
      _line(
        'duration: ${_formatDuration(stopwatch.elapsed)}'
        '${succeeded ? '' : ' (failed)'}',
      );
    }
  }

  void _writeTimingReport({
    required bool succeeded,
    required Duration elapsed,
  }) {
    final payload = <String, Object?>{
      'runId': runId,
      'platform': platform.name,
      'succeeded': succeeded,
      'totalMs': elapsed.inMilliseconds,
      'appRoot': root.path,
      'cliRepo': config.cliRepo.path,
      'cliWorkspace': cliWorkspaceDir.path,
      'baseUrl': config.baseUrl,
      'didDomain': config.didDomain,
      'otpConfigured': config.otpConfigured,
      'steps': _timings.map((entry) => entry.toJson()).toList(),
    };
    File(
      '${reportDir.path}/timings.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
  }

  void _printTimingSummary({
    required bool succeeded,
    required Duration elapsed,
  }) {
    _section('Timing summary');
    for (final entry in _timings) {
      _line(
        '${entry.succeeded ? 'OK' : 'FAIL'} '
        '${entry.name}: ${_formatDuration(entry.elapsed)}',
      );
    }
    _line('total: ${_formatDuration(elapsed)}');
    _line('result: ${succeeded ? 'PASS' : 'FAIL'}');
    _line('timings: ${reportDir.path}/timings.json');
  }
}

class DesktopE2eConfig {
  const DesktopE2eConfig({
    required this.cliRepo,
    required this.flutterExecutable,
    required this.baseUrl,
    required this.didDomain,
    required this.pubHostedUrl,
    required this.otpConfigured,
  });

  factory DesktopE2eConfig.fromEnvironment(
    Directory root,
    DesktopE2ePlatform platform,
  ) {
    final env = Platform.environment;
    final prefix = platform == DesktopE2ePlatform.macos
        ? 'AWIKI_MACOS_E2E'
        : 'AWIKI_LINUX_E2E';
    String? envValue(String suffix) {
      return env['${prefix}_$suffix'] ?? env['AWIKI_DESKTOP_E2E_$suffix'];
    }

    final cliRepo = Directory(
      _resolvePath(root.path, envValue('CLI_REPO') ?? '../awiki-cli-rs2'),
    );
    final flutterExecutable = _firstNonEmpty(
      envValue('FLUTTER'),
      _firstNonEmpty(env['FLUTTER'], _defaultFlutterExecutable()),
    );
    final baseUrl = _normalizeBaseUrl(
      _firstNonEmpty(
        envValue('BASE_URL'),
        _firstNonEmpty(env['AWIKI_BASE_URL'], 'https://awiki.info'),
      ),
    );
    final didDomain = _firstNonEmpty(
      envValue('DID_DOMAIN'),
      _firstNonEmpty(env['AWIKI_DID_DOMAIN'], Uri.parse(baseUrl).host),
    );
    return DesktopE2eConfig(
      cliRepo: cliRepo,
      flutterExecutable: flutterExecutable,
      baseUrl: baseUrl,
      didDomain: didDomain,
      pubHostedUrl: _firstNonEmpty(
        env['PUB_HOSTED_URL'],
        'https://mirrors.tuna.tsinghua.edu.cn/dart-pub',
      ),
      otpConfigured:
          _firstNonEmpty(env['DEV_OTP_PHONE'], '').isNotEmpty &&
          _firstNonEmpty(env['DEV_OTP_CODE'], '').isNotEmpty,
    );
  }

  final Directory cliRepo;
  final String flutterExecutable;
  final String baseUrl;
  final String didDomain;
  final String pubHostedUrl;
  final bool otpConfigured;

  String get cliBinaryPath => '${cliRepo.path}/target/debug/awiki-cli';

  String get anpServiceEndpoint => '$baseUrl/anp-im/rpc';

  String get anpServiceDid => 'did:wba:$didDomain';
}

class DesktopE2eOptions {
  const DesktopE2eOptions({
    required this.platform,
    required this.dryRun,
    required this.skipCliBuild,
    required this.runPubGet,
    required this.skipFlutterSmoke,
    required this.help,
  });

  factory DesktopE2eOptions.parse(List<String> args) {
    DesktopE2ePlatform? platform;
    var dryRun = false;
    var skipCliBuild = false;
    var runPubGet = false;
    var skipFlutterSmoke = false;
    var help = false;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--platform') {
        index += 1;
        if (index >= args.length) {
          throw DesktopE2eFailure('--platform requires a value.');
        }
        platform = DesktopE2ePlatform.parse(args[index]);
        continue;
      }
      if (arg.startsWith('--platform=')) {
        platform = DesktopE2ePlatform.parse(
          arg.substring('--platform='.length),
        );
        continue;
      }
      switch (arg) {
        case '--dry-run':
          dryRun = true;
        case '--skip-cli-build':
          skipCliBuild = true;
        case '--pub-get':
          runPubGet = true;
        case '--skip-pub-get':
          runPubGet = false;
        case '--skip-flutter-smoke':
          skipFlutterSmoke = true;
        case '--help' || '-h':
          help = true;
        default:
          throw DesktopE2eFailure('Unknown argument: $arg');
      }
    }

    return DesktopE2eOptions(
      platform: platform,
      dryRun: dryRun,
      skipCliBuild: skipCliBuild,
      runPubGet: runPubGet,
      skipFlutterSmoke: skipFlutterSmoke,
      help: help,
    );
  }

  final DesktopE2ePlatform? platform;
  final bool dryRun;
  final bool skipCliBuild;
  final bool runPubGet;
  final bool skipFlutterSmoke;
  final bool help;

  static void printUsage() {
    stdout.writeln('''
Usage: dart run tests/e2e_test/harness/desktop_e2e_runner.dart [options]

Builds the shared desktop E2E smoke environment for macOS or Linux:
  1. Checks shared Flutter/Cargo tooling and platform-specific tools.
  2. Optionally runs flutter pub get.
  3. Builds awiki-cli-rs2's awiki-cli binary.
  4. Creates an isolated awiki-cli workspace under .e2e/<platform>/.
  5. Runs the desktop AwikiImCore.open integration smoke against AWIKI base URL.

Options:
  --platform=<macos|linux> Select desktop platform. Defaults to current host.
  --dry-run                Print commands without executing them.
  --pub-get                Run flutter pub get before validation.
  --skip-pub-get           Compatibility no-op; pub get is skipped by default.
  --skip-cli-build         Reuse awiki-cli-rs2/target/debug/awiki-cli.
  --skip-flutter-smoke     Skip flutter test -d <platform>.
  -h, --help               Show this help.

Environment:
  AWIKI_DESKTOP_E2E_FLUTTER    Flutter executable path.
  AWIKI_DESKTOP_E2E_CLI_REPO   awiki-cli-rs2 repo path (default: ../awiki-cli-rs2).
  AWIKI_DESKTOP_E2E_BASE_URL   Service base URL (default: https://awiki.info).
  AWIKI_DESKTOP_E2E_DID_DOMAIN DID domain (default: host of base URL).

  Platform-specific aliases are also supported:
  AWIKI_MACOS_E2E_* and AWIKI_LINUX_E2E_*.

  DEV_OTP_PHONE / DEV_OTP_CODE are detected for later live auth flows but are
  not printed or persisted by this runner.
''');
  }
}

enum DesktopE2ePlatform {
  macos,
  linux;

  static DesktopE2ePlatform parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'macos' || 'darwin' => DesktopE2ePlatform.macos,
      'linux' => DesktopE2ePlatform.linux,
      _ => throw DesktopE2eFailure(
        'Unsupported desktop E2E platform "$value". Use macos or linux.',
      ),
    };
  }

  static DesktopE2ePlatform fromHost() {
    if (Platform.isLinux) {
      return DesktopE2ePlatform.linux;
    }
    return DesktopE2ePlatform.macos;
  }

  String get label => switch (this) {
    DesktopE2ePlatform.macos => 'macOS',
    DesktopE2ePlatform.linux => 'Linux',
  };

  String get flutterDevice => switch (this) {
    DesktopE2ePlatform.macos => 'macos',
    DesktopE2ePlatform.linux => 'linux',
  };
}

class DesktopCommandRunner {
  const DesktopCommandRunner({required this.dryRun});

  final bool dryRun;

  Future<DesktopCommandResult> run(
    String executable,
    List<String> args, {
    required Directory workingDirectory,
    Map<String, String>? environment,
    File? logFile,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final commandLine = <String>[
      executable,
      ...args,
    ].map(_shellQuote).join(' ');
    _line('\$ $commandLine');
    if (dryRun) {
      if (logFile != null) {
        logFile.createSync(recursive: true);
        logFile.writeAsStringSync('[dry-run] $commandLine\n');
      }
      return const DesktopCommandResult(
        exitCode: 0,
        stdoutText: '',
        stderrText: '',
      );
    }

    late final ProcessResult result;
    try {
      result = await Process.run(
        executable,
        args,
        workingDirectory: workingDirectory.path,
        environment: environment,
        runInShell: false,
      ).timeout(timeout);
    } on TimeoutException {
      throw DesktopE2eFailure(
        'Command timed out after ${timeout.inSeconds}s: $commandLine',
      );
    } on ProcessException catch (error) {
      throw DesktopE2eFailure('Command failed to start: $commandLine\n$error');
    }

    final stdoutText = result.stdout.toString();
    final stderrText = result.stderr.toString();
    if (logFile != null) {
      logFile.createSync(recursive: true);
      logFile.writeAsStringSync(
        'command: $commandLine\n'
        'cwd: ${workingDirectory.path}\n'
        'exitCode: ${result.exitCode}\n\n'
        '--- stdout ---\n$stdoutText\n'
        '--- stderr ---\n$stderrText\n',
      );
    }
    if (stdoutText.trim().isNotEmpty) {
      stdout.write(stdoutText);
      if (!stdoutText.endsWith('\n')) {
        stdout.writeln();
      }
    }
    if (stderrText.trim().isNotEmpty) {
      stderr.write(stderrText);
      if (!stderrText.endsWith('\n')) {
        stderr.writeln();
      }
    }
    if (result.exitCode != 0) {
      final hint = logFile == null ? '' : ' See log: ${logFile.path}';
      throw DesktopE2eFailure(
        'Command exited with code ${result.exitCode}: $commandLine.$hint',
      );
    }
    return DesktopCommandResult(
      exitCode: result.exitCode,
      stdoutText: stdoutText,
      stderrText: stderrText,
    );
  }
}

class DesktopCommandResult {
  const DesktopCommandResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}

class DesktopE2eTimingEntry {
  const DesktopE2eTimingEntry({
    required this.name,
    required this.elapsed,
    required this.succeeded,
  });

  final String name;
  final Duration elapsed;
  final bool succeeded;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'ms': elapsed.inMilliseconds,
    'succeeded': succeeded,
  };
}

class DesktopE2eFailure implements Exception {
  DesktopE2eFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

String _replaceYamlValue(String text, String key, String value) {
  final lines = text.split('\n');
  var replaced = false;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('$key:')) {
      final indent = line.substring(0, line.length - trimmed.length);
      lines[index] = '$indent$key: $value';
      replaced = true;
    }
  }
  if (!replaced) {
    throw DesktopE2eFailure('Cannot find key "$key" in CLI config.yaml.');
  }
  return lines.join('\n');
}

String _newRunId() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  String three(int value) => value.toString().padLeft(3, '0');
  return '${now.year}${two(now.month)}${two(now.day)}T'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}'
      '${three(now.millisecond)}Z';
}

String _formatDuration(Duration duration) {
  if (duration.inMinutes >= 1) {
    final seconds = duration.inSeconds % 60;
    return '${duration.inMinutes}m${seconds.toString().padLeft(2, '0')}s';
  }
  if (duration.inSeconds >= 1) {
    return '${duration.inSeconds}.${(duration.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
  }
  return '${duration.inMilliseconds}ms';
}

String _resolvePath(String root, String path) {
  if (path.startsWith('/')) {
    return Directory(path).absolute.path;
  }
  return Directory('$root/$path').absolute.path;
}

String _defaultFlutterExecutable() {
  const knownLocalFlutter = '/Users/cs/development/flutter/bin/flutter';
  if (File(knownLocalFlutter).existsSync()) {
    return knownLocalFlutter;
  }
  return 'flutter';
}

String _normalizeBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'https://awiki.info';
  }
  return trimmed.replaceAll(RegExp(r'/+$'), '');
}

String _firstNonEmpty(String? value, String fallback) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}

String _shellQuote(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:=@+,-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

void _section(String title) {
  stdout.writeln('\n== $title ==');
}

void _line(String message) {
  stdout.writeln(message);
}
