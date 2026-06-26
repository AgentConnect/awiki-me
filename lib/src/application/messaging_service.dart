import '../domain/entities/chat_message.dart';
import '../domain/entities/chat_mention.dart';
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

  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  });

  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
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

abstract interface class LocalHistoryMessagingService {
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });
}

class ImCoreMessagingService
    implements MessagingService, LocalHistoryMessagingService {
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
  Future<ChatMessage> sendPayload({
    required AppThreadRef thread,
    required Map<String, Object?> payload,
    bool secure = true,
    String? idempotencyKey,
  }) {
    return _messages.sendPayload(
      thread: thread,
      payload: payload,
      secure: secure,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<ChatMessage> sendMentionText({
    required AppThreadRef thread,
    required String text,
    required List<ChatMentionDraft> mentions,
    String? idempotencyKey,
  }) {
    return _messages.sendPayload(
      thread: thread,
      payload: ChatMentionPayload.toP9Json(text: text, draftMentions: mentions),
      secure: false,
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
    bool includeControlPayloads = false,
  }) {
    return _messages.loadHistory(
      thread,
      limit: limit,
      cursor: cursor,
      includeControlPayloads: includeControlPayloads,
    );
  }

  @override
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) {
    final messages = _messages;
    if (messages is! LocalHistoryMessageCorePort) {
      throw UnsupportedError('Message core does not expose local history.');
    }
    return (messages as LocalHistoryMessageCorePort).loadLocalHistory(
      thread,
      limit: limit,
      cursor: cursor,
      includeControlPayloads: includeControlPayloads,
    );
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    return _messages.retryByResendOriginalContent(failed);
  }
}
