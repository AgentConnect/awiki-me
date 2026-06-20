import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/presentation/agents/agent_visual_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support.dart';

void main() {
  test('active run takes precedence over latest ready status', () {
    const agent = AgentSummary(
      agentDid: 'did:agent:runtime',
      kind: AgentKind.runtime,
      daemonAgentDid: 'did:agent:daemon',
      runtime: 'hermes',
      displayName: 'Hermes',
      activeState: 'active',
      latest: AgentLatestStatus(status: 'ready'),
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

  test('pending daemon upgrade takes precedence over needs-upgrade latest', () {
    const agent = AgentSummary(
      agentDid: 'did:agent:daemon',
      kind: AgentKind.daemon,
      displayName: '代理 1',
      activeState: 'active',
      latest: AgentLatestStatus(status: 'needs_upgrade', needsUpgrade: true),
    );

    final status = AgentVisualStatus.fromAgent(agent, isPendingUpgrade: true);

    expect(status.kind, AgentVisualStatusKind.processing);
    expect(status.rawStatus, 'upgrading');
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

  test('generic CLI runtime card lifecycle maps to visual states', () {
    final expectations = <String, AgentVisualStatusKind>{
      'needs_setup': AgentVisualStatusKind.needsConfig,
      'queued': AgentVisualStatusKind.processing,
      'running': AgentVisualStatusKind.processing,
      'dead_letter': AgentVisualStatusKind.failed,
      'failed': AgentVisualStatusKind.failed,
      'manual_review_required': AgentVisualStatusKind.failed,
      'disabled': AgentVisualStatusKind.disabled,
      'created': AgentVisualStatusKind.ready,
      'ready': AgentVisualStatusKind.ready,
      'final_sent': AgentVisualStatusKind.ready,
    };

    for (final entry in expectations.entries) {
      final agent = _runtimeWithCard(entry.key);

      final status = AgentVisualStatus.fromAgent(agent);

      expect(status.kind, entry.value, reason: entry.key);
      expect(status.rawStatus, 'runtime_card:${entry.key}');
    }
  });

  test('generic CLI runtime card fails closed for invalid schema', () {
    final agent = _runtimeWithCard(
      'needs_setup',
      diagnosticsSummary: genericCliRuntimeCardDiagnostics(
        lifecycleState: 'needs_setup',
        statusSchemaVersion: 99,
      ),
      latestStatus: 'ready',
    );

    final status = AgentVisualStatus.fromAgent(agent);

    expect(status.kind, AgentVisualStatusKind.ready);
    expect(status.rawStatus, 'ready');
  });

  test('generic CLI runtime card rejects sensitive diagnostics', () {
    final agent = _runtimeWithCard(
      'needs_setup',
      diagnosticsSummary: genericCliRuntimeCardDiagnostics(
        lifecycleState: 'needs_setup',
        containsUserContent: true,
      ),
      latestStatus: 'ready',
    );

    final status = AgentVisualStatus.fromAgent(agent);

    expect(status.kind, AgentVisualStatusKind.ready);
    expect(status.rawStatus, 'ready');
  });

  test('critical runtime card state overrides stale active run signals', () {
    final agent = _runtimeWithCard(
      'needs_setup',
      recentRuns: const <AgentRunStatus>[
        AgentRunStatus(
          runId: 'run_1',
          messageId: 'msg_1',
          runtimeAgentDid: 'did:agent:runtime',
          status: 'running',
        ),
      ],
    );

    final status = AgentVisualStatus.fromAgent(agent, hasPendingTurn: true);

    expect(status.kind, AgentVisualStatusKind.needsConfig);
    expect(status.rawStatus, 'runtime_card:needs_setup');
  });

  test(
    'noncritical runtime card does not override local active run signal',
    () {
      final agent = _runtimeWithCard(
        'created',
        recentRuns: const <AgentRunStatus>[
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
      expect(status.rawStatus, isNull);
    },
  );

  test('non-runtime agents ignore generic CLI runtime card diagnostics', () {
    final agent = AgentSummary(
      agentDid: 'did:agent:daemon',
      kind: AgentKind.daemon,
      displayName: '代理 1',
      activeState: 'active',
      latest: AgentLatestStatus(
        status: 'ready',
        diagnosticsSummary: genericCliRuntimeCardDiagnostics(
          lifecycleState: 'needs_setup',
        ),
      ),
    );

    final status = AgentVisualStatus.fromAgent(agent);

    expect(status.kind, AgentVisualStatusKind.ready);
    expect(status.rawStatus, 'ready');
  });
}

AgentSummary _runtimeWithCard(
  String lifecycleState, {
  String latestStatus = 'offline',
  Map<String, Object?>? diagnosticsSummary,
  List<AgentRunStatus> recentRuns = const <AgentRunStatus>[],
}) {
  return AgentSummary(
    agentDid: 'did:agent:runtime',
    kind: AgentKind.runtime,
    daemonAgentDid: 'did:agent:daemon',
    runtime: 'codex',
    displayName: 'Codex',
    activeState: 'active',
    latest: AgentLatestStatus(
      status: latestStatus,
      diagnosticsSummary:
          diagnosticsSummary ??
          genericCliRuntimeCardDiagnostics(lifecycleState: lifecycleState),
    ),
    recentRuns: recentRuns,
  );
}
