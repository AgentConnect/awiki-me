import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/entities/agent/agent_display_name.dart';
import '../domain/entities/agent/agent_summary.dart';
import '../domain/entities/conversation_summary.dart';
import '../core/performance_logger.dart';
import 'agent/agent_control_projection.dart';
import 'models/app_conversation_read_ref.dart';
import 'models/app_thread_ref.dart';
import 'models/app_thread_read_watermark.dart';
import 'models/conversation_patch.dart';
import 'models/product_local_models.dart';
import 'ports/agent_inventory_port.dart';
import 'ports/conversation_core_port.dart';
import 'product_local_store.dart';

const bool _conversationServiceTraceEnabled = bool.fromEnvironment(
  'AWIKI_CONVERSATION_SERVICE_TRACE',
  defaultValue: false,
);

abstract interface class ConversationService {
  Future<List<ConversationSummary>> loadConversationSnapshot({
    required String ownerDid,
  });

  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  });

  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  });

  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  });

  Future<ConversationPage> listConversationSummariesFastPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
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

  Future<ConversationPage> listConversationsPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  });

  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  });

  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  });

  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  });

  /// Legacy adapter boundary for pre-canonical callers.
  ///
  /// Product UI must hide by [ConversationSummary.conversationId] through
  /// [hideConversationFromRecents].
  @Deprecated('Use hideConversationFromRecents with a canonical conversation')
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

  Future<void> ensureConversationInRecents({
    required String ownerDid,
    required String conversationId,
    DateTime? updatedAt,
  });
}

abstract interface class ConversationReadService {
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  });
}

class ImCoreConversationService
    implements ConversationService, ConversationReadService {
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
      () => _mergeAgentConversationDuplicates(
        items,
        projection,
        ownerDid: ownerDid,
      ),
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
                ownerDid: ownerDid,
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
  Stream<ConversationListPatch> watchConversationPatches({
    required String ownerDid,
  }) async* {
    await for (final patch in _conversations.watchConversationPatches()) {
      if (patch.ownerDid != ownerDid) {
        continue;
      }
      switch (patch.kind) {
        case CoreConversationPatchKind.reset:
          yield await _normalizePatchReset(ownerDid: ownerDid, patch: patch);
        case CoreConversationPatchKind.upsert:
          final item = patch.item;
          if (item == null) {
            yield _repairPatch(
              ownerDid: ownerDid,
              version: patch.version,
              unreadTotal: patch.unreadTotal,
              reason: 'missing_upsert_item',
            );
            continue;
          }
          final normalized = await normalizeConversationForRecents(
            ownerDid: ownerDid,
            conversation: item,
          );
          if (normalized == null) {
            yield ConversationListPatch(
              kind: ConversationListPatchKind.remove,
              ownerDid: ownerDid,
              version: patch.version,
              unreadTotal: patch.unreadTotal,
              threadId: item.threadId,
              conversationId: item.conversationId,
              conversationKey: item.conversationKey,
            );
            continue;
          }
          yield ConversationListPatch(
            kind: ConversationListPatchKind.upsert,
            ownerDid: ownerDid,
            version: patch.version,
            unreadTotal: patch.unreadTotal,
            item: normalized,
            conversationId: normalized.conversationId,
          );
        case CoreConversationPatchKind.remove:
          yield ConversationListPatch(
            kind: ConversationListPatchKind.remove,
            ownerDid: ownerDid,
            version: patch.version,
            unreadTotal: patch.unreadTotal,
            threadId: patch.threadId,
            conversationId: patch.conversationId,
          );
        case CoreConversationPatchKind.reorder:
          yield ConversationListPatch(
            kind: ConversationListPatchKind.reorder,
            ownerDid: ownerDid,
            version: patch.version,
            unreadTotal: patch.unreadTotal,
            threadId: patch.threadId,
            conversationId: patch.conversationId,
            index: patch.index,
          );
        case CoreConversationPatchKind.repairRequired:
          yield _repairPatch(
            ownerDid: ownerDid,
            version: patch.version,
            unreadTotal: patch.unreadTotal,
            reason: patch.reason ?? 'repair_required',
          );
      }
    }
  }

  Future<ConversationListPatch> _normalizePatchReset({
    required String ownerDid,
    required CoreConversationPatch patch,
  }) async {
    final visible = await enrichConversationSummaries(
      ownerDid: ownerDid,
      conversations: patch.items,
    );
    return ConversationListPatch(
      kind: ConversationListPatchKind.reset,
      ownerDid: ownerDid,
      version: patch.version,
      unreadTotal: patch.unreadTotal,
      items: visible,
    );
  }

  ConversationListPatch _repairPatch({
    required String ownerDid,
    required int version,
    required int unreadTotal,
    required String reason,
  }) {
    return ConversationListPatch(
      kind: ConversationListPatchKind.repairRequired,
      ownerDid: ownerDid,
      version: version,
      unreadTotal: unreadTotal,
      reason: reason,
    );
  }

  @override
  Future<ConversationStoreRepairResult> repairConversationStore({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    final patch = await AwikiPerformanceLogger.async(
      'conversation_service.repair_store.core',
      _conversations.repairConversationStore,
      fields: <String, Object?>{'limit': limit, 'unread_only': unreadOnly},
      level: AwikiPerformanceLogLevel.verbose,
    );
    final conversations = await listConversations(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    );
    return ConversationStoreRepairResult(
      conversations: conversations,
      version: patch.version,
    );
  }

  @override
  Future<List<ConversationSummary>> listConversationSummariesFast({
    required String ownerDid,
    int limit = 100,
    bool unreadOnly = false,
  }) async {
    return (await listConversationSummariesFastPage(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    )).items;
  }

  @override
  Future<ConversationPage> listConversationSummariesFastPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    final page = await AwikiPerformanceLogger.async(
      'conversation_service.fast_local.core_list',
      () => _conversations.listConversationPage(
        limit: limit,
        cursor: cursor,
        unreadOnly: unreadOnly,
      ),
      fields: <String, Object?>{
        'limit': limit,
        'cursor': cursor != null,
        'unread_only': unreadOnly,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    final items = page.items;
    final projection =
        _cachedAgentProjection ?? const _AgentConversationProjection();
    final mergedItems = AwikiPerformanceLogger.sync(
      'conversation_service.fast_local.merge_cached_agents',
      () => _mergeAgentConversationDuplicates(
        items,
        projection,
        ownerDid: ownerDid,
      ),
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
      label: 'conversation_service.fast_local.overlays',
    );
    final visible = AwikiPerformanceLogger.sync(
      'conversation_service.fast_local.filter_sort',
      () {
        final result = mergedItems
            .where(
              (item) => shouldShowConversationForChatList(
                item,
                ownerDid: ownerDid,
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
        'merged': mergedItems.length,
        'overlays': overlays.length,
        'cache_hit': _cachedAgentProjection != null,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    AwikiPerformanceLogger.log(
      'conversation_service.fast_local',
      fields: <String, Object?>{
        'items': items.length,
        'visible': visible.length,
        'has_more': page.hasMore,
        'agent_projection_cache_hit': _cachedAgentProjection != null,
      },
    );
    return ConversationPage(
      items: visible,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
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
      () => _mergeAgentConversationDuplicates(
        conversations,
        agentProjection,
        ownerDid: ownerDid,
      ),
      fields: <String, Object?>{
        'items': conversations.length,
        'agents': agentProjection.agentCount,
        'runtime_agents': agentProjection.runtimeAgents.length,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    final overlays = await _loadOverlaysForConversations(
      ownerDid: ownerDid,
      conversations: mergedItems,
      projection: agentProjection,
      label: 'conversation_service.overlays',
    );
    final visible = AwikiPerformanceLogger.sync(
      'conversation_service.filter_sort',
      () {
        final result = mergedItems
            .where(
              (item) => shouldShowConversationForChatList(
                item,
                ownerDid: ownerDid,
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
    return (await listConversationsPage(
      ownerDid: ownerDid,
      limit: limit,
      unreadOnly: unreadOnly,
    )).items;
  }

  @override
  Future<ConversationPage> listConversationsPage({
    required String ownerDid,
    int limit = 100,
    String? cursor,
    bool unreadOnly = false,
  }) async {
    final totalWatch = Stopwatch()..start();
    final base = await listConversationSummariesFastPage(
      ownerDid: ownerDid,
      limit: limit,
      cursor: cursor,
      unreadOnly: unreadOnly,
    );
    final visible = await enrichConversationSummaries(
      ownerDid: ownerDid,
      conversations: base.items,
    );
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_service.list',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        'items': base.items.length,
        'visible': visible.length,
        'has_more': base.hasMore,
      },
    );
    return ConversationPage(
      items: visible,
      nextCursor: base.nextCursor,
      hasMore: base.hasMore,
    );
  }

  @override
  Future<ConversationSummary?> normalizeConversationForRecents({
    required String ownerDid,
    required ConversationSummary conversation,
  }) async {
    final projection = await _loadAgentConversationProjection();
    final merged = _mergeAgentConversationDuplicates(
      <ConversationSummary>[conversation],
      projection,
      ownerDid: ownerDid,
    );
    if (merged.isEmpty) {
      return null;
    }
    final normalized = merged.single;
    if (!shouldShowConversationForChatList(
      normalized,
      ownerDid: ownerDid,
      daemonAgentDids: projection.daemonAgentDids,
    )) {
      return null;
    }
    final overlays = await _loadOverlaysForConversations(
      ownerDid: ownerDid,
      conversations: <ConversationSummary>[normalized],
      projection: projection,
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
  Future<void> markThreadRead(
    AppThreadRef thread, {
    AppThreadReadWatermark? watermark,
  }) {
    _conversationServiceTrace(
      'mark_read.delegate',
      fields: <String, Object?>{
        'thread_ref': _appThreadRefTrace(thread),
        'has_watermark': watermark?.isEmpty == false,
        'watermark_seq': watermark?.lastReadThreadSeq,
        'watermark_message_hash': AwikiPerformanceLogger.safeHash(
          watermark?.lastReadMessageId,
        ),
      },
    );
    return _conversations.markThreadRead(thread, watermark: watermark);
  }

  @override
  Future<void> markConversationRead(
    AppConversationReadRef conversation, {
    AppThreadReadWatermark? watermark,
  }) {
    final conversations = _conversations;
    if (conversations is! ConversationReadCorePort) {
      throw UnsupportedError(
        'Conversation core does not expose conversation-id read state.',
      );
    }
    _conversationServiceTrace(
      'mark_conversation_read',
      fields: <String, Object?>{
        'conversation_hash': AwikiPerformanceLogger.safeHash(
          conversation.conversationId,
        ),
        'has_watermark': watermark?.isEmpty == false,
        'watermark_seq': watermark?.lastReadThreadSeq,
        'watermark_message_hash': AwikiPerformanceLogger.safeHash(
          watermark?.lastReadMessageId,
        ),
      },
    );
    return (conversations as ConversationReadCorePort).markConversationRead(
      conversation,
      watermark: watermark,
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
    await _setConversationHiddenByCanonicalId(
      ownerDid: ownerDid,
      conversation: normalized,
      projection: projection,
      hidden: true,
      updatedAt: now,
    );
  }

  @override
  Future<void> ensureConversationInRecents({
    required String ownerDid,
    required String conversationId,
    DateTime? updatedAt,
  }) async {
    final canonicalId = conversationId.trim();
    if (canonicalId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'must not be empty',
      );
    }
    final now = updatedAt ?? DateTime.now().toUtc();
    await _conversations.ensureConversation(canonicalId);
    await _localStore.setConversationHiddenByConversationId(
      ownerDid: ownerDid,
      conversationId: canonicalId,
      hidden: false,
      updatedAt: now,
    );
  }

  Future<void> _setConversationHiddenByCanonicalId({
    required String ownerDid,
    required ConversationSummary conversation,
    required _AgentConversationProjection projection,
    required bool hidden,
    required DateTime updatedAt,
  }) async {
    final conversationId = _canonicalOverlayKey(conversation);
    final overlays = await _loadOverlaysForConversations(
      ownerDid: ownerDid,
      conversations: <ConversationSummary>[conversation],
      projection: projection,
      label: 'conversation_service.hidden.overlays',
    );
    final existing = _preferredOverlayForConversation(
      conversation,
      overlays,
      projection,
    );
    await _localStore.upsertConversationOverlayByConversationId(
      (existing ??
              ProductConversationOverlay(
                ownerDid: ownerDid,
                threadId: conversationId,
                conversationId: conversationId,
                updatedAt: updatedAt,
              ))
          .copyWith(
            threadId: conversationId,
            conversationId: conversationId,
            hidden: hidden,
            updatedAt: updatedAt,
          ),
    );
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
    return conversation;
  }

  Future<Map<String, ProductConversationOverlay>>
  _loadOverlaysForConversations({
    required String ownerDid,
    required Iterable<ConversationSummary> conversations,
    required _AgentConversationProjection projection,
    required String label,
  }) async {
    final items = conversations.toList(growable: false);
    final canonicalKeys = items
        .map(_canonicalOverlayKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    return AwikiPerformanceLogger.async(
      '$label.canonical',
      () => _localStore.loadConversationOverlaysByConversationId(
        ownerDid: ownerDid,
        conversationIds: canonicalKeys,
      ),
      fields: <String, Object?>{'keys': canonicalKeys.length},
      level: AwikiPerformanceLogLevel.verbose,
    );
  }
}

bool _isConversationHidden(
  ConversationSummary conversation,
  Map<String, ProductConversationOverlay> overlays,
  _AgentConversationProjection projection,
) {
  final overlay = _canonicalOverlayForConversation(conversation, overlays);
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
  return _canonicalOverlayForConversation(conversation, overlays);
}

ProductConversationOverlay? _canonicalOverlayForConversation(
  ConversationSummary conversation,
  Map<String, ProductConversationOverlay> overlays,
) {
  return overlays[_canonicalOverlayKey(conversation)];
}

String _canonicalOverlayKey(ConversationSummary conversation) {
  return conversation.conversationId.trim();
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

List<ConversationSummary> _mergeAgentConversationDuplicates(
  List<ConversationSummary> items,
  _AgentConversationProjection projection, {
  required String ownerDid,
}) {
  final byKey = <String, ConversationSummary>{};
  for (final item in items) {
    final key = item.conversationId;
    final existing = byKey[key];
    if (existing == null ||
        item.lastMessageAt.isAfter(existing.lastMessageAt)) {
      byKey[key] = item;
    }
  }
  return byKey.values.toList(growable: false);
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
    peerLocalNote: item.isGroup ? null : overlay.customTitle,
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
  final normalized = _trimLeadingAt(value?.trim()).toLowerCase();
  return normalized.isEmpty ? null : normalized;
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

void _conversationServiceTrace(
  String event, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  if (!_conversationServiceTraceEnabled) {
    return;
  }
  final details = <String>[];
  for (final entry in fields.entries) {
    final value = entry.value;
    if (value != null) {
      details.add('${entry.key}=${_collapseConversationServiceTrace(value)}');
    }
  }
  debugPrint(
    details.isEmpty
        ? '[awiki_me][conversation_service_trace] event=$event'
        : '[awiki_me][conversation_service_trace] event=$event ${details.join(' ')}',
  );
}

String _appThreadRefTrace(AppThreadRef ref) {
  final kind = switch (ref) {
    AppDirectThreadRef() => 'direct',
    AppGroupThreadRef() => 'group',
    AppMessageThreadRef() => 'thread',
  };
  return '$kind:${AwikiPerformanceLogger.safeHash(ref.stableId)}';
}

String _collapseConversationServiceTrace(Object value) {
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  final raw = value.toString();
  final buffer = StringBuffer();
  var lastWasWhitespace = false;
  for (final rune in raw.runes) {
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      if (!lastWasWhitespace) {
        buffer.write('_');
      }
      lastWasWhitespace = true;
    } else {
      buffer.write(char);
      lastWasWhitespace = false;
    }
  }
  return buffer.toString();
}
