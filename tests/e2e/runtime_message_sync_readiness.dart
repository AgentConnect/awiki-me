// [INPUT]: The exact Runtime Agent's persisted bootstrap state and error code.
// [OUTPUT]: A fail-closed Core readiness condition for Recovery fixture setup.
// [POS]: Test-only oracle; real Runtime prompt/reply acceptance remains required.

bool runtimeCoreBootstrapReady({
  required String? bootstrapState,
  required String? lastErrorCode,
}) =>
    (bootstrapState == 'tail_bootstrapped' || bootstrapState == 'active') &&
    lastErrorCode == null;

bool daemonPublicSyncV2Ready(Object? status) {
  if (status is! Map) return false;
  final probe = status['sync_probe'];
  return probe is Map &&
      probe['v2_subprotocol_negotiated'] == true &&
      probe['v2_bootstrap_completed'] == true &&
      probe['last_reconcile_protocol'] == 'sync_v2' &&
      probe['legacy_sync_used'] == false;
}

// A ready file precedes the first tail bootstrap. Do not send the first
// command until its receiving replica is ready; WebSocket hints are optional.
bool daemonPublicCommandReceiverReady(Object? status) {
  if (status is! Map || status['ready'] != true) return false;
  final probe = status['sync_probe'];
  return probe is Map &&
      probe['v2_bootstrap_completed'] == true &&
      probe['last_reconcile_protocol'] == 'sync_v2' &&
      probe['legacy_sync_used'] == false;
}
