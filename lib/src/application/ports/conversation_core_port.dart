import '../../domain/entities/conversation_summary.dart';
import '../models/app_thread_ref.dart';

abstract interface class ConversationCorePort {
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  });

  /// Marks known unread messages in a thread as read through IM Core.
  Future<void> markThreadRead(AppThreadRef thread);
}
