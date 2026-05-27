import '../domain/entities/chat_message.dart';
import 'models/attachment_models.dart';
import 'models/app_thread_ref.dart';
import 'ports/message_core_port.dart';

abstract interface class MessagingService {
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

class ImCoreMessagingService implements MessagingService {
  const ImCoreMessagingService({required MessageCorePort messages})
    : _messages = messages;

  final MessageCorePort _messages;

  @override
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
  }) {
    return _messages.sendText(thread: thread, content: content);
  }

  @override
  Future<ChatMessage> sendAttachment({
    required AppThreadRef thread,
    required AttachmentDraft attachment,
    String? caption,
    String? idempotencyKey,
  }) {
    return _messages.sendAttachment(
      thread: thread,
      attachment: attachment,
      caption: caption,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<AttachmentDownloadResult> downloadAttachment({
    required AppThreadRef thread,
    required String messageId,
    String? attachmentId,
    String? localPath,
  }) {
    return _messages.downloadAttachment(
      thread: thread,
      messageId: messageId,
      attachmentId: attachmentId,
      localPath: localPath,
    );
  }

  @override
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
  }) {
    return _messages.loadHistory(thread, limit: limit, cursor: cursor);
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    return _messages.retryByResendOriginalContent(failed);
  }
}
