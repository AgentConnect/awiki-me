import '../ports/message_sync_core_port.dart';

enum RemotePushSyncDisposition {
  succeeded,
  retryableFailure,
  recoveryRequired,
  authRevoked,
  blocked,
  capacityExceeded,
  staleSession,
  ignored,
}

final class RemotePushSyncReceipt {
  const RemotePushSyncReceipt({
    required this.disposition,
    this.committedIncomingMessages = const <CommittedIncomingMessage>[],
    this.recoveredIncomingMessages = const <LocalIncomingMessage>[],
  });

  final RemotePushSyncDisposition disposition;
  final List<CommittedIncomingMessage> committedIncomingMessages;
  final List<LocalIncomingMessage> recoveredIncomingMessages;

  bool get canAcknowledge => disposition == RemotePushSyncDisposition.succeeded;
}
