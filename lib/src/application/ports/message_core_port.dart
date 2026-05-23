import '../../domain/entities/chat_message.dart';
import '../models/app_thread_ref.dart';

abstract interface class MessageCorePort {
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
