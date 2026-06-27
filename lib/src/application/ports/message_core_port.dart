import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_mention.dart';
import '../models/attachment_models.dart';
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

  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  });

  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });

  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed);
}

abstract interface class LocalHistoryMessageCorePort {
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });
}

abstract interface class ThreadPatchMessageCorePort {
  Stream<ThreadMessagePatch> watchThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  });

  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  });
}
