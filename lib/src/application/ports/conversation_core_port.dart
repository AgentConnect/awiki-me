import '../../domain/entities/conversation_summary.dart';
import '../models/app_conversation_read_ref.dart';
import '../models/app_thread_ref.dart';
import '../models/app_thread_read_watermark.dart';
import '../models/conversation_patch.dart';

abstract interface class ConversationCorePort {
  Future<List<ConversationSummary>> loadConversationSnapshot();

  Future<void> clearConversationSnapshot();

  Stream<CoreConversationPatch> watchConversationPatches();

  Future<CoreConversationPatch> repairConversationStore();

  Future<List<ConversationSummary>> listConversations({
    int limit = 100,
    bool unreadOnly = false,
  });

  Future<CoreConversationPage> listConversationPage({
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  });

  /// Legacy migration adapter. New read paths should prefer
  /// [ConversationReadCorePort.markConversationRead] so im-core owns the
  /// canonical conversation identity and read watermark.
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  });
}

abstract interface class ConversationReadCorePort {
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  });
}
