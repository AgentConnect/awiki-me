enum AppMessageSyncMode { uninitialized, idle, recovering, retryable, blocked }

enum AppMessageSyncDirtyDomain { messages, readState }

enum AppMessageSyncRetryState {
  none,
  pending,
  inFlight,
  scheduled,
  permanentFailure,
}

enum AppMessageSyncFailureStage { prepare, coreSync, postCommitProjection }

enum AppMessageSyncFailureCategory {
  auth,
  transport,
  service,
  localState,
  protocol,
  projection,
  unknown,
}

/// Redacted product-safe diagnostics. It intentionally contains no cursor,
/// account/device identifier, message content, token, or payload.
class AppMessageSyncDiagnostics {
  const AppMessageSyncDiagnostics({
    this.lastSuccessAt,
    required this.mode,
    required this.pendingMutationCount,
    this.dirtyDomains = const <AppMessageSyncDirtyDomain>[],
    required this.retryState,
    this.nextRetryAt,
  });

  final DateTime? lastSuccessAt;
  final AppMessageSyncMode mode;
  final int pendingMutationCount;
  final List<AppMessageSyncDirtyDomain> dirtyDomains;
  final AppMessageSyncRetryState retryState;
  final DateTime? nextRetryAt;
}

/// Product-owned, payload-free diagnostics serialization.
///
/// A failed refresh advances [refreshAttemptSequence] without advancing
/// [refreshSuccessSequence], so consumers cannot mistake retained values for a
/// current successful observation.
class AppMessageSyncSafeDiagnostics {
  const AppMessageSyncSafeDiagnostics({
    required this.refreshAttemptSequence,
    required this.refreshSuccessSequence,
    this.refreshedAt,
    this.lastSuccessAt,
    required this.mode,
    required this.pendingMutationCount,
    this.dirtyDomains = const <AppMessageSyncDirtyDomain>[],
    required this.retryState,
    this.nextRetryAt,
    this.firstRetryableFailureAt,
    this.lastFailureAt,
    this.lastFailureStage,
    this.lastFailureCategory,
    this.lastFailureCode,
    this.lastFailureHttpStatus,
    this.retryableFailureSurfaceAt,
    this.retryableFailureVisible = false,
    this.consecutiveRetryableFailures = 0,
    this.automaticRetryPending = false,
  });

  final int refreshAttemptSequence;
  final int refreshSuccessSequence;
  final DateTime? refreshedAt;
  final DateTime? lastSuccessAt;
  final AppMessageSyncMode mode;
  final int pendingMutationCount;
  final List<AppMessageSyncDirtyDomain> dirtyDomains;
  final AppMessageSyncRetryState retryState;
  final DateTime? nextRetryAt;
  final DateTime? firstRetryableFailureAt;
  final DateTime? lastFailureAt;
  final AppMessageSyncFailureStage? lastFailureStage;
  final AppMessageSyncFailureCategory? lastFailureCategory;
  final String? lastFailureCode;
  final int? lastFailureHttpStatus;
  final DateTime? retryableFailureSurfaceAt;
  final bool retryableFailureVisible;
  final int consecutiveRetryableFailures;
  final bool automaticRetryPending;

  bool get isCurrent =>
      refreshSuccessSequence > 0 &&
      refreshAttemptSequence == refreshSuccessSequence &&
      refreshedAt != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 2,
    'current': isCurrent,
    'refresh_attempt_sequence': refreshAttemptSequence,
    'refresh_success_sequence': refreshSuccessSequence,
    'refreshed_at': refreshedAt?.toUtc().toIso8601String(),
    'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
    'mode': mode.name,
    'pending_mutation_count': pendingMutationCount,
    'dirty_domains': dirtyDomains.map((domain) => domain.name).toList(),
    'retry_state': retryState.name,
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
    'first_retryable_failure_at': firstRetryableFailureAt
        ?.toUtc()
        .toIso8601String(),
    'last_failure_at': lastFailureAt?.toUtc().toIso8601String(),
    'last_failure_stage': lastFailureStage?.name,
    'last_failure_category': lastFailureCategory?.name,
    'last_failure_code': lastFailureCode,
    'last_failure_http_status': lastFailureHttpStatus,
    'retryable_failure_surface_at': retryableFailureSurfaceAt
        ?.toUtc()
        .toIso8601String(),
    'retryable_failure_visible': retryableFailureVisible,
    'consecutive_retryable_failures': consecutiveRetryableFailures,
    'automatic_retry_pending': automaticRetryPending,
  };
}
