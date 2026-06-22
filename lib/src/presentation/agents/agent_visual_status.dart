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
    if (hasPendingTurn || agent.recentRuns.any(AgentVisualStatus.isActiveRun)) {
      return const AgentVisualStatus(AgentVisualStatusKind.processing);
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
    final status = run.status.trim().toLowerCase();
    return status == 'queued' || status == 'pending' || status == 'running';
  }
}
