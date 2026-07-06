import 'agent_status.dart';

class AgentSummary {
  const AgentSummary({
    required this.agentDid,
    required this.kind,
    this.daemonAgentDid,
    this.runtime,
    this.handle,
    required this.displayName,
    required this.activeState,
    required this.latest,
    this.daemonEffectiveStatus,
    this.recentRuns = const <AgentRunStatus>[],
  });

  final String agentDid;
  final AgentKind kind;
  final String? daemonAgentDid;
  final String? runtime;
  final String? handle;
  final String displayName;
  final String activeState;
  final AgentLatestStatus latest;
  final DaemonEffectiveStatus? daemonEffectiveStatus;
  final List<AgentRunStatus> recentRuns;

  bool get isDaemon => kind == AgentKind.daemon;
  bool get isRuntime => kind == AgentKind.runtime;

  factory AgentSummary.fromJson(Map<String, Object?> json) {
    final kind = _parseKind(json['agent_kind']?.toString());
    return AgentSummary(
      agentDid: json['agent_did']?.toString() ?? '',
      kind: kind,
      daemonAgentDid: _optionalString(json['daemon_agent_did']),
      runtime: _optionalString(json['runtime']),
      handle: _optionalString(json['handle']),
      displayName: json['display_name']?.toString() ?? '',
      activeState: json['active_state']?.toString() ?? 'active',
      latest: normalizeAgentLatestStatusForKind(
        kind,
        AgentLatestStatus.fromJson(_readMap(json['status'])),
      ),
      daemonEffectiveStatus: kind == AgentKind.daemon
          ? _daemonEffectiveStatusFromJson(json['daemon_effective_status'])
          : null,
      recentRuns: _readList(json['recent_runs'])
          .map((item) => AgentRunStatus.fromJson(_readMap(item)))
          .where((run) => run.runId.isNotEmpty)
          .toList(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'agent_did': agentDid,
      'agent_kind': kind == AgentKind.daemon ? 'daemon' : 'runtime',
      'daemon_agent_did': daemonAgentDid,
      'runtime': runtime,
      'handle': handle,
      'display_name': displayName,
      'active_state': activeState,
      'status': normalizeAgentLatestStatusForKind(kind, latest).toJson(),
      'daemon_effective_status': daemonEffectiveStatus?.toJson(),
      'recent_runs': recentRuns.map((run) => run.toJson()).toList(),
    };
  }
}

DaemonEffectiveStatus? _daemonEffectiveStatusFromJson(Object? value) {
  final map = _readMap(value);
  if (map.isEmpty) {
    return null;
  }
  return DaemonEffectiveStatus.fromJson(map);
}

AgentLatestStatus normalizeAgentLatestStatusForKind(
  AgentKind kind,
  AgentLatestStatus latest,
) {
  if (kind == AgentKind.daemon) {
    return latest;
  }
  final status = latest.status.trim().toLowerCase();
  return AgentLatestStatus(
    status: status == 'needs_upgrade'
        ? (latest.needsConfig ? 'needs_config' : 'ready')
        : latest.status,
    lastSeenAt: latest.lastSeenAt,
    version: null,
    latestVersion: null,
    minSupportedVersion: null,
    platform: null,
    service: null,
    needsUpgrade: false,
    needsConfig: latest.needsConfig,
    lastErrorCode: latest.lastErrorCode,
    lastErrorSummary: latest.lastErrorSummary,
    diagnosticsSummary: latest.diagnosticsSummary,
  );
}

AgentKind _parseKind(String? value) {
  return value == 'runtime' ? AgentKind.runtime : AgentKind.daemon;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

Map<String, Object?> _readMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

List<Object?> _readList(Object? value) {
  return value is List ? value : const <Object?>[];
}
