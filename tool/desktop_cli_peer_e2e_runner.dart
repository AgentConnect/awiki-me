import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const String _desktopCliPeerScenario = 'desktop-app-cli-peer';
const List<String> _desktopCliPeerCaseIds = <String>[
  'AUTH-E2E-001',
  'MSG-E2E-001',
  'MSG-E2E-002',
  'MSG-REG-001',
];

Future<void> main(List<String> args) async {
  try {
    final options = DesktopCliPeerOptions.parse(args);
    if (options.help) {
      DesktopCliPeerOptions.printUsage();
      return;
    }
    final runner = DesktopCliPeerRunner(
      root: Directory.current,
      options: options,
      environment: Platform.environment,
    );
    await runner.run();
  } on DesktopCliPeerFailure catch (error) {
    stderr.writeln('\nDesktop CLI peer E2E failed: ${error.message}');
    exitCode = 1;
  }
}

class DesktopCliPeerRunner {
  DesktopCliPeerRunner({
    required this.root,
    required this.options,
    required Map<String, String> environment,
    DesktopCommandRunner? commands,
  }) : environment = Map<String, String>.unmodifiable(environment),
       commands =
           commands ??
           DesktopCommandRunner(
             root: root,
             dryRun: options.dryRun,
             redactor: DesktopSecretRedactor.fromEnvironment(environment),
           ),
       redactor = DesktopSecretRedactor.fromEnvironment(environment);

  final Directory root;
  final DesktopCliPeerOptions options;
  final Map<String, String> environment;
  final DesktopCommandRunner commands;
  final DesktopSecretRedactor redactor;

  late final DesktopCliPeerConfig config;
  late final String runId;
  late final Directory reportDir;
  late final Directory cliWorkspaceDir;
  late final Directory cliHomeDir;
  late final Directory appStateRootDir;
  final List<DesktopTimingEntry> _timings = <DesktopTimingEntry>[];

  Future<void> run() async {
    config = DesktopCliPeerConfig.from(options, environment);
    runId = options.runId ?? _newRunId();
    reportDir = Directory('${root.path}/.e2e/desktop-cli-peer/$runId/reports')
      ..createSync(recursive: true);
    cliWorkspaceDir = Directory(
      '${root.path}/.e2e/desktop-cli-peer/$runId/cli-peer',
    );
    cliHomeDir = Directory(
      '${root.path}/.e2e/desktop-cli-peer/$runId/cli-home',
    );
    appStateRootDir = Directory(
      '${root.path}/.e2e/desktop-cli-peer/$runId/app',
    );
    _addRuntimeSecret(reportDir.path);
    _addRuntimeSecret(cliWorkspaceDir.path);
    _addRuntimeSecret(cliHomeDir.path);
    _addRuntimeSecret(appStateRootDir.path);
    if (!options.dryRun) {
      cliWorkspaceDir.createSync(recursive: true);
      cliHomeDir.createSync(recursive: true);
      appStateRootDir.createSync(recursive: true);
    }

    final totalStopwatch = Stopwatch()..start();
    var succeeded = false;
    try {
      _section('AWiki Desktop CLI peer E2E $runId');
      _line('platform: ${config.platform.name}');
      _line('reports: ${redactor.redact(reportDir.path)}');
      _line('cli workspace: ${redactor.redact(cliWorkspaceDir.path)}');
      _line('cli home: ${redactor.redact(cliHomeDir.path)}');
      _line('app state: ${redactor.redact(appStateRootDir.path)}');
      _line('app handle: ${config.appHandle}');
      _line('cli handle: ${config.cliHandle}');
      _line('service base: ${config.serviceBaseUrl}');
      _line('user service: ${config.userServiceUrl ?? config.serviceBaseUrl}');
      _line(
        'message service: '
        '${config.messageServiceUrl ?? config.serviceBaseUrl}',
      );

      await _timed('Checking tooling', _checkTooling);
      await _timed('Preparing CLI workspace', _prepareCliWorkspace);
      await _timed('Preparing CLI identity', _prepareCliIdentity);
      await _timed('Checking CLI ready state', _checkCliReady);

      if (options.prepareOnly) {
        _section('Prepare-only completed');
        _line('Flutter desktop smoke was not started.');
      } else {
        await _timed(
          'Planning Flutter desktop smoke',
          _planFlutterDesktopSmoke,
        );
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
    if (config.platform == DesktopE2ePlatform.linux) {
      await commands.requireExecutable('xvfb-run');
    }
    if (_shouldBuildCli) {
      await commands.requireExecutable('cargo');
    } else {
      await commands.requireFile(config.cliBin);
    }
  }

  Future<void> _prepareCliWorkspace() async {
    if (_shouldBuildCli) {
      await commands.run(
        'cargo',
        const <String>[
          'build',
          '-p',
          'awiki-cli',
          '--bin',
          'awiki-cli',
          '--release',
          '--locked',
        ],
        workingDirectory: Directory('${root.parent.path}/awiki-cli-rs2'),
        timeout: const Duration(minutes: 20),
      );
    }

    await _cli(const <String>['--format', 'json', 'init']);
    await _writeCliConfig();
    await _cli(const <String>['--format', 'json', 'config', 'show']);
  }

  Future<void> _writeCliConfig() async {
    final file = File('${cliWorkspaceDir.path}/config.yaml');
    final configMap = file.existsSync()
        ? _toStringKeyMap(loadYaml(file.readAsStringSync()), path: 'config')
        : <String, Object?>{};
    final services = _mapAt(configMap, 'services', optional: true);
    services['service_base_url'] = config.serviceBaseUrl;
    services['user_service_endpoint'] =
        config.userServiceUrl ?? config.serviceBaseUrl;
    services['message_service_endpoint'] =
        config.messageServiceUrl ?? config.serviceBaseUrl;
    services['did_domain'] = config.didDomain;
    if (config.anpServiceUrl != null) {
      services['anp_service_endpoint'] = config.anpServiceUrl;
    }
    if (config.anpServiceDid != null) {
      services['anp_service_did'] = config.anpServiceDid;
    }
    configMap['schema_version'] = 1;
    configMap['services'] = services;

    if (options.dryRun) {
      _line(
        'would write CLI config: ${redactor.redact(file.path)} '
        '(service_base_url=${config.serviceBaseUrl}, '
        'user_service_endpoint=${config.userServiceUrl ?? config.serviceBaseUrl}, '
        'message_service_endpoint=${config.messageServiceUrl ?? config.serviceBaseUrl}, '
        'did_domain=${config.didDomain})',
      );
      return;
    }
    cliWorkspaceDir.createSync(recursive: true);
    file.writeAsStringSync(_renderYamlMap(configMap));
  }

  Future<void> _prepareCliIdentity() async {
    final recover = await _cli(<String>[
      '--format',
      'json',
      'id',
      'recover',
      '--handle',
      config.cliHandle,
      '--phone',
      config.otpPhone,
      '--otp',
      config.otpCode,
    ], allowFailure: true);
    if (recover.exitCode == 0 || options.dryRun) {
      return;
    }
    if (!_looksRecoverableForRegister(recover.output)) {
      throw DesktopCliPeerFailure(
        'CLI peer recover failed and did not look like a missing-handle error.',
      );
    }
    final register = await _cli(<String>[
      '--format',
      'json',
      'id',
      'register',
      '--handle',
      config.cliHandle,
      '--phone',
      config.otpPhone,
      '--otp',
      config.otpCode,
    ], allowFailure: true);
    if (register.exitCode != 0) {
      throw DesktopCliPeerFailure('CLI peer register failed.');
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
    final flutterArgs = <String>[
      'test',
      'integration_test/desktop_cli_peer_smoke_test.dart',
      '-d',
      config.platform.name,
      '--dart-define=AWIKI_E2E=true',
      '--dart-define=AWIKI_E2E_PLATFORM=${config.platform.name}',
      '--dart-define=AWIKI_BASE_URL=${config.serviceBaseUrl}',
      '--dart-define=AWIKI_SERVICE_BASE_URL=${config.serviceBaseUrl}',
      '--dart-define=AWIKI_DID_DOMAIN=${config.didDomain}',
      '--dart-define=AWIKI_E2E_RUN_ID=$runId',
      '--dart-define=AWIKI_E2E_APP_HANDLE=${config.appHandle}',
      '--dart-define=AWIKI_E2E_CLI_HANDLE=${config.cliHandle}',
      '--dart-define=DEV_OTP_PHONE=${config.otpPhone}',
      '--dart-define=DEV_OTP_CODE=${config.otpCode}',
      '--dart-define=AWIKI_CLI_BIN=${config.cliBin}',
      '--dart-define=AWIKI_CLI_WORKSPACE_HOME_DIR=${cliWorkspaceDir.path}',
      '--dart-define=AWIKI_CLI_HOME_DIR=${cliHomeDir.path}',
      '--dart-define=AWIKI_E2E_APP_STATE_ROOT=${appStateRootDir.path}',
      if (config.userServiceUrl != null)
        '--dart-define=AWIKI_USER_SERVICE_URL=${config.userServiceUrl}',
      if (config.messageServiceUrl != null)
        '--dart-define=AWIKI_MESSAGE_SERVICE_URL=${config.messageServiceUrl}',
      if (config.mailServiceUrl != null)
        '--dart-define=AWIKI_MAIL_SERVICE_URL=${config.mailServiceUrl}',
      if (config.anpServiceUrl != null)
        '--dart-define=AWIKI_ANP_SERVICE_URL=${config.anpServiceUrl}',
      if (config.anpServiceDid != null)
        '--dart-define=AWIKI_ANP_SERVICE_DID=${config.anpServiceDid}',
    ];
    if (config.platform == DesktopE2ePlatform.linux) {
      await commands.run('xvfb-run', <String>['-a', 'flutter', ...flutterArgs]);
    } else {
      await commands.run('flutter', flutterArgs);
    }
  }

  Future<DesktopCommandResult> _cli(
    List<String> args, {
    bool allowFailure = false,
  }) {
    return commands.captureResult(
      config.cliBin,
      args,
      environment: <String, String>{
        ...environment,
        'HOME': cliHomeDir.path,
        'AWIKI_CLI_WORKSPACE_HOME_DIR': cliWorkspaceDir.path,
      },
      allowFailure: allowFailure,
    );
  }

  bool get _shouldBuildCli =>
      options.cliBin == null && _env(environment, 'AWIKI_CLI_BIN') == null;

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
        'scenario': _desktopCliPeerScenario,
        'caseIds': _desktopCliPeerCaseIds,
        'runId': runId,
        'platform': config.platform.name,
        'dryRun': options.dryRun,
        'prepareOnly': options.prepareOnly,
        'serviceBaseUrl': config.serviceBaseUrl,
        'userServiceUrl': config.userServiceUrl ?? config.serviceBaseUrl,
        'messageServiceUrl': config.messageServiceUrl ?? config.serviceBaseUrl,
        'mailServiceUrl': config.mailServiceUrl,
        'anpServiceUrl': config.anpServiceUrl,
        'anpServiceDid': config.anpServiceDid,
        'didDomain': config.didDomain,
        'appHandle': config.appHandle,
        'cliHandle': config.cliHandle,
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
      throw DesktopCliPeerFailure(
        'Required executable was not found: $executable',
      );
    }
    logLine(
      '$executable: ${result.output.trim().isEmpty ? 'dry-run' : 'found'}',
    );
  }

  Future<void> requireFile(String path) async {
    logLine('check file: ${redactor.redact(path)}');
    if (!dryRun && !File(path).existsSync()) {
      throw DesktopCliPeerFailure('Required file was not found: $path');
    }
  }

  Future<void> run(
    String executable,
    List<String> args, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool allowFailure = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final result = await captureResult(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      allowFailure: allowFailure,
      timeout: timeout,
    );
    if (result.exitCode != 0 && !allowFailure) {
      throw DesktopCliPeerFailure(
        '$executable exited with code ${result.exitCode}.',
      );
    }
  }

  Future<DesktopCommandResult> captureResult(
    String executable,
    List<String> args, {
    Directory? workingDirectory,
    Map<String, String>? environment,
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
      runInShell: false,
    ).timeout(timeout);
    final out = (result.stdout as String?) ?? '';
    final err = (result.stderr as String?) ?? '';
    final output = out.isNotEmpty ? out : err;
    if (result.exitCode != 0 && !allowFailure) {
      throw DesktopCliPeerFailure(
        redactor.redact(
          '$executable ${args.join(' ')} failed with code ${result.exitCode}.\n'
          '$err',
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

class DesktopCliPeerOptions {
  DesktopCliPeerOptions({
    required this.platform,
    required this.dryRun,
    required this.prepareOnly,
    required this.help,
    this.serviceBaseUrl,
    this.didDomain,
    this.anpServiceUrl,
    this.anpServiceDid,
    this.appHandle,
    this.cliHandle,
    this.cliBin,
    this.runId,
  });

  final DesktopE2ePlatform? platform;
  final bool dryRun;
  final bool prepareOnly;
  final bool help;
  final String? serviceBaseUrl;
  final String? didDomain;
  final String? anpServiceUrl;
  final String? anpServiceDid;
  final String? appHandle;
  final String? cliHandle;
  final String? cliBin;
  final String? runId;

  static DesktopCliPeerOptions parse(List<String> args) {
    DesktopE2ePlatform? platform;
    var dryRun = false;
    var prepareOnly = false;
    var help = false;
    String? serviceBaseUrl;
    String? didDomain;
    String? anpServiceUrl;
    String? anpServiceDid;
    String? appHandle;
    String? cliHandle;
    String? cliBin;
    String? runId;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--platform':
          index += 1;
          if (index >= args.length) {
            throw DesktopCliPeerFailure('--platform requires a value.');
          }
          platform = DesktopE2ePlatform.parse(args[index]);
          break;
        case '--service-base-url':
          serviceBaseUrl = _takeValue(args, ++index, '--service-base-url');
          break;
        case '--did-domain':
          didDomain = _takeValue(args, ++index, '--did-domain');
          break;
        case '--anp-service-url':
          anpServiceUrl = _takeValue(args, ++index, '--anp-service-url');
          break;
        case '--anp-service-did':
          anpServiceDid = _takeValue(args, ++index, '--anp-service-did');
          break;
        case '--app-handle':
          appHandle = _takeValue(args, ++index, '--app-handle');
          break;
        case '--cli-handle':
          cliHandle = _takeValue(args, ++index, '--cli-handle');
          break;
        case '--cli-bin':
          cliBin = _takeValue(args, ++index, '--cli-bin');
          break;
        case '--run-id':
          runId = _takeValue(args, ++index, '--run-id');
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
          throw DesktopCliPeerFailure('Unknown argument: $arg');
      }
    }

    return DesktopCliPeerOptions(
      platform: platform,
      dryRun: dryRun,
      prepareOnly: prepareOnly,
      help: help,
      serviceBaseUrl: serviceBaseUrl,
      didDomain: didDomain,
      anpServiceUrl: anpServiceUrl,
      anpServiceDid: anpServiceDid,
      appHandle: appHandle,
      cliHandle: cliHandle,
      cliBin: cliBin,
      runId: runId,
    );
  }

  static void printUsage() {
    stdout.writeln('''
Run the AWiki Me Desktop App + CLI peer E2E smoke.

Usage:
  dart run tool/desktop_cli_peer_e2e_runner.dart --platform linux [--dry-run] [--prepare-only]

Options:
  --platform macos|linux       Desktop platform target.
  --service-base-url URL       Overrides AWIKI_SERVICE_BASE_URL/AWIKI_BASE_URL.
  --did-domain DOMAIN          Overrides AWIKI_DID_DOMAIN.
  --app-handle HANDLE          App-side test handle.
  --cli-handle HANDLE          CLI peer test handle.
  --cli-bin PATH               Existing awiki-cli binary.
  --run-id ID                  Stable run id for repeatable local debugging.
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
    this.userServiceUrl,
    this.messageServiceUrl,
    this.mailServiceUrl,
    this.anpServiceUrl,
    this.anpServiceDid,
  });

  final DesktopE2ePlatform platform;
  final String serviceBaseUrl;
  final String didDomain;
  final String otpPhone;
  final String otpCode;
  final String appHandle;
  final String cliHandle;
  final String cliBin;
  final String? userServiceUrl;
  final String? messageServiceUrl;
  final String? mailServiceUrl;
  final String? anpServiceUrl;
  final String? anpServiceDid;

  static DesktopCliPeerConfig from(
    DesktopCliPeerOptions options,
    Map<String, String> environment,
  ) {
    final platform =
        options.platform ??
        (throw DesktopCliPeerFailure('--platform is required.'));
    final serviceBaseUrl =
        options.serviceBaseUrl ??
        _env(environment, 'AWIKI_SERVICE_BASE_URL') ??
        _env(environment, 'AWIKI_BASE_URL') ??
        'https://awiki.ai';
    final didDomain =
        options.didDomain ??
        _env(environment, 'AWIKI_DID_DOMAIN') ??
        'awiki.ai';
    final otpPhone =
        _env(environment, 'DEV_OTP_PHONE') ??
        (options.dryRun ? '<DEV_OTP_PHONE>' : null);
    final otpCode =
        _env(environment, 'DEV_OTP_CODE') ??
        (options.dryRun ? '<DEV_OTP_CODE>' : null);
    if (otpPhone == null || otpPhone.isEmpty) {
      throw DesktopCliPeerFailure('DEV_OTP_PHONE is required.');
    }
    if (otpCode == null || otpCode.isEmpty) {
      throw DesktopCliPeerFailure('DEV_OTP_CODE is required.');
    }
    final appHandle =
        options.appHandle ??
        _env(environment, 'AWIKI_E2E_APP_HANDLE') ??
        'awiki-e2e-app';
    final cliHandle =
        options.cliHandle ??
        _env(environment, 'AWIKI_E2E_CLI_HANDLE') ??
        'awiki-e2e-cli';
    if (appHandle.toLowerCase() == cliHandle.toLowerCase()) {
      throw DesktopCliPeerFailure('App handle and CLI handle must differ.');
    }
    final cliBin =
        options.cliBin ??
        _env(environment, 'AWIKI_CLI_BIN') ??
        '../awiki-cli-rs2/target/release/awiki-cli';
    return DesktopCliPeerConfig(
      platform: platform,
      serviceBaseUrl: serviceBaseUrl,
      didDomain: didDomain,
      otpPhone: otpPhone,
      otpCode: otpCode,
      appHandle: appHandle,
      cliHandle: cliHandle,
      cliBin: cliBin,
      userServiceUrl: _env(environment, 'AWIKI_USER_SERVICE_URL'),
      messageServiceUrl: _env(environment, 'AWIKI_MESSAGE_SERVICE_URL'),
      mailServiceUrl: _env(environment, 'AWIKI_MAIL_SERVICE_URL'),
      anpServiceUrl:
          options.anpServiceUrl ?? _env(environment, 'AWIKI_ANP_SERVICE_URL'),
      anpServiceDid:
          options.anpServiceDid ?? _env(environment, 'AWIKI_ANP_SERVICE_DID'),
    );
  }
}

enum DesktopE2ePlatform {
  macos,
  linux;

  static DesktopE2ePlatform parse(String value) {
    return switch (value.trim().toLowerCase()) {
      'macos' => DesktopE2ePlatform.macos,
      'linux' => DesktopE2ePlatform.linux,
      _ => throw DesktopCliPeerFailure(
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

  factory DesktopSecretRedactor.fromEnvironment(Map<String, String> env) {
    return DesktopSecretRedactor(<String>[
      env['DEV_OTP_PHONE'] ?? '',
      env['DEV_OTP_CODE'] ?? '',
      env['AWIKI_JWT'] ?? '',
      env['AWIKI_TOKEN'] ?? '',
      env['AWIKI_CLI_WORKSPACE_HOME_DIR'] ?? '',
      env['AWIKI_E2E_APP_STATE_ROOT'] ?? '',
    ]);
  }

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

class DesktopCliPeerFailure implements Exception {
  DesktopCliPeerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

bool _looksRecoverableForRegister(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not found') ||
      lower.contains('handle_not_found') ||
      lower.contains('not_registered') ||
      lower.contains('not registered') ||
      lower.contains('404');
}

String? _env(Map<String, String> environment, String key) {
  final value = environment[key]?.trim();
  return value == null || value.isEmpty ? null : value;
}

String _takeValue(List<String> args, int index, String flag) {
  if (index >= args.length) {
    throw DesktopCliPeerFailure('$flag requires a value.');
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
    throw DesktopCliPeerFailure('$path must be a map.');
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
  throw DesktopCliPeerFailure('$key must be configured as a map.');
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
