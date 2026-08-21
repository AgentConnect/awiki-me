// [INPUT]: Runner argv plus checked-in case membership constants.
// [OUTPUT]: Parsed run controls and the canonical case-to-scenario mapping.
// [POS]: CLI selection boundary; contains no execution or product assertions.

part of '../runner.dart';

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
  dart run tests/e2e/runner.dart --case multi-device
  dart run tests/e2e/runner.dart --case multi-device-remote-join
  dart run tests/e2e/runner.dart --case multi-device-remote-recovery
  dart run tests/e2e/runner.dart --case multi-device-remote-recovery-fresh
  dart run tests/e2e/runner.dart --case handle-recovery-local-data
  dart run tests/e2e/runner.dart --case multi-device-app-pair-recovery-registration-rejoin-management-transfer
  dart run tests/e2e/runner.dart --case multi-device-app-pair
  dart run tests/e2e/runner.dart --case multi-device-app-pair-functional
  dart run tests/e2e/runner.dart --case multi-device-app-pair-content-sync
  dart run tests/e2e/runner.dart --case step4-revoke-mls
  dart run tests/e2e/runner.dart --case full
  dart run tests/e2e/runner.dart --case inbound
  dart run tests/e2e/runner.dart --case restart
  dart run tests/e2e/runner.dart --case display-name-fallback
  dart run tests/e2e/runner.dart --case identity-switch
  dart run tests/e2e/runner.dart --case performance
  dart run tests/e2e/runner.dart --case personal-agent
  dart run tests/e2e/runner.dart --case codex-agent
  dart run tests/e2e/runner.dart --case claude-code-agent

Options:
  --config PATH                Local YAML config. Defaults to $_defaultDesktopE2eConfigPath.
  --run-id ID                  Stable run id for repeatable local debugging.
  --case smoke|multi-device|multi-device-remote-join|multi-device-remote-recovery|multi-device-remote-recovery-fresh|handle-recovery-local-data|multi-device-app-pair-recovery-registration-rejoin-management-transfer|multi-device-app-pair|multi-device-app-pair-functional|multi-device-app-pair-content-sync|step4-revoke-mls|full|performance|direct|group|attachment|contacts|inbound|identity-switch|restart|display-name-fallback|personal-agent|codex-agent|claude-code-agent
                               smoke and multi-device run local App/native
                               checks. multi-device-remote-join is the explicit,
                               unattended real App/CLI message-driven
                               member Join flow in both directions against
                               awiki.info. Only its test-scoped user-presence
                               port is automated; production LocalAuthentication
                               is unchanged and not attested.
                               multi-device-remote-recovery drives the visible
                               Handle Recovery V1 flow against awiki.info with
                               the protected fixed test OTP and E2E-only user
                               presence on Linux or macOS.
                               multi-device-remote-recovery-fresh runs only
                               the six Fresh Root business-continuity cases
                               and their cold-process restart verification.
                               handle-recovery-local-data runs only the
                               Settings Recovery continuity case over the
                               preserved App/Core root.
                               multi-device-app-pair-recovery-registration-
                               rejoin-management-transfer runs on Linux/Xvfb
                               or macOS with an explicit awiki.info config and
                               covers the opaque registration continuation
                               through P5.
                               multi-device-app-pair builds and drives two
                               isolated real App processes on Linux/Xvfb or
                               macOS; it currently runs only the remote member Join
                               flow with an E2E-only unattended user-presence
                               decision.
                               multi-device-app-pair-functional reuses the two
                               isolated Apps with an E2E-only user-presence
                               port to run unattended Agent-inventory and
                               Direct-message convergence checks. It does not
                               attest operating-system user presence.
                               multi-device-app-pair-content-sync reuses one
                               Join and one CLI peer to check mixed tail-only,
                               Group, attachment, and read-state convergence.
                               full runs the audited App+CLI peer flow and then
                               one real App-admin/CLI-member Join + root
                               completion lifecycle; it therefore also requires
                               the remote Join gate and protected OTP fixture.
                               The other cases run real App+CLI peer flows. The
                               performance case records product-level startup,
                               conversation, and send-to-visible timings and
                               applies the configured performance budgets. The
                               restart case launches two Flutter processes
                               against one isolated App state root. The
                               personal-agent case is the full UI acceptance
                               gate for Personal Agent; codex-agent and
                               claude-code-agent are user-visible runtime
                               Agent reply gates. Probes are only lower level
                               helpers.
  --prepare-only               Prepare CLI peer but do not start Flutter test.
  --dry-run                    Print planned commands without side effects.
''');
  }
}

enum DesktopE2eCase implements DesktopE2eCaseContract {
  smoke(_desktopSmokeCaseIds),
  multiDevice(_multiDeviceCapabilityGateCaseIds),
  multiDeviceRemoteJoin(_multiDeviceRemoteJoinCaseIds),
  multiDeviceRemoteRecovery(_multiDeviceRemoteRecoveryCaseIds),
  handleRecoveryLocalData(_handleRecoveryLocalDataCaseIds),
  multiDeviceRemoteRecoveryFresh(_handleRecoveryFreshCaseIds),
  multiDeviceAppPairRecoveryRegistration(
    _multiDeviceAppPairRecoveryRegistrationCaseIds,
  ),
  multiDeviceAppPair(_multiDeviceAppPairCaseIds),
  multiDeviceAppPairFunctional(_multiDeviceAppPairFunctionalCaseIds),
  multiDeviceAppPairContentSync(_multiDeviceAppPairContentSyncCaseIds),
  step4RevokeMls(_step4RevokeMlsCaseIds),
  full(_desktopCliPeerCaseIds),
  performance(_desktopCliPeerPerformanceCaseIds),
  direct(_desktopCliPeerDirectCaseIds),
  group(_desktopCliPeerGroupCaseIds),
  attachment(_desktopCliPeerAttachmentCaseIds),
  contacts(_desktopCliPeerContactsCaseIds),
  contactFirst(_desktopCliPeerContactFirstCaseIds),
  inbound(_desktopCliPeerInboundCaseIds),
  identitySwitch(_desktopIdentitySwitchCaseIds),
  restart(_desktopCliPeerRestartCaseIds),
  displayNameFallback(_desktopCliPeerDisplayNameFallbackCaseIds),
  personalAgent(_personalAgentCaseIds),
  codexAgent(_codexAgentCaseIds),
  claudeCodeAgent(_claudeCodeAgentCaseIds);

  const DesktopE2eCase(this.caseIds);

  @override
  final List<String> caseIds;

  String get testFile {
    return switch (this) {
      DesktopE2eCase.smoke => 'integration_test/app_smoke_test.dart',
      DesktopE2eCase.multiDevice =>
        'integration_test/multi_device_capability_gate_test.dart',
      DesktopE2eCase.multiDeviceRemoteJoin =>
        'integration_test/multi_device_join_ui_test.dart',
      DesktopE2eCase.multiDeviceRemoteRecovery =>
        'integration_test/handle_recovery_ui_test.dart',
      DesktopE2eCase.handleRecoveryLocalData =>
        'integration_test/handle_recovery_ui_test.dart',
      DesktopE2eCase.multiDeviceRemoteRecoveryFresh =>
        'integration_test/handle_recovery_ui_test.dart',
      DesktopE2eCase.multiDeviceAppPairRecoveryRegistration =>
        'integration_test/handle_recovery_ui_test.dart',
      DesktopE2eCase.multiDeviceAppPair => _multiDeviceAppPairTarget,
      DesktopE2eCase.multiDeviceAppPairFunctional => _multiDeviceAppPairTarget,
      DesktopE2eCase.multiDeviceAppPairContentSync => _multiDeviceAppPairTarget,
      DesktopE2eCase.step4RevokeMls =>
        'integration_test/multi_device_join_ui_test.dart',
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
      DesktopE2eCase.contactFirst =>
        'integration_test/desktop_cli_peer_contact_first_test.dart',
      DesktopE2eCase.inbound =>
        'integration_test/desktop_cli_peer_inbound_test.dart',
      DesktopE2eCase.identitySwitch =>
        'integration_test/desktop_identity_switch_test.dart',
      DesktopE2eCase.restart =>
        'integration_test/desktop_cli_peer_restart_phase_b_test.dart',
      DesktopE2eCase.displayNameFallback =>
        'integration_test/desktop_cli_peer_display_name_fallback_test.dart',
      DesktopE2eCase.personalAgent =>
        'integration_test/personal_agent_full_ui_test.dart',
      DesktopE2eCase.codexAgent =>
        'integration_test/codex_agent_full_ui_test.dart',
      DesktopE2eCase.claudeCodeAgent =>
        'integration_test/claude_code_agent_full_ui_test.dart',
    };
  }

  @override
  String get caseName {
    return switch (this) {
      DesktopE2eCase.personalAgent => 'personal-agent',
      DesktopE2eCase.codexAgent => 'codex-agent',
      DesktopE2eCase.claudeCodeAgent => 'claude-code-agent',
      DesktopE2eCase.displayNameFallback => 'display-name-fallback',
      DesktopE2eCase.contactFirst => 'contact-first',
      DesktopE2eCase.identitySwitch => 'identity-switch',
      DesktopE2eCase.multiDevice => 'multi-device',
      DesktopE2eCase.multiDeviceRemoteJoin => 'multi-device-remote-join',
      DesktopE2eCase.multiDeviceRemoteRecovery =>
        'multi-device-remote-recovery',
      DesktopE2eCase.handleRecoveryLocalData => 'handle-recovery-local-data',
      DesktopE2eCase.multiDeviceRemoteRecoveryFresh =>
        'multi-device-remote-recovery-fresh',
      DesktopE2eCase.multiDeviceAppPairRecoveryRegistration =>
        'multi-device-app-pair-recovery-registration-rejoin-management-transfer',
      DesktopE2eCase.multiDeviceAppPair => 'multi-device-app-pair',
      DesktopE2eCase.multiDeviceAppPairFunctional =>
        'multi-device-app-pair-functional',
      DesktopE2eCase.multiDeviceAppPairContentSync =>
        'multi-device-app-pair-content-sync',
      DesktopE2eCase.step4RevokeMls => 'step4-revoke-mls',
      _ => name,
    };
  }

  bool get requiresCliPeer =>
      this != DesktopE2eCase.smoke &&
      this != DesktopE2eCase.multiDevice &&
      this != DesktopE2eCase.multiDeviceRemoteRecovery &&
      this != DesktopE2eCase.handleRecoveryLocalData &&
      this != DesktopE2eCase.multiDeviceRemoteRecoveryFresh &&
      this != DesktopE2eCase.multiDeviceAppPairRecoveryRegistration &&
      this != DesktopE2eCase.multiDeviceAppPair;

  bool get publishesNicknameFixture =>
      this != DesktopE2eCase.performance &&
      this != DesktopE2eCase.displayNameFallback;

  String get reportScope {
    return switch (this) {
      DesktopE2eCase.smoke => 'smoke',
      DesktopE2eCase.multiDevice => 'multi-device',
      DesktopE2eCase.multiDeviceRemoteJoin => 'multi-device-remote-join',
      DesktopE2eCase.multiDeviceRemoteRecovery =>
        'multi-device-remote-recovery',
      DesktopE2eCase.handleRecoveryLocalData => 'handle-recovery-local-data',
      DesktopE2eCase.multiDeviceRemoteRecoveryFresh =>
        'multi-device-remote-recovery-fresh',
      DesktopE2eCase.multiDeviceAppPairRecoveryRegistration =>
        'multi-device-app-pair-recovery-registration-rejoin-management-transfer',
      DesktopE2eCase.multiDeviceAppPair => 'multi-device-app-pair',
      DesktopE2eCase.multiDeviceAppPairFunctional =>
        'multi-device-app-pair-functional',
      DesktopE2eCase.multiDeviceAppPairContentSync =>
        'multi-device-app-pair-content-sync',
      DesktopE2eCase.step4RevokeMls => 'step4-revoke-mls',
      DesktopE2eCase.personalAgent => 'personal-agent',
      DesktopE2eCase.codexAgent => 'codex-agent',
      DesktopE2eCase.claudeCodeAgent => 'claude-code-agent',
      _ => 'desktop-cli-peer',
    };
  }

  Duration get flutterTimeout {
    return switch (this) {
      DesktopE2eCase.claudeCodeAgent => const Duration(minutes: 15),
      DesktopE2eCase.codexAgent => const Duration(minutes: 8),
      DesktopE2eCase.personalAgent => const Duration(minutes: 16),
      DesktopE2eCase.performance => const Duration(minutes: 12),
      DesktopE2eCase.restart => const Duration(minutes: 10),
      DesktopE2eCase.displayNameFallback => const Duration(minutes: 15),
      DesktopE2eCase.identitySwitch => const Duration(minutes: 10),
      DesktopE2eCase.multiDeviceRemoteJoin => const Duration(minutes: 22),
      DesktopE2eCase.multiDeviceRemoteRecovery => const Duration(minutes: 20),
      DesktopE2eCase.handleRecoveryLocalData => const Duration(minutes: 45),
      DesktopE2eCase.multiDeviceRemoteRecoveryFresh => const Duration(
        minutes: 45,
      ),
      DesktopE2eCase.multiDeviceAppPairRecoveryRegistration => const Duration(
        minutes: 25,
      ),
      DesktopE2eCase.multiDeviceAppPair => const Duration(minutes: 25),
      DesktopE2eCase.multiDeviceAppPairFunctional => const Duration(
        minutes: 30,
      ),
      DesktopE2eCase.multiDeviceAppPairContentSync => const Duration(
        minutes: 20,
      ),
      DesktopE2eCase.step4RevokeMls => const Duration(minutes: 25),
      _ => const Duration(minutes: 5),
    };
  }

  String get scenario {
    return switch (this) {
      DesktopE2eCase.personalAgent => _personalAgentScenario,
      DesktopE2eCase.codexAgent => _codexAgentScenario,
      DesktopE2eCase.claudeCodeAgent => _claudeCodeAgentScenario,
      DesktopE2eCase.performance => _desktopCliPeerPerformanceScenario,
      DesktopE2eCase.multiDevice => _multiDeviceCapabilityGateScenario,
      DesktopE2eCase.multiDeviceRemoteJoin => _multiDeviceRemoteJoinScenario,
      DesktopE2eCase.multiDeviceRemoteRecovery =>
        _multiDeviceRemoteRecoveryScenario,
      DesktopE2eCase.handleRecoveryLocalData =>
        _handleRecoveryLocalDataScenario,
      DesktopE2eCase.multiDeviceRemoteRecoveryFresh =>
        _multiDeviceRemoteRecoveryFreshScenario,
      DesktopE2eCase.multiDeviceAppPairRecoveryRegistration =>
        _multiDeviceAppPairRecoveryRegistrationScenario,
      DesktopE2eCase.multiDeviceAppPair => _multiDeviceAppPairScenario,
      DesktopE2eCase.multiDeviceAppPairFunctional =>
        _multiDeviceAppPairFunctionalScenario,
      DesktopE2eCase.multiDeviceAppPairContentSync =>
        _multiDeviceAppPairContentSyncScenario,
      DesktopE2eCase.step4RevokeMls => _multiDeviceRemoteJoinScenario,
      _ => _desktopCliPeerScenario,
    };
  }

  String get runConfigPath {
    return switch (this) {
      DesktopE2eCase.personalAgent => _personalAgentRunConfigPath,
      DesktopE2eCase.codexAgent => _codexAgentRunConfigPath,
      DesktopE2eCase.claudeCodeAgent => _claudeCodeAgentRunConfigPath,
      DesktopE2eCase.multiDeviceRemoteJoin =>
        _multiDeviceRemoteJoinRunConfigPath,
      DesktopE2eCase.multiDeviceRemoteRecovery =>
        _multiDeviceRemoteRecoveryRunConfigPath,
      DesktopE2eCase.handleRecoveryLocalData =>
        _multiDeviceRemoteRecoveryRunConfigPath,
      DesktopE2eCase.multiDeviceRemoteRecoveryFresh =>
        _multiDeviceRemoteRecoveryRunConfigPath,
      DesktopE2eCase.multiDeviceAppPairRecoveryRegistration =>
        _multiDeviceRemoteRecoveryRunConfigPath,
      DesktopE2eCase.multiDeviceAppPair => _multiDeviceAppPairRunConfigPath,
      DesktopE2eCase.multiDeviceAppPairFunctional =>
        _multiDeviceAppPairRunConfigPath,
      DesktopE2eCase.multiDeviceAppPairContentSync =>
        _multiDeviceAppPairRunConfigPath,
      DesktopE2eCase.step4RevokeMls => _multiDeviceRemoteJoinRunConfigPath,
      _ => _desktopCliPeerRunConfigPath,
    };
  }

  static DesktopE2eCase parse(String value) {
    return switch (value.trim().toLowerCase()) {
      '' || 'smoke' || 'app' || 'local' => DesktopE2eCase.smoke,
      'multi-device' ||
      'multi_device' ||
      'device-capability' ||
      'device_capability' => DesktopE2eCase.multiDevice,
      'multi-device-remote-join' ||
      'multi_device_remote_join' ||
      'remote-multi-device-join' ||
      'remote_multi_device_join' => DesktopE2eCase.multiDeviceRemoteJoin,
      'multi-device-remote-recovery' ||
      'multi_device_remote_recovery' ||
      'remote-multi-device-recovery' ||
      'remote_multi_device_recovery' =>
        DesktopE2eCase.multiDeviceRemoteRecovery,
      'multi-device-remote-recovery-fresh' ||
      'multi_device_remote_recovery_fresh' ||
      'remote-multi-device-recovery-fresh' ||
      'remote_multi_device_recovery_fresh' =>
        DesktopE2eCase.multiDeviceRemoteRecoveryFresh,
      'handle-recovery-local-data' ||
      'handle_recovery_local_data' ||
      'local-data-recovery' ||
      'local_data_recovery' => DesktopE2eCase.handleRecoveryLocalData,
      'multi-device-app-pair-recovery-registration-rejoin-management-transfer' ||
      'multi_device_app_pair_recovery_registration_rejoin_management_transfer' =>
        DesktopE2eCase.multiDeviceAppPairRecoveryRegistration,
      'multi-device-app-pair' ||
      'multi_device_app_pair' => DesktopE2eCase.multiDeviceAppPair,
      'multi-device-app-pair-functional' ||
      'multi_device_app_pair_functional' =>
        DesktopE2eCase.multiDeviceAppPairFunctional,
      'multi-device-app-pair-content-sync' ||
      'multi_device_app_pair_content_sync' =>
        DesktopE2eCase.multiDeviceAppPairContentSync,
      'step4-revoke-mls' || 'step4_revoke_mls' => DesktopE2eCase.step4RevokeMls,
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
      'contact-first' ||
      'contact_first' ||
      'contact-first-only' => DesktopE2eCase.contactFirst,
      'inbound' ||
      'inbound-first' ||
      'inbound_first' ||
      'inbound-only' => DesktopE2eCase.inbound,
      'identity-switch' ||
      'identity_switch' ||
      'switch-identity' ||
      'switch_identity' => DesktopE2eCase.identitySwitch,
      'restart' ||
      'process-restart' ||
      'process_restart' ||
      'cold-restart' ||
      'cold_restart' => DesktopE2eCase.restart,
      'display-name-fallback' ||
      'display_name_fallback' ||
      'handle-fallback' ||
      'handle_fallback' => DesktopE2eCase.displayNameFallback,
      'personal-agent' ||
      'personal_agent' ||
      'message-agent' ||
      'message_agent' ||
      'msgagent' ||
      'im-agent' ||
      'im_agent' => DesktopE2eCase.personalAgent,
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
        'Use smoke, multi-device, multi-device-remote-join, '
        'multi-device-remote-recovery, '
        'multi-device-remote-recovery-fresh, '
        'multi-device-app-pair-recovery-registration-rejoin-management-transfer, '
        'multi-device-app-pair, multi-device-app-pair-functional, '
        'multi-device-app-pair-content-sync, '
        'step4-revoke-mls, full, performance, direct, '
        'group, attachment, contacts, inbound, identity-switch, restart, '
        'display-name-fallback, '
        'personal-agent, codex-agent, or claude-code-agent.',
      ),
    };
  }
}
