import '../ports/message_sync_core_port.dart';

enum RemotePushSyncDisposition {
  succeeded,
  retryableFailure,
  recoveryRequired,
  authRevoked,
  staleSession,
  ignored,
}

final class RemotePushSyncReceipt {
  const RemotePushSyncReceipt({
    required this.disposition,
    this.committedIncomingMessages = const <CommittedIncomingMessage>[],
    this.errorCode,
    this.eventsApplied = 0,
    this.duplicatesSkipped = 0,
    this.lastStatus,
  });

  final RemotePushSyncDisposition disposition;
  final List<CommittedIncomingMessage> committedIncomingMessages;
  final String? errorCode;
  final int eventsApplied;
  final int duplicatesSkipped;
  final String? lastStatus;

  bool get canAcknowledge => disposition == RemotePushSyncDisposition.succeeded;
}
