import 'dart:async';
import 'dart:io';

import 'src/agent_im_config.dart';
import 'src/cli_peer_adapter.dart';
import 'src/e2e_report.dart';
import 'src/scenario_registry.dart';
import 'src/secret_redactor.dart';
import '../scenarios/agent_im_delegated_message/delegated_message_scenario.dart';

Future<void> main(List<String> args) async {
  try {
    final options = DesktopE2eOptions.parse(args);
    if (options.help) {
      DesktopE2eOptions.printUsage();
      return;
    }

    final root = Directory.current;
    final agentImConfig = options.configPath == null
        ? null
        : AgentImDelegatedConfig.load(File(options.configPath!));
    final platform = options.platform ?? DesktopE2ePlatform.fromHost();
    if (agentImConfig != null && agentImConfig.app.platform != platform.name) {
      throw DesktopE2eFailure(
        'Config app.platform (${agentImConfig.app.platform}) must match '
        '--platform (${platform.name}).',
      );
    }
    final config = DesktopE2eConfig.fromEnvironment(
      root,
      platform,
      agentImConfig: agentImConfig,
    );
    final runner = DesktopE2eRunner(
      root: root,
      platform: platform,
      config: config,
      options: options,
      agentImConfig: agentImConfig,
    );
    await runner.run();
  } on AgentImConfigFailure catch (error) {
    stderr.writeln('\nDesktop E2E failed: ${error.message}');
    exitCode = 1;
  } on AgentImCliPeerFailure catch (error) {
    stderr.writeln('\nDesktop E2E failed: ${error.message}');
    exitCode = 1;
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
    this.agentImConfig,
  }) : commands = DesktopCommandRunner(
         dryRun: options.dryRun,
         redactor: const SecretRedactor(),
       );

  final Directory root;
  final DesktopE2ePlatform platform;
  final DesktopE2eConfig config;
  final DesktopE2eOptions options;
  final AgentImDelegatedConfig? agentImConfig;
  final DesktopCommandRunner commands;

  late final String runId;
  late final Directory reportDir;
  late final Directory cliWorkspaceDir;
  late final Directory agentImCliPeerWorkspaceDir;
  late final E2eReportWriter reportWriter;
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
    reportWriter = E2eReportWriter(directory: reportDir);
    cliWorkspaceDir = Directory(
      '${root.path}/.e2e/${platform.name}/cli-workspaces/$runId',
    )..createSync(recursive: true);
    agentImCliPeerWorkspaceDir = Directory('${cliWorkspaceDir.path}/peer-b');
    final totalStopwatch = Stopwatch()..start();
    var succeeded = false;

    try {
      _section('AWiki Me ${platform.label} E2E $runId');
      _line('app root: ${root.path}');
      _line('platform: ${platform.name}');
      _line('cli repo: ${config.cliRepo.path}');
      _line('base URL: ${config.baseUrl}');
      _line('DID domain: ${config.didDomain}');
      if (options.scenario != null) {
        _line('scenario: ${options.scenario}');
        _line('scenario config: ${options.configPath}');
      }
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
      if (options.scenario != null) {
        await _timed('Agent IM scenario plan', _agentImScenarioPlan);
      }
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

  Future<void> _agentImScenarioPlan() async {
    final scenario = options.scenario;
    if (scenario == null) {
      return;
    }
    if (agentImConfig == null) {
      throw DesktopE2eFailure(
        '--config is required when --scenario=$scenario is used.',
      );
    }
    const registry = E2eScenarioRegistry();
    if (!registry.supports(scenario)) {
      throw DesktopE2eFailure(
        'Unsupported scenario "$scenario". '
        'Supported: $agentImDelegatedMessageScenario.',
      );
    }
    final plan = registry.buildAgentImPlan(
      runId: runId,
      platform: platform.name,
      config: agentImConfig!,
      cliBinaryPath: config.cliBinaryPath,
      cliPeerWorkspace: agentImCliPeerWorkspaceDir.path,
      ordinaryMessageText: _agentImOrdinaryMessageText(),
    );
    reportWriter.writeJson('scenario-plan.json', plan.toJson());
    reportWriter.writeJson('cli-peer-plan.json', plan.cliPeerPlan.toJson());
    for (final step in plan.steps) {
      _line('[plan] ${step.name}: ${step.detail}');
    }
    for (final command in plan.cliPeerPlan.commands) {
      _line(
        '[cli-peer-plan] ${command.label}: '
        '${command.toJson(plan.cliPeerPlan.binary)['command']}',
      );
    }
    for (final command in plan.remoteCommands) {
      _line('[remote-plan] ${command.label}: ${command.command}');
    }
    _line('scenario plan: ${reportDir.path}/scenario-plan.json');
    _line('cli peer plan: ${reportDir.path}/cli-peer-plan.json');
    final adapter = _agentImCliPeerAdapter(agentImConfig!);
    final scenarioResult =
        await AgentImDelegatedMessageScenario(config: agentImConfig!).run(
          runId: runId,
          platform: platform.name,
          dryRun: options.dryRun,
          reportDir: reportDir,
          cliWorkspaceDir: agentImCliPeerWorkspaceDir,
          remoteCommands: plan.remoteCommands,
          cliPeerFlow: options.dryRun
              ? null
              : () => adapter.runOrdinaryMessageFlow(
                  runId: runId,
                  targetHandle: agentImConfig!.accounts.appUser.handle,
                  messageText: _agentImOrdinaryMessageText(),
                ),
        );
    reportWriter.writeJson(
      'agent-im-scenario-result.json',
      scenarioResult.toJson(),
    );
    for (final item in scenarioResult.cases) {
      _line(
        '[scenario] ${item.id} ${item.status}: '
        '${item.reason ?? item.evidence.join('; ')}',
      );
    }
    _line(
      'agent im scenario result: '
      '${reportDir.path}/agent-im-scenario-result.json',
    );
    if (scenarioResult.hasBlockingFailure) {
      throw DesktopE2eFailure(
        'Agent IM scenario reported blocking failure. See '
        '${reportDir.path}/agent-im-scenario-result.json',
      );
    }
  }

  AgentImCliPeerAdapter _agentImCliPeerAdapter(
    AgentImDelegatedConfig scenarioConfig,
  ) {
    return AgentImCliPeerAdapter(
      config: scenarioConfig,
      cliRepo: config.cliRepo,
      binary: File(config.cliBinaryPath),
      workspace: agentImCliPeerWorkspaceDir,
      reportDir: reportDir,
      runner: commands,
      dryRun: options.dryRun,
    );
  }

  String _agentImOrdinaryMessageText() =>
      AgentImCliPeerAdapterPlan.defaultOrdinaryMessageText(runId);

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
    reportWriter.writeJson('timings.json', payload);
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
    this.agentImConfig,
  });

  factory DesktopE2eConfig.fromEnvironment(
    Directory root,
    DesktopE2ePlatform platform, {
    AgentImDelegatedConfig? agentImConfig,
  }) {
    final env = Platform.environment;
    final prefix = platform == DesktopE2ePlatform.macos
        ? 'AWIKI_MACOS_E2E'
        : 'AWIKI_LINUX_E2E';
    String? envValue(String suffix) {
      return env['${prefix}_$suffix'] ?? env['AWIKI_DESKTOP_E2E_$suffix'];
    }

    final cliRepo = Directory(
      _resolvePath(
        root.path,
        envValue('CLI_REPO') ??
            agentImConfig?.cliPeer.repo ??
            '../awiki-cli-rs2',
      ),
    );
    final flutterExecutable = _firstNonEmpty(
      envValue('FLUTTER'),
      _firstNonEmpty(env['FLUTTER'], _defaultFlutterExecutable()),
    );
    final baseUrl = _normalizeBaseUrl(
      _firstNonEmpty(
        envValue('BASE_URL'),
        _firstNonEmpty(
          env['AWIKI_BASE_URL'],
          agentImConfig?.service.baseUrl ?? 'https://awiki.info',
        ),
      ),
    );
    final didDomain = _firstNonEmpty(
      envValue('DID_DOMAIN'),
      _firstNonEmpty(
        env['AWIKI_DID_DOMAIN'],
        agentImConfig?.service.didDomain ?? Uri.parse(baseUrl).host,
      ),
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
      agentImConfig: agentImConfig,
    );
  }

  final Directory cliRepo;
  final String flutterExecutable;
  final String baseUrl;
  final String didDomain;
  final String pubHostedUrl;
  final bool otpConfigured;
  final AgentImDelegatedConfig? agentImConfig;

  String get cliBinaryPath {
    final binary = agentImConfig?.cliPeer.binary ?? 'target/debug/awiki-cli';
    if (binary.startsWith('/')) {
      return File(binary).absolute.path;
    }
    return File('${cliRepo.path}/$binary').absolute.path;
  }

  String get anpServiceEndpoint => '$baseUrl/anp-im/rpc';

  String get anpServiceDid => 'did:wba:$didDomain';
}

class DesktopE2eOptions {
  const DesktopE2eOptions({
    required this.platform,
    required this.dryRun,
    required this.scenario,
    required this.configPath,
    required this.skipCliBuild,
    required this.runPubGet,
    required this.skipFlutterSmoke,
    required this.help,
  });

  factory DesktopE2eOptions.parse(List<String> args) {
    DesktopE2ePlatform? platform;
    var dryRun = false;
    String? scenario;
    String? configPath;
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
      if (arg == '--scenario') {
        index += 1;
        if (index >= args.length) {
          throw DesktopE2eFailure('--scenario requires a value.');
        }
        scenario = args[index].trim();
        continue;
      }
      if (arg.startsWith('--scenario=')) {
        scenario = arg.substring('--scenario='.length).trim();
        continue;
      }
      if (arg == '--config') {
        index += 1;
        if (index >= args.length) {
          throw DesktopE2eFailure('--config requires a path.');
        }
        configPath = args[index].trim();
        continue;
      }
      if (arg.startsWith('--config=')) {
        configPath = arg.substring('--config='.length).trim();
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
      scenario: scenario?.isEmpty == true ? null : scenario,
      configPath: configPath?.isEmpty == true ? null : configPath,
      skipCliBuild: skipCliBuild,
      runPubGet: runPubGet,
      skipFlutterSmoke: skipFlutterSmoke,
      help: help,
    );
  }

  final DesktopE2ePlatform? platform;
  final bool dryRun;
  final String? scenario;
  final String? configPath;
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
  --scenario=<name>         Run a named E2E scenario plan.
  --config=<path>           Scenario config path, for example
                            tests/e2e_test/configs/agent_im_delegated.example.yaml.
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

class DesktopCommandRunner implements AgentImCliCommandRunner {
  const DesktopCommandRunner({
    required this.dryRun,
    this.redactor = const SecretRedactor(),
  });

  final bool dryRun;
  final SecretRedactor redactor;

  @override
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
    _line('\$ ${redactor.redact(commandLine)}');
    if (dryRun) {
      if (logFile != null) {
        logFile.createSync(recursive: true);
        logFile.writeAsStringSync(redactor.redact('[dry-run] $commandLine\n'));
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
    final redactedStdout = redactor.redact(stdoutText);
    final redactedStderr = redactor.redact(stderrText);
    if (logFile != null) {
      logFile.createSync(recursive: true);
      logFile.writeAsStringSync(
        redactor.redact(
          'command: $commandLine\n'
          'cwd: ${workingDirectory.path}\n'
          'exitCode: ${result.exitCode}\n\n'
          '--- stdout ---\n$stdoutText\n'
          '--- stderr ---\n$stderrText\n',
        ),
      );
    }
    if (redactedStdout.trim().isNotEmpty) {
      stdout.write(redactedStdout);
      if (!redactedStdout.endsWith('\n')) {
        stdout.writeln();
      }
    }
    if (redactedStderr.trim().isNotEmpty) {
      stderr.write(redactedStderr);
      if (!redactedStderr.endsWith('\n')) {
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

class DesktopCommandResult extends AgentImCliCommandResult {
  const DesktopCommandResult({
    required super.exitCode,
    required super.stdoutText,
    required super.stderrText,
  });
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
