import 'package:awiki_im_core/awiki_im_core.dart' as core;

/// Retry only the public, retryable inventory fence during E2E preparation.
/// The caller's existing readiness deadline is shared with these attempts.
Future<T> retryStaleGroupInventory<T>(
  Future<T> Function() operation, {
  required DateTime deadline,
  required Future<void> Function() yieldToReceive,
  DateTime Function()? now,
}) async {
  final clock = now ?? DateTime.now;
  for (var attempt = 0; ; attempt++) {
    try {
      return await operation();
    } on core.AwikiImCoreException catch (error) {
      if (error.code != 'service_error' ||
          error.serviceCode != 'group.local_cursor_stale' ||
          attempt >= 2 ||
          !clock().isBefore(deadline)) {
        rethrow;
      }
      await yieldToReceive();
      if (!clock().isBefore(deadline)) rethrow;
    }
  }
}
