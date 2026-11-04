import 'dart:async';

import 'package:awiki_me/src/application/models/app_thread_read_watermark.dart';

import 'closed_onboarding_diagnostics.dart';

/// A recovery fixture needs a final remote ACK, while Core may first report a
/// successor queued behind another read. Resubmit only that known, exact local
/// watermark under one deadline; other partial/error results remain terminal.
Future<AppConversationReadCommitResult> awaitRecoveryFixtureReadAck({
  required AppThreadReadWatermark watermark,
  required Future<AppConversationReadCommitResult> Function(
    AppThreadReadWatermark watermark,
  )
  markRead,
  required Duration timeout,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  if (timeout <= Duration.zero || pollInterval <= Duration.zero) {
    throw ArgumentError('Read fixture durations must be positive.');
  }
  if (watermark.lastReadMessageId?.trim().isNotEmpty != true ||
      !RegExp(
        r'^(0|[1-9][0-9]*)$',
      ).hasMatch(watermark.lastReadThreadSeq ?? '')) {
    throw ArgumentError('Read fixture requires an exact message and sequence.');
  }
  final watch = Stopwatch()..start();
  Duration remaining() {
    final value = timeout - watch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('Recovery fixture read ACK did not converge.');
    }
    return value;
  }

  while (true) {
    final requestBudget = remaining();
    final result = await markRead(watermark).timeout(requestBudget);
    final effective = result.effectiveWatermark;
    final exact =
        effective?.lastReadMessageId == watermark.lastReadMessageId &&
        effective?.lastReadThreadSeq == watermark.lastReadThreadSeq;
    if (exact &&
        result.remoteAcknowledged &&
        !result.partial &&
        !result.fallbackUsed &&
        !result.pendingRemoteAck) {
      return result;
    }
    final queued =
        exact &&
        !result.remoteAcknowledged &&
        result.partial &&
        !result.fallbackUsed &&
        result.pendingRemoteAck &&
        result.warnings.length == 1 &&
        result.warnings.single ==
            'Read watermark is queued behind an in-flight predecessor';
    if (!queued) {
      throw StateError(
        'Recovery fixture read was not acknowledged exactly '
        '(remoteAck=${result.remoteAcknowledged}, partial=${result.partial}, '
        'fallback=${result.fallbackUsed}, pending=${result.pendingRemoteAck}, '
        'effectivePresent=${effective != null}, '
        'effectiveIdMatch=${effective?.lastReadMessageId == watermark.lastReadMessageId}, '
        'effectiveSeqMatch=${effective?.lastReadThreadSeq == watermark.lastReadThreadSeq}, '
        'warnings=${result.warnings.length}, '
        'warningCategories=${recoveryReadWarningCategories(result.warnings)}, '
        'httpStatuses=${recoveryReadHttpStatuses(result.warnings)}, '
        'serviceCodes=${recoveryReadServiceCodes(result.warnings)}).',
      );
    }
    final budget = remaining();
    await Future<void>.delayed(budget < pollInterval ? budget : pollInterval);
  }
}
