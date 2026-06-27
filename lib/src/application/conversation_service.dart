import 'dart:async';

import '../domain/entities/agent/agent_display_name.dart';
import '../domain/entities/agent/agent_summary.dart';
import '../domain/entities/conversation_identity.dart';
import '../domain/entities/conversation_summary.dart';
import '../core/performance_logger.dart';
import 'agent/agent_control_projection.dart';
import 'models/app_thread_ref.dart';
import 'models/product_local_models.dart';
import 'ports/agent_inventory_port.dart';
import 'ports/conversation_core_port.dart';
import 'product_local_store.dart';

abstract interface class ConversationService {
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  });

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
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  }) async {
    final items = await AwikiPerformanceLogger.async(
      'conversation_service.snapshot.core_load',
      _conversations.loadConversationSnapshot,
      level: AwikiPerformanceLogLevel.verbose,
    );
    final projection =
        _cachedAgentProjection ?? const _AgentConversationProjection();
    final mergedItems = AwikiPerformanceLogger.sync(
      'conversation_service.snapshot.merge_cached_agents',
      () => _mergeAgentConversationDuplicates(items, projection),
      fields: <String, Object?>{
        'items': items.length,
        'cache_hit': _cachedAgentProjection != null,
        'agents': projection.agentCount,
        'runtime_agents': projection.runtimeAgents.length,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    final overlays = await _loadOverlaysForConversations(
      ownerDid: ownerDid,
      conversations: mergedItems,
      projection: projection,
      label: 'conversation_service.snapshot.overlays',
    );
    final visible = AwikiPerformanceLogger.sync(
      'conversation_service.snapshot.filter_sort',
      () {
        final result = mergedItems
            .where(
              (item) => shouldShowConversationForChatList(
                item,
                daemonAgentDids: projection.daemonAgentDids,
              ),
            )
            .where((item) => !_isConversationHidden(item, overlays, projection))
            .map(
              (item) => _applyOverlay(
                _applyAgentLifecycleProjection(item, projection),
                _preferredOverlayForConversation(item, overlays, projection),
              ),
            )
            .toList();
        _sortConversationsForDisplay(
          result,
          overlays: overlays,
          projection: projection,
        );
        return result;
      },
      fields: <String, Object?>{
        'items': items.length,
        'merged': mergedItems.length,
        'overlays': overlays.length,
        'cache_hit': _cachedAgentProjection != null,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    AwikiPerformanceLogger.log(
      'conversation_service.snapshot',
      fields: <String, Object?>{
        'items': items.length,
        'visible': visible.length,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    return visible;
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
      level: AwikiPerformanceLogLevel.verbose,
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
      level: AwikiPerformanceLogLevel.verbose,
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
      level: AwikiPerformanceLogLevel.verbose,
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
      level: AwikiPerformanceLogLevel.verbose,
    );
    final overlayKeys = _overlayKeysForConversations(
      mergedItems,
      agentProjection,
      includeHandleAliasesForStrongIdentity: true,
    ).toList(growable: false);
    final overlays = await _loadOverlaysForKeys(
      ownerDid: ownerDid,
      keys: overlayKeys,
      label: 'conversation_service.overlays',
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
            .where(
              (item) => !_isConversationHidden(item, overlays, agentProjection),
            )
            .map(
              (item) => _applyOverlay(
                _applyAgentLifecycleProjection(item, agentProjection),
                _preferredOverlayForConversation(
                  item,
                  overlays,
                  agentProjection,
                ),
              ),
            )
            .toList();
        _sortConversationsForDisplay(
          result,
          overlays: overlays,
          projection: agentProjection,
        );
        return result;
      },
      fields: <String, Object?>{
        'merged': mergedItems.length,
        'overlays': overlays.length,
      },
      level: AwikiPerformanceLogLevel.verbose,
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
    final overlays = await _loadOverlaysForKeys(
      ownerDid: ownerDid,
      keys: _conversationOverlayKeys(
        normalized,
        projection,
        includeHandleAliasesForStrongIdentity: true,
      ),
      label: 'conversation_service.normalize.overlays',
    );
    if (_isConversationHidden(normalized, overlays, projection)) {
      return null;
    }
    return _applyOverlay(
      _applyAgentLifecycleProjection(normalized, projection),
      _preferredOverlayForConversation(normalized, overlays, projection),
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
    final projection = await _loadAgentConversationProjection();
    final normalized = _conversationWithVisibilityKey(conversation, projection);
    final now = updatedAt ?? DateTime.now().toUtc();
    for (final key in _conversationOverlayKeys(
      normalized,
      projection,
      includeHandleAliasesForStrongIdentity: true,
    )) {
      await _localStore.setConversationHidden(
        ownerDid: ownerDid,
        conversationKey: key,
        hidden: true,
        updatedAt: now,
      );
    }
  }

  @override
  Future<void> restoreConversationToRecents({
    required String ownerDid,
    required ConversationSummary conversation,
    DateTime? updatedAt,
  }) async {
    final projection = await _loadAgentConversationProjection();
    final normalized = _conversationWithVisibilityKey(conversation, projection);
    final now = updatedAt ?? DateTime.now().toUtc();
    for (final key in _conversationOverlayKeys(
      normalized,
      projection,
      includeHandleAliasesForStrongIdentity: true,
    )) {
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

  ConversationSummary _conversationWithVisibilityKey(
    ConversationSummary conversation,
    _AgentConversationProjection projection,
  ) {
    return conversation.copyWith(
      conversationKey: _conversationIdentity(
        conversation,
        projection,
      ).primaryKey,
    );
  }

  Future<Map<String, ProductConversationOverlay>>
  _loadOverlaysForConversations({
    required String ownerDid,
    required Iterable<ConversationSummary> conversations,
    required _AgentConversationProjection projection,
    required String label,
  }) {
    return _loadOverlaysForKeys(
      ownerDid: ownerDid,
      keys: _overlayKeysForConversations(
        conversations,
        projection,
        includeHandleAliasesForStrongIdentity: true,
      ),
      label: label,
    );
  }

  Future<Map<String, ProductConversationOverlay>> _loadOverlaysForKeys({
    required String ownerDid,
    required Iterable<String> keys,
    required String label,
  }) {
    final overlayKeys = keys.toList(growable: false);
    return AwikiPerformanceLogger.async(
      label,
      () => _localStore.loadConversationOverlays(
        ownerDid: ownerDid,
        threadIds: overlayKeys,
      ),
      fields: <String, Object?>{'keys': overlayKeys.length},
      level: AwikiPerformanceLogLevel.verbose,
    );
  }
}

Iterable<String> _overlayKeysForConversations(
  Iterable<ConversationSummary> conversations,
  _AgentConversationProjection projection, {
  bool includeHandleAliasesForStrongIdentity = false,
}) {
  final keys = <String>{};
  for (final conversation in conversations) {
    keys.addAll(
      _conversationOverlayKeys(
        conversation,
        projection,
        includeHandleAliasesForStrongIdentity:
            includeHandleAliasesForStrongIdentity,
      ),
    );
  }
  return keys;
}

bool _isConversationHidden(
  ConversationSummary conversation,
  Map<String, ProductConversationOverlay> overlays,
  _AgentConversationProjection projection,
) {
  final overlay = _latestOverlayForConversation(
    conversation,
    overlays,
    projection,
  );
  if (overlay == null || !overlay.hidden) {
    return false;
  }
  return !conversation.lastMessageAt.isAfter(overlay.updatedAt);
}

ProductConversationOverlay? _preferredOverlayForConversation(
  ConversationSummary conversation,
  Map<String, ProductConversationOverlay> overlays,
  _AgentConversationProjection projection,
) {
  for (final key in _conversationOverlayKeys(conversation, projection)) {
    final overlay = overlays[key];
    if (overlay != null) {
      return overlay;
    }
  }
  return null;
}

ProductConversationOverlay? _latestOverlayForConversation(
  ConversationSummary conversation,
  Map<String, ProductConversationOverlay> overlays,
  _AgentConversationProjection projection,
) {
  ProductConversationOverlay? latest;
  for (final key in _conversationOverlayKeys(conversation, projection)) {
    final overlay = overlays[key];
    if (overlay == null) {
      continue;
    }
    if (latest == null || overlay.updatedAt.isAfter(latest.updatedAt)) {
      latest = overlay;
    }
  }
  return latest;
}

void _sortConversationsForDisplay(
  List<ConversationSummary> conversations, {
  required Map<String, ProductConversationOverlay> overlays,
  required _AgentConversationProjection projection,
}) {
  conversations.sort((a, b) {
    final aPinned =
        _preferredOverlayForConversation(a, overlays, projection)?.pinned ==
        true;
    final bPinned =
        _preferredOverlayForConversation(b, overlays, projection)?.pinned ==
        true;
    if (aPinned != bPinned) {
      return aPinned ? -1 : 1;
    }
    return b.lastMessageAt.compareTo(a.lastMessageAt);
  });
}

List<String> _conversationOverlayKeys(
  ConversationSummary conversation,
  _AgentConversationProjection projection, {
  bool includeHandleAliasesForStrongIdentity = false,
}) {
  return _conversationIdentity(
    conversation,
    projection,
    includeHandleAliasesForStrongIdentity:
        includeHandleAliasesForStrongIdentity,
  ).keys;
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
            conversationKey: _conversationIdentity(item, projection).primaryKey,
          ),
        )
        .toList(growable: false);
  }
  final byKey = <String, ConversationSummary>{};
  for (final item in items) {
    final key = _conversationIdentity(item, projection).primaryKey;
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

ConversationVisibilityIdentity _conversationIdentity(
  ConversationSummary item,
  _AgentConversationProjection projection, {
  bool includeHandleAliasesForStrongIdentity = false,
}) {
  final agent = _agentForConversation(item, projection);
  return conversationVisibilityIdentity(
    item,
    runtimeAgentDid: agent?.isRuntime == true ? agent?.agentDid : null,
    includeHandleAliasesForStrongIdentity:
        includeHandleAliasesForStrongIdentity,
  );
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
  return normalizedDirectPeer(value);
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
