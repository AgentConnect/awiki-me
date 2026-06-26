import 'dart:async';

import '../domain/entities/agent/agent_display_name.dart';
import '../domain/entities/agent/agent_summary.dart';
import '../domain/entities/conversation_summary.dart';
import '../core/performance_logger.dart';
import 'agent/agent_control_projection.dart';
import 'models/app_thread_ref.dart';
import 'models/product_local_models.dart';
import 'ports/agent_inventory_port.dart';
import 'ports/conversation_core_port.dart';
import 'product_local_store.dart';

abstract interface class ConversationService {
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  });

  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  });

  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  });

  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  });

  Future<void> markThreadRead(AppThreadRef thread);

  Future<void> setThreadHidden({
    required String ownerDid,
    required String threadId,
    required bool hidden,
    DateTime? updatedAt,
  });

  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  });

  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  });
}

class ImCoreConversationService implements ConversationService {
  ImCoreConversationService({
    required ConversationCorePort conversations,
    required ProductLocalStore localStore,
    AgentInventoryPort? agentInventory,
    this.agentProjectionTimeout = const Duration(seconds: 3),
  }) : _conversations = conversations,
       _agentInventory = agentInventory,
       _localStore = localStore;

  final ConversationCorePort _conversations;
  final AgentInventoryPort? _agentInventory;
  final ProductLocalStore _localStore;
  final Duration agentProjectionTimeout;
  _AgentConversationProjection? _cachedAgentProjection;

  ImCoreConversationService withAgentInventory(AgentInventoryPort inventory) {
    return ImCoreConversationService(
      conversations: _conversations,
      localStore: _localStore,
      agentInventory: inventory,
      agentProjectionTimeout: agentProjectionTimeout,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    final items = await AwikiPerformanceLogger.async(
      'conversation_service.fast_local.core_list',
      () => _conversations.listConversations(
        limit: limit,
        unreadOnly: unreadOnly,
      ),
      fields: <String, Object?>{'limit': limit, 'unread_only': unreadOnly},
    );
    final projection =
        _cachedAgentProjection ?? const _AgentConversationProjection();
    final mergedItems = AwikiPerformanceLogger.sync(
      'conversation_service.fast_local.merge_cached_agents',
      () => _mergeAgentConversationDuplicates(items, projection),
      fields: <String, Object?>{
        'items': items.length,
        'cache_hit': _cachedAgentProjection != null,
        'agents': projection.agentCount,
        'runtime_agents': projection.runtimeAgents.length,
      },
    );
    final visible = AwikiPerformanceLogger.sync(
      'conversation_service.fast_local.filter_sort',
      () {
        final result = mergedItems
            .where(
              (item) => shouldShowConversationForChatList(
                item,
                daemonAgentDids: projection.daemonAgentDids,
              ),
            )
            .map((item) => _applyAgentLifecycleProjection(item, projection))
            .toList();
        result.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
        return result;
      },
      fields: <String, Object?>{
        'merged': mergedItems.length,
        'cache_hit': _cachedAgentProjection != null,
      },
    );
    AwikiPerformanceLogger.log(
      'conversation_service.fast_local',
      fields: <String, Object?>{
        'items': items.length,
        'visible': visible.length,
        'agent_projection_cache_hit': _cachedAgentProjection != null,
      },
    );
    return visible;
  }

  @override
  Future<List<ConversationSummary>> enrichConversationSummaries({
    required String ownerDid,
    required List<ConversationSummary> conversations,
  }) async {
    final totalWatch = Stopwatch()..start();
    if (conversations.isEmpty) {
      return conversations;
    }
    final agentProjection = await AwikiPerformanceLogger.async(
      'conversation_service.agent_projection',
      () => _loadAgentConversationProjection(),
      fields: <String, Object?>{'items': conversations.length},
    );
    final mergedItems = AwikiPerformanceLogger.sync(
      'conversation_service.merge_agents',
      () => _mergeAgentConversationDuplicates(conversations, agentProjection),
      fields: <String, Object?>{
        'items': conversations.length,
        'agents': agentProjection.agentCount,
        'runtime_agents': agentProjection.runtimeAgents.length,
      },
    );
    final overlayKeys = _overlayKeysForConversations(
      mergedItems,
    ).toList(growable: false);
    final overlays = await AwikiPerformanceLogger.async(
      'conversation_service.overlays',
      () => _localStore.loadConversationOverlays(
        ownerDid: ownerDid,
        threadIds: overlayKeys,
      ),
      fields: <String, Object?>{'keys': overlayKeys.length},
    );
    final visible = AwikiPerformanceLogger.sync(
      'conversation_service.filter_sort',
      () {
        final result = mergedItems
            .where(
              (item) => shouldShowConversationForChatList(
                item,
                daemonAgentDids: agentProjection.daemonAgentDids,
              ),
            )
            .where((item) => !_isConversationHidden(item, overlays))
            .map(
              (item) => _applyOverlay(
                _applyAgentLifecycleProjection(item, agentProjection),
                _preferredOverlayForConversation(item, overlays),
              ),
            )
            .toList();
        result.sort((a, b) {
          final aPinned = overlays[a.threadId]?.pinned == true;
          final bPinned = overlays[b.threadId]?.pinned == true;
          if (aPinned != bPinned) {
            return aPinned ? -1 : 1;
          }
          return b.lastMessageAt.compareTo(a.lastMessageAt);
        });
        return result;
      },
      fields: <String, Object?>{
        'merged': mergedItems.length,
        'overlays': overlays.length,
      },
    );
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_service.enrich',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        'items': conversations.length,
        'merged': mergedItems.length,
        'visible': visible.length,
      },
    );
    return visible;
  }

  @override
  Future<List<ConversationSummary>> listConversations({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    final totalWatch = Stopwatch()..start();
    final base = await listConversationSummariesFast(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    );
    final visible = await enrichConversationSummaries(
      ownerDid: ownerDid,
      conversations: base,
    );
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_service.list',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        'items': base.length,
        'visible': visible.length,
      },
    );
    return visible;
  }

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    final projection = await _loadAgentConversationProjection();
    final merged = _mergeAgentConversationDuplicates(<ConversationSummary>[
      conversation,
    ], projection);
    if (merged.isEmpty) {
      return null;
    }
    final normalized = merged.single;
    if (!shouldShowConversationForChatList(
      normalized,
      daemonAgentDids: projection.daemonAgentDids,
    )) {
      return null;
    }
    final overlays = await _localStore.loadConversationOverlays(
      ownerDid: ownerDid,
      threadIds: normalized.visibilityKeys,
    );
    if (_isConversationHidden(normalized, overlays)) {
      return null;
    }
    return _applyOverlay(
      _applyAgentLifecycleProjection(normalized, projection),
      _preferredOverlayForConversation(normalized, overlays),
    );
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

  @override
  Future<void> hideConversationFromRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {
    final normalized = await _conversationWithVisibilityKey(conversation);
    return _localStore.setConversationHidden(
      ownerDid: ownerDid,
      conversationKey: normalized.visibilityKey,
      hidden: true,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {
    final normalized = await _conversationWithVisibilityKey(conversation);
    final now = updatedAt ?? DateTime.now().toUtc();
    for (final key in normalized.visibilityKeys) {
      await _localStore.setConversationHidden(
        ownerDid: ownerDid,
        conversationKey: key,
        hidden: false,
        updatedAt: now,
      );
    }
  }

  Future<_AgentConversationProjection>
  _loadAgentConversationProjection() async {
    final inventory = _agentInventory;
    if (inventory == null) {
      return const _AgentConversationProjection();
    }
    try {
      final agents = await AwikiPerformanceLogger.async(
        'conversation_service.agent_projection.list_agents',
        () => inventory
            .listAgents(includeInactive: true)
            .timeout(agentProjectionTimeout),
      );
      final projection = _AgentConversationProjection.fromAgents(agents);
      _cachedAgentProjection = projection;
      return projection;
    } on Object {
      AwikiPerformanceLogger.log('conversation_service.agent_projection.error');
      return _cachedAgentProjection ?? const _AgentConversationProjection();
    }
  }

  Future<ConversationSummary> _conversationWithVisibilityKey(
    ConversationSummary conversation,
  ) async {
    final projection = await _loadAgentConversationProjection();
    return conversation.copyWith(
      conversationKey: _conversationMergeKey(conversation, projection),
    );
  }
}

Iterable<String> _overlayKeysForConversations(
  Iterable<ConversationSummary> conversations,
) {
  final keys = <String>{};
  for (final conversation in conversations) {
    keys.addAll(conversation.visibilityKeys);
  }
  return keys;
}

bool _isConversationHidden(
  ConversationSummary conversation,
  Map<String, ProductConversationOverlay> overlays,
) {
  return conversation.visibilityKeys.any(
    (key) => overlays[key]?.hidden == true,
  );
}

ProductConversationOverlay? _preferredOverlayForConversation(
  ConversationSummary conversation,
  Map<String, ProductConversationOverlay> overlays,
) {
  for (final key in conversation.visibilityKeys) {
    final overlay = overlays[key];
    if (overlay != null) {
      return overlay;
    }
  }
  return null;
}

List<ConversationSummary> _mergeAgentConversationDuplicates(
  List<ConversationSummary> items,
  _AgentConversationProjection projection,
) {
  if (items.isEmpty) {
    return items;
  }
  if (items.length < 2 || projection.runtimeAgents.isEmpty) {
    return items
        .map(
          (item) => item.copyWith(
            conversationKey: _conversationMergeKey(item, projection),
          ),
        )
        .toList(growable: false);
  }
  final byKey = <String, ConversationSummary>{};
  for (final item in items) {
    final key = _conversationMergeKey(item, projection);
    final existing = byKey[key];
    byKey[key] = existing == null
        ? item.copyWith(conversationKey: key)
        : _mergeConversationDuplicate(
            existing,
            item,
          ).copyWith(conversationKey: key);
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
    unreadMentionCount: first.unreadMentionCount + second.unreadMentionCount,
    firstUnreadMentionMessageId:
        first.firstUnreadMentionMessageId ?? second.firstUnreadMentionMessageId,
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

  int get agentCount => agentByDid.length;

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
