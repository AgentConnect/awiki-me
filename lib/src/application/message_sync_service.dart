import '../core/performance_logger.dart';
import '../domain/entities/chat_message.dart';
import 'models/app_thread_ref.dart';
import 'ports/message_sync_core_port.dart';

abstract interface class MessageSyncService {
  Future<MessageSyncDeltaResult> syncNow({
    required String reason,
    int limit = 100,
  });

  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int limit = 100,
  });
}

class ImCoreMessageSyncService implements MessageSyncService {
  const ImCoreMessageSyncService({required MessageSyncCorePort sync})
    : _sync = sync;

  final MessageSyncCorePort _sync;

  @override
  Future<MessageSyncDeltaResult> syncNow({
    required String reason,
    int limit = 100,
  }) {
    return AwikiPerformanceLogger.async(
      'message_sync.delta',
      () => _sync.syncDelta(limit: limit, reason: reason),
      fields: <String, Object?>{'reason': reason, 'limit': limit},
    );
  }

  @override
  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int limit = 100,
  }) {
    return AwikiPerformanceLogger.async(
      'message_sync.thread_after',
      () => _sync.syncThreadAfter(
        thread: thread,
        afterServerSeq: afterServerSeq,
        limit: limit,
      ),
      fields: <String, Object?>{
        'thread': thread.stableId,
        'has_after_server_seq': afterServerSeq != null,
        'limit': limit,
      },
    );
  }
}

String? maxServerSequenceForMessages(Iterable<ChatMessage> messages) {
  int? maxSeq;
  for (final message in messages) {
    final seq = message.serverSequence;
    if (seq == null) {
      continue;
    }
    if (maxSeq == null || seq > maxSeq) {
      maxSeq = seq;
    }
  }
  return maxSeq?.toString();
}
