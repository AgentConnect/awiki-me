enum AppMessageSyncMode { uninitialized, idle, recovering, retryable, blocked }

enum AppMessageSyncDirtyDomain { messages, readState }

enum AppMessageSyncRetryState {
  none,
  pending,
  inFlight,
  scheduled,
  permanentFailure,
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
