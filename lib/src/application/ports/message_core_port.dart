import '../../domain/entities/chat_message.dart';
import '../models/attachment_models.dart';
import '../models/app_thread_ref.dart';

abstract interface class MessageCorePort {
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  });

  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
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
  });

  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed);
}
