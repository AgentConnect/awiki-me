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

  test('daemon upgrade error takes precedence over needs-upgrade latest', () {
    const agent = AgentSummary(
      agentDid: 'did:agent:daemon',
      kind: AgentKind.daemon,
      displayName: '代理 1',
      activeState: 'active',
      latest: AgentLatestStatus(status: 'needs_upgrade', needsUpgrade: true),
    );

    final status = AgentVisualStatus.fromAgent(agent, hasUpgradeError: true);

    expect(status.kind, AgentVisualStatusKind.failed);
    expect(status.rawStatus, 'upgrade_failed');
  });

  test('pending daemon upgrade flag does not affect runtime health', () {
    const agent = AgentSummary(
      agentDid: 'did:agent:runtime',
      kind: AgentKind.runtime,
      daemonAgentDid: 'did:agent:daemon',
      runtime: 'hermes',
      displayName: 'Hermes',
      activeState: 'active',
      latest: AgentLatestStatus(status: 'ready'),
    );

    final status = AgentVisualStatus.fromAgent(agent, isPendingUpgrade: true);

    expect(status.kind, AgentVisualStatusKind.ready);
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

  test('daemon latest upgrade state is mapped to needs-upgrade', () {
    expect(
      AgentVisualStatus.fromDaemonLatest(
        const AgentLatestStatus(status: 'needs_upgrade'),
      ).kind,
      AgentVisualStatusKind.needsUpgrade,
    );
    expect(
      AgentVisualStatus.fromDaemonLatest(
        const AgentLatestStatus(status: 'ready', needsUpgrade: true),
      ).kind,
      AgentVisualStatusKind.needsUpgrade,
    );
  });

  test('generic CLI runtime card lifecycle maps to visual states', () {
    final now = DateTime.utc(2026, 1, 1, 12);
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
      final agent = _runtimeWithCard(entry.key, lastSeenAt: now);

      final status = AgentVisualStatus.fromAgent(agent, now: now);

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
      final now = DateTime.utc(2026, 1, 1, 12);
      final agent = _runtimeWithCard(
        'created',
        lastSeenAt: now,
        recentRuns: const <AgentRunStatus>[
          AgentRunStatus(
            runId: 'run_1',
            messageId: 'msg_1',
            runtimeAgentDid: 'did:agent:runtime',
            status: 'running',
          ),
        ],
      );

      final status = AgentVisualStatus.fromAgent(agent, now: now);

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

  test('runtime latest ignores daemon-scoped upgrade state', () {
    expect(
      AgentVisualStatus.fromRuntimeLatest(
        const AgentLatestStatus(status: 'needs_upgrade', needsUpgrade: true),
      ).kind,
      AgentVisualStatusKind.ready,
    );
    expect(
      AgentVisualStatus.fromRuntimeLatest(
        const AgentLatestStatus(
          status: 'needs_upgrade',
          needsUpgrade: true,
          needsConfig: true,
        ),
      ).kind,
      AgentVisualStatusKind.needsConfig,
    );
  });

  test(
    'runtime latest config and failure states are user-facing health states',
    () {
      expect(
        AgentVisualStatus.fromRuntimeLatest(
          const AgentLatestStatus(status: 'ready', needsConfig: true),
        ).kind,
        AgentVisualStatusKind.needsConfig,
      );
      expect(
        AgentVisualStatus.fromRuntimeLatest(
          const AgentLatestStatus(status: 'failed'),
        ).kind,
        AgentVisualStatusKind.failed,
      );
    },
  );

  test(
    'runtime summary normalizes daemon release fields out of latest status',
    () {
      final agent = AgentSummary.fromJson(<String, Object?>{
        'agent_did': 'did:agent:runtime',
        'agent_kind': 'runtime',
        'daemon_agent_did': 'did:agent:daemon',
        'display_name': 'Hermes',
        'active_state': 'active',
        'status': <String, Object?>{
          'status': 'needs_upgrade',
          'version': '0.1.31',
          'latest_version': '0.1.35',
          'min_supported_version': '0.1.35',
          'platform': 'linux-amd64',
          'service': 'systemd_user',
          'needs_upgrade': true,
          'needs_config': false,
        },
      });

      expect(agent.latest.status, 'ready');
      expect(agent.latest.needsUpgrade, isFalse);
      expect(agent.latest.version, isNull);
      expect(agent.latest.latestVersion, isNull);
      expect(agent.latest.minSupportedVersion, isNull);
      expect(agent.latest.platform, isNull);
      expect(agent.latest.service, isNull);
      expect(agent.toJson()['status'], isA<Map<String, Object?>>());
      final serialized = agent.toJson()['status']! as Map<String, Object?>;
      expect(serialized['needs_upgrade'], isFalse);
      expect(serialized['version'], isNull);
      expect(serialized['latest_version'], isNull);
      expect(serialized['min_supported_version'], isNull);
      expect(serialized['platform'], isNull);
      expect(serialized['service'], isNull);
    },
  );

  test(
    'stale generic CLI running runtime card falls back to latest health',
    () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final agent = _runtimeWithCard(
        'running',
        latestStatus: 'ready',
        lastSeenAt: now.subtract(const Duration(minutes: 11)),
      );

      final status = AgentVisualStatus.fromAgent(agent, now: now);

      expect(status.kind, AgentVisualStatusKind.ready);
      expect(status.rawStatus, 'ready');
    },
  );

  test(
    'missing last-seen generic CLI running card does not show processing',
    () {
      final agent = _runtimeWithCard('running', latestStatus: 'ready');

      final status = AgentVisualStatus.fromAgent(
        agent,
        now: DateTime.utc(2026, 1, 1, 12),
      );

      expect(status.kind, AgentVisualStatusKind.ready);
      expect(status.rawStatus, 'ready');
    },
  );
}

AgentSummary _runtimeWithCard(
  String lifecycleState, {
  String latestStatus = 'offline',
  Map<String, Object?>? diagnosticsSummary,
  List<AgentRunStatus> recentRuns = const <AgentRunStatus>[],
  DateTime? lastSeenAt,
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
      lastSeenAt: lastSeenAt,
      diagnosticsSummary:
          diagnosticsSummary ??
          genericCliRuntimeCardDiagnostics(lifecycleState: lifecycleState),
    ),
    recentRuns: recentRuns,
  );
}
