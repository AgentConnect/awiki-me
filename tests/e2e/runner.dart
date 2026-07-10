import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'case_attestation.dart';

const String _defaultDesktopE2eConfigPath = 'tests/e2e/configs/e2e.local.yaml';
const String _desktopE2eSuiteManifestPath = 'tests/e2e/suite_manifest.json';
const String _desktopCliPeerRunConfigPath =
    '.e2e/desktop-cli-peer/current/run_config.json';
const String _desktopCliPeerProductTimingsFileName = 'product_timings.json';
const String _caseAttestationFileName = 'case_attestation.json';
const String _messageAgentRunConfigPath =
    '.e2e/message-agent/current/run_config.json';
const String _codexAgentRunConfigPath =
    '.e2e/codex-agent/current/run_config.json';
const String _claudeCodeAgentRunConfigPath =
    '.e2e/claude-code-agent/current/run_config.json';
const String _desktopCliPeerScenario = 'desktop-app-cli-peer';
const String _desktopCliPeerPerformanceScenario =
    'desktop-app-cli-peer-performance';
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
const List<String> _desktopCliPeerPerformanceCaseIds = <String>[
  'PERF-E2E-001', // real backend App + CLI peer performance gate.
  'PERF-E2E-002', // multi-conversation dataset coverage.
  'PERF-E2E-003', // cold App shell and conversation-list visible timings.
  'PERF-E2E-004', // snapshot, fast local hydrate, and full hydrate timings.
  'PERF-E2E-005', // App -> CLI send-to-visible latency.
  'PERF-E2E-006', // CLI -> App send-to-visible latency.
  'PERF-E2E-007', // no full conversation refresh during send/receive gate.
  'PERF-E2E-008', // long-thread open/load timing.
  'PERF-E2E-009', // product timing report schema.
  'PERF-E2E-010', // hard budget failure semantics.
  'PERF-E2E-011', // soft budget warning semantics.
  'PERF-E2E-012', // retained failure diagnostics.
];
const Set<String> _desktopCliPeerPerformanceRequiredMetrics = <String>{
  'app.bootstrap_create_ms',
  'app.launch_to_shell_visible_ms',
  'performance_dataset.prepare_ms',
  'conversation_list.remote_sync_warmup_ms',
  'conversation_list.warmup_fast_local_ms',
  'conversation_list.warmup_item_count',
  'conversation_list.snapshot_load_ms',
  'conversation_list.snapshot_item_count',
  'conversation_list.fast_local_hydrate_ms',
  'conversation_list.fast_local_item_count',
  'conversation_list.fast_local_page_scan_ms',
  'conversation_list.fast_local_paged_item_count',
  'conversation_list.full_hydrate_ms',
  'conversation_list.full_hydrate_item_count',
  'conversation_list.full_page_scan_ms',
  'conversation_list.full_paged_item_count',
  'conversation_list.first_non_empty_visible_ms',
  'performance_dataset.long_thread_prepare_ms',
  'message.app_send_to_local_visible_ms',
  'message.app_send_to_cli_inbox_visible_ms',
  'message.app_send_to_cli_history_visible_ms',
  'message.cli_send_app_thread_after_ms',
  'message.cli_send_to_app_open_first_paint_ms',
  'message.cli_send_to_app_history_visible_ms',
  'message.cli_send_to_conversation_preview_visible_ms',
  'thread.realtime_open_first_paint_ms',
  'thread.history_initial_load_ms',
  'thread.open_to_first_message_visible_ms',
  'thread.initial_item_count',
  'cache.raw_thread_state_count',
  'cache.canonical_thread_count',
  'cache.total_retained_messages',
  'cache.active_patch_subscription_count',
  'cache.message_route_entry_count',
  'cache.trimmed_message_count',
  'cache.evicted_thread_count',
  'cache.protected_overflow_count',
};
const Set<String> _desktopCliPeerPerformanceRequiredDatasetFields = <String>{
  'conversationCountTarget',
  'conversationCountObserved',
  'warmupConversationCountObserved',
  'visibleConversationCountObserved',
  'longThreadMessageCountTarget',
  'longThreadMessageCountObserved',
};
const Set<String> _desktopCliPeerPerformanceRequiredCounters = <String>{
  'performance_dataset.existing_count',
  'performance_dataset.created_count',
  'performance_dataset.long_thread_initial_count',
  'performance_dataset.long_thread_created_count',
  'performance_dataset.long_thread_observed_count',
  'message_sync.warmup_events_applied',
  'message_sync.warmup_pages_fetched',
  'message_sync.warmup_snapshot_required_count',
  'message_sync.warmup_has_more_count',
  'conversation_list.fast_local_pages_fetched',
  'conversation_list.full_pages_fetched',
  'conversation.full_refresh_during_send_receive_count',
  'conversation.list_conversations_calls_total',
  'conversation.patch_apply_count',
  'conversation.patch_repair_count',
  'cache.trimmed_message_count',
  'cache.evicted_thread_count',
  'cache.protected_overflow_count',
};
const int _desktopCliPeerPerformanceMaxCachedMessages = 1200;
const int _desktopCliPeerPerformanceMaxCachedCanonicalThreads = 100;
const int _desktopCliPeerPerformanceMaxActivePatchSubscriptions = 100;
const List<String> _messageAgentCaseIds = <String>[
  'MSGAGENT-E2E-001', // App UI selects daemon and enables Message Agent.
  'MSGAGENT-E2E-002', // CLI peer message is recovered into App UI.
  'MSGAGENT-E2E-004', // UI revoke converges in User Service and daemon state.
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
  late final Directory appIdentityWorkspaceDir;
  late final Directory appIdentityHomeDir;
  late final Directory appStateRootDir;
  late final File runConfigFile;
  late final File productTimingsFile;
  late final File caseAttestationFile;
  late final File resourceLedgerFile;
  late final DesktopE2eSuiteManifest suiteManifest;
  late final DesktopE2eSuiteDefinition suiteDefinition;
  final List<DesktopTimingEntry> _timings = <DesktopTimingEntry>[];
  final Map<String, E2eCaseAttestationResult> _attestedCases =
      <String, E2eCaseAttestationResult>{};
  String? _caseAttestationError;
  DesktopProductTimingReport? _productTimingReport;
  DesktopPerformanceBudgetResult? _performanceBudgetResult;
  Map<String, Object?> _identityPreflight = const <String, Object?>{
    'status': 'not_run',
  };
  String? _failureCode;
  String? _failureSummary;
  bool _resourceSideEffectsPossible = false;

  Future<void> run() async {
    suiteManifest = DesktopE2eSuiteManifest.load(root);
    suiteDefinition = suiteManifest.definitionFor(options.e2eCase);
    suiteDefinition.validateCodeCaseIds(options.e2eCase.caseIds);
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
    appIdentityWorkspaceDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/app-identity-cli',
    );
    appIdentityHomeDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/app-identity-home',
    );
    appStateRootDir = Directory('${root.path}/.e2e/$runScope/$runId/app');
    runConfigFile = File('${root.path}/${options.e2eCase.runConfigPath}');
    productTimingsFile = File(
      '${reportDir.path}/$_desktopCliPeerProductTimingsFileName',
    );
    caseAttestationFile = File('${reportDir.path}/$_caseAttestationFileName');
    resourceLedgerFile = File('${reportDir.path}/resource_ledger.json');
    _addRuntimeSecret(reportDir.path);
    _addRuntimeSecret(cliWorkspaceDir.path);
    _addRuntimeSecret(cliHomeDir.path);
    _addRuntimeSecret(appIdentityWorkspaceDir.path);
    _addRuntimeSecret(appIdentityHomeDir.path);
    _addRuntimeSecret(appStateRootDir.path);
    _addRuntimeSecret(runConfigFile.path);
    _addRuntimeSecret(productTimingsFile.path);
    _addRuntimeSecret(caseAttestationFile.path);
    _addRuntimeSecret(resourceLedgerFile.path);
    if (!options.dryRun && !options.prepareOnly) {
      if (caseAttestationFile.existsSync()) {
        caseAttestationFile.deleteSync();
      }
      final temporary = File('${caseAttestationFile.path}.tmp');
      if (temporary.existsSync()) {
        temporary.deleteSync();
      }
    }
    if (!options.dryRun && options.e2eCase.requiresCliPeer) {
      cliWorkspaceDir.createSync(recursive: true);
      cliHomeDir.createSync(recursive: true);
      appIdentityWorkspaceDir.createSync(recursive: true);
      appIdentityHomeDir.createSync(recursive: true);
      appStateRootDir.createSync(recursive: true);
    }

    final totalStopwatch = Stopwatch()..start();
    var orchestrationSucceeded = false;
    try {
      if (options.e2eCase == DesktopE2eCase.smoke) {
        await _runLocalSmoke();
      } else {
        await _runAppCliPeer();
      }
      orchestrationSucceeded = true;
      if (!options.dryRun && !options.prepareOnly) {
        _loadCaseAttestation(requireComplete: true);
      }
    } on DesktopCommandTimeout catch (error) {
      _failureCode = 'command_timeout';
      _failureSummary = error.safeSummary;
      if (!options.dryRun && !options.prepareOnly) {
        _loadCaseAttestation(requireComplete: false);
      }
      rethrow;
    } on E2eFailure catch (error) {
      final failure = _classifyFailure(error);
      _failureCode = failure.code;
      _failureSummary = failure.summary;
      if (!options.dryRun && !options.prepareOnly) {
        _loadCaseAttestation(requireComplete: false);
      }
      rethrow;
    } on Object catch (error) {
      _failureCode = 'unexpected_error';
      _failureSummary = 'Unexpected ${error.runtimeType}.';
      if (!options.dryRun && !options.prepareOnly) {
        _loadCaseAttestation(requireComplete: false);
      }
      rethrow;
    } finally {
      totalStopwatch.stop();
      _writeResourceLedger();
      _writeTimingReport(
        orchestrationSucceeded: orchestrationSucceeded,
        totalElapsed: totalStopwatch.elapsed,
      );
      _printTimingSummary(
        orchestrationSucceeded: orchestrationSucceeded,
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
      return _runFlutterTest(
        'integration_test/app_smoke_test.dart',
        caseIds: const <String>['SMOKE-E2E-001'],
      );
    });
    await _timed('Flutter native IM Core smoke', () {
      return _runFlutterTest(
        'integration_test/im_core_open_smoke_test.dart',
        caseIds: const <String>['NATIVE-E2E-001'],
      );
    });
  }

  Future<void> _runAppCliPeer() async {
    final peerConfig = DesktopCliPeerConfig.from(options, fileConfig);
    config = peerConfig;
    if (!options.dryRun && !commands.dryRun) {
      suiteDefinition.validateRemoteTarget(peerConfig);
    }
    _addRuntimeSecret(peerConfig.otpPhone);
    _addRuntimeSecret(peerConfig.otpCode);
    _addRuntimeSecret(peerConfig.cliBin);
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
    if (peerConfig.e2eCase == DesktopE2eCase.performance) {
      await _timed(
        'Preparing performance App identity',
        _preparePerformanceAppIdentity,
      );
    }

    if (options.prepareOnly) {
      _section('Prepare-only completed');
      _line('Flutter desktop E2E was not started.');
      return;
    }
    await _writeFlutterRunConfig(peerConfig);
    await _timed('Flutter App + CLI peer flow', _planFlutterDesktopSmoke);
    if (!options.dryRun && peerConfig.e2eCase == DesktopE2eCase.performance) {
      _productTimingReport = _readProductTimingReport();
      _performanceBudgetResult = DesktopPerformanceBudgetResult.evaluate(
        config: peerConfig.performance,
        report: _productTimingReport,
      );
      final failures = _performanceBudgetResult!.hardFailures;
      if (failures.isNotEmpty) {
        throw E2eFailure(
          'Performance E2E budget failed: ${failures.join('; ')}',
        );
      }
    } else if (peerConfig.e2eCase == DesktopE2eCase.performance) {
      _performanceBudgetResult = DesktopPerformanceBudgetResult(
        hardFailures: const <String>[],
        softWarnings: const <String>[],
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
    final peerConfig = _requireConfig();
    if (peerConfig.platform == DesktopE2ePlatform.linux) {
      await commands.requireExecutable('xvfb-run');
    }
    await commands.requireFile(peerConfig.cliBin);
  }

  Future<void> _prepareCliWorkspace() async {
    await _cli(const <String>['--format', 'json', 'init']);
    await _prepareCliTenant(workspaceDir: cliWorkspaceDir, homeDir: cliHomeDir);
    await _writeCliConfig(cliWorkspaceDir);
    await _cli(const <String>['--format', 'json', 'config', 'show']);
  }

  Future<void> _prepareCliTenant({
    required Directory workspaceDir,
    required Directory homeDir,
  }) async {
    final peerConfig = _requireConfig();
    final tenantName = _tenantName;
    await _cliForWorkspace(
      workspaceDir: workspaceDir,
      homeDir: homeDir,
      args: <String>[
        '--format',
        'json',
        'tenant',
        'create',
        tenantName,
        '--backend-base-url',
        peerConfig.serviceBaseUrl,
        '--did-host',
        peerConfig.didDomain,
        '--display-name',
        'AWiki E2E $runId',
      ],
    );
    await _cliForWorkspace(
      workspaceDir: workspaceDir,
      homeDir: homeDir,
      args: <String>['--format', 'json', 'tenant', 'use', tenantName],
    );
    await _cliForWorkspace(
      workspaceDir: workspaceDir,
      homeDir: homeDir,
      args: const <String>['--format', 'json', 'tenant', 'current'],
    );
  }

  String get _tenantName {
    final suffix = runId
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final bounded = suffix.length <= 40 ? suffix : suffix.substring(0, 40);
    return 'e2e-${bounded.isEmpty ? 'run' : bounded}';
  }

  Future<void> _writeCliConfig(Directory workspaceDir) async {
    final peerConfig = _requireConfig();
    final file = File('${workspaceDir.path}/tenants/$_tenantName/config.yaml');
    final configMap = file.existsSync()
        ? _toStringKeyMap(loadYaml(file.readAsStringSync()), path: 'config')
        : <String, Object?>{};
    final services = _mapAt(configMap, 'services', optional: true);
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
        '(tenant_backend=${peerConfig.serviceBaseUrl}, '
        'tenant_did_host=${peerConfig.didDomain}, '
        'anp_service_endpoint=${services['anp_service_endpoint']}, '
        'anp_service_did=${services['anp_service_did']}, '
        'mail_service_url=${services['mail_service_url']})',
      );
    } else {
      workspaceDir.createSync(recursive: true);
    }
    file.parent.createSync(recursive: true);
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
    _resourceSideEffectsPossible = true;
  }

  Future<void> _checkCliReady() async {
    final peerConfig = _requireConfig();
    final current = await _cli(const <String>[
      '--format',
      'json',
      'id',
      'current',
    ]);
    await _cli(const <String>['--format', 'json', 'id', 'status']);
    await _cli(const <String>[
      '--format',
      'json',
      'msg',
      'inbox',
      '--limit',
      '1',
    ]);
    if (options.dryRun || commands.dryRun) {
      _identityPreflight = <String, Object?>{
        'status': options.dryRun ? 'dry_run' : 'not_executed_command_stub',
        'cliHandleMatchesCurrent': false,
        'appHandleResolvable': false,
        'identitiesDistinct': false,
      };
      return;
    }
    if (!isAuditableGitSha(peerConfig.cliSourceRef)) {
      throw E2eFailure(
        'cliPeer.sourceRef must be the exact non-zero 40-character commit SHA used to build the CLI/SDK.',
      );
    }
    final cliResolved = await _cli(<String>[
      '--format',
      'json',
      'id',
      'resolve',
      '--handle',
      peerConfig.cliHandle,
    ]);
    final appResolved = await _cli(<String>[
      '--format',
      'json',
      'id',
      'resolve',
      '--handle',
      peerConfig.appHandle,
    ]);
    final currentDid = _cliDidFromJson(current.output, current: true);
    final cliDid = _cliDidFromJson(cliResolved.output);
    final appDid = _cliDidFromJson(appResolved.output);
    final cliMatches = currentDid == cliDid;
    final identitiesDistinct = currentDid != appDid;
    _identityPreflight = <String, Object?>{
      'status': cliMatches && identitiesDistinct ? 'passed' : 'failed',
      'cliHandleMatchesCurrent': cliMatches,
      'appHandleResolvable': true,
      'identitiesDistinct': identitiesDistinct,
      'containsRawDids': false,
    };
    if (!cliMatches) {
      throw E2eFailure('CLI peer identity mismatch.');
    }
    if (!identitiesDistinct) {
      throw E2eFailure('App and CLI peer identities must be distinct.');
    }
  }

  Future<void> _preparePerformanceAppIdentity() async {
    final peerConfig = _requireConfig();
    await _cliForWorkspace(
      workspaceDir: appIdentityWorkspaceDir,
      homeDir: appIdentityHomeDir,
      args: const <String>['--format', 'json', 'init'],
    );
    await _prepareCliTenant(
      workspaceDir: appIdentityWorkspaceDir,
      homeDir: appIdentityHomeDir,
    );
    await _writeCliConfig(appIdentityWorkspaceDir);
    await _cliForWorkspace(
      workspaceDir: appIdentityWorkspaceDir,
      homeDir: appIdentityHomeDir,
      args: const <String>['--format', 'json', 'config', 'show'],
    );
    final recover = await _cliForWorkspace(
      workspaceDir: appIdentityWorkspaceDir,
      homeDir: appIdentityHomeDir,
      args: <String>[
        '--format',
        'json',
        'id',
        'recover',
        '--handle',
        peerConfig.appHandle,
        '--phone',
        peerConfig.otpPhone,
        '--otp',
        peerConfig.otpCode,
      ],
      allowFailure: true,
    );
    if (recover.exitCode == 0 || options.dryRun) {
      return;
    }
    if (!_looksRecoverableForRegister(recover.output)) {
      throw E2eFailure(
        'Performance App identity recover failed and did not look like a '
        'missing-handle error: ${redactor.redact(recover.output)}',
      );
    }
    final register = await _cliForWorkspace(
      workspaceDir: appIdentityWorkspaceDir,
      homeDir: appIdentityHomeDir,
      args: <String>[
        '--format',
        'json',
        'id',
        'register',
        '--handle',
        peerConfig.appHandle,
        '--phone',
        peerConfig.otpPhone,
        '--otp',
        peerConfig.otpCode,
      ],
      allowFailure: true,
    );
    if (register.exitCode != 0) {
      throw E2eFailure(
        'Performance App identity register failed: '
        '${redactor.redact(register.output)}',
      );
    }
  }

  Future<void> _planFlutterDesktopSmoke() async {
    final peerConfig = _requireConfig();
    final flutterArgs = <String>[
      'test',
      '--dart-define=AWIKI_E2E=true',
      '--dart-define=AWIKI_E2E_APP_STATE_ROOT=${appStateRootDir.path}',
      peerConfig.e2eCase.testFile,
      '-d',
      peerConfig.platform.name,
      ..._caseAttestationDartDefines(suiteDefinition.caseIds),
    ];
    _resourceSideEffectsPossible = true;
    await _runFlutterArgs(
      flutterArgs,
      platform: peerConfig.platform,
      timeout: _effectiveFlutterTimeout(peerConfig),
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
        'sourceRef': peerConfig.cliSourceRef,
        'workspace': cliWorkspaceDir.path,
        'home': cliHomeDir.path,
      },
      'suite': <String, Object?>{
        'manifestRevision': suiteManifest.sourceRevision,
        'tier': suiteDefinition.tier,
        'cleanupPolicy': suiteDefinition.cleanupPolicy,
      },
      'app': <String, Object?>{'stateRoot': appStateRootDir.path},
      'performance': <String, Object?>{
        'enabled': peerConfig.e2eCase == DesktopE2eCase.performance,
        'productTimingsPath': productTimingsFile.path,
        'datasetConversationCount':
            peerConfig.performance.datasetConversationCount,
        'longThreadMessageCount': peerConfig.performance.longThreadMessageCount,
        'requiredMetrics': peerConfig.performance.requiredMetrics.toList(),
        'hardBudgetMs': peerConfig.performance.hardBudgetMs,
        'softBudgetMs': peerConfig.performance.softBudgetMs,
        'maxFullRefreshDuringSendReceive':
            peerConfig.performance.maxFullRefreshDuringSendReceive,
      },
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

  Future<void> _runFlutterTest(
    String testFile, {
    required List<String> caseIds,
  }) {
    return _runFlutterArgs(
      <String>[
        'test',
        '--dart-define=AWIKI_E2E=true',
        '--dart-define=AWIKI_E2E_APP_STATE_ROOT=${appStateRootDir.path}',
        testFile,
        '-d',
        platform.name,
        ..._caseAttestationDartDefines(caseIds),
      ],
      platform: platform,
      timeout: suiteDefinition.timeout,
    );
  }

  List<String> _caseAttestationDartDefines(List<String> caseIds) => <String>[
    '--dart-define=$e2eCaseAttestationPathDefine=${caseAttestationFile.path}',
    '--dart-define=$e2eCaseScenarioDefine=${options.e2eCase.scenario}',
    '--dart-define=$e2eCaseRunIdDefine=$runId',
    '--dart-define=$e2eCaseIdsDefine=${caseIds.join(',')}',
  ];

  Future<void> _runFlutterArgs(
    List<String> flutterArgs, {
    required DesktopE2ePlatform platform,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (platform == DesktopE2ePlatform.linux) {
      await commands.run('xvfb-run', <String>[
        '-a',
        'flutter',
        ...flutterArgs,
      ], timeout: timeout);
      return;
    }
    await commands.run('flutter', flutterArgs, timeout: timeout);
  }

  Future<DesktopCommandResult> _cli(
    List<String> args, {
    bool allowFailure = false,
  }) {
    return _cliForWorkspace(
      workspaceDir: cliWorkspaceDir,
      homeDir: cliHomeDir,
      args: args,
      allowFailure: allowFailure,
    );
  }

  Future<DesktopCommandResult> _cliForWorkspace({
    required Directory workspaceDir,
    required Directory homeDir,
    required List<String> args,
    bool allowFailure = false,
  }) {
    final environment = <String, String>{
      'HOME': homeDir.path,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': workspaceDir.path,
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

  DesktopProductTimingReport _readProductTimingReport() {
    if (!productTimingsFile.existsSync()) {
      throw E2eFailure(
        'Performance product timing report was not written: '
        '${productTimingsFile.path}',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(productTimingsFile.readAsStringSync());
    } on Object catch (error) {
      throw E2eFailure(
        'Performance product timing report is not valid JSON: $error',
      );
    }
    if (decoded is! Map) {
      throw E2eFailure(
        'Performance product timing report must be a JSON object.',
      );
    }
    return DesktopProductTimingReport.fromJson(<String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    });
  }

  void _loadCaseAttestation({required bool requireComplete}) {
    try {
      final attestation = E2eCaseAttestation.read(caseAttestationFile);
      final validation = E2eCaseAttestationValidation.validate(
        attestation: attestation,
        expectedScenario: options.e2eCase.scenario,
        expectedRunId: runId,
        expectedCaseIds: suiteDefinition.caseIds,
      );
      _attestedCases
        ..clear()
        ..addEntries(
          validation.caseById.entries.where(
            (entry) => suiteDefinition.caseIds.contains(entry.key),
          ),
        );
      _caseAttestationError = validation.passed
          ? null
          : validation.errors.join('; ');
      if (!requireComplete) {
        return;
      }
      if (!validation.passed) {
        throw FormatException(validation.errors.join('; '));
      }
    } on Object catch (error) {
      final message = redactor.redact(error.toString());
      _caseAttestationError = message;
      if (requireComplete) {
        throw E2eFailure('E2E case attestation failed closed: $message');
      }
    }
  }

  String _caseStatus(String caseId) {
    if (options.dryRun) {
      return 'dry_run';
    }
    if (options.prepareOnly) {
      return 'prepared';
    }
    return _attestedCases[caseId]?.status ?? 'not_run';
  }

  String _suiteStatus({required bool orchestrationSucceeded}) {
    if (!orchestrationSucceeded) {
      return 'failed';
    }
    if (options.dryRun) {
      return 'dry_run';
    }
    if (options.prepareOnly) {
      return 'prepared';
    }
    final allPassed = suiteDefinition.caseIds.every(
      (caseId) => _caseStatus(caseId) == 'passed',
    );
    return orchestrationSucceeded && allPassed ? 'passed' : 'failed';
  }

  void _writeTimingReport({
    required bool orchestrationSucceeded,
    required Duration totalElapsed,
  }) {
    final productTimingReport = _productTimingReport;
    final performanceBudgetResult = _performanceBudgetResult;
    const encoder = JsonEncoder.withIndent('  ');
    final file = File(_timingsPath);
    if (!options.dryRun) {
      reportDir.createSync(recursive: true);
    }
    file.writeAsStringSync(
      encoder.convert(<String, Object?>{
        'schemaVersion': 2,
        'status': _suiteStatus(orchestrationSucceeded: orchestrationSucceeded),
        'mode': options.dryRun
            ? 'dry_run'
            : options.prepareOnly
            ? 'prepared'
            : 'real',
        'scenario': (config?.e2eCase ?? options.e2eCase).scenario,
        'caseIds': suiteDefinition.caseIds,
        'passedCaseIds': <String>[
          for (final caseId in suiteDefinition.caseIds)
            if (_caseStatus(caseId) == 'passed') caseId,
        ],
        'caseResults': <Map<String, Object?>>[
          for (final caseId in suiteDefinition.caseIds)
            <String, Object?>{
              'caseId': caseId,
              'status': _caseStatus(caseId),
              'mode': options.dryRun
                  ? 'dry_run'
                  : options.prepareOnly
                  ? 'prepared'
                  : 'real',
              if (_attestedCases[caseId] != null)
                'startedAt': _attestedCases[caseId]!.startedAt,
              if (_attestedCases[caseId] != null)
                'finishedAt': _attestedCases[caseId]!.finishedAt,
              'phases': _attestedCases[caseId]?.phases ?? const <String>[],
            },
        ],
        'attestation': <String, Object?>{
          'schemaVersion': e2eCaseAttestationSchemaVersion,
          'path': '<redacted-attestation-path>',
          'status': options.dryRun
              ? 'not_expected_dry_run'
              : options.prepareOnly
              ? 'not_expected_prepared'
              : _caseAttestationError == null &&
                    suiteDefinition.caseIds.every(
                      (caseId) => _caseStatus(caseId) == 'passed',
                    )
              ? 'verified'
              : 'invalid',
          if (_caseAttestationError != null) 'error': _caseAttestationError,
        },
        'runId': runId,
        'platform': platform.name,
        'case': (config?.e2eCase ?? options.e2eCase).caseName,
        'suiteManifest': <String, Object?>{
          'schemaVersion': suiteManifest.schemaVersion,
          'sourceRevision': suiteManifest.sourceRevision,
          'path': _desktopE2eSuiteManifestPath,
        },
        'suitePolicy': suiteDefinition.toReportJson(),
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
        if (config != null)
          'anpServiceDid': config!.anpServiceDid == null
              ? null
              : '<redacted-service-did>',
        if (config != null) 'didDomain': config!.didDomain,
        if (config != null) 'appHandle': config!.appHandle,
        if (config != null) 'cliHandle': config!.cliHandle,
        if (config != null) 'cliSourceRef': config!.cliSourceRef,
        if (config != null) 'sdkSourceRef': config!.cliSourceRef,
        'identityPreflight': _identityPreflight,
        'resourceLifecycle': <String, Object?>{
          'cleanupPolicy': suiteDefinition.cleanupPolicy,
          'cleanupStatus': _resourceCleanupStatus,
          'reasonCode': _resourceCleanupReasonCode,
          'ledgerPath': '<redacted-resource-ledger-path>',
        },
        if (_failureCode != null)
          'failure': <String, Object?>{
            'code': _failureCode,
            'summary': _failureSummary ?? 'E2E failed.',
          },
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
        if (config?.e2eCase == DesktopE2eCase.performance)
          'dataset':
              productTimingReport?.dataset ??
              config?.performance.dataset.toJson(),
        if (config?.e2eCase == DesktopE2eCase.performance)
          'budgets': config!.performance.budgetsJson(),
        if (productTimingReport != null) 'metrics': productTimingReport.metrics,
        if (productTimingReport != null)
          'counters': productTimingReport.counters,
        if (productTimingReport != null)
          'appProductTimings': productTimingReport.appProductTimings,
        if (config?.e2eCase == DesktopE2eCase.performance)
          'toolingTimings': [
            for (final entry in _timings)
              <String, Object?>{
                'name': entry.name,
                'status': entry.succeeded ? 'success' : 'failed',
                'elapsedMs': entry.elapsed.inMilliseconds,
              },
          ],
        if (performanceBudgetResult != null)
          'hardFailures': performanceBudgetResult.hardFailures,
        if (performanceBudgetResult != null)
          'softWarnings': performanceBudgetResult.softWarnings,
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

  Duration _effectiveFlutterTimeout(DesktopCliPeerConfig peerConfig) {
    if (peerConfig.e2eCase != DesktopE2eCase.performance) {
      return suiteDefinition.timeout;
    }
    final performanceTimeout = peerConfig.flutterTimeout;
    return performanceTimeout > suiteDefinition.timeout
        ? performanceTimeout
        : suiteDefinition.timeout;
  }

  String _cliDidFromJson(String output, {bool current = false}) {
    Object? decoded;
    try {
      decoded = jsonDecode(output);
    } on Object {
      throw E2eFailure('CLI identity preflight returned invalid JSON.');
    }
    if (decoded is! Map) {
      throw E2eFailure('CLI identity preflight returned an invalid object.');
    }
    final data = decoded['data'];
    if (data is! Map) {
      throw E2eFailure('CLI identity preflight omitted data.');
    }
    if (current) {
      final identity = data['identity'];
      final did = identity is Map ? identity['did'] : null;
      if (did is String && did.trim().isNotEmpty) {
        return did.trim();
      }
    } else {
      for (final key in const <String>['lookup', 'resolve']) {
        final value = data[key];
        final did = value is Map ? value['did'] : null;
        if (did is String && did.trim().isNotEmpty) {
          return did.trim();
        }
      }
    }
    throw E2eFailure('CLI identity preflight omitted a canonical DID.');
  }

  String get _resourceCleanupStatus {
    if (options.dryRun) {
      return 'not_applicable_dry_run';
    }
    if (options.prepareOnly || !_resourceSideEffectsPossible) {
      return 'not_needed';
    }
    return suiteDefinition.cleanupPolicy == 'none' ? 'not_needed' : 'residual';
  }

  String get _resourceCleanupReasonCode {
    if (_resourceCleanupStatus != 'residual') {
      return 'none';
    }
    return 'remote_public_delete_api_unavailable';
  }

  void _writeResourceLedger() {
    reportDir.createSync(recursive: true);
    final targetHost = config == null
        ? null
        : Uri.tryParse(config!.serviceBaseUrl)?.host;
    resourceLedgerFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'runId': runId,
        'scenario': options.e2eCase.scenario,
        'suite': options.e2eCase.caseName,
        'namespace': runId,
        'targetHost': targetHost,
        'cleanupPolicy': suiteDefinition.cleanupPolicy,
        'cleanupStatus': _resourceCleanupStatus,
        'reasonCode': _resourceCleanupReasonCode,
        'resourceCategories': suiteDefinition.resourceCategories,
        'resourceCounts': <String, Object?>{
          'fixedIdentityPool': config == null ? 0 : 2,
          'createdIdentities': _resourceSideEffectsPossible ? 'unknown' : 0,
          'messages': _resourceSideEffectsPossible ? 'unknown' : 0,
          'groups': _resourceSideEffectsPossible ? 'unknown' : 0,
          'attachments': _resourceSideEffectsPossible ? 'unknown' : 0,
        },
        'identityPreflightStatus': _identityPreflight['status'],
        'containsRawDids': false,
        'containsSecrets': false,
        if (config != null) 'cliSourceRef': config!.cliSourceRef,
      }),
    );
  }

  ({String code, String summary}) _classifyFailure(E2eFailure error) {
    final message = redactor.redact(error.message);
    if (message.contains('CLI peer identity mismatch') ||
        message.contains('id resolve') ||
        message.contains('identity preflight')) {
      return (
        code: 'identity_preflight_failed',
        summary:
            'Remote account-pool identity preflight failed; inspect the redacted runner log.',
      );
    }
    if (message.contains('cliPeer.sourceRef')) {
      return (
        code: 'source_ref_unverified',
        summary: 'CLI/SDK source ref is missing or not an exact commit SHA.',
      );
    }
    if (message.contains('audited remote')) {
      return (
        code: 'target_policy_failed',
        summary:
            'The product E2E target does not match the audited remote policy.',
      );
    }
    if (message.startsWith('flutter ') || message.startsWith('xvfb-run ')) {
      return (
        code: 'flutter_product_failed',
        summary:
            'Flutter product E2E failed; inspect case attestation and the redacted runner log.',
      );
    }
    final firstLine = message.split('\n').first.trim();
    return (
      code: 'e2e_failure',
      summary: firstLine.length <= 240
          ? firstLine
          : '${firstLine.substring(0, 237)}...',
    );
  }

  void _printTimingSummary({
    required bool orchestrationSucceeded,
    required Duration totalElapsed,
  }) {
    _section('Timing summary');
    _line(
      'status: ${_suiteStatus(orchestrationSucceeded: orchestrationSucceeded)}',
    );
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

class DesktopE2eSuiteManifest {
  DesktopE2eSuiteManifest({
    required this.schemaVersion,
    required this.sourceRevision,
    required this.definitions,
  });

  final int schemaVersion;
  final String sourceRevision;
  final Map<String, DesktopE2eSuiteDefinition> definitions;

  static DesktopE2eSuiteManifest load(Directory root) {
    final scopedFile = File('${root.path}/$_desktopE2eSuiteManifestPath');
    final repositoryFile = File(_desktopE2eSuiteManifestPath);
    final file = scopedFile.existsSync() ? scopedFile : repositoryFile;
    if (!file.existsSync()) {
      throw E2eFailure('E2E suite manifest was not found.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Object {
      throw E2eFailure('E2E suite manifest is not valid JSON.');
    }
    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      throw E2eFailure('E2E suite manifest must use schemaVersion 1.');
    }
    final sourceRevision = decoded['sourceRevision'];
    final suites = decoded['suites'];
    if (sourceRevision is! String || sourceRevision.trim().isEmpty) {
      throw E2eFailure('E2E suite manifest has no sourceRevision.');
    }
    if (suites is! Map) {
      throw E2eFailure('E2E suite manifest has no suites object.');
    }
    final definitions = <String, DesktopE2eSuiteDefinition>{};
    for (final entry in suites.entries) {
      final name = entry.key.toString();
      final raw = entry.value;
      if (raw is! Map) {
        throw E2eFailure('E2E suite "$name" must be an object.');
      }
      definitions[name] = DesktopE2eSuiteDefinition.fromJson(name, raw);
    }
    return DesktopE2eSuiteManifest(
      schemaVersion: 1,
      sourceRevision: sourceRevision.trim(),
      definitions: definitions,
    );
  }

  DesktopE2eSuiteDefinition definitionFor(DesktopE2eCase e2eCase) {
    final definition = definitions[e2eCase.caseName];
    if (definition == null) {
      throw E2eFailure(
        'E2E suite manifest does not define ${e2eCase.caseName}.',
      );
    }
    return definition;
  }
}

class DesktopE2eSuiteDefinition {
  DesktopE2eSuiteDefinition({
    required this.name,
    required this.tier,
    required this.requiredFor,
    required this.owner,
    required this.estimatedMinutes,
    required this.timeout,
    required this.cleanupPolicy,
    required this.allowedHosts,
    required this.allowedDidDomains,
    required this.resourceCategories,
    required this.caseIds,
  });

  final String name;
  final String tier;
  final List<String> requiredFor;
  final String owner;
  final int estimatedMinutes;
  final Duration timeout;
  final String cleanupPolicy;
  final List<String> allowedHosts;
  final List<String> allowedDidDomains;
  final List<String> resourceCategories;
  final List<String> caseIds;

  static DesktopE2eSuiteDefinition fromJson(String name, Map raw) {
    List<String> stringList(String key) {
      final value = raw[key];
      if (value is! List || value.any((item) => item is! String)) {
        throw E2eFailure('E2E suite "$name" has invalid $key.');
      }
      return value.cast<String>();
    }

    final tier = raw['tier'];
    final owner = raw['owner'];
    final estimatedMinutes = raw['estimatedMinutes'];
    final timeoutMinutes = raw['timeoutMinutes'];
    final cleanupPolicy = raw['cleanupPolicy'];
    if (tier is! String || tier.trim().isEmpty) {
      throw E2eFailure('E2E suite "$name" has no tier.');
    }
    if (owner is! String || owner.trim().isEmpty) {
      throw E2eFailure('E2E suite "$name" has no owner.');
    }
    if (estimatedMinutes is! int || estimatedMinutes <= 0) {
      throw E2eFailure('E2E suite "$name" has invalid estimatedMinutes.');
    }
    if (timeoutMinutes is! int || timeoutMinutes <= 0) {
      throw E2eFailure('E2E suite "$name" has invalid timeoutMinutes.');
    }
    if (cleanupPolicy is! String || cleanupPolicy.trim().isEmpty) {
      throw E2eFailure('E2E suite "$name" has no cleanupPolicy.');
    }
    final caseIds = stringList('caseIds');
    if (caseIds.isEmpty || caseIds.toSet().length != caseIds.length) {
      throw E2eFailure('E2E suite "$name" has missing or duplicate caseIds.');
    }
    return DesktopE2eSuiteDefinition(
      name: name,
      tier: tier.trim(),
      requiredFor: stringList('requiredFor'),
      owner: owner.trim(),
      estimatedMinutes: estimatedMinutes,
      timeout: Duration(minutes: timeoutMinutes),
      cleanupPolicy: cleanupPolicy.trim(),
      allowedHosts: stringList('allowedHosts'),
      allowedDidDomains: stringList('allowedDidDomains'),
      resourceCategories: stringList('resourceCategories'),
      caseIds: caseIds,
    );
  }

  void validateCodeCaseIds(List<String> codeCaseIds) {
    if (!_sameOrderedStrings(caseIds, codeCaseIds)) {
      throw E2eFailure(
        'E2E suite manifest drift for "$name"; caseIds do not match the Flutter scenario contract.',
      );
    }
  }

  void validateRemoteTarget(DesktopCliPeerConfig config) {
    if (allowedHosts.isEmpty && allowedDidDomains.isEmpty) {
      return;
    }
    if (!allowedDidDomains.contains(config.didDomain)) {
      throw E2eFailure(
        'E2E suite "$name" must target an audited remote DID domain.',
      );
    }
    final urls = <String>[
      config.serviceBaseUrl,
      config.userServiceUrl ?? config.serviceBaseUrl,
      config.messageServiceUrl ?? config.serviceBaseUrl,
    ];
    for (final value in urls) {
      final uri = Uri.tryParse(value);
      if (uri == null || !allowedHosts.contains(uri.host)) {
        throw E2eFailure(
          'E2E suite "$name" must target an audited remote host.',
        );
      }
      if (uri.scheme != 'https') {
        throw E2eFailure(
          'E2E suite "$name" requires secure remote service URLs.',
        );
      }
    }
    final ws = config.messageServiceWsUrl;
    final wsUri = ws == null ? null : Uri.tryParse(ws);
    if (wsUri == null ||
        wsUri.scheme != 'wss' ||
        !allowedHosts.contains(wsUri.host) ||
        wsUri.path != '/im/ws') {
      throw E2eFailure(
        'E2E suite "$name" requires the audited remote WebSocket endpoint.',
      );
    }
  }

  Map<String, Object?> toReportJson() => <String, Object?>{
    'tier': tier,
    'requiredFor': requiredFor,
    'owner': owner,
    'estimatedMinutes': estimatedMinutes,
    'timeoutMinutes': timeout.inMinutes,
    'cleanupPolicy': cleanupPolicy,
    'unexpectedSkipBudget': 0,
  };
}

bool _sameOrderedStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool isAuditableGitSha(String value) {
  final normalized = value.trim();
  return RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(normalized) &&
      !RegExp(r'^0{40}$').hasMatch(normalized);
}

String _basename(String path) {
  return path.replaceAll('\\', '/').split('/').last;
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
    final process = await Process.start(
      executable,
      args,
      workingDirectory: (workingDirectory ?? root).path,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final exitFuture = process.exitCode;
    int processExitCode;
    try {
      processExitCode = await exitFuture.timeout(timeout);
    } on TimeoutException {
      final terminated = await _terminateProcessTree(process);
      try {
        await exitFuture.timeout(const Duration(seconds: 2));
      } on Object {
        // The tree has already received a hard-kill fallback below.
      }
      throw DesktopCommandTimeout(
        executable: executable,
        timeout: timeout,
        terminated: terminated,
      );
    }
    final out = await stdoutFuture;
    final err = await stderrFuture;
    final output = out.isNotEmpty ? out : err;
    if (processExitCode != 0 && !allowFailure) {
      throw E2eFailure(
        redactor.redact(
          '$executable ${args.join(' ')} failed with code $processExitCode.\n'
          'stdout:\n$out\n'
          'stderr:\n$err',
        ),
      );
    }
    return DesktopCommandResult(exitCode: processExitCode, output: output);
  }

  Future<bool> _terminateProcessTree(Process process) async {
    if (Platform.isWindows) {
      final result = await Process.run('taskkill', <String>[
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]);
      return result.exitCode == 0;
    }
    final descendants = await _descendantPids(process.pid);
    var signalled = false;
    for (final pid in descendants.reversed) {
      signalled = Process.killPid(pid, ProcessSignal.sigterm) || signalled;
    }
    signalled = process.kill(ProcessSignal.sigterm) || signalled;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (final pid in descendants.reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    process.kill(ProcessSignal.sigkill);
    return signalled;
  }

  Future<List<int>> _descendantPids(int parentPid) async {
    final descendants = <int>[];
    final queue = <int>[parentPid];
    while (queue.isNotEmpty) {
      final parent = queue.removeLast();
      ProcessResult result;
      try {
        result = await Process.run('pgrep', <String>[
          '-P',
          '$parent',
        ]).timeout(const Duration(seconds: 1));
      } on Object {
        continue;
      }
      if (result.exitCode != 0) {
        continue;
      }
      final children = (result.stdout as String)
          .split(RegExp(r'\s+'))
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      descendants.addAll(children);
      queue.addAll(children);
    }
    return descendants;
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

class DesktopCommandTimeout extends E2eFailure {
  DesktopCommandTimeout({
    required this.executable,
    required this.timeout,
    required this.terminated,
  }) : super(
         '$executable timed out after ${timeout.inMilliseconds}ms; '
         'child process tree termination ${terminated ? 'was requested' : 'could not be confirmed'}.',
       );

  final String executable;
  final Duration timeout;
  final bool terminated;

  String get safeSummary =>
      'Command ${_basename(executable)} timed out after '
      '${timeout.inMilliseconds}ms; child process tree terminated=$terminated.';
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
  dart run tests/e2e/runner.dart --case performance
  dart run tests/e2e/runner.dart --case message-agent
  dart run tests/e2e/runner.dart --case codex-agent
  dart run tests/e2e/runner.dart --case claude-code-agent

Options:
  --config PATH                Local YAML config. Defaults to $_defaultDesktopE2eConfigPath.
  --run-id ID                  Stable run id for repeatable local debugging.
  --case smoke|full|performance|direct|group|attachment|contacts|message-agent|codex-agent|claude-code-agent
                               smoke runs local App/native checks. The other
                               cases run real App+CLI peer flows. The
                               performance case records product-level startup,
                               conversation, and send-to-visible timings and
                               applies the configured performance budgets. The
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
    required this.cliSourceRef,
    required this.e2eCase,
    required this.performance,
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
  final String cliSourceRef;
  final DesktopE2eCase e2eCase;
  final DesktopPerformanceConfig performance;
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

  Duration get flutterTimeout {
    if (e2eCase == DesktopE2eCase.performance) {
      return performance.flutterTimeout;
    }
    return e2eCase.flutterTimeout;
  }

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
      cliSourceRef: fileConfig.cliSourceRef ?? 'unrecorded',
      e2eCase: options.e2eCase,
      performance: fileConfig.performance ?? DesktopPerformanceConfig.defaults,
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
    this.cliSourceRef,
    this.performance,
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
      cliBin = null,
      cliSourceRef = null,
      performance = null;

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
  final String? cliSourceRef;
  final DesktopPerformanceConfig? performance;

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
    final performance = _mapAt(raw, 'performance', optional: true);
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
      cliSourceRef: _stringAt(cliPeer, 'sourceRef'),
      performance: DesktopPerformanceConfig.fromYaml(performance),
    );
  }
}

class DesktopPerformanceDataset {
  const DesktopPerformanceDataset({
    required this.conversationCountTarget,
    required this.longThreadMessageCountTarget,
  });

  final int conversationCountTarget;
  final int longThreadMessageCountTarget;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'conversationCountTarget': conversationCountTarget,
      'longThreadMessageCountTarget': longThreadMessageCountTarget,
    };
  }
}

class DesktopPerformanceConfig {
  DesktopPerformanceConfig({
    required this.datasetConversationCount,
    required this.longThreadMessageCount,
    required this.requiredMetrics,
    required this.hardBudgetMs,
    required this.softBudgetMs,
    required this.maxFullRefreshDuringSendReceive,
  });

  static final DesktopPerformanceConfig defaults = DesktopPerformanceConfig(
    datasetConversationCount: 100,
    longThreadMessageCount: 100,
    requiredMetrics: _desktopCliPeerPerformanceRequiredMetrics,
    hardBudgetMs: const <String, int>{
      'app.launch_to_shell_visible_ms': 30000,
      'conversation_list.first_non_empty_visible_ms': 10000,
      'conversation_list.snapshot_load_ms': 5000,
      'conversation_list.fast_local_hydrate_ms': 5000,
      'conversation_list.fast_local_page_scan_ms': 30000,
      'conversation_list.full_hydrate_ms': 15000,
      'conversation_list.full_page_scan_ms': 60000,
      'message.app_send_to_cli_inbox_visible_ms': 90000,
      'message.app_send_to_cli_history_visible_ms': 90000,
      'message.cli_send_app_thread_after_ms': 90000,
      'message.cli_send_to_app_open_first_paint_ms': 90000,
      'message.cli_send_to_app_history_visible_ms': 90000,
      'message.cli_send_to_conversation_preview_visible_ms': 90000,
      'thread.realtime_open_first_paint_ms': 5000,
      'thread.open_to_first_message_visible_ms': 8000,
      'thread.history_initial_load_ms': 8000,
    },
    softBudgetMs: const <String, int>{
      'app.launch_to_shell_visible_ms': 15000,
      'conversation_list.first_non_empty_visible_ms': 3000,
      'conversation_list.snapshot_load_ms': 1000,
      'conversation_list.fast_local_hydrate_ms': 1500,
      'conversation_list.fast_local_page_scan_ms': 15000,
      'conversation_list.full_hydrate_ms': 5000,
      'conversation_list.full_page_scan_ms': 30000,
      'message.app_send_to_cli_inbox_visible_ms': 20000,
      'message.app_send_to_cli_history_visible_ms': 20000,
      'message.cli_send_app_thread_after_ms': 20000,
      'message.cli_send_to_app_open_first_paint_ms': 5000,
      'message.cli_send_to_app_history_visible_ms': 20000,
      'message.cli_send_to_conversation_preview_visible_ms': 20000,
      'thread.realtime_open_first_paint_ms': 1500,
      'thread.open_to_first_message_visible_ms': 3000,
      'thread.history_initial_load_ms': 3000,
    },
    maxFullRefreshDuringSendReceive: 0,
  );

  final int datasetConversationCount;
  final int longThreadMessageCount;
  final Set<String> requiredMetrics;
  final Map<String, int> hardBudgetMs;
  final Map<String, int> softBudgetMs;
  final int maxFullRefreshDuringSendReceive;

  Duration get flutterTimeout {
    const baseMinutes = 12;
    final extraConversations = datasetConversationCount - 500;
    if (extraConversations <= 0) {
      return const Duration(minutes: baseMinutes);
    }
    final extraBlocks = (extraConversations + 249) ~/ 250;
    return Duration(minutes: baseMinutes + extraBlocks * 6);
  }

  DesktopPerformanceDataset get dataset => DesktopPerformanceDataset(
    conversationCountTarget: datasetConversationCount,
    longThreadMessageCountTarget: longThreadMessageCount,
  );

  Map<String, Object?> budgetsJson() {
    return <String, Object?>{
      'requiredMetrics': requiredMetrics.toList()..sort(),
      'hardBudgetMs': hardBudgetMs,
      'softBudgetMs': softBudgetMs,
      'maxFullRefreshDuringSendReceive': maxFullRefreshDuringSendReceive,
    };
  }

  static DesktopPerformanceConfig fromYaml(Map<String, Object?> map) {
    final defaults = DesktopPerformanceConfig.defaults;
    final dataset = _mapAt(map, 'dataset', optional: true);
    final budgets = _mapAt(map, 'budgets', optional: true);
    return DesktopPerformanceConfig(
      datasetConversationCount:
          _intAt(dataset, 'conversationCount') ??
          defaults.datasetConversationCount,
      longThreadMessageCount:
          _intAt(dataset, 'longThreadMessageCount') ??
          defaults.longThreadMessageCount,
      requiredMetrics: <String>{
        ...defaults.requiredMetrics,
        ...?_stringSetAt(budgets, 'requiredMetrics'),
      },
      hardBudgetMs: <String, int>{
        ...defaults.hardBudgetMs,
        ...?_intMapAt(budgets, 'hardBudgetMs'),
      },
      softBudgetMs: <String, int>{
        ...defaults.softBudgetMs,
        ...?_intMapAt(budgets, 'softBudgetMs'),
      },
      maxFullRefreshDuringSendReceive:
          _intAt(budgets, 'maxFullRefreshDuringSendReceive') ??
          defaults.maxFullRefreshDuringSendReceive,
    );
  }
}

class DesktopProductTimingReport {
  DesktopProductTimingReport({
    required this.dataset,
    required this.metrics,
    required this.counters,
    required this.appProductTimings,
  });

  final Map<String, Object?> dataset;
  final Map<String, num> metrics;
  final Map<String, int> counters;
  final List<Map<String, Object?>> appProductTimings;

  static DesktopProductTimingReport fromJson(Map<String, Object?> json) {
    final dataset = _jsonMapAt(json, 'dataset');
    final metrics = <String, num>{};
    for (final entry in _jsonMapAt(json, 'metrics').entries) {
      final value = entry.value;
      if (value is num) {
        metrics[entry.key] = value;
      }
    }
    final counters = <String, int>{};
    for (final entry in _jsonMapAt(json, 'counters').entries) {
      final value = entry.value;
      if (value is int) {
        counters[entry.key] = value;
      } else if (value is num) {
        counters[entry.key] = value.round();
      }
    }
    final productTimings = <Map<String, Object?>>[];
    final rawTimings = json['appProductTimings'];
    if (rawTimings is List) {
      for (final value in rawTimings) {
        if (value is Map) {
          productTimings.add(<String, Object?>{
            for (final entry in value.entries)
              entry.key.toString(): entry.value,
          });
        }
      }
    }
    return DesktopProductTimingReport(
      dataset: dataset,
      metrics: metrics,
      counters: counters,
      appProductTimings: productTimings,
    );
  }
}

class DesktopPerformanceBudgetResult {
  DesktopPerformanceBudgetResult({
    required this.hardFailures,
    required this.softWarnings,
  });

  final List<String> hardFailures;
  final List<String> softWarnings;

  static DesktopPerformanceBudgetResult evaluate({
    required DesktopPerformanceConfig config,
    required DesktopProductTimingReport? report,
  }) {
    final hardFailures = <String>[];
    final softWarnings = <String>[];
    if (report == null) {
      hardFailures.add('missing product timing report');
      return DesktopPerformanceBudgetResult(
        hardFailures: hardFailures,
        softWarnings: softWarnings,
      );
    }
    for (final metric in config.requiredMetrics) {
      if (!report.metrics.containsKey(metric)) {
        hardFailures.add('missing required metric $metric');
      }
    }
    for (final field in _desktopCliPeerPerformanceRequiredDatasetFields) {
      if (!report.dataset.containsKey(field)) {
        hardFailures.add('missing required dataset field $field');
      }
    }
    for (final counter in _desktopCliPeerPerformanceRequiredCounters) {
      if (!report.counters.containsKey(counter)) {
        hardFailures.add('missing required counter $counter');
      }
    }
    final observedConversations =
        _numFromJson(report.dataset['visibleConversationCountObserved']) ?? 0;
    if (observedConversations < config.datasetConversationCount) {
      hardFailures.add(
        'dataset conversation count $observedConversations is below target '
        '${config.datasetConversationCount}',
      );
    }
    final observedLongThread =
        _numFromJson(report.dataset['longThreadMessageCountObserved']) ?? 0;
    if (observedLongThread < config.longThreadMessageCount) {
      hardFailures.add(
        'long thread message count $observedLongThread is below target '
        '${config.longThreadMessageCount}',
      );
    }
    final fullRefreshCount =
        report
            .counters['conversation.full_refresh_during_send_receive_count'] ??
        0;
    if (fullRefreshCount > config.maxFullRefreshDuringSendReceive) {
      hardFailures.add(
        'conversation full refresh during send/receive count $fullRefreshCount '
        'exceeds ${config.maxFullRefreshDuringSendReceive}',
      );
    }
    final totalRetainedMessages =
        _numFromJson(report.metrics['cache.total_retained_messages']) ?? 0;
    final protectedOverflowCount =
        report.counters['cache.protected_overflow_count'] ?? 0;
    final maxRetainedMessages =
        _desktopCliPeerPerformanceMaxCachedMessages + protectedOverflowCount;
    if (totalRetainedMessages > maxRetainedMessages) {
      hardFailures.add(
        'cache total retained messages ${totalRetainedMessages.round()} '
        'exceeds $maxRetainedMessages',
      );
    }
    final canonicalThreadCount =
        _numFromJson(report.metrics['cache.canonical_thread_count']) ?? 0;
    final maxCanonicalThreads =
        _desktopCliPeerPerformanceMaxCachedCanonicalThreads +
        protectedOverflowCount;
    if (canonicalThreadCount > maxCanonicalThreads) {
      hardFailures.add(
        'cache canonical thread count ${canonicalThreadCount.round()} '
        'exceeds $maxCanonicalThreads',
      );
    }
    final activePatchSubscriptions =
        _numFromJson(report.metrics['cache.active_patch_subscription_count']) ??
        0;
    if (activePatchSubscriptions >
        _desktopCliPeerPerformanceMaxActivePatchSubscriptions) {
      hardFailures.add(
        'cache active patch subscription count '
        '${activePatchSubscriptions.round()} exceeds '
        '$_desktopCliPeerPerformanceMaxActivePatchSubscriptions',
      );
    }
    for (final entry in config.hardBudgetMs.entries) {
      final actual = report.metrics[entry.key];
      if (actual != null && actual > entry.value) {
        hardFailures.add(
          '${entry.key} ${actual.round()}ms exceeds hard budget '
          '${entry.value}ms',
        );
      }
    }
    for (final entry in config.softBudgetMs.entries) {
      final actual = report.metrics[entry.key];
      if (actual != null && actual > entry.value) {
        softWarnings.add(
          '${entry.key} ${actual.round()}ms exceeds soft budget '
          '${entry.value}ms',
        );
      }
    }
    return DesktopPerformanceBudgetResult(
      hardFailures: hardFailures,
      softWarnings: softWarnings,
    );
  }
}

enum DesktopE2eCase {
  smoke(_desktopSmokeCaseIds),
  full(_desktopCliPeerCaseIds),
  performance(_desktopCliPeerPerformanceCaseIds),
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
      DesktopE2eCase.performance =>
        'integration_test/desktop_cli_peer_performance_test.dart',
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
      DesktopE2eCase.performance => const Duration(minutes: 12),
      _ => const Duration(minutes: 5),
    };
  }

  String get scenario {
    return switch (this) {
      DesktopE2eCase.messageAgent => _messageAgentScenario,
      DesktopE2eCase.codexAgent => _codexAgentScenario,
      DesktopE2eCase.claudeCodeAgent => _claudeCodeAgentScenario,
      DesktopE2eCase.performance => _desktopCliPeerPerformanceScenario,
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
      'performance' ||
      'perf' ||
      'startup-performance' ||
      'startup_performance' ||
      'conversation-performance' ||
      'conversation_performance' => DesktopE2eCase.performance,
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
        'Use smoke, full, performance, direct, group, attachment, contacts, '
        'message-agent, codex-agent, or claude-code-agent.',
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
    output = output.replaceAll(
      RegExp(r'did:[A-Za-z0-9._%~/-]+(?::[A-Za-z0-9._%~/-]+)+'),
      '<redacted-did>',
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

int? _intAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  final parsed = int.tryParse(value.toString().trim());
  if (parsed == null) {
    throw E2eFailure('$key must be an integer value.');
  }
  return parsed;
}

Set<String>? _stringSetAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw E2eFailure('$key must be a list of strings.');
  }
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toSet();
}

Map<String, int>? _intMapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return null;
  }
  if (value is! Map<String, Object?>) {
    throw E2eFailure('$key must be configured as a map.');
  }
  return <String, int>{
    for (final entry in value.entries) entry.key: _intAt(value, entry.key) ?? 0,
  };
}

Map<String, Object?> _jsonMapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return <String, Object?>{};
}

num? _numFromJson(Object? value) {
  if (value is num) {
    return value;
  }
  return num.tryParse(value?.toString() ?? '');
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
    return <String, Object?>{};
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
