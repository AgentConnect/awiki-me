import '../models/common.dart';
import '../models/message_models.dart';

abstract class ImConversationApi {
  Future<ImPage<ImConversationDto>> list(ImListConversationsRequest request);
  Future<ImConversationDto?> get(String threadId);
  Future<void> markThreadRead(String threadId);
  Future<void> deleteLocalThread(String threadId);
}

class ImListConversationsRequest {
  const ImListConversationsRequest({
    this.limit = 50,
    this.cursor,
    this.kind,
    this.unreadOnly = false,
  });

  final int limit;
  final String? cursor;
  final ImThreadKind? kind;
  final bool unreadOnly;
}
