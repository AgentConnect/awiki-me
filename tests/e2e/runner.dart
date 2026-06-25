import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const String _defaultDesktopE2eConfigPath = 'tests/e2e/configs/e2e.local.yaml';
const String _desktopCliPeerRunConfigPath =
    '.e2e/desktop-cli-peer/current/run_config.json';
const String _messageAgentRunConfigPath =
    '.e2e/message-agent/current/run_config.json';
const String _codexAgentRunConfigPath =
    '.e2e/codex-agent/current/run_config.json';
const String _claudeCodeAgentRunConfigPath =
    '.e2e/claude-code-agent/current/run_config.json';
const String _desktopCliPeerScenario = 'desktop-app-cli-peer';
const String _messageAgentScenario = 'message-agent-full-ui';
const String _codexAgentScenario = 'codex-agent-full-ui';
const String _claudeCodeAgentScenario = 'claude-code-agent-full-ui';
const List<String> _desktopCliPeerCaseIds = <String>[
  'AUTH-E2E-001',
  'MSG-E2E-001',
  'MSG-E2E-002',
  'MSG-REG-001',
  'GROUP-E2E-001',
  'GROUP-E2E-002',
  'GROUP-P9-001',
  'GROUP-P9-002',
  'GROUP-REG-001',
  'CONTACT-E2E-001',
  'CONTACT-E2E-002',
  'CONTACT-REG-001',
  'ATTACH-E2E-001',
  'ATTACH-E2E-002',
  'ATTACH-REG-001',
];
const List<String> _desktopSmokeCaseIds = <String>[
  'SMOKE-E2E-001',
  'NATIVE-E2E-001',
];
const List<String> _desktopCliPeerGroupCaseIds = <String>[
  'AUTH-E2E-001',
  'GROUP-E2E-001',
  'GROUP-E2E-002',
  'GROUP-P9-001',
  'GROUP-P9-002',
  'GROUP-REG-001',
];
const List<String> _desktopCliPeerDirectCaseIds = <String>[
  'AUTH-E2E-001',
  'MSG-E2E-001',
  'MSG-E2E-002',
  'MSG-REG-001',
];
const List<String> _desktopCliPeerAttachmentCaseIds = <String>[
  'AUTH-E2E-001',
  'ATTACH-E2E-001',
  'ATTACH-E2E-002',
  'ATTACH-REG-001',
];
const List<String> _desktopCliPeerContactsCaseIds = <String>[
  'AUTH-E2E-001',
  'CONTACT-E2E-001',
  'CONTACT-E2E-002',
  'CONTACT-REG-001',
];
const List<String> _messageAgentCaseIds = <String>[
  'MSGAGENT-E2E-001', // App UI selects daemon and enables Message Agent.
  'MSGAGENT-E2E-002', // CLI peer message is recovered into App UI.
  'MSGAGENT-E2E-003', // App confirms draft/action and returns result.
  'MSGAGENT-E2E-004', // Pause/delete/revoke UI lifecycle entries are visible.
];
const List<String> _codexAgentCaseIds = <String>[
  'CODEXAGENT-E2E-001', // App creates/selects a Codex runtime Agent.
  'CODEXAGENT-E2E-002', // App UI sends a deterministic prompt to Codex.
  'CODEXAGENT-E2E-003', // daemon records runtime_run + runtime_final_outbox sent.
  'CODEXAGENT-E2E-004', // App local history and visible UI show the Codex reply.
];
const List<String> _claudeCodeAgentCaseIds = <String>[
  'CLAUDECODEAGENT-E2E-001', // App creates/selects a Claude Code runtime Agent.
  'CLAUDECODEAGENT-E2E-002', // App UI sends a deterministic prompt to Claude Code.
  'CLAUDECODEAGENT-E2E-003', // daemon records runtime_run + runtime_final_outbox sent.
  'CLAUDECODEAGENT-E2E-004', // App local history and visible UI show the Claude Code reply.
];

Future<void> main(List<String> args) async {
  try {
    final options = DesktopE2eOptions.parse(args);
    if (options.help) {
      DesktopE2eOptions.printUsage();
      return;
    }
    final runner = DesktopE2eRunner(root: Directory.current, options: options);
    await runner.run();
  } on E2eFailure catch (error) {
    stderr.writeln('\nDesktop CLI peer E2E failed: ${error.message}');
    exitCode = 1;
  }
}

class DesktopE2eRunner {
  DesktopE2eRunner({
    required this.root,
    required this.options,
    DesktopCommandRunner? commands,
  }) : commands =
           commands ??
           DesktopCommandRunner(
             root: root,
             dryRun: options.dryRun,
             redactor: DesktopSecretRedactor(const <String>[]),
           ),
       redactor = DesktopSecretRedactor(const <String>[]);

  final Directory root;
  final DesktopE2eOptions options;
  final DesktopCommandRunner commands;
  final DesktopSecretRedactor redactor;

  DesktopE2eFileConfig fileConfig = const DesktopE2eFileConfig.empty();
  DesktopCliPeerConfig? config;
  late final DesktopE2ePlatform platform;
  late final String runId;
  late final Directory reportDir;
  late final Directory cliWorkspaceDir;
  late final Directory cliHomeDir;
  late final Directory appStateRootDir;
  late final File runConfigFile;
  final List<DesktopTimingEntry> _timings = <DesktopTimingEntry>[];

  Future<void> run() async {
    fileConfig = DesktopE2eFileConfig.load(
      root: root,
      path: options.configPath,
    );
    _addRuntimeSecret(fileConfig.path ?? '');
    _addRuntimeSecret(fileConfig.otpPhone ?? '');
    _addRuntimeSecret(fileConfig.otpCode ?? '');
    platform = fileConfig.platform ?? DesktopE2ePlatform.fromHost();
    runId = options.runId ?? _newRunId();
    final runScope = options.e2eCase.reportScope;
    reportDir = Directory('${root.path}/.e2e/$runScope/$runId/reports')
      ..createSync(recursive: true);
    cliWorkspaceDir = Directory('${root.path}/.e2e/$runScope/$runId/cli-peer');
    cliHomeDir = Directory('${root.path}/.e2e/$runScope/$runId/cli-home');
    appStateRootDir = Directory('${root.path}/.e2e/$runScope/$runId/app');
    runConfigFile = File('${root.path}/${options.e2eCase.runConfigPath}');
    _addRuntimeSecret(reportDir.path);
    _addRuntimeSecret(cliWorkspaceDir.path);
    _addRuntimeSecret(cliHomeDir.path);
    _addRuntimeSecret(appStateRootDir.path);
    _addRuntimeSecret(runConfigFile.path);
    if (!options.dryRun && options.e2eCase.requiresCliPeer) {
      cliWorkspaceDir.createSync(recursive: true);
      cliHomeDir.createSync(recursive: true);
      appStateRootDir.createSync(recursive: true);
    }

    final totalStopwatch = Stopwatch()..start();
    var succeeded = false;
    try {
      if (options.e2eCase == DesktopE2eCase.smoke) {
        await _runLocalSmoke();
      } else {
        await _runAppCliPeer();
      }
      succeeded = true;
    } finally {
      totalStopwatch.stop();
      _writeTimingReport(
        succeeded: succeeded,
        totalElapsed: totalStopwatch.elapsed,
      );
      _printTimingSummary(
        succeeded: succeeded,
        totalElapsed: totalStopwatch.elapsed,
      );
    }
  }

  Future<void> _runLocalSmoke() async {
    _section('AWiki Desktop local smoke E2E $runId');
    _line('platform: ${platform.name}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('case: ${options.e2eCase.caseName}');

    await _timed('Checking desktop tooling', () async {
      await commands.requireExecutable('flutter');
      if (platform == DesktopE2ePlatform.linux) {
        await commands.requireExecutable('xvfb-run');
      }
    });
    await _timed('Flutter App smoke', () {
      return _runFlutterTest('integration_test/app_smoke_test.dart');
    });
    await _timed('Flutter native IM Core smoke', () {
      return _runFlutterTest('integration_test/im_core_open_smoke_test.dart');
    });
  }

  Future<void> _runAppCliPeer() async {
    final peerConfig = DesktopCliPeerConfig.from(options, fileConfig);
    config = peerConfig;
    _addRuntimeSecret(peerConfig.otpPhone);
    _addRuntimeSecret(peerConfig.otpCode);
    _addRuntimeSecret(peerConfig.daemonStateRoot ?? '');
    _addRuntimeSecret(peerConfig.daemonReadyFile ?? '');
    _addRuntimeSecret(peerConfig.daemonEnvFile ?? '');
    _section('AWiki Desktop App + CLI peer E2E $runId');
    _line('platform: ${peerConfig.platform.name}');
    _line('config: ${fileConfig.path ?? '<not found>'}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('cli workspace: ${redactor.redact(cliWorkspaceDir.path)}');
    _line('cli home: ${redactor.redact(cliHomeDir.path)}');
    _line('app state: ${redactor.redact(appStateRootDir.path)}');
    if (peerConfig.daemonEnvFile != null) {
      _line('daemon env file: ${redactor.redact(peerConfig.daemonEnvFile!)}');
    }
    _line('app handle: ${peerConfig.appHandle}');
    _line('cli handle: ${peerConfig.cliHandle}');
    _line('case: ${peerConfig.e2eCase.caseName}');
    _line('service base: ${peerConfig.serviceBaseUrl}');
    _line(
      'user service: ${peerConfig.userServiceUrl ?? peerConfig.serviceBaseUrl}',
    );
    _line(
      'message service: '
      '${peerConfig.messageServiceUrl ?? peerConfig.serviceBaseUrl}',
    );

    await _timed('Checking tooling', _checkTooling);
    await _timed('Preparing CLI workspace', _prepareCliWorkspace);
    await _timed('Preparing CLI identity', _prepareCliIdentity);
    await _timed('Checking CLI ready state', _checkCliReady);

    if (options.prepareOnly) {
      _section('Prepare-only completed');
      _line('Flutter desktop E2E was not started.');
      return;
    }
    await _writeFlutterRunConfig(peerConfig);
    await _timed('Flutter App + CLI peer flow', _planFlutterDesktopSmoke);
  }

  Future<T> _timed<T>(String name, Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();
    var succeeded = false;
    try {
      final result = await action();
      succeeded = true;
      return result;
    } finally {
      stopwatch.stop();
      _timings.add(
        DesktopTimingEntry(
          name: name,
          elapsed: stopwatch.elapsed,
          succeeded: succeeded,
        ),
      );
    }
  }

  Future<void> _checkTooling() async {
    await commands.requireExecutable('flutter');
    final peerConfig = _requireConfig();
    if (peerConfig.platform == DesktopE2ePlatform.linux) {
      await commands.requireExecutable('xvfb-run');
    }
    await commands.requireFile(peerConfig.cliBin);
  }

  Future<void> _prepareCliWorkspace() async {
    await _cli(const <String>['--format', 'json', 'init']);
    await _writeCliConfig();
    await _cli(const <String>['--format', 'json', 'config', 'show']);
  }

  Future<void> _writeCliConfig() async {
    final peerConfig = _requireConfig();
    final file = File('${cliWorkspaceDir.path}/config.yaml');
    final configMap = file.existsSync()
        ? _toStringKeyMap(loadYaml(file.readAsStringSync()), path: 'config')
        : <String, Object?>{};
    final services = _mapAt(configMap, 'services', optional: true);
    services['service_base_url'] = peerConfig.serviceBaseUrl;
    services['user_service_endpoint'] =
        peerConfig.userServiceUrl ?? peerConfig.serviceBaseUrl;
    services['message_service_endpoint'] =
        peerConfig.messageServiceUrl ?? peerConfig.serviceBaseUrl;
    services['did_domain'] = peerConfig.didDomain;
    services['anp_service_endpoint'] =
        peerConfig.anpServiceUrl ?? '${peerConfig.serviceBaseUrl}/anp-im/rpc';
    services['anp_service_did'] =
        peerConfig.anpServiceDid ?? 'did:wba:${peerConfig.didDomain}';
    services['mail_service_url'] =
        peerConfig.mailServiceUrl ?? peerConfig.serviceBaseUrl;
    configMap['schema_version'] = 1;
    configMap['services'] = services;

    if (options.dryRun) {
      _line(
        'would write CLI config: ${redactor.redact(file.path)} '
        '(service_base_url=${peerConfig.serviceBaseUrl}, '
        'user_service_endpoint=${peerConfig.userServiceUrl ?? peerConfig.serviceBaseUrl}, '
        'message_service_endpoint=${peerConfig.messageServiceUrl ?? peerConfig.serviceBaseUrl}, '
        'did_domain=${peerConfig.didDomain}, '
        'anp_service_endpoint=${services['anp_service_endpoint']}, '
        'anp_service_did=${services['anp_service_did']}, '
        'mail_service_url=${services['mail_service_url']})',
      );
      return;
    }
    cliWorkspaceDir.createSync(recursive: true);
    file.writeAsStringSync(_renderYamlMap(configMap));
  }

  Future<void> _prepareCliIdentity() async {
    final peerConfig = _requireConfig();
    final recover = await _cli(<String>[
      '--format',
      'json',
      'id',
      'recover',
      '--handle',
      peerConfig.cliHandle,
      '--phone',
      peerConfig.otpPhone,
      '--otp',
      peerConfig.otpCode,
    ], allowFailure: true);
    if (recover.exitCode == 0 || options.dryRun) {
      return;
    }
    if (!_looksRecoverableForRegister(recover.output)) {
      throw E2eFailure(
        'CLI peer recover failed and did not look like a missing-handle error: '
        '${redactor.redact(recover.output)}',
      );
    }
    final register = await _cli(<String>[
      '--format',
      'json',
      'id',
      'register',
      '--handle',
      peerConfig.cliHandle,
      '--phone',
      peerConfig.otpPhone,
      '--otp',
      peerConfig.otpCode,
    ], allowFailure: true);
    if (register.exitCode != 0) {
      throw E2eFailure(
        'CLI peer register failed: ${redactor.redact(register.output)}',
      );
    }
  }

  Future<void> _checkCliReady() async {
    await _cli(const <String>['--format', 'json', 'id', 'current']);
    await _cli(const <String>['--format', 'json', 'id', 'status']);
    await _cli(const <String>[
      '--format',
      'json',
      'msg',
      'inbox',
      '--limit',
      '1',
    ]);
  }

  Future<void> _planFlutterDesktopSmoke() async {
    final peerConfig = _requireConfig();
    final flutterArgs = <String>[
      'test',
      '--dart-define=AWIKI_E2E=true',
      peerConfig.e2eCase.testFile,
      '-d',
      peerConfig.platform.name,
    ];
    await _runFlutterArgs(
      flutterArgs,
      platform: peerConfig.platform,
      timeout: peerConfig.e2eCase.flutterTimeout,
    );
  }

  Future<void> _writeFlutterRunConfig(DesktopCliPeerConfig peerConfig) async {
    final payload = <String, Object?>{
      'enabled': true,
      'runId': runId,
      'platform': peerConfig.platform.name,
      'case': peerConfig.e2eCase.caseName,
      'service': <String, Object?>{
        'baseUrl': peerConfig.serviceBaseUrl,
        'userServiceUrl': peerConfig.userServiceUrl,
        'messageServiceUrl': peerConfig.messageServiceUrl,
        'messageServiceWsUrl': peerConfig.messageServiceWsUrl,
        'mailServiceUrl': peerConfig.mailServiceUrl,
        'didDomain': peerConfig.didDomain,
        'anpServiceUrl': peerConfig.anpServiceUrl,
        'anpServiceDid': peerConfig.anpServiceDid,
      },
      'otp': <String, Object?>{
        'phone': peerConfig.otpPhone,
        'code': peerConfig.otpCode,
      },
      'accounts': <String, Object?>{
        'appUser': <String, Object?>{'handle': peerConfig.appHandle},
        'cliPeer': <String, Object?>{'handle': peerConfig.cliHandle},
      },
      'cliPeer': <String, Object?>{
        'binary': peerConfig.cliBin,
        'workspace': cliWorkspaceDir.path,
        'home': cliHomeDir.path,
      },
      'app': <String, Object?>{'stateRoot': appStateRootDir.path},
      'daemon': <String, Object?>{
        'rustRepo': peerConfig.daemonRustRepo,
        'binary': peerConfig.daemonBinary,
        'stateRoot': peerConfig.daemonStateRoot,
        'readyFile': peerConfig.daemonReadyFile,
        'handle': peerConfig.daemonHandle,
        'envFile': peerConfig.daemonEnvFile,
        'fakeHermesGatewayCommand': peerConfig.daemonFakeHermesGatewayCommand,
      },
      'messageAgent': <String, Object?>{
        'enabled': peerConfig.messageAgentEnabled,
        'runtimeProvider': peerConfig.messageAgentRuntimeProvider,
        'processingScope': peerConfig.messageAgentProcessingScope,
        'realBackend': peerConfig.messageAgentRealBackend,
      },
      'codexAgent': <String, Object?>{
        'enabled': peerConfig.codexAgentEnabled,
        'realBackend': peerConfig.codexAgentRealBackend,
        'prompt': peerConfig.codexAgentPrompt ?? _defaultCodexPrompt(runId),
        'expectedReply':
            peerConfig.codexAgentExpectedReply ??
            _defaultCodexExpectedReply(runId),
      },
      'claudeCodeAgent': <String, Object?>{
        'enabled': peerConfig.claudeCodeAgentEnabled,
        'realBackend': peerConfig.claudeCodeAgentRealBackend,
        'prompt':
            peerConfig.claudeCodeAgentPrompt ?? _defaultClaudeCodePrompt(runId),
        'expectedReply':
            peerConfig.claudeCodeAgentExpectedReply ??
            _defaultClaudeCodeExpectedReply(runId),
      },
    };
    if (options.dryRun && !options.prepareOnly) {
      _line('would write Flutter E2E run config: ${runConfigFile.path}');
    }
    await runConfigFile.parent.create(recursive: true);
    await runConfigFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
  }

  Future<void> _runFlutterTest(String testFile) {
    return _runFlutterArgs(<String>[
      'test',
      '--dart-define=AWIKI_E2E=true',
      testFile,
      '-d',
      platform.name,
    ], platform: platform, timeout: options.e2eCase.flutterTimeout);
  }

  Future<void> _runFlutterArgs(
    List<String> flutterArgs, {
    required DesktopE2ePlatform platform,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (platform == DesktopE2ePlatform.linux) {
      await commands.run(
        'xvfb-run',
        <String>['-a', 'flutter', ...flutterArgs],
        timeout: timeout,
      );
      return;
    }
    await commands.run('flutter', flutterArgs, timeout: timeout);
  }

  Future<DesktopCommandResult> _cli(
    List<String> args, {
    bool allowFailure = false,
  }) {
    final environment = <String, String>{
      'HOME': cliHomeDir.path,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': cliWorkspaceDir.path,
    };
    for (final name in const <String>[
      'PATH',
      'LANG',
      'LC_ALL',
      'TMPDIR',
      'SSL_CERT_FILE',
      'SSL_CERT_DIR',
    ]) {
      final value = Platform.environment[name];
      if (value != null && value.trim().isNotEmpty) {
        environment[name] = value;
      }
    }
    return commands.captureResult(
      _requireConfig().cliBin,
      args,
      environment: environment,
      includeParentEnvironment: false,
      allowFailure: allowFailure,
    );
  }

  DesktopCliPeerConfig _requireConfig() {
    final peerConfig = config;
    if (peerConfig == null) {
      throw E2eFailure('App + CLI peer config is not initialized.');
    }
    return peerConfig;
  }

  String get _timingsPath => '${reportDir.path}/timings.json';

  void _writeTimingReport({
    required bool succeeded,
    required Duration totalElapsed,
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    final file = File(_timingsPath);
    if (!options.dryRun) {
      reportDir.createSync(recursive: true);
    }
    file.writeAsStringSync(
      encoder.convert(<String, Object?>{
        'status': succeeded ? 'success' : 'failed',
        'scenario': (config?.e2eCase ?? options.e2eCase).scenario,
        'caseIds': (config?.e2eCase ?? options.e2eCase).caseIds,
        'runId': runId,
        'platform': platform.name,
        'case': (config?.e2eCase ?? options.e2eCase).caseName,
        'dryRun': options.dryRun,
        'prepareOnly': options.prepareOnly,
        'configPath': fileConfig.path == null ? null : '<redacted-config-path>',
        if (config != null) 'serviceBaseUrl': config!.serviceBaseUrl,
        if (config != null)
          'userServiceUrl': config!.userServiceUrl ?? config!.serviceBaseUrl,
        if (config != null)
          'messageServiceUrl':
              config!.messageServiceUrl ?? config!.serviceBaseUrl,
        if (config != null) 'messageServiceWsUrl': config!.messageServiceWsUrl,
        if (config != null) 'mailServiceUrl': config!.mailServiceUrl,
        if (config != null) 'anpServiceUrl': config!.anpServiceUrl,
        if (config != null) 'anpServiceDid': config!.anpServiceDid,
        if (config != null) 'didDomain': config!.didDomain,
        if (config != null) 'appHandle': config!.appHandle,
        if (config != null) 'cliHandle': config!.cliHandle,
        if (config != null)
          'daemonRustRepo': config!.daemonRustRepo == null
              ? null
              : '<redacted-daemon-repo>',
        if (config != null)
          'daemonEnvFile': config!.daemonEnvFile == null
              ? null
              : '<redacted-daemon-env-file>',
        if (config != null)
          'messageAgent': <String, Object?>{
            'enabled': config!.messageAgentEnabled,
            'runtimeProvider': config!.messageAgentRuntimeProvider,
            'processingScope': config!.messageAgentProcessingScope,
            'realBackend': config!.messageAgentRealBackend,
          },
        if (config != null)
          'codexAgent': <String, Object?>{
            'enabled': config!.codexAgentEnabled,
            'realBackend': config!.codexAgentRealBackend,
            'prompt': '<redacted-deterministic-prompt>',
            'expectedReply':
                config!.codexAgentExpectedReply ??
                _defaultCodexExpectedReply(runId),
          },
        if (config != null)
          'claudeCodeAgent': <String, Object?>{
            'enabled': config!.claudeCodeAgentEnabled,
            'realBackend': config!.claudeCodeAgentRealBackend,
            'prompt': '<redacted-deterministic-prompt>',
            'expectedReply':
                config!.claudeCodeAgentExpectedReply ??
                _defaultClaudeCodeExpectedReply(runId),
          },
        'cliWorkspace': '<redacted-workspace>',
        'cliHome': '<redacted-home>',
        'appStateRoot': '<redacted-app-state>',
        'totalMs': totalElapsed.inMilliseconds,
        'steps': [
          for (final entry in _timings)
            <String, Object?>{
              'name': entry.name,
              'status': entry.succeeded ? 'success' : 'failed',
              'elapsedMs': entry.elapsed.inMilliseconds,
            },
        ],
      }),
    );
  }

  void _printTimingSummary({
    required bool succeeded,
    required Duration totalElapsed,
  }) {
    _section('Timing summary');
    _line('status: ${succeeded ? 'success' : 'failed'}');
    _line('total: ${_formatDuration(totalElapsed)}');
    for (final entry in _timings) {
      _line(
        '${entry.name}: ${_formatDuration(entry.elapsed)}'
        '${entry.succeeded ? '' : ' (failed)'}',
      );
    }
    _line('timings: ${redactor.redact(_timingsPath)}');
  }

  void _section(String title) {
    _line('');
    _line('== ${redactor.redact(title)} ==');
  }

  void _line(String line) {
    commands.logLine(redactor.redact(line));
  }

  void _addRuntimeSecret(String value) {
    redactor.addSecret(value);
    commands.redactor.addSecret(value);
  }
}

class DesktopCommandRunner {
  DesktopCommandRunner({
    required this.root,
    required this.dryRun,
    required this.redactor,
    void Function(String line)? logLine,
  }) : logLine = logLine ?? _defaultLogLine;

  final Directory root;
  final bool dryRun;
  final DesktopSecretRedactor redactor;
  final void Function(String line) logLine;

  Future<void> requireExecutable(String executable) async {
    final command = Platform.isWindows ? 'where' : 'which';
    final result = await captureResult(command, <String>[
      executable,
    ], allowFailure: true);
    if (result.output.trim().isEmpty && !dryRun) {
      throw E2eFailure('Required executable was not found: $executable');
    }
    logLine(
      '$executable: ${result.output.trim().isEmpty ? 'dry-run' : 'found'}',
    );
  }

  Future<void> requireFile(String path) async {
    logLine('check file: ${redactor.redact(path)}');
    if (!dryRun && !File(path).existsSync()) {
      throw E2eFailure('Required file was not found: $path');
    }
  }

  Future<void> run(
    String executable,
    List<String> args, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool allowFailure = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final result = await captureResult(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      allowFailure: allowFailure,
      timeout: timeout,
    );
    if (result.exitCode != 0 && !allowFailure) {
      throw E2eFailure('$executable exited with code ${result.exitCode}.');
    }
  }

  Future<DesktopCommandResult> captureResult(
    String executable,
    List<String> args, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool allowFailure = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    _command(executable, args);
    if (dryRun) {
      return const DesktopCommandResult(exitCode: 0, output: '');
    }
    final result = await Process.run(
      executable,
      args,
      workingDirectory: (workingDirectory ?? root).path,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: false,
    ).timeout(timeout);
    final out = (result.stdout as String?) ?? '';
    final err = (result.stderr as String?) ?? '';
    final output = out.isNotEmpty ? out : err;
    if (result.exitCode != 0 && !allowFailure) {
      throw E2eFailure(
        redactor.redact(
          '$executable ${args.join(' ')} failed with code ${result.exitCode}.\n'
          'stdout:\n$out\n'
          'stderr:\n$err',
        ),
      );
    }
    return DesktopCommandResult(exitCode: result.exitCode, output: output);
  }

  void _command(String executable, List<String> args) {
    final rendered = <String>[
      executable,
      ...args,
    ].map(_quoteIfNeeded).join(' ');
    logLine(r'$ ' + redactor.redact(rendered));
  }
}

class DesktopCommandResult {
  const DesktopCommandResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

class DesktopE2eOptions {
  DesktopE2eOptions({
    required this.dryRun,
    required this.prepareOnly,
    required this.help,
    this.configPath = _defaultDesktopE2eConfigPath,
    this.runId,
    this.e2eCase = DesktopE2eCase.smoke,
  });

  final bool dryRun;
  final bool prepareOnly;
  final bool help;
  final String configPath;
  final String? runId;
  final DesktopE2eCase e2eCase;

  static DesktopE2eOptions parse(List<String> args) {
    var dryRun = false;
    var prepareOnly = false;
    var help = false;
    var configPath = _defaultDesktopE2eConfigPath;
    String? runId;
    var e2eCase = DesktopE2eCase.smoke;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--config':
          configPath = _takeValue(args, ++index, '--config');
          break;
        case '--run-id':
          runId = _takeValue(args, ++index, '--run-id');
          break;
        case '--case':
          e2eCase = DesktopE2eCase.parse(_takeValue(args, ++index, '--case'));
          break;
        case '--dry-run':
          dryRun = true;
          break;
        case '--prepare-only':
          prepareOnly = true;
          break;
        case '-h':
        case '--help':
          help = true;
          break;
        default:
          throw E2eFailure('Unknown argument: $arg');
      }
    }

    return DesktopE2eOptions(
      dryRun: dryRun,
      prepareOnly: prepareOnly,
      help: help,
      configPath: configPath,
      runId: runId,
      e2eCase: e2eCase,
    );
  }

  static void printUsage() {
    stdout.writeln('''
Run the AWiki Me Desktop App + CLI peer E2E smoke.

Usage:
  dart run tests/e2e/runner.dart --case smoke
  dart run tests/e2e/runner.dart --case full
  dart run tests/e2e/runner.dart --case message-agent
  dart run tests/e2e/runner.dart --case codex-agent
  dart run tests/e2e/runner.dart --case claude-code-agent

Options:
  --config PATH                Local YAML config. Defaults to $_defaultDesktopE2eConfigPath.
  --run-id ID                  Stable run id for repeatable local debugging.
  --case smoke|full|direct|group|attachment|contacts|message-agent|codex-agent|claude-code-agent
                               smoke runs local App/native checks. The other
                               cases run real App+CLI peer flows. The
                               message-agent case is the full UI acceptance
                               gate for Message Agent; codex-agent and
                               claude-code-agent are user-visible runtime
                               Agent reply gates. Probes are only lower level
                               helpers.
  --prepare-only               Prepare CLI peer but do not start Flutter test.
  --dry-run                    Print planned commands without side effects.
''');
  }
}

class DesktopCliPeerConfig {
  DesktopCliPeerConfig({
    required this.platform,
    required this.serviceBaseUrl,
    required this.didDomain,
    required this.otpPhone,
    required this.otpCode,
    required this.appHandle,
    required this.cliHandle,
    required this.cliBin,
    required this.e2eCase,
    this.userServiceUrl,
    this.messageServiceUrl,
    this.messageServiceWsUrl,
    this.mailServiceUrl,
    this.anpServiceUrl,
    this.anpServiceDid,
    this.daemonRustRepo,
    this.daemonBinary,
    this.daemonStateRoot,
    this.daemonReadyFile,
    this.daemonHandle,
    this.daemonEnvFile,
    this.daemonFakeHermesGatewayCommand,
    this.messageAgentEnabled = false,
    this.messageAgentRuntimeProvider = 'hermes',
    this.messageAgentProcessingScope = 'all_conversations',
    this.messageAgentRealBackend = false,
    this.codexAgentEnabled = false,
    this.codexAgentRealBackend = false,
    this.codexAgentPrompt,
    this.codexAgentExpectedReply,
    this.claudeCodeAgentEnabled = false,
    this.claudeCodeAgentRealBackend = false,
    this.claudeCodeAgentPrompt,
    this.claudeCodeAgentExpectedReply,
  });

  final DesktopE2ePlatform platform;
  final String serviceBaseUrl;
  final String didDomain;
  final String otpPhone;
  final String otpCode;
  final String appHandle;
  final String cliHandle;
  final String cliBin;
  final DesktopE2eCase e2eCase;
  final String? userServiceUrl;
  final String? messageServiceUrl;
  final String? messageServiceWsUrl;
  final String? mailServiceUrl;
  final String? anpServiceUrl;
  final String? anpServiceDid;
  final String? daemonRustRepo;
  final String? daemonBinary;
  final String? daemonStateRoot;
  final String? daemonReadyFile;
  final String? daemonHandle;
  final String? daemonEnvFile;
  final String? daemonFakeHermesGatewayCommand;
  final bool messageAgentEnabled;
  final String messageAgentRuntimeProvider;
  final String messageAgentProcessingScope;
  final bool messageAgentRealBackend;
  final bool codexAgentEnabled;
  final bool codexAgentRealBackend;
  final String? codexAgentPrompt;
  final String? codexAgentExpectedReply;
  final bool claudeCodeAgentEnabled;
  final bool claudeCodeAgentRealBackend;
  final String? claudeCodeAgentPrompt;
  final String? claudeCodeAgentExpectedReply;

  static DesktopCliPeerConfig from(
    DesktopE2eOptions options,
    DesktopE2eFileConfig fileConfig,
  ) {
    final sourcePath = fileConfig.path ?? options.configPath;
    if (fileConfig.path == null) {
      throw E2eFailure('E2E config file was not found: $sourcePath');
    }
    final platform = fileConfig.platform ?? DesktopE2ePlatform.fromHost();
    final serviceBaseUrl = _requiredConfig(
      fileConfig.serviceBaseUrl,
      'service.baseUrl',
      sourcePath,
    );
    final didDomain = _requiredConfig(
      fileConfig.didDomain,
      'service.didDomain',
      sourcePath,
    );
    final otpPhone = _requiredConfig(
      fileConfig.otpPhone,
      'otp.phone',
      sourcePath,
    );
    final otpCode = _requiredConfig(fileConfig.otpCode, 'otp.code', sourcePath);
    final appHandle = _requiredConfig(
      fileConfig.appHandle,
      'accounts.appUser.handle',
      sourcePath,
    );
    final cliHandle = _requiredConfig(
      fileConfig.cliHandle,
      'accounts.cliPeer.handle',
      sourcePath,
    );
    if (appHandle.toLowerCase() == cliHandle.toLowerCase()) {
      throw E2eFailure('App handle and CLI handle must differ.');
    }
    final cliBin = _requiredConfig(
      fileConfig.cliBin,
      'cliPeer.binary',
      sourcePath,
    );
    return DesktopCliPeerConfig(
      platform: platform,
      serviceBaseUrl: serviceBaseUrl,
      didDomain: didDomain,
      otpPhone: otpPhone,
      otpCode: otpCode,
      appHandle: appHandle,
      cliHandle: cliHandle,
      cliBin: cliBin,
      e2eCase: options.e2eCase,
      userServiceUrl: fileConfig.userServiceUrl,
      messageServiceUrl: fileConfig.messageServiceUrl,
      messageServiceWsUrl: fileConfig.messageServiceWsUrl,
      mailServiceUrl: fileConfig.mailServiceUrl,
      anpServiceUrl: fileConfig.anpServiceUrl,
      anpServiceDid: fileConfig.anpServiceDid,
      daemonRustRepo: fileConfig.daemonRustRepo,
      daemonBinary: fileConfig.daemonBinary,
      daemonStateRoot: fileConfig.daemonStateRoot,
      daemonReadyFile: fileConfig.daemonReadyFile,
      daemonHandle: fileConfig.daemonHandle,
      daemonEnvFile: fileConfig.daemonEnvFile,
      daemonFakeHermesGatewayCommand: fileConfig.daemonFakeHermesGatewayCommand,
      messageAgentEnabled: _effectiveMessageAgentEnabled(
        options,
        fileConfig,
        sourcePath,
      ),
      messageAgentRuntimeProvider:
          fileConfig.messageAgentRuntimeProvider ?? 'hermes',
      messageAgentProcessingScope:
          fileConfig.messageAgentProcessingScope ?? 'all_conversations',
      messageAgentRealBackend: fileConfig.messageAgentRealBackend ?? false,
      codexAgentEnabled: _effectiveCodexAgentEnabled(
        options,
        fileConfig,
        sourcePath,
      ),
      codexAgentRealBackend: _effectiveCodexAgentRealBackend(
        options,
        fileConfig,
      ),
      codexAgentPrompt: fileConfig.codexAgentPrompt,
      codexAgentExpectedReply: fileConfig.codexAgentExpectedReply,
      claudeCodeAgentEnabled: _effectiveClaudeCodeAgentEnabled(
        options,
        fileConfig,
        sourcePath,
      ),
      claudeCodeAgentRealBackend: _effectiveClaudeCodeAgentRealBackend(
        options,
        fileConfig,
      ),
      claudeCodeAgentPrompt: fileConfig.claudeCodeAgentPrompt,
      claudeCodeAgentExpectedReply: fileConfig.claudeCodeAgentExpectedReply,
    );
  }
}

bool _effectiveMessageAgentEnabled(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
  String sourcePath,
) {
  final configured = fileConfig.messageAgentEnabled;
  if (options.e2eCase != DesktopE2eCase.messageAgent) {
    return configured ?? false;
  }
  if (configured == false) {
    throw E2eFailure(
      'messageAgent.enabled must be true for --case message-agent in $sourcePath.',
    );
  }
  return true;
}

bool _effectiveCodexAgentEnabled(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
  String sourcePath,
) {
  final configured = fileConfig.codexAgentEnabled;
  if (options.e2eCase != DesktopE2eCase.codexAgent) {
    return configured ?? false;
  }
  if (configured == false) {
    throw E2eFailure(
      'codexAgent.enabled must be true for --case codex-agent in $sourcePath.',
    );
  }
  return true;
}

bool _effectiveCodexAgentRealBackend(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
) {
  if (options.e2eCase == DesktopE2eCase.codexAgent) {
    return fileConfig.codexAgentRealBackend ?? true;
  }
  return fileConfig.codexAgentRealBackend ?? false;
}

bool _effectiveClaudeCodeAgentEnabled(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
  String sourcePath,
) {
  final configured = fileConfig.claudeCodeAgentEnabled;
  if (options.e2eCase != DesktopE2eCase.claudeCodeAgent) {
    return configured ?? false;
  }
  if (configured == false) {
    throw E2eFailure(
      'claudeCodeAgent.enabled must be true for --case claude-code-agent in $sourcePath.',
    );
  }
  return true;
}

bool _effectiveClaudeCodeAgentRealBackend(
  DesktopE2eOptions options,
  DesktopE2eFileConfig fileConfig,
) {
  if (options.e2eCase == DesktopE2eCase.claudeCodeAgent) {
    return fileConfig.claudeCodeAgentRealBackend ?? true;
  }
  return fileConfig.claudeCodeAgentRealBackend ?? false;
}

String _defaultCodexExpectedReply(String runId) {
  final suffix = runId
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'OK-CODEX-${suffix.isEmpty ? 'E2E' : suffix}';
}

String _defaultCodexPrompt(String runId) {
  return 'Reply exactly ${_defaultCodexExpectedReply(runId)} and nothing else';
}

String _defaultClaudeCodeExpectedReply(String runId) {
  final suffix = runId
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'OK-CLAUDE-CODE-${suffix.isEmpty ? 'E2E' : suffix}';
}

String _defaultClaudeCodePrompt(String runId) {
  return 'Reply exactly ${_defaultClaudeCodeExpectedReply(runId)} and nothing else';
}

class DesktopE2eFileConfig {
  const DesktopE2eFileConfig({
    this.path,
    this.platform,
    this.serviceBaseUrl,
    this.userServiceUrl,
    this.messageServiceUrl,
    this.messageServiceWsUrl,
    this.mailServiceUrl,
    this.didDomain,
    this.anpServiceUrl,
    this.anpServiceDid,
    this.daemonRustRepo,
    this.daemonBinary,
    this.daemonStateRoot,
    this.daemonReadyFile,
    this.daemonHandle,
    this.daemonEnvFile,
    this.daemonFakeHermesGatewayCommand,
    this.messageAgentEnabled,
    this.messageAgentRuntimeProvider,
    this.messageAgentProcessingScope,
    this.messageAgentRealBackend,
    this.codexAgentEnabled,
    this.codexAgentRealBackend,
    this.codexAgentPrompt,
    this.codexAgentExpectedReply,
    this.claudeCodeAgentEnabled,
    this.claudeCodeAgentRealBackend,
    this.claudeCodeAgentPrompt,
    this.claudeCodeAgentExpectedReply,
    this.otpPhone,
    this.otpCode,
    this.appHandle,
    this.cliHandle,
    this.cliBin,
  });

  const DesktopE2eFileConfig.empty()
    : path = null,
      platform = null,
      serviceBaseUrl = null,
      userServiceUrl = null,
      messageServiceUrl = null,
      messageServiceWsUrl = null,
      mailServiceUrl = null,
      didDomain = null,
      anpServiceUrl = null,
      anpServiceDid = null,
      daemonRustRepo = null,
      daemonBinary = null,
      daemonStateRoot = null,
      daemonReadyFile = null,
      daemonHandle = null,
      daemonEnvFile = null,
      daemonFakeHermesGatewayCommand = null,
      messageAgentEnabled = null,
      messageAgentRuntimeProvider = null,
      messageAgentProcessingScope = null,
      messageAgentRealBackend = null,
      codexAgentEnabled = null,
      codexAgentRealBackend = null,
      codexAgentPrompt = null,
      codexAgentExpectedReply = null,
      claudeCodeAgentEnabled = null,
      claudeCodeAgentRealBackend = null,
      claudeCodeAgentPrompt = null,
      claudeCodeAgentExpectedReply = null,
      otpPhone = null,
      otpCode = null,
      appHandle = null,
      cliHandle = null,
      cliBin = null;

  final String? path;
  final DesktopE2ePlatform? platform;
  final String? serviceBaseUrl;
  final String? userServiceUrl;
  final String? messageServiceUrl;
  final String? messageServiceWsUrl;
  final String? mailServiceUrl;
  final String? didDomain;
  final String? anpServiceUrl;
  final String? anpServiceDid;
  final String? daemonRustRepo;
  final String? daemonBinary;
  final String? daemonStateRoot;
  final String? daemonReadyFile;
  final String? daemonHandle;
  final String? daemonEnvFile;
  final String? daemonFakeHermesGatewayCommand;
  final bool? messageAgentEnabled;
  final String? messageAgentRuntimeProvider;
  final String? messageAgentProcessingScope;
  final bool? messageAgentRealBackend;
  final bool? codexAgentEnabled;
  final bool? codexAgentRealBackend;
  final String? codexAgentPrompt;
  final String? codexAgentExpectedReply;
  final bool? claudeCodeAgentEnabled;
  final bool? claudeCodeAgentRealBackend;
  final String? claudeCodeAgentPrompt;
  final String? claudeCodeAgentExpectedReply;
  final String? otpPhone;
  final String? otpCode;
  final String? appHandle;
  final String? cliHandle;
  final String? cliBin;

  static DesktopE2eFileConfig load({
    required Directory root,
    required String path,
  }) {
    final file = File(_resolvePath(root, path));
    if (!file.existsSync()) {
      return const DesktopE2eFileConfig.empty();
    }
    final raw = _toStringKeyMap(loadYaml(file.readAsStringSync()), path: path);
    final service = _mapAt(raw, 'service', optional: true);
    final accounts = _mapAt(raw, 'accounts', optional: true);
    final appUser = _mapAt(accounts, 'appUser', optional: true);
    final cliUser = _mapAt(accounts, 'cliPeer', optional: true);
    final cliPeer = _mapAt(raw, 'cliPeer', optional: true);
    final daemon = _mapAt(raw, 'daemon', optional: true);
    final messageAgent = _mapAt(raw, 'messageAgent', optional: true);
    final codexAgent = _mapAt(raw, 'codexAgent', optional: true);
    final claudeCodeAgent = _mapAt(raw, 'claudeCodeAgent', optional: true);
    final otp = _mapAt(raw, 'otp', optional: true);

    final baseUrl = _stringAt(service, 'baseUrl');
    final didDomain = _stringAt(service, 'didDomain');
    final otpPhone = _stringAt(otp, 'phone');
    final otpCode = _stringAt(otp, 'code');
    final appHandle = _stringAt(appUser, 'handle');
    final cliHandle = _stringAt(cliUser, 'handle');
    final cliBin = _stringAt(cliPeer, 'binary');
    final platformValue = _stringAt(raw, 'platform');

    return DesktopE2eFileConfig(
      path: file.path,
      platform: platformValue == null
          ? null
          : DesktopE2ePlatform.parse(platformValue),
      serviceBaseUrl: baseUrl,
      userServiceUrl: _stringAt(service, 'userServiceUrl'),
      messageServiceUrl: _stringAt(service, 'messageServiceUrl'),
      messageServiceWsUrl: _stringAt(service, 'messageServiceWsUrl'),
      mailServiceUrl: _stringAt(service, 'mailServiceUrl'),
      didDomain: didDomain,
      anpServiceUrl: _stringAt(service, 'anpServiceUrl'),
      anpServiceDid: _stringAt(service, 'anpServiceDid'),
      daemonRustRepo: _stringAt(daemon, 'rustRepo'),
      daemonBinary: _resolveOptionalPath(root, _stringAt(daemon, 'binary')),
      daemonStateRoot: _resolveOptionalPath(
        root,
        _stringAt(daemon, 'stateRoot'),
      ),
      daemonReadyFile: _resolveOptionalPath(
        root,
        _stringAt(daemon, 'readyFile'),
      ),
      daemonHandle: _stringAt(daemon, 'handle'),
      daemonEnvFile: _resolveOptionalPath(root, _stringAt(daemon, 'envFile')),
      daemonFakeHermesGatewayCommand: _stringAt(
        daemon,
        'fakeHermesGatewayCommand',
      ),
      messageAgentEnabled: _boolAt(messageAgent, 'enabled'),
      messageAgentRuntimeProvider: _stringAt(messageAgent, 'runtimeProvider'),
      messageAgentProcessingScope: _stringAt(messageAgent, 'processingScope'),
      messageAgentRealBackend: _boolAt(messageAgent, 'realBackend'),
      codexAgentEnabled: _boolAt(codexAgent, 'enabled'),
      codexAgentRealBackend: _boolAt(codexAgent, 'realBackend'),
      codexAgentPrompt: _stringAt(codexAgent, 'prompt'),
      codexAgentExpectedReply: _stringAt(codexAgent, 'expectedReply'),
      claudeCodeAgentEnabled: _boolAt(claudeCodeAgent, 'enabled'),
      claudeCodeAgentRealBackend: _boolAt(claudeCodeAgent, 'realBackend'),
      claudeCodeAgentPrompt: _stringAt(claudeCodeAgent, 'prompt'),
      claudeCodeAgentExpectedReply: _stringAt(claudeCodeAgent, 'expectedReply'),
      otpPhone: otpPhone,
      otpCode: otpCode,
      appHandle: appHandle,
      cliHandle: cliHandle,
      cliBin: cliBin == null ? null : _resolvePath(root, cliBin),
    );
  }
}

enum DesktopE2eCase {
  smoke(_desktopSmokeCaseIds),
  full(_desktopCliPeerCaseIds),
  direct(_desktopCliPeerDirectCaseIds),
  group(_desktopCliPeerGroupCaseIds),
  attachment(_desktopCliPeerAttachmentCaseIds),
  contacts(_desktopCliPeerContactsCaseIds),
  messageAgent(_messageAgentCaseIds),
  codexAgent(_codexAgentCaseIds),
  claudeCodeAgent(_claudeCodeAgentCaseIds);

  const DesktopE2eCase(this.caseIds);

  final List<String> caseIds;

  String get testFile {
    return switch (this) {
      DesktopE2eCase.smoke => 'integration_test/app_smoke_test.dart',
      DesktopE2eCase.full =>
        'integration_test/desktop_cli_peer_smoke_test.dart',
      DesktopE2eCase.direct =>
        'integration_test/desktop_cli_peer_direct_test.dart',
      DesktopE2eCase.group =>
        'integration_test/desktop_cli_peer_group_test.dart',
      DesktopE2eCase.attachment =>
        'integration_test/desktop_cli_peer_attachment_test.dart',
      DesktopE2eCase.contacts =>
        'integration_test/desktop_cli_peer_contacts_test.dart',
      DesktopE2eCase.messageAgent =>
        'integration_test/message_agent_full_ui_test.dart',
      DesktopE2eCase.codexAgent =>
        'integration_test/codex_agent_full_ui_test.dart',
      DesktopE2eCase.claudeCodeAgent =>
        'integration_test/claude_code_agent_full_ui_test.dart',
    };
  }

  String get caseName {
    return switch (this) {
      DesktopE2eCase.messageAgent => 'message-agent',
      DesktopE2eCase.codexAgent => 'codex-agent',
      DesktopE2eCase.claudeCodeAgent => 'claude-code-agent',
      _ => name,
    };
  }

  bool get requiresCliPeer => this != DesktopE2eCase.smoke;

  String get reportScope {
    return switch (this) {
      DesktopE2eCase.smoke => 'smoke',
      DesktopE2eCase.messageAgent => 'message-agent',
      DesktopE2eCase.codexAgent => 'codex-agent',
      DesktopE2eCase.claudeCodeAgent => 'claude-code-agent',
      _ => 'desktop-cli-peer',
    };
  }

  Duration get flutterTimeout {
    return switch (this) {
      DesktopE2eCase.claudeCodeAgent => const Duration(minutes: 15),
      DesktopE2eCase.codexAgent => const Duration(minutes: 8),
      DesktopE2eCase.messageAgent => const Duration(minutes: 10),
      _ => const Duration(minutes: 5),
    };
  }

  String get scenario {
    return switch (this) {
      DesktopE2eCase.messageAgent => _messageAgentScenario,
      DesktopE2eCase.codexAgent => _codexAgentScenario,
      DesktopE2eCase.claudeCodeAgent => _claudeCodeAgentScenario,
      _ => _desktopCliPeerScenario,
    };
  }

  String get runConfigPath {
    return switch (this) {
      DesktopE2eCase.messageAgent => _messageAgentRunConfigPath,
      DesktopE2eCase.codexAgent => _codexAgentRunConfigPath,
      DesktopE2eCase.claudeCodeAgent => _claudeCodeAgentRunConfigPath,
      _ => _desktopCliPeerRunConfigPath,
    };
  }

  static DesktopE2eCase parse(String value) {
    return switch (value.trim().toLowerCase()) {
      '' || 'smoke' || 'app' || 'local' => DesktopE2eCase.smoke,
      'full' => DesktopE2eCase.full,
      'direct' ||
      'dm' ||
      'message' ||
      'messages' ||
      'direct-only' => DesktopE2eCase.direct,
      'group' || 'groups' || 'group-only' => DesktopE2eCase.group,
      'attachment' ||
      'attachments' ||
      'file' ||
      'files' ||
      'attachment-only' => DesktopE2eCase.attachment,
      'contact' ||
      'contacts' ||
      'people' ||
      'follow' ||
      'contact-only' => DesktopE2eCase.contacts,
      'message-agent' ||
      'message_agent' ||
      'msgagent' ||
      'im-agent' ||
      'im_agent' => DesktopE2eCase.messageAgent,
      'codex-agent' ||
      'codex_agent' ||
      'codexagent' ||
      'agent-codex' ||
      'agent_codex' => DesktopE2eCase.codexAgent,
      'claude-code-agent' ||
      'claude_code_agent' ||
      'claudecodeagent' ||
      'agent-claude-code' ||
      'agent_claude_code' ||
      'claude-agent' ||
      'claude_agent' => DesktopE2eCase.claudeCodeAgent,
      _ => throw E2eFailure(
        'Unsupported E2E case "$value". '
        'Use smoke, full, direct, group, attachment, contacts, message-agent, '
        'codex-agent, or claude-code-agent.',
      ),
    };
  }
}

enum DesktopE2ePlatform {
  macos,
  linux;

  static DesktopE2ePlatform fromHost() {
    if (Platform.isMacOS) {
      return DesktopE2ePlatform.macos;
    }
    if (Platform.isLinux) {
      return DesktopE2ePlatform.linux;
    }
    throw E2eFailure('Only macOS and Linux desktop E2E are supported.');
  }

  static DesktopE2ePlatform parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'macos' => DesktopE2ePlatform.macos,
      'linux' => DesktopE2ePlatform.linux,
      _ => throw E2eFailure(
        'Unsupported desktop platform "$value". Use macos or linux.',
      ),
    };
  }
}

class DesktopSecretRedactor {
  DesktopSecretRedactor(Iterable<String> secrets)
    : _secrets =
          secrets
              .where((secret) => secret.trim().isNotEmpty)
              .map((secret) => secret.trim())
              .toSet()
              .toList()
            ..sort((a, b) => b.length.compareTo(a.length));

  final List<String> _secrets;

  void addSecret(String secret) {
    final value = secret.trim();
    if (value.isEmpty || _secrets.contains(value)) {
      return;
    }
    _secrets.add(value);
    _secrets.sort((a, b) => b.length.compareTo(a.length));
  }

  String redact(String input) {
    var output = input;
    for (final secret in _secrets) {
      output = output.replaceAll(secret, '<redacted>');
    }
    output = output.replaceAll(
      RegExp(
        r'(otp|token|jwt|private[_-]?key|secret|authorization)=([^\s]+)',
        caseSensitive: false,
      ),
      '<redacted-key>=<redacted>',
    );
    output = output.replaceAllMapped(
      RegExp(r'(--otp|--phone)\s+([^\s]+)', caseSensitive: false),
      (match) => '${match.group(1)} <redacted>',
    );
    return output;
  }
}

class DesktopTimingEntry {
  DesktopTimingEntry({
    required this.name,
    required this.elapsed,
    required this.succeeded,
  });

  final String name;
  final Duration elapsed;
  final bool succeeded;
}

class E2eFailure implements Exception {
  E2eFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _looksRecoverableForRegister(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not found') ||
      lower.contains('handle_not_found') ||
      lower.contains('not active') ||
      lower.contains('not_registered') ||
      lower.contains('not registered') ||
      lower.contains('404');
}

String? _stringAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  final string = value.toString().trim();
  return string.isEmpty ? null : string;
}

bool? _boolAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  final normalized = value.toString().trim().toLowerCase();
  return switch (normalized) {
    '' => null,
    '1' || 'true' || 'yes' || 'on' => true,
    '0' || 'false' || 'no' || 'off' => false,
    _ => throw E2eFailure('$key must be a boolean value.'),
  };
}

String _requiredConfig(String? value, String key, String sourcePath) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    throw E2eFailure('$key is required in $sourcePath.');
  }
  return trimmed;
}

String _resolvePath(Directory root, String path) {
  final value = path.trim();
  if (value.isEmpty) {
    return value;
  }
  if (value.startsWith('/')) {
    return value;
  }
  return '${root.path}/$value';
}

String? _resolveOptionalPath(Directory root, String? path) {
  if (path == null) {
    return null;
  }
  return _resolvePath(root, path);
}

String _takeValue(List<String> args, int index, String flag) {
  if (index >= args.length) {
    throw E2eFailure('$flag requires a value.');
  }
  return args[index];
}

String _newRunId() {
  final now = DateTime.now().toUtc();
  final timestamp =
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}'
      '${now.hour.toString().padLeft(2, '0')}'
      '${now.minute.toString().padLeft(2, '0')}'
      '${now.second.toString().padLeft(2, '0')}';
  final suffix = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return '$timestamp-$suffix';
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds < 1) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inMinutes < 1) {
    return '${duration.inSeconds}.${(duration.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
  }
  return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
}

String _quoteIfNeeded(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (!RegExp(r'''[\s'"$]''').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

void _defaultLogLine(String line) {
  stdout.writeln(line);
}

Map<String, Object?> _toStringKeyMap(Object? value, {required String path}) {
  if (value == null) {
    return <String, Object?>{};
  }
  if (value is! YamlMap && value is! Map) {
    throw E2eFailure('$path must be a map.');
  }
  final map = value as Map;
  return <String, Object?>{
    for (final entry in map.entries)
      entry.key.toString(): _normalizeYamlValue(entry.value),
  };
}

Object? _normalizeYamlValue(Object? value) {
  if (value is YamlMap || value is Map) {
    return _toStringKeyMap(value, path: 'nested map');
  }
  if (value is YamlList || value is List) {
    return [for (final item in value as Iterable) _normalizeYamlValue(item)];
  }
  return value;
}

Map<String, Object?> _mapAt(
  Map<String, Object?> map,
  String key, {
  bool optional = false,
}) {
  final value = map[key];
  if (value == null && optional) {
    final nested = <String, Object?>{};
    map[key] = nested;
    return nested;
  }
  if (value is Map<String, Object?>) {
    return value;
  }
  throw E2eFailure('$key must be configured as a map.');
}

String _renderYamlMap(Map<String, Object?> map, {int indent = 0}) {
  final buffer = StringBuffer();
  for (final entry in map.entries) {
    final spaces = ' ' * indent;
    final value = entry.value;
    if (value is Map<String, Object?>) {
      buffer.writeln('$spaces${entry.key}:');
      buffer.write(_renderYamlMap(value, indent: indent + 2));
    } else if (value is bool || value is num) {
      buffer.writeln('$spaces${entry.key}: $value');
    } else {
      buffer.writeln(
        '$spaces${entry.key}: ${_yamlScalar(value?.toString() ?? '')}',
      );
    }
  }
  return buffer.toString();
}

String _yamlScalar(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (RegExp(r'^[A-Za-z0-9._/:@+-]+$').hasMatch(value)) {
    return value;
  }
  return jsonEncode(value);
}
