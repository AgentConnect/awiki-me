import '../../domain/entities/chat_message.dart';
import '../models/app_thread_ref.dart';

abstract interface class MessageSyncCorePort {
  Future<MessageSyncDeltaResult> syncDelta({
    int? limit,
    String? deviceId,
    String? reason,
  });

  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int? limit,
  });
}

class MessageSyncDeltaResult {
  const MessageSyncDeltaResult({
    required this.eventsApplied,
    required this.pagesFetched,
    this.lastAppliedEventSeq,
    required this.hasMore,
    required this.snapshotRequired,
    this.retentionFloorEventSeq,
    this.warnings = const <String>[],
  });

  final int eventsApplied;
  final int pagesFetched;
  final String? lastAppliedEventSeq;
  final bool hasMore;
  final bool snapshotRequired;
  final String? retentionFloorEventSeq;
  final List<String> warnings;
}

class MessageSyncThreadAfterResult {
  const MessageSyncThreadAfterResult({
    required this.messages,
    this.nextAfterServerSeq,
    required this.hasMore,
    this.warnings = const <String>[],
  });

  final List<ChatMessage> messages;
  final String? nextAfterServerSeq;
  final bool hasMore;
  final List<String> warnings;
}
