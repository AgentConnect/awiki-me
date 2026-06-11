import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/presentation/agents/agent_visual_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active run takes precedence over latest ready status', () {
    final agent = AgentSummary(
      agentDid: 'did:agent:runtime',
      kind: AgentKind.runtime,
      daemonAgentDid: 'did:agent:daemon',
      runtime: 'hermes',
      displayName: 'Hermes',
      activeState: 'active',
      latest: const AgentLatestStatus(status: 'ready'),
      recentRuns: <AgentRunStatus>[
        AgentRunStatus(
          runId: 'run_1',
          messageId: 'msg_1',
          runtimeAgentDid: 'did:agent:runtime',
          status: 'running',
        ),
      ],
    );

    final status = AgentVisualStatus.fromAgent(agent);

    expect(status.kind, AgentVisualStatusKind.processing);
    expect(status.label, '正在处理');
  });

  test('local pending turn takes precedence over latest ready status', () {
    const agent = AgentSummary(
      agentDid: 'did:agent:runtime',
      kind: AgentKind.runtime,
      daemonAgentDid: 'did:agent:daemon',
      runtime: 'hermes',
      displayName: 'Hermes',
      activeState: 'active',
      latest: AgentLatestStatus(status: 'ready'),
    );

    final status = AgentVisualStatus.fromAgent(agent, hasPendingTurn: true);

    expect(status.kind, AgentVisualStatusKind.processing);
  });

  test(
    'inactive agent state is not overridden by stale processing signals',
    () {
      const agent = AgentSummary(
        agentDid: 'did:agent:runtime',
        kind: AgentKind.runtime,
        daemonAgentDid: 'did:agent:daemon',
        runtime: 'hermes',
        displayName: 'Hermes',
        activeState: 'archived',
        latest: AgentLatestStatus(status: 'ready'),
      );

      final status = AgentVisualStatus.fromAgent(agent, hasPendingTurn: true);

      expect(status.kind, AgentVisualStatusKind.disabled);
    },
  );

  test('latest config and upgrade flags are mapped to user-facing states', () {
    expect(
      AgentVisualStatus.fromLatest(
        const AgentLatestStatus(status: 'ready', needsConfig: true),
      ).kind,
      AgentVisualStatusKind.needsConfig,
    );
    expect(
      AgentVisualStatus.fromLatest(
        const AgentLatestStatus(status: 'ready', needsUpgrade: true),
      ).kind,
      AgentVisualStatusKind.needsUpgrade,
    );
    expect(
      AgentVisualStatus.fromLatest(
        const AgentLatestStatus(status: 'failed'),
      ).kind,
      AgentVisualStatusKind.failed,
    );
  });
}
