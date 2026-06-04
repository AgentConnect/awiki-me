enum AgentKind { daemon, runtime }

enum DaemonStatus {
  installing,
  registering,
  ready,
  offline,
  failed,
  needsUpgrade,
}

enum RuntimeStatus {
  creating,
  ready,
  failed,
  disabled,
  needsConfig,
  needsUpgrade,
}

enum RunStatus { queued, running, succeeded, failed }

class AgentRunStatus {
  const AgentRunStatus({
    required this.runId,
    required this.messageId,
    required this.runtimeAgentDid,
    this.conversationId,
    required this.status,
    this.startedAt,
    this.updatedAt,
    this.lastErrorCode,
    this.lastErrorSummary,
  });

  final String runId;
  final String messageId;
  final String runtimeAgentDid;
  final String? conversationId;
  final String status;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final String? lastErrorCode;
  final String? lastErrorSummary;

  factory AgentRunStatus.fromJson(Map<String, Object?> json) {
    return AgentRunStatus(
      runId: json['run_id']?.toString() ?? '',
      messageId: json['message_id']?.toString() ?? '',
      runtimeAgentDid: json['runtime_agent_did']?.toString() ?? '',
      conversationId: _optionalString(json['conversation_id']),
      status: json['status']?.toString() ?? 'queued',
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      lastErrorCode: _optionalString(json['last_error_code']),
      lastErrorSummary: _optionalString(json['last_error_summary']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'run_id': runId,
      'message_id': messageId,
      'runtime_agent_did': runtimeAgentDid,
      'conversation_id': conversationId,
      'status': status,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'last_error_code': lastErrorCode,
      'last_error_summary': lastErrorSummary,
    };
  }
}

class AgentLatestStatus {
  const AgentLatestStatus({
    required this.status,
    this.lastSeenAt,
    this.version,
    this.minSupportedVersion,
    this.platform,
    this.service,
    this.needsUpgrade = false,
    this.needsConfig = false,
    this.lastErrorCode,
    this.lastErrorSummary,
    this.diagnosticsSummary = const <String, Object?>{},
  });

  final String status;
  final DateTime? lastSeenAt;
  final String? version;
  final String? minSupportedVersion;
  final String? platform;
  final String? service;
  final bool needsUpgrade;
  final bool needsConfig;
  final String? lastErrorCode;
  final String? lastErrorSummary;
  final Map<String, Object?> diagnosticsSummary;

  factory AgentLatestStatus.fromJson(Map<String, Object?> json) {
    return AgentLatestStatus(
      status: json['status']?.toString() ?? 'offline',
      lastSeenAt: DateTime.tryParse(json['last_seen_at']?.toString() ?? ''),
      version: _optionalString(json['version']),
      minSupportedVersion: _optionalString(json['min_supported_version']),
      platform: _optionalString(json['platform']),
      service: _optionalString(json['service']),
      needsUpgrade: json['needs_upgrade'] == true,
      needsConfig: json['needs_config'] == true,
      lastErrorCode: _optionalString(json['last_error_code']),
      lastErrorSummary: _optionalString(json['last_error_summary']),
      diagnosticsSummary: _readMap(json['diagnostics_summary']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'last_seen_at': lastSeenAt?.toUtc().toIso8601String(),
      'version': version,
      'min_supported_version': minSupportedVersion,
      'platform': platform,
      'service': service,
      'needs_upgrade': needsUpgrade,
      'needs_config': needsConfig,
      'last_error_code': lastErrorCode,
      'last_error_summary': lastErrorSummary,
      'diagnostics_summary': diagnosticsSummary,
    };
  }
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
