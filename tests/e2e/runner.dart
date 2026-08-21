import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:yaml/yaml.dart';

import 'account_state_operator_contract.dart';
import 'app_pair_protocol.dart';
import 'case_attestation.dart';
import 'host_platform.dart';
import 'performance_contract.dart';
import 'prepared_integration_process.dart';
import 'remote_multi_device_join_contract.dart';
import 'runner/failure.dart';
import 'runner/flutter_build_isolation.dart';
import 'runner/manifest.dart';
import 'runner/platform.dart';
import 'runner/process_runner.dart';
import 'runner/redaction.dart';
import '../../tool/ensure_linux_im_core.dart';
import '../../tool/isolated_e2e_app_builder.dart' show directorySha256;

export 'runner/failure.dart';
export 'runner/flutter_build_isolation.dart';
export 'runner/manifest.dart';
export 'runner/platform.dart';
export 'runner/process_runner.dart';
export 'runner/redaction.dart';

part 'runner/scenarios/app_pair.dart';
part 'runner/scenarios/desktop_peer.dart';
part 'runner/scenarios/join.dart';
part 'runner/scenarios/recovery.dart';
part 'runner/config.dart';
part 'runner/app_artifacts.dart';
part 'runner/options.dart';
part 'runner/performance.dart';
part 'runner/reporting.dart';

const String _defaultDesktopE2eConfigPath = 'tests/e2e/configs/e2e.local.yaml';
const String _desktopCliPeerRunConfigPath =
    '.e2e/desktop-cli-peer/current/run_config.json';
const String _desktopCliPeerProductTimingsFileName = 'product_timings.json';
const String _caseAttestationFileName = 'case_attestation.json';
const String _personalAgentRunConfigPath =
    '.e2e/personal-agent/current/run_config.json';
const String _codexAgentRunConfigPath =
    '.e2e/codex-agent/current/run_config.json';
const String _claudeCodeAgentRunConfigPath =
    '.e2e/claude-code-agent/current/run_config.json';
const String _desktopCliPeerScenario = 'desktop-app-cli-peer';
const String _desktopCliPeerPerformanceScenario =
    'desktop-app-cli-peer-performance';
const String _multiDeviceCapabilityGateScenario =
    'multi-device-capability-gate';
const String _multiDeviceRemoteJoinScenario =
    'multi-device-remote-message-driven-member-join';
const String _multiDeviceRemoteJoinRunConfigPath =
    '.e2e/multi-device-remote-join/current/run_config.json';
const String _multiDeviceRemoteRecoveryScenario =
    'multi-device-handle-recovery-v1';
const String _multiDeviceRemoteRecoveryFreshScenario =
    'multi-device-handle-recovery-fresh-v1';
const String _handleRecoveryLocalDataScenario = 'handle-recovery-local-data-v1';
const String _multiDeviceAppPairRecoveryRegistrationScenario =
    'multi-device-app-pair-recovery-registration-rejoin-management-transfer';
const String _multiDeviceRemoteRecoveryRunConfigPath =
    '.e2e/multi-device-remote-recovery/current/run_config.json';
const String _multiDeviceAppPairScenario =
    'multi-device-two-isolated-app-member-join';
const String _multiDeviceAppPairFunctionalScenario =
    'multi-device-two-isolated-app-functional';
const String _multiDeviceAppPairContentSyncScenario =
    'multi-device-two-isolated-app-content-sync';
const String _multiDeviceAppPairRunConfigPath =
    '.e2e/multi-device-app-pair/current/run_config.json';
const String _multiDeviceAppPairTarget =
    'integration_test/multi_device_app_pair_test.dart';
const String _multiDeviceRemoteJoinGateEnv =
    'AWIKI_MULTI_DEVICE_REMOTE_JOIN_E2E_ENABLED';
const String _multiDeviceRemoteRecoveryGateEnv =
    'AWIKI_MULTI_DEVICE_REMOTE_RECOVERY_E2E_ENABLED';
const String _multiDeviceRemoteHandlePrefixEnv =
    'AWIKI_MULTI_DEVICE_E2E_HANDLE_PREFIX';
const String _syncRecoveryEnableEnv = 'AWIKI_MESSAGE_SYNC_V2_RECOVERY_E2E';
const String _syncRecoveryOperatorModeEnv =
    'AWIKI_MULTI_DEVICE_E2E_OPERATOR_MODE';
const String _syncRecoveryTargetEnv = 'AWIKI_SYSTEM_TEST_TARGET';
const String _syncRecoveryTarget = 'awiki-info-testing';
const String _accountStateEnableEnv = 'AWIKI_ACCOUNT_STATE_V1_E2E';
const String _accountStateOperatorCommandEnv =
    'AWIKI_ACCOUNT_STATE_E2E_OPERATOR_COMMAND_JSON';
const String _accountStateFailpointEnableEnv =
    'AWIKI_ACCOUNT_STATE_TEST_FAILPOINTS_ENABLED';
const String _remoteTargetManifestEnv = 'AWIKI_SYSTEM_TEST_TARGET_MANIFEST';
const String _awikiCliRustRepoEnv = 'AWIKI_CLI_RUST_REPO';
const String _preparedAppArtifactDirectoryEnv =
    'AWIKI_E2E_PREPARED_APP_ARTIFACT_DIR';
const String _requiredPreparedAppArtifactsEnv =
    'AWIKI_E2E_REQUIRED_PREPARED_APP_ARTIFACTS';
const String _e2eCliBinaryEnv = 'AWIKI_E2E_CLI_BINARY';
const String _e2eCliSourceRefEnv = 'AWIKI_E2E_CLI_SOURCE_REF';
const String _e2eDaemonBinaryEnv = 'AWIKI_E2E_DAEMON_BINARY';
const String _e2eOtpPhoneEnv = 'AWIKI_E2E_OTP_PHONE';
const String _e2eOtpCodeEnv = 'AWIKI_E2E_OTP_CODE';
const String _defaultRemoteTargetManifestPath =
    '../awiki-system-test/suites/remote-test-targets.json';
const Set<String> _accountStateRequiredTargetCapabilities = <String>{
  'multi-device-v1',
  'message-sync-v2',
  'account-state-sync-v1',
};
const String _desktopCliPeerDisplayName = 'AWiki E2E CLI Peer';
const String _personalAgentScenario = 'personal-agent-full-ui';
const String _codexAgentScenario = 'codex-agent-full-ui';
const String _claudeCodeAgentScenario = 'claude-code-agent-full-ui';
const List<String> _desktopCliPeerCaseIds = <String>[
  'AUTH-E2E-001',
  'CONV-CANON-E2E-001',
  'MSG-E2E-001',
  'MSG-E2E-002',
  'MSG-REG-001',
  'DISPLAY-NAME-REG-001',
  'GROUP-CANON-E2E-001',
  'GROUP-E2E-001',
  'GROUP-E2E-002',
  'GROUP-P9-001',
  'GROUP-P9-002',
  'GROUP-REG-001',
  'CONTACT-E2E-001',
  'CONTACT-E2E-002',
  'CONTACT-REG-001',
  'CONTACT-MSG-E2E-001',
  'CONV-LIST-E2E-001',
  'UNREAD-MULTI-E2E-001',
  'MSG-SEQUENCE-E2E-001',
  'DISPLAY-NAME-E2E-001',
  'ATTACH-E2E-001',
  'ATTACH-E2E-002',
  'ATTACH-REG-001',
  'DISPLAY-NAME-E2E-004',
  'ROOT-TRANSFER-E2E-001',
];
const List<String> _desktopSmokeCaseIds = <String>[
  'AGENT-NOTIFY-SMOKE-E2E-001',
  'AGENT-STALE-DAEMON-DELETE-SMOKE-E2E-001',
  'SMOKE-E2E-001',
  'NATIVE-E2E-001',
];
const List<String> _multiDeviceCapabilityGateCaseIds = <String>[
  'MULTI-DEVICE-CAPABILITY-GATE-E2E-001',
];
const List<String> _multiDeviceRemoteJoinCaseIds = <String>[
  'DEVICE-JOIN-E2E-001',
  'DEVICE-JOIN-E2E-002',
  'DEVICE-JOIN-MESSAGE-CORE-E2E-001',
];
const List<String> _multiDeviceRemoteRecoveryCaseIds = <String>[
  'HANDLE-RECOVERY-V1-E2E-001',
  'HANDLE-RECOVERY-V1-E2E-002',
  'HANDLE-RECOVERY-V1-E2E-003',
];
const List<String> _handleRecoveryLocalDataCaseIds = <String>[
  'HANDLE-RECOVERY-SETTINGS-CONTINUITY-E2E-001',
];
const List<String> _handleRecoveryFreshCaseIds = <String>[
  'HANDLE-RECOVERY-FRESH-AGENT-INVENTORY-E2E-001',
  'HANDLE-RECOVERY-FRESH-AGENT-MESSAGE-E2E-001',
  'HANDLE-RECOVERY-FRESH-DIRECT-INBOUND-E2E-001',
  'HANDLE-RECOVERY-FRESH-GROUP-REBIND-E2E-001',
  'HANDLE-RECOVERY-FRESH-GROUP-INBOUND-E2E-001',
  'HANDLE-RECOVERY-FRESH-RESTART-E2E-001',
];
const List<String> _multiDeviceAppPairRecoveryRegistrationCaseIds = <String>[
  'HANDLE-RECOVERY-REGISTRATION-REJOIN-E2E-001',
];
const List<String> _multiDeviceAppPairCaseIds = <String>[
  'DEVICE-JOIN-E2E-004',
  'DEVICE-JOIN-E2E-005',
];
const List<String> _multiDeviceAppPairFunctionalCaseIds = <String>[
  'DEVICE-AGENT-SYNC-E2E-001',
  'DEVICE-AGENT-MESSAGE-SYNC-E2E-001',
  'DEVICE-MESSAGE-SYNC-E2E-001',
  'DEVICE-MESSAGE-SYNC-E2E-002',
  'DEVICE-MESSAGE-ONLINE-SYNC-E2E-001',
  'DEVICE-MESSAGE-TAIL-ONLY-E2E-001',
  'DEVICE-MESSAGE-READ-SYNC-E2E-001',
  'DEVICE-MESSAGE-OFFLINE-RECOVERY-E2E-001',
  'DEVICE-MESSAGE-HINT-LOSS-E2E-001',
  'DEVICE-MESSAGE-RECONNECT-E2E-001',
  'DEVICE-MESSAGE-PATCH-READY-E2E-001',
  'DEVICE-MESSAGE-DIAGNOSTICS-E2E-001',
  'DEVICE-AGENT-ADD-SYNC-E2E-001',
  'DEVICE-AGENT-RENAME-SYNC-E2E-001',
  'DEVICE-AGENT-DELETE-SYNC-E2E-001',
  'DEVICE-AGENT-UNBIND-SYNC-E2E-001',
  'DEVICE-AGENT-ARCHIVE-SYNC-E2E-001',
  'DEVICE-PROFILE-SYNC-E2E-001',
  'DEVICE-ACCOUNT-DOMAIN-ISOLATION-E2E-001',
  'DEVICE-REGISTRY-SYNC-E2E-001',
  'DEVICE-MESSAGE-GENERATION-FENCE-E2E-001',
];
const List<String> _multiDeviceAppPairContentSyncCaseIds = <String>[
  'DEVICE-CONTENT-TAIL-ONLY-E2E-001',
  'DEVICE-GROUP-SYNC-E2E-001',
  'DEVICE-ATTACHMENT-SYNC-E2E-001',
  'DEVICE-GROUP-READ-SYNC-E2E-001',
];
const List<String> _step4RevokeMlsCaseIds = <String>[
  'STEP4-GROUP-PAGINATION-E2E-001',
  'DEVICE-REVOKE-E2E-001',
  'MLS-MULTI-DEVICE-E2E-002',
];
const List<String> _desktopCliPeerGroupCaseIds = <String>[
  'AUTH-E2E-001',
  'GROUP-CANON-E2E-001',
  'GROUP-E2E-001',
  'GROUP-E2E-002',
  'GROUP-P9-001',
  'GROUP-P9-002',
  'GROUP-REG-001',
];
const List<String> _desktopCliPeerDirectCaseIds = <String>[
  'AUTH-E2E-001',
  'CONV-CANON-E2E-001',
  'MSG-E2E-001',
  'MSG-E2E-002',
  'MSG-REG-001',
  'DISPLAY-NAME-REG-001',
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
  'CONTACT-MSG-E2E-001',
  'CONTACT-FIRST-CONV-E2E-001',
];
const List<String> _desktopCliPeerContactFirstCaseIds = <String>[
  'CONTACT-FIRST-CONV-E2E-001',
];
const List<String> _desktopCliPeerInboundCaseIds = <String>[
  'INBOUND-FIRST-CONV-E2E-001',
];
const List<String> _desktopIdentitySwitchCaseIds = <String>[
  'IDENTITY-SWITCH-E2E-001',
];
const List<String> _desktopCliPeerRestartCaseIds = <String>[
  'PROCESS-RESTART-E2E-001',
  'MESSAGE-PATCH-RESTART-E2E-001',
  'IDENTITY-DELETE-E2E-001',
];
const List<String> _desktopCliPeerDisplayNameFallbackCaseIds = <String>[
  'DISPLAY-NAME-E2E-002',
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
const int _desktopCliPeerPerformanceMaxCachedMessages = 1200;
const int _desktopCliPeerPerformanceMaxCachedCanonicalThreads = 100;
const int _desktopCliPeerPerformanceMaxActivePatchSubscriptions = 100;
const List<String> _personalAgentCaseIds = <String>[
  'PERSONALAGENT-E2E-001', // App UI selects daemon and enables Personal Agent.
  'PERSONALAGENT-E2E-002', // CLI peer message is recovered into App UI.
  'PERSONALAGENT-E2E-004', // UI revoke converges in User Service and daemon state.
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
    stderr.writeln('\nDesktop E2E failed: ${error.message}');
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
  RemoteMultiDeviceJoinConfig? remoteMultiDeviceJoinConfig;
  RemoteHandleRecoveryConfig? remoteHandleRecoveryConfig;
  RemoteMultiDeviceAppPairConfig? remoteMultiDeviceAppPairConfig;
  late final DesktopE2ePlatform platform;
  late final E2eHostPlatform hostPlatform;
  late final String runId;
  late final Directory reportDir;
  late final Directory cliWorkspaceDir;
  late final Directory cliHomeDir;
  late final Directory multiDeviceCliAdminWorkspaceDir;
  late final Directory multiDeviceCliAdminHomeDir;
  late final Directory rootTransferCliMemberWorkspaceDir;
  late final Directory rootTransferCliMemberHomeDir;
  late final Directory appStateRootDir;
  late final Directory multiDeviceAppJoiningStateRootDir;
  late final Directory rootTransferAppAdminStateRootDir;
  late final Directory appPairAdminStateRootDir;
  late final Directory appPairJoinerStateRootDir;
  late final Directory appPairDaemonStateRootDir;
  late final File appPairDaemonReadyFile;
  late final Directory appPairBuildRootDir;
  late final Directory appPairArtifactRootDir;
  late final File runConfigFile;
  late final File remoteMultiDeviceRunConfigFile;
  late final File appPairRunConfigFile;
  late final File productTimingsFile;
  late final File caseAttestationFile;
  late final File scenarioProgressFile;
  late final File failureObservationFile;
  late final File invocationCompletionFile;
  late final File resourceLedgerFile;
  late final File processRestartHandoffFile;
  late final File credentialDeleteMarkerFile;
  late final DesktopFlutterBuildIsolation flutterBuildIsolation;
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
      environment: Platform.environment,
    );
    _addRuntimeSecret(fileConfig.path ?? '');
    _addRuntimeSecret(fileConfig.otpPhone ?? '');
    _addRuntimeSecret(fileConfig.otpCode ?? '');
    platform = fileConfig.platform ?? DesktopE2ePlatform.fromHost();
    hostPlatform = await E2eHostPlatform.detect();
    suiteDefinition.validatePlatform(platform.name);
    if (!options.dryRun && !commands.dryRun) {
      try {
        hostPlatform.requireOperatingSystem(platform.name);
      } on StateError catch (error) {
        throw E2eFailure(error.message);
      }
    }
    flutterBuildIsolation = DesktopFlutterBuildIsolation(
      root: root,
      platform: platform,
    );
    runId = options.runId ?? _newRunId();
    final runScope = options.e2eCase.reportScope;
    reportDir = Directory('${root.path}/.e2e/$runScope/$runId/reports')
      ..createSync(recursive: true);
    commands.diagnosticDirectory = reportDir;
    cliWorkspaceDir = Directory('${root.path}/.e2e/$runScope/$runId/cli-peer');
    cliHomeDir = Directory('${root.path}/.e2e/$runScope/$runId/cli-home');
    multiDeviceCliAdminWorkspaceDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/cli-admin',
    );
    multiDeviceCliAdminHomeDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/cli-admin-home',
    );
    rootTransferCliMemberWorkspaceDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/root-transfer-cli-member',
    );
    rootTransferCliMemberHomeDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/root-transfer-cli-member-home',
    );
    appStateRootDir = Directory('${root.path}/.e2e/$runScope/$runId/app');
    multiDeviceAppJoiningStateRootDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/app-joining-device',
    );
    rootTransferAppAdminStateRootDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/root-transfer-app-admin',
    );
    appPairAdminStateRootDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/app-pair/admin-state',
    );
    appPairJoinerStateRootDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/app-pair/joiner-state',
    );
    appPairDaemonStateRootDir = Directory('${root.path}/.e2e/apf/$runId/d');
    appPairDaemonReadyFile = File(
      '${appPairDaemonStateRootDir.path}/ready.json',
    );
    appPairBuildRootDir = appPairBuildCacheRoot(root);
    appPairArtifactRootDir = Directory(
      '${root.path}/.e2e/$runScope/$runId/app-pair/artifacts',
    );
    runConfigFile = File('${root.path}/${options.e2eCase.runConfigPath}');
    remoteMultiDeviceRunConfigFile = File(
      '${root.path}/$_multiDeviceRemoteJoinRunConfigPath',
    );
    appPairRunConfigFile = File(
      '${root.path}/$_multiDeviceAppPairRunConfigPath',
    );
    productTimingsFile = File(
      '${reportDir.path}/$_desktopCliPeerProductTimingsFileName',
    );
    caseAttestationFile = File('${reportDir.path}/$_caseAttestationFileName');
    scenarioProgressFile = e2eScenarioProgressFileForAttestation(
      caseAttestationFile,
    );
    failureObservationFile = e2eFailureObservationFileForAttestation(
      caseAttestationFile,
    );
    invocationCompletionFile = e2eInvocationCompletionFileForAttestation(
      caseAttestationFile,
    );
    resourceLedgerFile = File('${reportDir.path}/resource_ledger.json');
    processRestartHandoffFile = File(
      '${reportDir.parent.path}/process_restart_handoff.json',
    );
    credentialDeleteMarkerFile = File(
      '${processRestartHandoffFile.path}.credential_deleted.json',
    );
    _addRuntimeSecret(reportDir.path);
    _addRuntimeSecret(cliWorkspaceDir.path);
    _addRuntimeSecret(cliHomeDir.path);
    _addRuntimeSecret(multiDeviceCliAdminWorkspaceDir.path);
    _addRuntimeSecret(multiDeviceCliAdminHomeDir.path);
    _addRuntimeSecret(rootTransferCliMemberWorkspaceDir.path);
    _addRuntimeSecret(rootTransferCliMemberHomeDir.path);
    _addRuntimeSecret(appStateRootDir.path);
    _addRuntimeSecret(multiDeviceAppJoiningStateRootDir.path);
    _addRuntimeSecret(rootTransferAppAdminStateRootDir.path);
    _addRuntimeSecret(appPairAdminStateRootDir.path);
    _addRuntimeSecret(appPairJoinerStateRootDir.path);
    _addRuntimeSecret(appPairDaemonStateRootDir.path);
    _addRuntimeSecret(appPairDaemonReadyFile.path);
    _addRuntimeSecret(appPairBuildRootDir.path);
    _addRuntimeSecret(appPairArtifactRootDir.path);
    _addRuntimeSecret(runConfigFile.path);
    _addRuntimeSecret(remoteMultiDeviceRunConfigFile.path);
    _addRuntimeSecret(appPairRunConfigFile.path);
    _addRuntimeSecret(productTimingsFile.path);
    _addRuntimeSecret(caseAttestationFile.path);
    _addRuntimeSecret(scenarioProgressFile.path);
    _addRuntimeSecret(failureObservationFile.path);
    _addRuntimeSecret(invocationCompletionFile.path);
    _addRuntimeSecret(resourceLedgerFile.path);
    _addRuntimeSecret(processRestartHandoffFile.path);
    _addRuntimeSecret(credentialDeleteMarkerFile.path);
    if (!options.dryRun && !options.prepareOnly) {
      if (caseAttestationFile.existsSync()) {
        caseAttestationFile.deleteSync();
      }
      final temporary = File('${caseAttestationFile.path}.tmp');
      if (temporary.existsSync()) {
        temporary.deleteSync();
      }
      if (scenarioProgressFile.existsSync()) {
        scenarioProgressFile.deleteSync();
      }
      final progressTemporary = File('${scenarioProgressFile.path}.tmp');
      if (progressTemporary.existsSync()) {
        progressTemporary.deleteSync();
      }
      if (failureObservationFile.existsSync()) {
        failureObservationFile.deleteSync();
      }
      final failureObservationTemporary = File(
        '${failureObservationFile.path}.tmp',
      );
      if (failureObservationTemporary.existsSync()) {
        failureObservationTemporary.deleteSync();
      }
      if (invocationCompletionFile.existsSync()) {
        invocationCompletionFile.deleteSync();
      }
      final completionTemporary = File('${invocationCompletionFile.path}.tmp');
      if (completionTemporary.existsSync()) completionTemporary.deleteSync();
      if (processRestartHandoffFile.existsSync()) {
        processRestartHandoffFile.deleteSync();
      }
      if (credentialDeleteMarkerFile.existsSync()) {
        credentialDeleteMarkerFile.deleteSync();
      }
    }
    if (!options.dryRun && options.e2eCase.requiresCliPeer) {
      cliWorkspaceDir.createSync(recursive: true);
      cliHomeDir.createSync(recursive: true);
      if (options.e2eCase == DesktopE2eCase.multiDeviceRemoteJoin ||
          options.e2eCase == DesktopE2eCase.multiDeviceRemoteRecovery ||
          options.e2eCase == DesktopE2eCase.step4RevokeMls) {
        multiDeviceCliAdminWorkspaceDir.createSync(recursive: true);
        multiDeviceCliAdminHomeDir.createSync(recursive: true);
        multiDeviceAppJoiningStateRootDir.createSync(recursive: true);
      }
      if (options.e2eCase == DesktopE2eCase.full) {
        rootTransferCliMemberWorkspaceDir.createSync(recursive: true);
        rootTransferCliMemberHomeDir.createSync(recursive: true);
        rootTransferAppAdminStateRootDir.createSync(recursive: true);
      }
      appStateRootDir.createSync(recursive: true);
    }
    if (!options.dryRun &&
        (options.e2eCase == DesktopE2eCase.multiDeviceRemoteRecovery ||
            options.e2eCase == DesktopE2eCase.handleRecoveryLocalData ||
            options.e2eCase == DesktopE2eCase.multiDeviceRemoteRecoveryFresh ||
            options.e2eCase ==
                DesktopE2eCase.multiDeviceAppPairRecoveryRegistration)) {
      appStateRootDir.createSync(recursive: true);
      multiDeviceAppJoiningStateRootDir.createSync(recursive: true);
    }
    if (!options.dryRun &&
        (options.e2eCase == DesktopE2eCase.multiDeviceAppPair ||
            options.e2eCase == DesktopE2eCase.multiDeviceAppPairFunctional ||
            options.e2eCase == DesktopE2eCase.multiDeviceAppPairContentSync)) {
      resetAppPairRuntimeDirectories(
        functional:
            options.e2eCase == DesktopE2eCase.multiDeviceAppPairFunctional,
        contentSync:
            options.e2eCase == DesktopE2eCase.multiDeviceAppPairContentSync,
        adminStateRoot: appPairAdminStateRootDir,
        joinerStateRoot: appPairJoinerStateRootDir,
        daemonStateRoot: appPairDaemonStateRootDir,
        cliWorkspace: cliWorkspaceDir,
        cliHome: cliHomeDir,
      );
      appPairBuildRootDir.createSync(recursive: true);
      appPairArtifactRootDir.createSync(recursive: true);
    }

    final totalStopwatch = Stopwatch()..start();
    var orchestrationSucceeded = false;
    try {
      switch (options.e2eCase) {
        case DesktopE2eCase.smoke:
          await _runLocalSmoke();
        case DesktopE2eCase.multiDevice:
          await _runLocalMultiDeviceCapabilityGate();
        case DesktopE2eCase.multiDeviceRemoteJoin:
          await _runRemoteMultiDeviceJoin();
        case DesktopE2eCase.multiDeviceRemoteRecovery:
          await _runRemoteHandleRecovery();
        case DesktopE2eCase.handleRecoveryLocalData:
          await _runRemoteHandleRecovery();
        case DesktopE2eCase.multiDeviceRemoteRecoveryFresh:
          await _runRemoteHandleRecovery();
        case DesktopE2eCase.multiDeviceAppPairRecoveryRegistration:
          await _runRemoteHandleRecovery();
        case DesktopE2eCase.multiDeviceAppPair:
          await _runRemoteMultiDeviceAppPair();
        case DesktopE2eCase.multiDeviceAppPairFunctional:
          await _runRemoteMultiDeviceAppPair();
        case DesktopE2eCase.multiDeviceAppPairContentSync:
          await _runRemoteMultiDeviceAppPair();
        case DesktopE2eCase.step4RevokeMls:
          await _runRemoteMultiDeviceJoin();
        case DesktopE2eCase.full:
          await _runFull();
        default:
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
      if (processRestartHandoffFile.existsSync()) {
        processRestartHandoffFile.deleteSync();
      }
      final handoffTemporary = File('${processRestartHandoffFile.path}.tmp');
      if (handoffTemporary.existsSync()) {
        handoffTemporary.deleteSync();
      }
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

  Future<void> _runFull() async {
    await _runAppCliPeer();
    if (options.prepareOnly) {
      await _runRemoteMultiDeviceJoin(caseIds: suiteDefinition.caseIds);
      return;
    }
    if (options.dryRun || commands.dryRun) {
      _line(
        'would run real App-admin + CLI-member Join and '
        'ROOT-TRANSFER-E2E-001 completion after the desktop peer flow',
      );
      return;
    }
    await _runRemoteMultiDeviceJoin(caseIds: suiteDefinition.caseIds);
  }

  Future<void> _runLocalSmoke() async {
    _section('AWiki Desktop local smoke E2E $runId');
    _line('platform: ${platform.name}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('case: ${options.e2eCase.caseName}');
    _line('flutter build dir: ${flutterBuildIsolation.buildDirectory}');

    await _timed('Checking desktop tooling', () async {
      await commands.requireExecutable('flutter');
      if (platform == DesktopE2ePlatform.linux) {
        await commands.requireExecutable('xvfb-run');
      }
    });
    if (platform == DesktopE2ePlatform.macos) {
      await _timed('Verifying native IM Core artifact', () {
        return commands.run('bash', const <String>[
          'scripts/verify_im_core_native_artifact.sh',
        ], timeout: const Duration(minutes: 1));
      });
    }
    if (!options.dryRun &&
        !commands.dryRun &&
        Platform.environment['AWIKI_E2E_USE_FLUTTER_TEST']?.trim() != '1') {
      final appArtifact = await _timed(
        'Preparing App smoke executable',
        () => _prepareIntegrationExecutable(
          name: 'smoke-app',
          target: 'integration_test/app_smoke_test.dart',
          bundleId: 'ai.awiki.awikime.dev.e2e.smoke.app',
          stateRoot: appStateRootDir,
        ),
      );
      final coreArtifact = await _timed(
        'Preparing native Core smoke executable',
        () => _prepareIntegrationExecutable(
          name: 'smoke-core',
          target: 'integration_test/im_core_open_smoke_test.dart',
          bundleId: 'ai.awiki.awikime.dev.e2e.smoke.core',
          stateRoot: appStateRootDir,
        ),
      );
      if (options.prepareOnly) return;
      await _timed('Executing prepared App smoke', () {
        return _executePreparedIntegration(
          artifact: appArtifact,
          caseIds: const <String>[
            'AGENT-NOTIFY-SMOKE-E2E-001',
            'AGENT-STALE-DAEMON-DELETE-SMOKE-E2E-001',
            'SMOKE-E2E-001',
          ],
          stateRoot: appStateRootDir,
        );
      });
      await _timed('Executing prepared native Core smoke', () {
        return _executePreparedIntegration(
          artifact: coreArtifact,
          caseIds: const <String>['NATIVE-E2E-001'],
          stateRoot: appStateRootDir,
        );
      });
      return;
    }
    await _timed('Flutter App smoke', () {
      return _runFlutterTest(
        'integration_test/app_smoke_test.dart',
        caseIds: const <String>[
          'AGENT-NOTIFY-SMOKE-E2E-001',
          'AGENT-STALE-DAEMON-DELETE-SMOKE-E2E-001',
          'SMOKE-E2E-001',
        ],
      );
    });
    await _timed('Flutter native IM Core smoke', () {
      return _runFlutterTest(
        'integration_test/im_core_open_smoke_test.dart',
        caseIds: const <String>['NATIVE-E2E-001'],
      );
    });
  }

  Future<_IsolatedAppArtifact> _prepareIntegrationExecutable({
    required String name,
    required String target,
    required String bundleId,
    required Directory stateRoot,
    List<String> dartDefines = const <String>[],
  }) async {
    final preparedDirectory =
        Platform.environment[_preparedAppArtifactDirectoryEnv]?.trim() ?? '';
    if (preparedDirectory.isNotEmpty) {
      final manifest = File('$preparedDirectory/$name.json');
      if (!manifest.existsSync()) {
        final required =
            Platform.environment[_requiredPreparedAppArtifactsEnv]
                ?.split(',')
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toSet() ??
            const <String>{};
        if (required.contains(name)) {
          throw E2eFailure(
            'Prepared integration artifact manifest is missing for $name.',
          );
        }
      } else {
        final artifact = _IsolatedAppArtifact.fromBuilderOutput(
          manifest.readAsStringSync(),
        );
        if (artifact.role != name ||
            artifact.target != target ||
            artifact.bundleId != bundleId) {
          throw E2eFailure(
            'Prepared integration artifact identity does not match $name.',
          );
        }
        final appRoot = artifact.appDirectory.resolveSymbolicLinksSync();
        final executable = artifact.executable.resolveSymbolicLinksSync();
        if (executable != appRoot && !executable.startsWith('$appRoot/')) {
          throw E2eFailure(
            'Prepared integration executable escapes its App artifact.',
          );
        }
        if (await directorySha256(artifact.appDirectory) !=
            artifact.artifactSha256) {
          throw E2eFailure(
            'Prepared integration App artifact hash changed for $name.',
          );
        }
        return artifact;
      }
    }
    final workRoot = Directory(
      '${root.path}/.e2e/build-cache/prepared-integration/'
      '${platform.name}/$name',
    );
    final artifactRoot = Directory(
      '${reportDir.parent.path}/prepared-artifacts',
    );
    _addRuntimeSecret(workRoot.path);
    _addRuntimeSecret(artifactRoot.path);
    final result = await commands.captureResult('dart', <String>[
      'tool/build_isolated_e2e_app.dart',
      '--name=$name',
      '--target=$target',
      '--state-root=${stateRoot.path}',
      '--work-root=${workRoot.path}',
      '--artifact-root=${artifactRoot.path}',
      '--bundle-id=$bundleId',
      '--platform=${platform.name}',
      '--flutter-bin=flutter',
      for (final define in dartDefines) '--dart-define=$define',
    ], timeout: const Duration(minutes: 12));
    return _IsolatedAppArtifact.fromBuilderOutput(result.output);
  }

  Future<void> _executePreparedIntegration({
    required _IsolatedAppArtifact artifact,
    required List<String> caseIds,
    required Directory stateRoot,
    Map<String, String> environment = const <String, String>{},
  }) async {
    if (platform == DesktopE2ePlatform.linux) {
      await commands.requireExecutable('setsid');
    }
    final execution = await runPreparedIntegrationExecutable(
      executable: artifact.executable,
      operatingSystem: platform.name,
      environment: <String, String>{
        'AWIKI_E2E_APP_STATE_ROOT': stateRoot.path,
        e2eCaseAttestationPathDefine: caseAttestationFile.path,
        e2eCaseScenarioDefine: options.e2eCase.scenario,
        e2eCaseRunIdDefine: runId,
        e2eCaseIdsDefine: caseIds.join(','),
        ...environment,
      },
      completionFile: invocationCompletionFile,
      expectedScenario: options.e2eCase.scenario,
      expectedRunId: runId,
      expectedCaseIds: caseIds,
      timeout: suiteDefinition.timeout,
      outputLine: (line) => _line(redactor.redact(line)),
    );
    if (!execution.terminatedAfterCompletion) {
      throw E2eFailure(
        'Prepared integration process did not reach its completion boundary.',
      );
    }
  }

  Future<void> _runLocalMultiDeviceCapabilityGate() async {
    _section('AWiki Desktop multi-device capability-gate E2E $runId');
    _line('platform: ${platform.name}');
    _line('reports: ${redactor.redact(reportDir.path)}');
    _line('case: ${options.e2eCase.caseName}');
    _line('flutter build dir: ${flutterBuildIsolation.buildDirectory}');

    await _timed('Checking desktop tooling', () async {
      await commands.requireExecutable('flutter');
      if (platform == DesktopE2ePlatform.linux) {
        await commands.requireExecutable('xvfb-run');
      }
    });
    await _timed('Flutter multi-device capability gate', () {
      return _runFlutterTest(
        'integration_test/multi_device_capability_gate_test.dart',
        caseIds: _multiDeviceCapabilityGateCaseIds,
      );
    });
  }

  Future<void> _runFlutterTest(
    String testFile, {
    required List<String> caseIds,
    Directory? appStateRoot,
  }) {
    return _runFlutterArgs(
      <String>[
        'test',
        '--dart-define=AWIKI_E2E=true',
        testFile,
        '-d',
        platform.name,
      ],
      platform: platform,
      timeout: suiteDefinition.timeout,
      runtimeCaseIds: caseIds,
      runtimeAppStateRoot: appStateRoot,
    );
  }

  Future<void> _runFlutterArgs(
    List<String> flutterArgs, {
    required DesktopE2ePlatform platform,
    Duration timeout = const Duration(minutes: 5),
    List<String>? runtimeCaseIds,
    Directory? runtimeAppStateRoot,
  }) async {
    await _withFlutterExecutionLease(platform, runId, () async {
      flutterBuildIsolation.prepare(dryRun: options.dryRun || commands.dryRun);
      final competingPids = await competingFlutterIntegrationTestPids();
      if (competingPids.isNotEmpty) {
        throw E2eFailure(
          'Another Flutter integration test is already running '
          '(pids=${competingPids.join(',')}); refusing to share the desktop '
          'device and application bundle.',
        );
      }
      final locale = desktopE2eUtf8Locale(
        platform: platform,
        lang: Platform.environment['LANG'],
        lcAll: Platform.environment['LC_ALL'],
      );
      final environment = <String, String>{
        'LANG': locale,
        'LC_ALL': locale,
        'AWIKI_E2E_APP_STATE_ROOT':
            (runtimeAppStateRoot ?? appStateRootDir).path,
        e2eCaseAttestationPathDefine: caseAttestationFile.path,
        e2eCaseScenarioDefine: options.e2eCase.scenario,
        e2eCaseRunIdDefine: runId,
        e2eCaseIdsDefine: (runtimeCaseIds ?? suiteDefinition.caseIds).join(','),
        ...flutterBuildIsolation.environment,
        if (config?.e2eCase == DesktopE2eCase.full) ...const <String, String>{
          _multiDeviceRemoteJoinGateEnv: '1',
          'AWIKI_MULTI_DEVICE_DEVICE_REVOKE_ENABLED': '1',
        },
      };
      final linuxNativeAssetsLink = flutterBuildIsolation
          .prepareLinuxNativeAssetsCompatibility(
            dryRun: options.dryRun || commands.dryRun,
          );
      try {
        if (platform == DesktopE2ePlatform.linux) {
          await commands.run(
            'xvfb-run',
            <String>['-a', 'flutter', ...flutterArgs],
            timeout: timeout,
            environment: environment,
          );
          return;
        }
        await commands.run(
          'flutter',
          flutterArgs,
          timeout: timeout,
          environment: environment,
        );
      } finally {
        flutterBuildIsolation.removeLinuxNativeAssetsCompatibility(
          linuxNativeAssetsLink,
        );
      }
    });
  }
}

Directory appPairBuildCacheRoot(Directory root) =>
    Directory('${root.absolute.path}/.e2e/build-cache/multi-device-app-pair');

({String code, String summary}) classifyDesktopE2eFailureMessage(
  String message,
) {
  final lower = message.toLowerCase();
  if (RegExp(r'service http error 5\d\d').hasMatch(lower) ||
      lower.contains('502 bad gateway') ||
      lower.contains('503 service unavailable') ||
      lower.contains('504 gateway time-out') ||
      lower.contains('transport_unavailable') ||
      lower.contains('transport unavailable') ||
      (lower.contains('service rpc error') &&
          lower.contains('network failure'))) {
    return (
      code: 'remote_service_unavailable',
      summary:
          'The remote product service was unavailable; inspect the redacted command log and retry after service recovery.',
    );
  }
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
      summary: 'CLI source ref is missing or not an exact commit SHA.',
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

String desktopE2eUtf8Locale({
  required DesktopE2ePlatform platform,
  String? lang,
  String? lcAll,
}) {
  for (final candidate in <String?>[lcAll, lang]) {
    final value = candidate?.trim() ?? '';
    if (RegExp(r'utf-?8', caseSensitive: false).hasMatch(value)) {
      if (platform == DesktopE2ePlatform.macos &&
          RegExp(r'^C[._-]', caseSensitive: false).hasMatch(value)) {
        continue;
      }
      return value;
    }
  }
  return platform == DesktopE2ePlatform.macos ? 'en_US.UTF-8' : 'C.UTF-8';
}

bool isAuditableGitSha(String value) {
  final normalized = value.trim();
  return RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(normalized) &&
      !RegExp(r'^0{40}$').hasMatch(normalized);
}

class DesktopCliTenantConfig {
  const DesktopCliTenantConfig({
    required this.backendBaseUrl,
    required this.didHost,
  });

  final String backendBaseUrl;
  final String didHost;
}

DesktopCliTenantConfig? cliTenantConfigFromListJson(
  String output,
  String tenantName,
) {
  Object? decoded;
  try {
    decoded = jsonDecode(output);
  } on Object {
    throw E2eFailure('CLI tenant preflight returned invalid JSON.');
  }
  final data = decoded is Map ? decoded['data'] : null;
  final tenants = data is Map ? data['tenants'] : null;
  if (tenants is! List) {
    throw E2eFailure('CLI tenant preflight omitted the tenant list.');
  }
  DesktopCliTenantConfig? result;
  for (final value in tenants) {
    if (value is! Map || value['name'] != tenantName) {
      continue;
    }
    if (result != null) {
      throw E2eFailure('CLI tenant preflight returned duplicate tenant names.');
    }
    final backendBaseUrl = value['backend_base_url'];
    final didHost = value['did_host'];
    if (backendBaseUrl is! String ||
        backendBaseUrl.trim().isEmpty ||
        didHost is! String ||
        didHost.trim().isEmpty) {
      throw E2eFailure('CLI tenant preflight returned incomplete target data.');
    }
    result = DesktopCliTenantConfig(
      backendBaseUrl: backendBaseUrl.trim(),
      didHost: didHost.trim(),
    );
  }
  return result;
}

bool cliCurrentIdentityReadyForHandle(
  String output, {
  required String handle,
  required String didDomain,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(output);
  } on Object {
    throw E2eFailure('CLI current identity preflight returned invalid JSON.');
  }
  final data = decoded is Map ? decoded['data'] : null;
  if (data is! Map || !data.containsKey('identity')) {
    throw E2eFailure('CLI current identity preflight omitted identity data.');
  }
  final identity = data['identity'];
  if (identity == null) {
    return false;
  }
  if (identity is! Map) {
    throw E2eFailure('CLI current identity preflight omitted identity data.');
  }
  final localPart = handle.trim().toLowerCase();
  final fullHandle = '$localPart.${_normalizedDomain(didDomain)}';
  final currentHandle = identity['handle']?.toString().trim().toLowerCase();
  final currentFullHandle = identity['full_handle']
      ?.toString()
      .trim()
      .toLowerCase();
  final userState = identity['user_state'];
  final readyForMessaging = userState is Map
      ? userState['ready_for_messaging']
      : null;
  return currentHandle == localPart &&
      currentFullHandle == fullHandle &&
      readyForMessaging == true;
}

bool _sameHttpEndpoint(String left, String right) {
  Uri parse(String value) {
    final uri = Uri.parse(value.trim());
    final path = uri.path == '/'
        ? ''
        : uri.path.replaceFirst(RegExp(r'/$'), '');
    return uri.replace(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      path: path,
      query: null,
      fragment: null,
    );
  }

  return parse(left) == parse(right);
}

String _normalizedDomain(String value) =>
    value.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');

bool daemonStateRootFitsUnixSocket(String stateRoot) {
  const int maxUnixSocketPathBytes = 103;
  final socketPath = '$stateRoot/run/d.sock';
  return utf8.encode(socketPath).length <= maxUnixSocketPathBytes;
}

String cliBuildCommitFromVersionJson(String output) {
  Object? decoded;
  try {
    decoded = jsonDecode(output);
  } on Object {
    throw E2eFailure('CLI version preflight returned invalid JSON.');
  }
  final data = decoded is Map ? decoded['data'] : null;
  final commit = data is Map ? data['commit'] : null;
  if (commit is! String || !isAuditableGitSha(commit)) {
    throw E2eFailure(
      'CLI version preflight did not report an auditable embedded commit.',
    );
  }
  return commit.trim().toLowerCase();
}

String cliBuildVersionFromVersionJson(String output) {
  Object? decoded;
  try {
    decoded = jsonDecode(output);
  } on Object {
    throw E2eFailure('CLI version preflight returned invalid JSON.');
  }
  final data = decoded is Map ? decoded['data'] : null;
  final version = data is Map ? data['version'] : null;
  if (version is! String || !_isCanonicalNumericVersion(version)) {
    throw E2eFailure(
      'CLI version preflight did not report a Core-compatible numeric version.',
    );
  }
  return version;
}

bool _isCanonicalNumericVersion(String version) {
  final components = version.split('.');
  if (components.isEmpty || components.length > 4) return false;
  return components.every(
    (component) =>
        component == '0' ||
        (component.isNotEmpty &&
            component.codeUnitAt(0) >= 0x31 &&
            component.codeUnitAt(0) <= 0x39 &&
            component.codeUnits
                .skip(1)
                .every((unit) => unit >= 0x30 && unit <= 0x39)),
  );
}

void _requireAppPairRecoveryOperatorEnvironment(
  Map<String, String> environment,
) {
  final mode = environment[_syncRecoveryOperatorModeEnv]?.trim();
  if (environment[_syncRecoveryEnableEnv]?.trim() != '1' ||
      environment[_syncRecoveryTargetEnv]?.trim() != _syncRecoveryTarget ||
      mode != 'ali') {
    throw E2eFailure(
      'The functional App-pair suite requires the reviewed sync-recovery '
      'operator opt-in, target, and managed Ali mode.',
    );
  }
}

List<String> _accountStateOperatorCommand(Map<String, String> environment) {
  final raw = environment[_accountStateOperatorCommandEnv]?.trim() ?? '';
  try {
    return parseAccountStateOperatorCommand(raw);
  } on FormatException catch (error) {
    throw E2eFailure(error.message);
  }
}

void _requireAppPairAccountStateOperatorEnvironment({
  required Directory root,
  required Map<String, String> environment,
}) {
  if (environment[_accountStateEnableEnv]?.trim() != '1' ||
      environment[_syncRecoveryTargetEnv]?.trim() != _syncRecoveryTarget ||
      environment[_syncRecoveryOperatorModeEnv]?.trim() != 'ali' ||
      environment[_accountStateFailpointEnableEnv]?.trim() != '1') {
    throw E2eFailure(
      'The App-pair Account State capability, failpoint, target, and mode '
      'gate is incomplete.',
    );
  }
  _accountStateOperatorCommand(environment);

  final configuredPath =
      environment[_remoteTargetManifestEnv]?.trim().isNotEmpty == true
      ? environment[_remoteTargetManifestEnv]!.trim()
      : _defaultRemoteTargetManifestPath;
  final manifestFile = File(
    configuredPath.startsWith('/')
        ? configuredPath
        : '${root.path}/$configuredPath',
  );
  Object? decoded;
  try {
    decoded = jsonDecode(manifestFile.readAsStringSync());
  } on Object {
    throw E2eFailure(
      'The App-pair reviewed remote target manifest is unavailable.',
    );
  }
  if (decoded is! Map || decoded['schemaVersion'] != 1) {
    throw E2eFailure(
      'The App-pair reviewed remote target manifest is invalid.',
    );
  }
  final targets = decoded['targets'];
  final target = targets is Map ? targets[_syncRecoveryTarget] : null;
  if (target is! Map ||
      target['didDomain'] != 'awiki.info' ||
      target['userServiceUrl'] != 'https://awiki.info' ||
      target['messageServiceUrl'] != 'https://awiki.info') {
    throw E2eFailure(
      'The App-pair reviewed remote target does not match awiki.info.',
    );
  }
  final rawCapabilities = target['capabilities'];
  final capabilities = rawCapabilities is List
      ? rawCapabilities.map((value) => value.toString()).toSet()
      : const <String>{};
  final missing = _accountStateRequiredTargetCapabilities.difference(
    capabilities,
  );
  if (missing.isNotEmpty) {
    throw E2eFailure(
      'The App-pair reviewed remote target is missing required Account '
      'State capabilities.',
    );
  }
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
