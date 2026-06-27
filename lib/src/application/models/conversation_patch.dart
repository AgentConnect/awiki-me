import '../../domain/entities/conversation_summary.dart';

enum ConversationListPatchKind { reset, upsert, remove, reorder, repairRequired }

class ConversationListPatch {
  const ConversationListPatch({
    required this.kind,
    required this.ownerDid,
    required this.version,
    required this.unreadTotal,
    this.items = const <ConversationSummary>[],
    this.item,
    this.index,
    this.threadId,
    this.conversationKey,
    this.reason,
  });

  final ConversationListPatchKind kind;
  final String ownerDid;
  final int version;
  final int unreadTotal;
  final List<ConversationSummary> items;
  final ConversationSummary? item;
  final int? index;
  final String? threadId;
  final String? conversationKey;
  final String? reason;
}

class ConversationStoreRepairResult {
  const ConversationStoreRepairResult({
    required this.conversations,
    required this.version,
  });

  final List<ConversationSummary> conversations;
  final int version;
}

enum CoreConversationPatchKind { reset, upsert, remove, reorder, repairRequired }

class CoreConversationPatch {
  const CoreConversationPatch({
    required this.kind,
    required this.ownerDid,
    required this.version,
    required this.unreadTotal,
    this.items = const <ConversationSummary>[],
    this.item,
    this.index,
    this.threadId,
    this.reason,
  });

  final CoreConversationPatchKind kind;
  final String ownerDid;
  final int version;
  final int unreadTotal;
  final List<ConversationSummary> items;
  final ConversationSummary? item;
  final int? index;
  final String? threadId;
  final String? reason;
}
