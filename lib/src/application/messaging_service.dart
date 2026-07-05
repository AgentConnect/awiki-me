import '../domain/entities/chat_message.dart';
import '../domain/entities/chat_mention.dart';
import 'models/attachment_models.dart';
import 'models/app_conversation_read_ref.dart';
import 'models/app_thread_ref.dart';
import 'models/thread_message_patch.dart';
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
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
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

  /// Legacy migration adapter. New reads should use
  /// [ConversationTimelineMessagingService.loadConversationTimeline].
  Future<List<ChatMessage>> loadHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });

  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed);
}

abstract interface class LocalHistoryMessagingService {
  /// Legacy migration adapter. New reads should use
  /// [ConversationTimelineMessagingService.loadConversationTimeline].
  Future<List<ChatMessage>> loadLocalHistory(
    AppThreadRef thread, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  });
}

abstract interface class ThreadPatchMessagingService {
  /// Legacy migration adapter. New patch streams should use
  /// [ConversationTimelineMessagingService.watchConversationTimelinePatches].
  Stream<ThreadMessagePatch> watchThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  });

  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  });
}

abstract interface class ConversationTimelineMessagingService {
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

class ImCoreMessagingService
    implements
        MessagingService,
        LocalHistoryMessagingService,
        ThreadPatchMessagingService,
        ConversationTimelineMessagingService {
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
    List<ChatMentionDraft> mentions = const <ChatMentionDraft>[],
    String? idempotencyKey,
  }) {
    return _messages.sendAttachment(
      thread: thread,
      attachment: attachment,
      caption: caption,
      mentions: mentions,
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
  Future<List<ChatMessage>> loadConversationTimeline(
    AppConversationReadRef conversation, {
    int limit = 100,
    String? cursor,
    bool includeControlPayloads = false,
  }) {
    final messages = _messages;
    if (messages is! ConversationTimelineMessageCorePort) {
      throw UnsupportedError(
        'Message core does not expose conversation timeline.',
      );
    }
    return (messages as ConversationTimelineMessageCorePort)
        .loadConversationTimeline(
          conversation,
          limit: limit,
          cursor: cursor,
          includeControlPayloads: includeControlPayloads,
        );
  }

  @override
  Stream<ThreadMessagePatch> watchThreadPatches(
    AppThreadRef thread, {
    int limit = 100,
  }) {
    final messages = _messages;
    if (messages is! ThreadPatchMessageCorePort) {
      throw UnsupportedError('Message core does not expose thread patches.');
    }
    return (messages as ThreadPatchMessageCorePort).watchThreadPatches(
      thread,
      limit: limit,
    );
  }

  @override
  Future<ThreadMessagePatch> repairThreadStore(
    AppThreadRef thread, {
    int limit = 100,
  }) {
    final messages = _messages;
    if (messages is! ThreadPatchMessageCorePort) {
      throw UnsupportedError('Message core does not expose thread patches.');
    }
    return (messages as ThreadPatchMessageCorePort).repairThreadStore(
      thread,
      limit: limit,
    );
  }

  @override
  Stream<ThreadMessagePatch> watchConversationTimelinePatches(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) {
    final messages = _messages;
    if (messages is! ConversationTimelineMessageCorePort) {
      throw UnsupportedError(
        'Message core does not expose conversation timeline patches.',
      );
    }
    return (messages as ConversationTimelineMessageCorePort)
        .watchConversationTimelinePatches(conversation, limit: limit);
  }

  @override
  Future<ThreadMessagePatch> repairConversationTimelineStore(
    AppConversationReadRef conversation, {
    int limit = 100,
  }) {
    final messages = _messages;
    if (messages is! ConversationTimelineMessageCorePort) {
      throw UnsupportedError(
        'Message core does not expose conversation timeline patches.',
      );
    }
    return (messages as ConversationTimelineMessageCorePort)
        .repairConversationTimelineStore(conversation, limit: limit);
  }

  @override
  Future<ChatMessage> retryByResendOriginalContent(ChatMessage failed) {
    return _messages.retryByResendOriginalContent(failed);
  }
}
