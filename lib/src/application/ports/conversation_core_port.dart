import '../../domain/entities/conversation_summary.dart';
import '../models/app_thread_ref.dart';

abstract interface class ConversationCorePort {
  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  });

  /// TODO: replace this unsupported boundary when IM Core exposes
  /// markThreadRead(ThreadRef) or unread message query/read-state fields.
  Future<void> markThreadRead(AppThreadRef thread);
}
