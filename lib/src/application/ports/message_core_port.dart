import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_mention.dart';
import '../models/attachment_models.dart';
import '../models/app_conversation_read_ref.dart';
import '../models/app_thread_ref.dart';
import '../models/thread_message_patch.dart';

abstract interface class MessageCorePort {
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  });

  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? idempotencyKey,
  });

  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  });

  Future<ChatMessage> sendConversationText({
    required AppConversationReadRef conversation,
    required String content,
    String? clientMessageId,
    String? idempotencyKey,
  });

  Future<ChatMessage> sendConversationPayload({
    required AppConversationReadRef conversation,
    required Map<String, Object?> payload,
    String? clientMessageId,
    String? idempotencyKey,
  });

  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  });

  /// Legacy migration adapter. New timeline reads should use
  /// [ConversationTimelineMessageCorePort.loadConversationTimeline].
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });

  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed);
}

abstract interface class LocalHistoryMessageCorePort {
  /// Legacy migration adapter. New local-first timeline reads should use
  /// [ConversationTimelineMessageCorePort.loadConversationTimeline].
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });
}

abstract interface class ThreadPatchMessageCorePort {
  /// Legacy migration adapter. New timeline patch streams should use
  /// [ConversationTimelineMessageCorePort.watchConversationTimelinePatches].
  Stream<ThreadMessagePatch> watchThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  });

  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  });
}

abstract interface class ConversationTimelineMessageCorePort {
  Future<List<ChatMessage>> loadConversationTimeline(
    AppConversationReadRef conversation, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });

  Stream<ThreadMessagePatch> watchConversationTimelinePatches(
    AppConversationReadRef conversation, {
    int limit = 100,
  });

  Future<ThreadMessagePatch> repairConversationTimelineStore(
    AppConversationReadRef conversation, {
    int limit = 100,
  });
}
