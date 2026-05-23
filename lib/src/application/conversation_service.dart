import '../domain/entities/conversation_summary.dart';
import 'models/app_thread_ref.dart';
import 'models/product_local_models.dart';
import 'ports/conversation_core_port.dart';
import 'product_local_store.dart';

abstract interface class ConversationService {
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  });

  Future<void> markThreadRead(AppThreadRef thread);

  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  });
}

class ImCoreConversationService implements ConversationService {
  const ImCoreConversationService({
    required ConversationCorePort conversations,
    required ProductLocalStore localStore,
  }) : _conversations = conversations,
       _localStore = localStore;

  final ConversationCorePort _conversations;
  final ProductLocalStore _localStore;

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    final items = await _conversations.listConversations(
      limit: limit,
      unreadOnly: unreadOnly,
    );
    final overlays = await _localStore.loadConversationOverlays(
      ownerDid: ownerDid,
      threadIds: items.map((item) => item.threadId),
    );
    final visible = items
        .where((item) => overlays[item.threadId]?.hidden != true)
        .map((item) => _applyOverlay(item, overlays[item.threadId]))
        .toList();
    visible.sort((a, b) {
      final aPinned = overlays[a.threadId]?.pinned == true;
      final bPinned = overlays[b.threadId]?.pinned == true;
      if (aPinned != bPinned) {
        return aPinned ? -1 : 1;
      }
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
    return visible;
  }

  @override
  Future<void> markThreadRead(AppThreadRef thread) {
    // TODO(im-core): replace once SDK exposes markThreadRead(ThreadRef) or
    // unread message query/read-state fields. Do not infer unread IDs from
    // history pages because current Message DTOs cannot prove read-state.
    return _conversations.markThreadRead(thread);
  }

  @override
  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  }) {
    return _localStore.setThreadHidden(
      ownerDid: ownerDid,
      threadId: threadId,
      hidden: hidden,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }
}

ConversationSummary _applyOverlay(
  ConversationSummary item,
  ProductConversationOverlay? overlay,
) {
  if (overlay == null) {
    return item;
  }
  return ConversationSummary(
    threadId: item.threadId,
    displayName: overlay.customTitle ?? item.displayName,
    lastMessagePreview: item.lastMessagePreview,
    lastMessageAt: item.lastMessageAt,
    unreadCount: item.unreadCount,
    isGroup: item.isGroup,
    targetDid: item.targetDid,
    groupId: item.groupId,
    avatarSeed: overlay.avatarSeed ?? item.avatarSeed,
  );
}
