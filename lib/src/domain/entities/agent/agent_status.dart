enum AgentKind { daemon, runtime }

enum DaemonStatus {
  installing,
  registering,
  ready,
  offline,
  failed,
  needsUpgrade,
}

enum RuntimeStatus { creating, ready, failed, disabled, needsConfig }

enum RunStatus { queued, running, succeeded, failed }

class AgentRunStatus {
  const AgentRunStatus({
    required this.runId,
    required this.messageId,
    required this.runtimeAgentDid,
    this.conversationId,
    this.requesterDid,
    this.requesterFullHandle,
    this.triggerKind,
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
  final String? requesterDid;
  final String? requesterFullHandle;
  final String? triggerKind;
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
      requesterDid: _optionalString(json['requester_did']),
      requesterFullHandle: _optionalString(json['requester_full_handle']),
      triggerKind: _optionalString(json['trigger_kind']),
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
      'requester_did': requesterDid,
      'requester_full_handle': requesterFullHandle,
      'trigger_kind': triggerKind,
      'status': status,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'last_error_code': lastErrorCode,
      'last_error_summary': lastErrorSummary,
    };
  }
}

bool isActiveAgentRunStatus(String status) {
  final normalized = status.trim().toLowerCase();
  return normalized == 'queued' ||
      normalized == 'pending' ||
      normalized == 'running' ||
      normalized == 'in_progress';
}

class AgentLatestStatus {
  const AgentLatestStatus({
    required this.status,
    this.lastSeenAt,
    this.version,
    this.latestVersion,
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
  final String? latestVersion;
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
      latestVersion: _optionalString(json['latest_version']),
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
      'latest_version': latestVersion,
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

  AgentRuntimeCardStatus? get runtimeCard =>
      AgentRuntimeCardStatus.fromDiagnosticsSummary(diagnosticsSummary);
}

class AgentRuntimeCardStatus {
  const AgentRuntimeCardStatus({
    required this.supported,
    required this.statusSchemaVersion,
    required this.runtimeFamily,
    required this.driverId,
    required this.lifecycleState,
    required this.operationalState,
    required this.setupReady,
    this.setupState,
    this.queueState,
    this.activeRunState,
    this.routeSessionState,
    this.queuedCount,
    this.runningCount,
    this.deadLetterCount,
    this.failedCount,
    this.oldestQueuedAgeMs,
    this.nextAction,
    this.attentionState,
    this.attentionItemCount,
    this.attentionNextAction,
    required this.containsUserContent,
    required this.containsProviderAuthMaterial,
    this.lastMessageIdWatermarkPolicy,
  });

  final bool supported;
  final int statusSchemaVersion;
  final String runtimeFamily;
  final String? driverId;
  final String lifecycleState;
  final String operationalState;
  final bool setupReady;
  final String? setupState;
  final String? queueState;
  final String? activeRunState;
  final String? routeSessionState;
  final int? queuedCount;
  final int? runningCount;
  final int? deadLetterCount;
  final int? failedCount;
  final int? oldestQueuedAgeMs;
  final String? nextAction;
  final String? attentionState;
  final int? attentionItemCount;
  final String? attentionNextAction;
  final bool containsUserContent;
  final bool containsProviderAuthMaterial;
  final String? lastMessageIdWatermarkPolicy;

  static AgentRuntimeCardStatus? fromDiagnosticsSummary(
    Map<String, Object?> diagnosticsSummary,
  ) {
    final configSummary = _readMap(diagnosticsSummary['config_summary']);
    final runtimeCard = _readMap(configSummary['runtime_card']);
    if (runtimeCard.isEmpty) {
      return null;
    }
    return AgentRuntimeCardStatus.fromJson(runtimeCard);
  }

  static AgentRuntimeCardStatus? fromJson(Map<String, Object?> json) {
    final statusSchemaVersion = _optionalNonNegativeInt(
      json['status_schema_version'],
    );
    final runtimeFamily = _optionalString(json['runtime_family']);
    final lifecycleState = _optionalString(json['lifecycle_state']);
    final operationalState = _optionalString(json['operational_state']);
    if (statusSchemaVersion != 2 ||
        runtimeFamily != 'generic-cli' ||
        lifecycleState == null ||
        operationalState == null) {
      return null;
    }
    final supported = _optionalBool(json['supported']) ?? false;
    final setupReady = _optionalBool(json['setup_ready']) ?? false;
    final containsUserContent =
        _optionalBool(json['contains_user_content']) ?? false;
    final containsProviderAuthMaterial =
        _optionalBool(json['contains_provider_auth_material']) ?? false;
    if (containsUserContent || containsProviderAuthMaterial) {
      return null;
    }
    return AgentRuntimeCardStatus(
      supported: supported,
      statusSchemaVersion: 2,
      runtimeFamily: 'generic-cli',
      driverId: _optionalString(json['driver_id']),
      lifecycleState: lifecycleState,
      operationalState: operationalState,
      setupReady: setupReady,
      setupState: _optionalString(json['setup_state']),
      queueState: _optionalString(json['queue_state']),
      activeRunState: _optionalString(json['active_run_state']),
      routeSessionState: _optionalString(json['route_session_state']),
      queuedCount: _optionalNonNegativeInt(json['queued_count']),
      runningCount: _optionalNonNegativeInt(json['running_count']),
      deadLetterCount: _optionalNonNegativeInt(json['dead_letter_count']),
      failedCount: _optionalNonNegativeInt(json['failed_count']),
      oldestQueuedAgeMs: _optionalNonNegativeInt(json['oldest_queued_age_ms']),
      nextAction: _optionalString(json['next_action']),
      attentionState: _optionalString(json['attention_state']),
      attentionItemCount: _optionalNonNegativeInt(json['attention_item_count']),
      attentionNextAction: _optionalString(json['attention_next_action']),
      containsUserContent: containsUserContent,
      containsProviderAuthMaterial: containsProviderAuthMaterial,
      lastMessageIdWatermarkPolicy: _optionalString(
        json['last_message_id_watermark_policy'],
      ),
    );
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

bool? _optionalBool(Object? value) {
  return value is bool ? value : null;
}

int? _optionalNonNegativeInt(Object? value) {
  final parsed = switch (value) {
    int() => value,
    String() => int.tryParse(value),
    _ => null,
  };
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}
