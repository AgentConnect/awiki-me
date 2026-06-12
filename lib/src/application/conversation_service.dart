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
    final visible = _mergeAgentConversationDuplicates(items, agentProjection)
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

List<ConversationSummary> _mergeAgentConversationDuplicates(
  List<ConversationSummary> items,
  _AgentConversationProjection projection,
) {
  if (items.length < 2 || projection.runtimeAgents.isEmpty) {
    return items;
  }
  final byKey = <String, ConversationSummary>{};
  for (final item in items) {
    final key = _conversationMergeKey(item, projection);
    final existing = byKey[key];
    byKey[key] = existing == null
        ? item
        : _mergeConversationDuplicate(existing, item);
  }
  return byKey.values.toList();
}

String _conversationMergeKey(
  ConversationSummary item,
  _AgentConversationProjection projection,
) {
  if (item.isGroup) {
    return 'group:${item.groupId ?? item.threadId}';
  }
  final agent = _agentForConversation(item, projection);
  if (agent != null && agent.isRuntime) {
    return 'runtime:${agent.agentDid}';
  }
  final targetPeer = _normalizedPeer(item.targetPeer);
  if (targetPeer != null) {
    return 'direct:$targetPeer';
  }
  final targetDid = item.targetDid?.trim();
  if (targetDid != null && targetDid.isNotEmpty) {
    return 'direct:$targetDid';
  }
  return 'thread:${item.threadId}';
}

ConversationSummary _mergeConversationDuplicate(
  ConversationSummary first,
  ConversationSummary second,
) {
  final latest = first.lastMessageAt.isBefore(second.lastMessageAt)
      ? second
      : first;
  final other = identical(latest, first) ? second : first;
  final identity = _preferredConversationIdentity(first, second, latest);
  return latest.copyWith(
    threadId: identity.threadId,
    unreadCount: first.unreadCount + second.unreadCount,
    targetDid: identity.targetDid ?? latest.targetDid ?? other.targetDid,
    targetPeer:
        _preferredTargetPeer(first, second) ??
        latest.targetPeer ??
        other.targetPeer,
    avatarSeed: identity.avatarSeed ?? latest.avatarSeed ?? other.avatarSeed,
    peerLifecycleState:
        first.isDeletedAgentConversation || second.isDeletedAgentConversation
        ? ConversationPeerLifecycleState.deletedAgent
        : ConversationPeerLifecycleState.active,
  );
}

ConversationSummary _preferredConversationIdentity(
  ConversationSummary first,
  ConversationSummary second,
  ConversationSummary latest,
) {
  final firstScore = _conversationIdentityScore(first);
  final secondScore = _conversationIdentityScore(second);
  if (firstScore == secondScore) {
    return latest;
  }
  return firstScore > secondScore ? first : second;
}

int _conversationIdentityScore(ConversationSummary item) {
  final targetPeer = _normalizedPeer(item.targetPeer);
  var score = 0;
  if (targetPeer != null && !targetPeer.startsWith('did:')) {
    score += 8;
  }
  if (item.threadId.startsWith('dm:peer-scope:')) {
    score += 4;
  }
  if ((item.targetDid?.trim().startsWith('did:') ?? false)) {
    score += 2;
  }
  if (targetPeer != null && targetPeer.startsWith('did:')) {
    score -= 2;
  }
  if (item.threadId.startsWith('dm:did:')) {
    score -= 1;
  }
  return score;
}

String? _preferredTargetPeer(
  ConversationSummary first,
  ConversationSummary second,
) {
  for (final item in <ConversationSummary>[first, second]) {
    final peer = _normalizedPeer(item.targetPeer);
    if (peer != null && !peer.startsWith('did:')) {
      return peer;
    }
  }
  return _normalizedPeer(first.targetPeer) ??
      _normalizedPeer(second.targetPeer);
}

ConversationSummary _applyAgentLifecycleProjection(
  ConversationSummary item,
  _AgentConversationProjection projection,
) {
  final agent = _agentForConversation(item, projection);
  if (agent == null) {
    return item;
  }
  if (!projection.deletedRuntimeAgentDids.contains(agent.agentDid)) {
    return item.copyWith(displayName: AgentDisplayName.title(agent));
  }
  return item.copyWith(
    displayName: AgentDisplayName.title(agent),
    peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
  );
}

AgentSummary? _agentForConversation(
  ConversationSummary item,
  _AgentConversationProjection projection,
) {
  final targetDid = item.targetDid?.trim();
  if (targetDid != null && targetDid.isNotEmpty) {
    final agent = projection.agentByDid[targetDid];
    if (agent != null) {
      return agent;
    }
  }
  final targetPeer = _normalizedPeer(item.targetPeer);
  if (targetPeer == null) {
    return null;
  }
  return projection.runtimeAgentByHandle[targetPeer] ??
      projection.runtimeAgentByHandle[_handleLocalPart(targetPeer)];
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
    this.runtimeAgentByHandle = const <String, AgentSummary>{},
  });

  factory _AgentConversationProjection.fromAgents(List<AgentSummary> agents) {
    final daemonDids = <String>{};
    final deletedRuntimeDids = <String>{};
    final agentByDid = <String, AgentSummary>{};
    final runtimeAgentByHandle = <String, AgentSummary>{};
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
      final normalizedHandle = _normalizedPeer(agent.handle);
      if (agent.isRuntime && normalizedHandle != null) {
        runtimeAgentByHandle[normalizedHandle] = agent;
        runtimeAgentByHandle[_handleLocalPart(normalizedHandle)] = agent;
      }
      if (agent.isRuntime && _isArchivedAgent(agent)) {
        deletedRuntimeDids.add(agentDid);
      }
    }
    return _AgentConversationProjection(
      daemonAgentDids: daemonDids,
      deletedRuntimeAgentDids: deletedRuntimeDids,
      agentByDid: agentByDid,
      runtimeAgentByHandle: runtimeAgentByHandle,
    );
  }

  final Set<String> daemonAgentDids;
  final Set<String> deletedRuntimeAgentDids;
  final Map<String, AgentSummary> agentByDid;
  final Map<String, AgentSummary> runtimeAgentByHandle;

  List<AgentSummary> get runtimeAgents =>
      agentByDid.values.where((agent) => agent.isRuntime).toList();
}

bool _isArchivedAgent(AgentSummary agent) {
  final activeState = agent.activeState.trim().toLowerCase();
  final latestStatus = agent.latest.status.trim().toLowerCase();
  return activeState == 'archived' || latestStatus == 'archived';
}

String? _normalizedPeer(String? value) {
  final peer = _trimLeadingAt(value?.trim()).trim();
  if (peer.isEmpty) {
    return null;
  }
  return peer.startsWith('did:') ? peer : peer.toLowerCase();
}

String _handleLocalPart(String value) {
  final normalized = _trimLeadingAt(value.trim()).toLowerCase();
  final dotIndex = normalized.indexOf('.');
  if (dotIndex <= 0) {
    return normalized;
  }
  return normalized.substring(0, dotIndex);
}

String _trimLeadingAt(String? value) {
  final text = value ?? '';
  return text.startsWith('@') ? text.substring(1).trimLeft() : text;
}
