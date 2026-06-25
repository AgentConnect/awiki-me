import '../../domain/entities/agent/agent_status.dart';
import '../../domain/entities/agent/agent_summary.dart';

enum AgentVisualStatusKind {
  processing,
  ready,
  needsConfig,
  needsUpgrade,
  failed,
  offline,
  disabled,
  unknown,
}

class AgentVisualStatus {
  const AgentVisualStatus(this.kind, {this.rawStatus});

  factory AgentVisualStatus.fromAgent(
    AgentSummary? agent, {
    bool hasPendingTurn = false,
    bool isPendingUpgrade = false,
    bool hasUpgradeError = false,
  }) {
    if (agent == null) {
      return const AgentVisualStatus(AgentVisualStatusKind.unknown);
    }
    final activeState = agent.activeState.trim().toLowerCase();
    if (activeState.isNotEmpty && activeState != 'active') {
      return AgentVisualStatus(
        AgentVisualStatusKind.disabled,
        rawStatus: activeState,
      );
    }
    if (agent.isDaemon && isPendingUpgrade) {
      return const AgentVisualStatus(
        AgentVisualStatusKind.processing,
        rawStatus: 'upgrading',
      );
    }
    if (agent.isDaemon && hasUpgradeError) {
      return const AgentVisualStatus(
        AgentVisualStatusKind.failed,
        rawStatus: 'upgrade_failed',
      );
    }
    if (agent.isRuntime) {
      final criticalRuntimeStatus = _fromRuntimeCard(
        agent.latest.runtimeCard,
        criticalOnly: true,
      );
      if (criticalRuntimeStatus != null) {
        return criticalRuntimeStatus;
      }
    }
    if (hasPendingTurn || agent.recentRuns.any(AgentVisualStatus.isActiveRun)) {
      return const AgentVisualStatus(AgentVisualStatusKind.processing);
    }
    if (agent.isRuntime) {
      final runtimeStatus = _fromRuntimeCard(agent.latest.runtimeCard);
      if (runtimeStatus != null) {
        return runtimeStatus;
      }
    }
    return agent.isDaemon
        ? AgentVisualStatus.fromDaemonLatest(agent.latest)
        : AgentVisualStatus.fromRuntimeLatest(agent.latest);
  }

  factory AgentVisualStatus.fromDaemonLatest(AgentLatestStatus latest) {
    final status = latest.status.trim().toLowerCase();
    if (latest.needsUpgrade || status == 'needs_upgrade') {
      return AgentVisualStatus(
        AgentVisualStatusKind.needsUpgrade,
        rawStatus: status,
      );
    }
    return switch (status) {
      'ready' => AgentVisualStatus(
        AgentVisualStatusKind.ready,
        rawStatus: status,
      ),
      'installing' ||
      'registering' ||
      'creating' ||
      'upgrading' ||
      'archiving' => AgentVisualStatus(
        AgentVisualStatusKind.processing,
        rawStatus: status,
      ),
      'failed' || 'error' || 'gateway_error' => AgentVisualStatus(
        AgentVisualStatusKind.failed,
        rawStatus: status,
      ),
      'offline' || 'not_running' || 'unavailable' => AgentVisualStatus(
        AgentVisualStatusKind.offline,
        rawStatus: status,
      ),
      'disabled' || 'archived' || 'deleted' => AgentVisualStatus(
        AgentVisualStatusKind.disabled,
        rawStatus: status,
      ),
      _ => AgentVisualStatus(AgentVisualStatusKind.unknown, rawStatus: status),
    };
  }

  final AgentVisualStatusKind kind;
  final String? rawStatus;

  bool get isProcessing => kind == AgentVisualStatusKind.processing;

  String get label {
    return switch (kind) {
      AgentVisualStatusKind.processing => '正在处理',
      AgentVisualStatusKind.ready => '正常',
      AgentVisualStatusKind.needsConfig => '需要配置',
      AgentVisualStatusKind.needsUpgrade => '需要升级',
      AgentVisualStatusKind.failed => '异常',
      AgentVisualStatusKind.offline => '离线',
      AgentVisualStatusKind.disabled => '已停用',
      AgentVisualStatusKind.unknown => '未知',
    };
  }

  factory AgentVisualStatus.fromRuntimeLatest(AgentLatestStatus latest) {
    final status = latest.status.trim().toLowerCase();
    if (latest.needsConfig || status == 'needs_config') {
      return AgentVisualStatus(
        AgentVisualStatusKind.needsConfig,
        rawStatus: status,
      );
    }
    return switch (status) {
      'ready' || 'needs_upgrade' => AgentVisualStatus(
        AgentVisualStatusKind.ready,
        rawStatus: status,
      ),
      'installing' || 'registering' || 'creating' || 'archiving' =>
        AgentVisualStatus(AgentVisualStatusKind.processing, rawStatus: status),
      'failed' || 'error' || 'gateway_error' => AgentVisualStatus(
        AgentVisualStatusKind.failed,
        rawStatus: status,
      ),
      'offline' || 'not_running' || 'unavailable' => AgentVisualStatus(
        AgentVisualStatusKind.offline,
        rawStatus: status,
      ),
      'disabled' || 'archived' || 'deleted' => AgentVisualStatus(
        AgentVisualStatusKind.disabled,
        rawStatus: status,
      ),
      _ => AgentVisualStatus(AgentVisualStatusKind.unknown, rawStatus: status),
    };
  }

  String get semanticLabel => '智能体状态：$label';

  static bool isActiveRun(AgentRunStatus run) {
    return isActiveAgentRunStatus(run.status);
  }

  static AgentVisualStatus? _fromRuntimeCard(
    AgentRuntimeCardStatus? card, {
    bool criticalOnly = false,
  }) {
    if (card == null) {
      return null;
    }
    final lifecycle = card.lifecycleState.trim().toLowerCase();
    final rawStatus = 'runtime_card:$lifecycle';
    return switch (lifecycle) {
      'needs_setup' => AgentVisualStatus(
        AgentVisualStatusKind.needsConfig,
        rawStatus: rawStatus,
      ),
      'dead_letter' || 'failed' || 'manual_review_required' =>
        AgentVisualStatus(AgentVisualStatusKind.failed, rawStatus: rawStatus),
      'disabled' => AgentVisualStatus(
        AgentVisualStatusKind.disabled,
        rawStatus: rawStatus,
      ),
      _ when criticalOnly => null,
      'queued' || 'running' => AgentVisualStatus(
        AgentVisualStatusKind.processing,
        rawStatus: rawStatus,
      ),
      'created' || 'ready' || 'final_sent' => AgentVisualStatus(
        AgentVisualStatusKind.ready,
        rawStatus: rawStatus,
      ),
      'unknown' => AgentVisualStatus(
        AgentVisualStatusKind.unknown,
        rawStatus: rawStatus,
      ),
      _ => null,
    };
  }
}
