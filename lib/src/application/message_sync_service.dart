import '../core/performance_logger.dart';
import '../domain/entities/chat_message.dart';
import 'models/app_conversation_read_ref.dart';
import 'models/app_thread_ref.dart';
import 'ports/message_sync_core_port.dart';

abstract interface class MessageSyncService {
  Future<MessageSyncOutcome> syncNow({required String reason, int limit = 100});

  Future<MessageSyncThreadAfterResult> syncThreadAfter({
    required AppThreadRef thread,
    String? afterServerSeq,
    int limit = 100,
  });
}

abstract interface class ConversationMessageSyncService {
  Future<MessageSyncThreadAfterResult> syncConversationAfter({
    required AppConversationReadRef conversation,
    String? afterServerSeq,
    int limit = 100,
  });
}

class ImCoreMessageSyncService
    implements MessageSyncService, ConversationMessageSyncService {
  const ImCoreMessageSyncService({required MessageSyncCorePort sync})
    : _sync = sync;

  final MessageSyncCorePort _sync;

  @override
  Future<MessageSyncOutcome> syncNow({
    required String reason,
    int limit = 100,
  }) {
    final coreReason = _coreMessageSyncReason(reason);
    return AwikiPerformanceLogger.async(
      'message_sync.now',
      () => _sync.syncNow(limit: limit, reason: coreReason),
      fields: <String, Object?>{
        'reason': reason,
        'core_reason': coreReason,
        'limit': limit,
      },
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

  @override
  Future<MessageSyncThreadAfterResult> syncConversationAfter({
    required AppConversationReadRef conversation,
    String? afterServerSeq,
    int limit = 100,
  }) {
    final sync = _sync;
    if (sync is! ConversationMessageSyncCorePort) {
      throw UnsupportedError(
        'Message sync core does not expose conversation-id sync.',
      );
    }
    return AwikiPerformanceLogger.async(
      'message_sync.conversation_after',
      () => (sync as ConversationMessageSyncCorePort).syncConversationAfter(
        conversation: conversation,
        afterServerSeq: afterServerSeq,
        limit: limit,
      ),
      fields: <String, Object?>{
        'conversation_hash': AwikiPerformanceLogger.safeHash(
          conversation.conversationId,
        ),
        'has_after_server_seq': afterServerSeq != null,
        'limit': limit,
      },
    );
  }
}

String _coreMessageSyncReason(String reason) {
  final normalized = reason.trim();
  return switch (normalized) {
    'session_start' || 'startup' => 'session_start',
    'app_resume' || 'app_resumed' => 'app_resume',
    'websocket_reconnect' || 'realtime_reconnected' => 'websocket_reconnect',
    'foreground_reconcile' || 'foreground_catch_up' => 'foreground_reconcile',
    'manual_refresh' => 'manual_refresh',
    'remote_push' => 'remote_push',
    'after_mutation' => 'after_mutation',
    'websocket_hint' ||
    'realtime_agent_control' ||
    'system_notification_changed' ||
    'realtime_gap' ||
    'realtime_dirty' ||
    'realtime_message' ||
    'realtime_persistent_fact' => 'websocket_hint',
    _ when normalized.startsWith('realtime_') => 'websocket_hint',
    _ => 'manual_refresh',
  };
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
