import '../domain/entities/agent/agent_display_name.dart';
import '../domain/entities/agent/agent_summary.dart';
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
    final agentProjection = await _loadAgentConversationProjection();
    final visible = items
        .where(
          (item) => shouldShowConversationForChatList(
            item,
            daemonAgentDids: agentProjection.daemonAgentDids,
          ),
        )
        .where((item) => overlays[item.threadId]?.hidden != true)
        .map(
          (item) => _applyOverlay(
            _applyAgentLifecycleProjection(item, agentProjection),
            overlays[item.threadId],
          ),
        )
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

  Future<_AgentConversationProjection>
  _loadAgentConversationProjection() async {
    final inventory = _agentInventory;
    if (inventory == null) {
      return const _AgentConversationProjection();
    }
    try {
      final agents = await inventory.listAgents(includeInactive: true);
      return _AgentConversationProjection.fromAgents(agents);
    } on Object {
      return const _AgentConversationProjection();
    }
  }
}

ConversationSummary _applyAgentLifecycleProjection(
  ConversationSummary item,
  _AgentConversationProjection projection,
) {
  final targetDid = item.targetDid?.trim();
  if (targetDid == null || targetDid.isEmpty) {
    return item;
  }
  if (!projection.deletedRuntimeAgentDids.contains(targetDid)) {
    final agent = projection.agentByDid[targetDid];
    if (agent == null) {
      return item;
    }
    return item.copyWith(displayName: AgentDisplayName.title(agent));
  }
  return item.copyWith(
    displayName: projection.agentByDid[targetDid] == null
        ? item.displayName
        : AgentDisplayName.title(projection.agentByDid[targetDid]!),
    peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
  );
}

ConversationSummary _applyOverlay(
  ConversationSummary item,
  ProductConversationOverlay? overlay,
) {
  if (overlay == null) {
    return item;
  }
  return item.copyWith(
    displayName: overlay.customTitle ?? item.displayName,
    avatarSeed: overlay.avatarSeed ?? item.avatarSeed,
  );
}

class _AgentConversationProjection {
  const _AgentConversationProjection({
    this.daemonAgentDids = const <String>{},
    this.deletedRuntimeAgentDids = const <String>{},
    this.agentByDid = const <String, AgentSummary>{},
  });

  factory _AgentConversationProjection.fromAgents(List<AgentSummary> agents) {
    final daemonDids = <String>{};
    final deletedRuntimeDids = <String>{};
    final agentByDid = <String, AgentSummary>{};
    for (final agent in agents) {
      final agentDid = agent.agentDid.trim();
      if (agentDid.isEmpty) {
        continue;
      }
      agentByDid[agentDid] = agent;
      if (agent.isDaemon) {
        daemonDids.add(agentDid);
        continue;
      }
      if (agent.isRuntime && _isArchivedAgent(agent)) {
        deletedRuntimeDids.add(agentDid);
      }
    }
    return _AgentConversationProjection(
      daemonAgentDids: daemonDids,
      deletedRuntimeAgentDids: deletedRuntimeDids,
      agentByDid: agentByDid,
    );
  }

  final Set<String> daemonAgentDids;
  final Set<String> deletedRuntimeAgentDids;
  final Map<String, AgentSummary> agentByDid;
}

bool _isArchivedAgent(AgentSummary agent) {
  final activeState = agent.activeState.trim().toLowerCase();
  final latestStatus = agent.latest.status.trim().toLowerCase();
  return activeState == 'archived' || latestStatus == 'archived';
}
