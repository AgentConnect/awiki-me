import 'agent_im_config.dart';
import 'cli_peer_adapter.dart';
import 'remote_adapter.dart';

const agentImDelegatedMessageScenario = 'agent-im-delegated-message';

final class E2eScenarioRegistry {
  const E2eScenarioRegistry();

  bool supports(String scenario) => scenario == agentImDelegatedMessageScenario;

  DesktopScenarioPlan buildAgentImPlan({
    required String runId,
    required String platform,
    required AgentImDelegatedConfig config,
    String? cliBinaryPath,
    String? cliPeerWorkspace,
    String? ordinaryMessageText,
  }) {
    final remoteCommands = AgentImRemoteAdapter(
      config,
    ).planEvidenceCommands(runId);
    final cliPeerPlan = AgentImCliPeerPlan(
      runId: runId,
      peerHandle: config.accounts.peerUser.handle,
      targetHandle: config.accounts.appUser.handle,
      workspace: cliPeerWorkspace ?? config.cliPeer.workspaceRoot,
      binary: cliBinaryPath ?? config.cliPeer.binary,
      commands: AgentImCliPeerAdapterPlan.commands(
        config: config,
        targetHandle: config.accounts.appUser.handle,
        messageText:
            ordinaryMessageText ??
            AgentImCliPeerAdapterPlan.defaultOrdinaryMessageText(runId),
      ),
    );
    return DesktopScenarioPlan(
      scenario: agentImDelegatedMessageScenario,
      runId: runId,
      platform: platform,
      steps: <DesktopScenarioStep>[
        DesktopScenarioStep(
          name: 'prepare configured CLI peer workspace',
          detail:
              'Use awiki-cli-rs2 with ${config.accounts.peerUser.handle} and workspace ${cliPeerPlan.workspace}.',
        ),
        DesktopScenarioStep(
          name: 'bootstrap App user message agent',
          detail:
              'Trigger awiki.daemon.bootstrap.v1 for ${config.accounts.appUser.handle}; delegated key fragment ${config.agent.delegatedKeyFragment}; runtime ${config.agent.expectedRuntime}; integration shim: integration_test/agent_im_delegated_message_e2e_test.dart.',
        ),
        DesktopScenarioStep(
          name: 'send ordinary non-E2EE message from CLI peer',
          detail:
              'CLI peer sends a runId-tagged ordinary message to App user and waits up to ${config.timeouts.messageProcess.inSeconds}s for processing evidence.',
        ),
        DesktopScenarioStep(
          name: 'collect remote awiki.info evidence',
          detail: remoteCommands.isEmpty
              ? 'Remote log collection disabled in config.'
              : 'Plan ${remoteCommands.length} ssh evidence commands via ${config.remote.sshAlias}; all output must pass redaction.',
        ),
        const DesktopScenarioStep(
          name: 'scan reports and logs for secrets',
          detail:
              'Scan report, CLI workspace, App logs, and collected remote evidence before accepting the run.',
        ),
      ],
      remoteCommands: remoteCommands,
      cliPeerPlan: cliPeerPlan,
      config: config.toReportJson(),
    );
  }
}

final class DesktopScenarioPlan {
  const DesktopScenarioPlan({
    required this.scenario,
    required this.runId,
    required this.platform,
    required this.steps,
    required this.remoteCommands,
    required this.cliPeerPlan,
    required this.config,
  });

  final String scenario;
  final String runId;
  final String platform;
  final List<DesktopScenarioStep> steps;
  final List<RemoteEvidenceCommand> remoteCommands;
  final AgentImCliPeerPlan cliPeerPlan;
  final Map<String, Object?> config;

  Map<String, Object?> toJson() => <String, Object?>{
    'scenario': scenario,
    'runId': runId,
    'platform': platform,
    'steps': [for (final step in steps) step.toJson()],
    'remoteCommands': [for (final command in remoteCommands) command.toJson()],
    'cliPeerPlan': cliPeerPlan.toJson(),
    'config': config,
  };
}

final class DesktopScenarioStep {
  const DesktopScenarioStep({required this.name, required this.detail});

  final String name;
  final String detail;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'detail': detail,
  };
}
