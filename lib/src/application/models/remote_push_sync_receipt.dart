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
  });

  final RemotePushSyncDisposition disposition;
  final List<CommittedIncomingMessage> committedIncomingMessages;

  bool get canAcknowledge => disposition == RemotePushSyncDisposition.succeeded;
}
