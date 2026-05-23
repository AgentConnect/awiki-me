import '../domain/entities/chat_message.dart';
import 'models/app_thread_ref.dart';
import 'ports/message_core_port.dart';

abstract interface class MessagingService {
  Future<ChatMessage> sendText({
    required AppThreadRef thread,
    required String content,
    String? clientMessageId,
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
    String? clientMessageId,
  }) {
    return _messages.sendText(
      thread: thread,
      content: content,
      clientMessageId: clientMessageId,
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
