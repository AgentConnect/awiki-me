import '../domain/entities/conversation_summary.dart';
import 'agent/agent_control_projection.dart';
import 'models/app_thread_ref.dart';
import 'models/product_local_models.dart';
import 'ports/agent_inventory_port.dart';
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
    AgentInventoryPort? agentInventory,
  }) : _conversations = conversations,
       _agentInventory = agentInventory,
       _localStore = localStore;

  final ConversationCorePort _conversations;
  final AgentInventoryPort? _agentInventory;
  final ProductLocalStore _localStore;

  ImCoreConversationService withAgentInventory(AgentInventoryPort inventory) {
    return ImCoreConversationService(
      conversations: _conversations,
      localStore: _localStore,
      agentInventory: inventory,
    );
  }

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
    final daemonAgentDids = await _loadDaemonAgentDids();
    final visible = items
        .where(
          (item) => shouldShowConversationForChatList(
            item,
            daemonAgentDids: daemonAgentDids,
          ),
        )
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

  Future<Set<String>> _loadDaemonAgentDids() async {
    final inventory = _agentInventory;
    if (inventory == null) {
      return const <String>{};
    }
    try {
      final agents = await inventory.listAgents();
      return agents
          .where((agent) => agent.isDaemon)
          .map((agent) => agent.agentDid.trim())
          .where((agentDid) => agentDid.isNotEmpty)
          .toSet();
    } on Object {
      return const <String>{};
    }
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
    lastMessagePayloadJson: item.lastMessagePayloadJson,
  );
}
