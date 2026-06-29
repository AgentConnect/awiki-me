import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/conversation_service.dart';
import '../../application/models/conversation_patch.dart';
import '../../core/group_display_name.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/agent/agent_display_name.dart';
import '../../domain/entities/conversation_identity.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/services/notification_facade.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../app_shell/providers/session_provider.dart';

const bool _conversationTraceEnabled = bool.fromEnvironment(
  'AWIKI_CONVERSATION_TRACE',
  defaultValue: false,
);

class ConversationListState {
  const ConversationListState({
    this.conversations = const <ConversationSummary>[],
    this.isLoading = false,
  });

  final List<ConversationSummary> conversations;
  final bool isLoading;

  int get unreadCount =>
      conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);

  ConversationListState copyWith({
    List<ConversationSummary>? conversations,
    bool? isLoading,
  }) {
    return ConversationListState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ConversationListController extends StateNotifier<ConversationListState> {
  ConversationListController(
    this.ref, {
    this.refreshTimeout = _defaultRefreshTimeout,
  }) : super(const ConversationListState());

  static const Duration _defaultRefreshTimeout = Duration(seconds: 12);

  final Ref ref;
  final Duration refreshTimeout;
  Future<void>? _refreshOperation;
  bool _refreshOperationFastLocal = false;
  bool _snapshotBootstrapActive = false;
  int? _snapshotBootstrapAllowedGeneration;
  int _refreshGeneration = 0;
  StreamSubscription<ConversationListPatch>? _patchSubscription;
  String? _patchSubscriptionOwnerDid;
  int _patchSubscriptionToken = 0;
  int _lastPatchVersion = 0;
  Future<void>? _patchRepairOperation;
  final Map<String, DateTime> _locallyHiddenConversationKeys =
      <String, DateTime>{};

  NotificationFacade get _notification => ref.read(notificationFacadeProvider);

  Future<void> ensureLoaded() {
    if (state.conversations.isNotEmpty) {
      return Future<void>.value();
    }
    return refreshFastLocal().catchError((_) {});
  }

  Future<void> refresh() {
    final active = _refreshOperation;
    final reused = active != null && !_refreshOperationFastLocal;
    final activeRefresh = reused ? active : _startRefresh(fastLocal: false);
    AwikiPerformanceLogger.log(
      'conversation_list.refresh.request',
      fields: <String, Object?>{
        'reused': reused,
        'current': state.conversations.length,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    if (!state.isLoading) {
      state = state.copyWith(isLoading: true);
    }
    _ensurePatchSubscriptionForCurrentSession();
    return _waitForRefresh(activeRefresh);
  }

  Future<void> refreshFastLocal() {
    final reused = _refreshOperation != null;
    final activeRefresh = _refreshOperation ?? _startRefresh(fastLocal: true);
    if (!reused && state.conversations.isEmpty) {
      final session = ref.read(sessionProvider).session;
      if (session != null) {
        _snapshotBootstrapAllowedGeneration = _refreshGeneration;
        unawaited(
          _bootstrapFromSnapshot(
            generation: _refreshGeneration,
            ownerDid: session.did,
          ).catchError((_) {}),
        );
      }
    }
    AwikiPerformanceLogger.log(
      'conversation_list.refresh_fast_local.request',
      fields: <String, Object?>{
        'reused': reused,
        'current': state.conversations.length,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
    if (!state.isLoading) {
      state = state.copyWith(isLoading: true);
    }
    _ensurePatchSubscriptionForCurrentSession();
    return _waitForRefresh(activeRefresh);
  }

  Future<void> _waitForRefresh(Future<void> operation) async {
    try {
      await operation.timeout(refreshTimeout);
    } on TimeoutException {
      if (identical(_refreshOperation, operation)) {
        _refreshOperation = null;
        _refreshOperationFastLocal = false;
        state = state.copyWith(isLoading: false);
      }
      rethrow;
    }
  }

  Future<void> _startRefresh({required bool fastLocal}) {
    final generation = ++_refreshGeneration;
    late final Future<void> operation;
    operation = _refresh(generation, fastLocal: fastLocal).whenComplete(() {
      if (identical(_refreshOperation, operation)) {
        _refreshOperation = null;
        _refreshOperationFastLocal = false;
      }
    });
    _refreshOperation = operation;
    _refreshOperationFastLocal = fastLocal;
    return operation;
  }

  Future<void> _refresh(int generation, {required bool fastLocal}) async {
    final totalWatch = Stopwatch()..start();
    state = state.copyWith(isLoading: true);
    try {
      final session = ref.read(sessionProvider).session;
      if (session == null) {
        await _cancelPatchSubscription();
        if (generation != _refreshGeneration) {
          return;
        }
        state = state.copyWith(
          conversations: const <ConversationSummary>[],
          isLoading: false,
        );
        await _updateBadgeCountBestEffort(0, source: 'refresh.no_session');
        return;
      }
      _ensurePatchSubscription(ownerDid: session.did, generation: generation);
      final conversationService = ref.read(conversationServiceProvider);
      if (!fastLocal) {
        final conversations = await AwikiPerformanceLogger.async(
          'conversation_list.refresh.service',
          () => conversationService.listConversations(ownerDid: session.did),
        );
        if (generation != _refreshGeneration) {
          return;
        }
        await _applyConversationRefresh(
          conversations,
          generation: generation,
          label: 'conversation_list.refresh',
          keepLocalOnly: !_snapshotBootstrapActive,
          badgeSource: 'refresh',
        );
        totalWatch.stop();
        AwikiPerformanceLogger.log(
          'conversation_list.refresh',
          elapsed: totalWatch.elapsed,
          fields: <String, Object?>{
            'items': state.conversations.length,
            'unread': state.unreadCount,
          },
        );
        return;
      }
      final conversations = await AwikiPerformanceLogger.async(
        'conversation_list.refresh_fast_local.service',
        () => conversationService.listConversationSummariesFast(
          ownerDid: session.did,
        ),
        level: AwikiPerformanceLogLevel.verbose,
      );
      if (generation != _refreshGeneration) {
        return;
      }
      await _applyConversationRefresh(
        conversations,
        generation: generation,
        label: 'conversation_list.refresh_fast_local',
        keepLocalOnly: !_snapshotBootstrapActive,
        badgeSource: 'refresh_fast_local',
      );
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'conversation_list.refresh_fast_local',
        elapsed: totalWatch.elapsed,
        fields: <String, Object?>{
          'items': state.conversations.length,
          'unread': state.unreadCount,
        },
      );
      unawaited(
        _enrichRefresh(
          generation: generation,
          ownerDid: session.did,
          base: conversations,
          conversationService: conversationService,
        ).catchError((_) {}),
      );
    } catch (_) {
      if (generation == _refreshGeneration) {
        state = state.copyWith(isLoading: false);
      }
      rethrow;
    }
  }

  Future<void> _enrichRefresh({
    required int generation,
    required String ownerDid,
    required List<ConversationSummary> base,
    required ConversationService conversationService,
  }) async {
    final totalWatch = Stopwatch()..start();
    final enriched = await AwikiPerformanceLogger.async(
      'conversation_list.refresh_enrich.service',
      () => conversationService.enrichConversationSummaries(
        ownerDid: ownerDid,
        conversations: base,
      ),
      fields: <String, Object?>{'base': base.length},
      level: AwikiPerformanceLogLevel.verbose,
    );
    if (generation != _refreshGeneration) {
      return;
    }
    await _applyConversationRefresh(
      enriched,
      generation: generation,
      label: 'conversation_list.refresh_enrich',
      badgeSource: 'refresh_enrich',
    );
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_list.refresh_enrich',
      elapsed: totalWatch.elapsed,
      fields: <String, Object?>{
        'items': state.conversations.length,
        'unread': state.unreadCount,
      },
    );
  }

  Future<void> _bootstrapFromSnapshot({
    required int generation,
    required String ownerDid,
  }) async {
    if (!_canApplySnapshotBootstrap(
      generation: generation,
      ownerDid: ownerDid,
    )) {
      return;
    }
    final conversations = await AwikiPerformanceLogger.async(
      'conversation_list.snapshot.service',
      () => ref
          .read(conversationServiceProvider)
          .loadConversationSnapshot(ownerDid: ownerDid),
      level: AwikiPerformanceLogLevel.verbose,
    );
    if (!_canApplySnapshotBootstrap(
          generation: generation,
          ownerDid: ownerDid,
        ) ||
        conversations.isEmpty ||
        state.conversations.isNotEmpty) {
      return;
    }
    state = state.copyWith(
      conversations: _filterLocallyHiddenConversations(conversations),
      isLoading: true,
    );
    _snapshotBootstrapActive = true;
    await _updateBadgeCountBestEffort(state.unreadCount, source: 'snapshot');
    AwikiPerformanceLogger.log(
      'conversation_list.snapshot',
      fields: <String, Object?>{
        'items': state.conversations.length,
        'unread': state.unreadCount,
      },
      level: AwikiPerformanceLogLevel.verbose,
    );
  }

  void _ensurePatchSubscriptionForCurrentSession() {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      unawaited(_cancelPatchSubscription());
      return;
    }
    _ensurePatchSubscription(
      ownerDid: session.did,
      generation: _refreshGeneration,
    );
  }

  void _ensurePatchSubscription({
    required String ownerDid,
    required int generation,
  }) {
    if (_patchSubscriptionOwnerDid == ownerDid && _patchSubscription != null) {
      return;
    }
    unawaited(_cancelPatchSubscription());
    _patchSubscriptionOwnerDid = ownerDid;
    final token = ++_patchSubscriptionToken;
    _lastPatchVersion = 0;
    _patchSubscription = ref
        .read(conversationServiceProvider)
        .watchConversationPatches(ownerDid: ownerDid)
        .listen(
          (patch) =>
              _handleConversationPatch(patch, ownerDid: ownerDid, token: token),
          onError: (_) => _schedulePatchRepair(
            ownerDid: ownerDid,
            generation: generation,
            token: token,
            reason: 'stream_error',
          ),
          onDone: () => _schedulePatchRepair(
            ownerDid: ownerDid,
            generation: generation,
            token: token,
            reason: 'stream_closed',
          ),
        );
  }

  Future<void> _cancelPatchSubscription() async {
    final subscription = _patchSubscription;
    _patchSubscription = null;
    _patchSubscriptionOwnerDid = null;
    _patchSubscriptionToken += 1;
    _lastPatchVersion = 0;
    await subscription?.cancel();
  }

  void _handleConversationPatch(
    ConversationListPatch patch, {
    required String ownerDid,
    required int token,
  }) {
    _trace(
      'patch.received',
      fields: <String, Object?>{
        'kind': patch.kind.name,
        'version': patch.version,
        'last_version': _lastPatchVersion,
        'unread_total': patch.unreadTotal,
        'thread_hash': _safeHash(patch.threadId),
        'reason': patch.reason,
      },
    );
    if (!_canApplyPatch(patch, ownerDid: ownerDid, token: token)) {
      _trace(
        'patch.ignored',
        fields: <String, Object?>{
          'reason': 'stale_or_owner_mismatch',
          'kind': patch.kind.name,
          'version': patch.version,
        },
      );
      return;
    }
    if (patch.version <= _lastPatchVersion) {
      _trace(
        'patch.ignored',
        fields: <String, Object?>{
          'reason': 'duplicate_or_old',
          'kind': patch.kind.name,
          'version': patch.version,
          'last_version': _lastPatchVersion,
        },
      );
      return;
    }
    if (_lastPatchVersion != 0 && patch.version != _lastPatchVersion + 1) {
      _trace(
        'patch.repair_scheduled',
        fields: <String, Object?>{
          'reason': 'version_gap',
          'version': patch.version,
          'last_version': _lastPatchVersion,
        },
      );
      _schedulePatchRepair(
        ownerDid: ownerDid,
        generation: _refreshGeneration,
        token: token,
        reason: 'version_gap',
      );
      _lastPatchVersion = patch.version;
      return;
    }
    _lastPatchVersion = patch.version;
    switch (patch.kind) {
      case ConversationListPatchKind.reset:
        _applyPatchReset(patch);
      case ConversationListPatchKind.upsert:
        final item = patch.item;
        if (item == null) {
          _schedulePatchRepair(
            ownerDid: ownerDid,
            generation: _refreshGeneration,
            token: token,
            reason: 'missing_upsert_item',
          );
          return;
        }
        _applyPatchUpsert(item);
      case ConversationListPatchKind.remove:
        _applyPatchRemove(patch);
      case ConversationListPatchKind.reorder:
        if (!_applyPatchReorder(patch)) {
          _schedulePatchRepair(
            ownerDid: ownerDid,
            generation: _refreshGeneration,
            token: token,
            reason: 'missing_reorder_item',
          );
        }
      case ConversationListPatchKind.repairRequired:
        _schedulePatchRepair(
          ownerDid: ownerDid,
          generation: _refreshGeneration,
          token: token,
          reason: patch.reason ?? 'repair_required',
        );
    }
  }

  bool _canApplyPatch(
    ConversationListPatch patch, {
    required String ownerDid,
    required int token,
  }) {
    return token == _patchSubscriptionToken &&
        patch.ownerDid == ownerDid &&
        _patchSubscriptionOwnerDid == ownerDid &&
        ref.read(sessionProvider).session?.did == ownerDid;
  }

  void _applyPatchReset(ConversationListPatch patch) {
    final currentConversations = state.conversations;
    final nextConversations = _filterLocallyHiddenConversations(
      _mergeConversationRefresh(
        refreshed: patch.items,
        local: currentConversations,
        keepLocalOnly: false,
      ),
    );
    final beforeUnread = state.unreadCount;
    final beforeItems = state.conversations.length;
    final beforeLoading = state.isLoading;
    if (!beforeLoading &&
        _sameConversationSummaryList(currentConversations, nextConversations)) {
      _snapshotBootstrapActive = false;
      _trace(
        'state.patch_reset.noop',
        fields: <String, Object?>{
          'items': beforeItems,
          'unread': beforeUnread,
          'version': patch.version,
        },
      );
      return;
    }
    state = state.copyWith(conversations: nextConversations, isLoading: false);
    _snapshotBootstrapActive = false;
    _trace(
      'state.patch_reset',
      fields: <String, Object?>{
        'before_items': beforeItems,
        'after_items': state.conversations.length,
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'version': patch.version,
      },
    );
    unawaited(
      _updateBadgeCountBestEffort(state.unreadCount, source: 'patch_reset'),
    );
  }

  void _applyPatchUpsert(ConversationSummary conversation) {
    if (_isLocallyHidden(conversation)) {
      return;
    }
    _snapshotBootstrapActive = false;
    _upsertConversation(conversation, source: 'patch_upsert');
  }

  void _applyPatchRemove(ConversationListPatch patch) {
    final threadId = patch.threadId?.trim();
    final conversationKey = patch.conversationKey?.trim();
    final next = state.conversations
        .where((item) {
          if (threadId != null &&
              threadId.isNotEmpty &&
              item.threadId == threadId) {
            return false;
          }
          if (conversationKey != null &&
              conversationKey.isNotEmpty &&
              item.visibilityKeys.contains(conversationKey)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (next.length == state.conversations.length) {
      return;
    }
    final beforeUnread = state.unreadCount;
    state = state.copyWith(conversations: next);
    _snapshotBootstrapActive = false;
    _trace(
      'state.patch_remove',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'thread_hash': _safeHash(threadId),
        'conversation_key_hash': _safeHash(conversationKey),
      },
    );
    unawaited(
      _updateBadgeCountBestEffort(state.unreadCount, source: 'patch_remove'),
    );
  }

  bool _applyPatchReorder(ConversationListPatch patch) {
    final threadId = patch.threadId?.trim();
    if (threadId == null || threadId.isEmpty) {
      return false;
    }
    final current = state.conversations.toList(growable: true);
    final currentIndex = current.indexWhere(
      (item) => item.threadId == threadId,
    );
    if (currentIndex < 0) {
      return false;
    }
    final item = current.removeAt(currentIndex);
    final targetIndex = (patch.index ?? 0).clamp(0, current.length);
    current.insert(targetIndex, item);
    state = state.copyWith(conversations: current);
    _snapshotBootstrapActive = false;
    _trace(
      'state.patch_reorder',
      fields: <String, Object?>{
        'unread': state.unreadCount,
        'thread_hash': _safeHash(threadId),
        'from': currentIndex,
        'to': targetIndex,
      },
    );
    unawaited(
      _updateBadgeCountBestEffort(state.unreadCount, source: 'patch_reorder'),
    );
    return true;
  }

  void _schedulePatchRepair({
    required String ownerDid,
    required int generation,
    required int token,
    required String reason,
  }) {
    if (_patchRepairOperation != null) {
      return;
    }
    _patchRepairOperation =
        _repairFromPatchStream(
          ownerDid: ownerDid,
          generation: generation,
          token: token,
          reason: reason,
        ).whenComplete(() {
          _patchRepairOperation = null;
        });
  }

  Future<void> _repairFromPatchStream({
    required String ownerDid,
    required int generation,
    required int token,
    required String reason,
  }) async {
    _trace(
      'patch_repair.start',
      fields: <String, Object?>{
        'reason': reason,
        'generation': generation,
        'current_generation': _refreshGeneration,
      },
    );
    if (token != _patchSubscriptionToken ||
        generation != _refreshGeneration ||
        ref.read(sessionProvider).session?.did != ownerDid) {
      _trace(
        'patch_repair.skip',
        fields: <String, Object?>{
          'reason': 'stale_or_owner_mismatch',
          'requested_reason': reason,
        },
      );
      return;
    }
    final repair = await AwikiPerformanceLogger.async(
      'conversation_list.patch_repair.service',
      () => ref
          .read(conversationServiceProvider)
          .repairConversationStore(ownerDid: ownerDid),
      fields: <String, Object?>{'reason': reason},
      level: AwikiPerformanceLogLevel.verbose,
    );
    if (token != _patchSubscriptionToken ||
        generation != _refreshGeneration ||
        ref.read(sessionProvider).session?.did != ownerDid) {
      _trace(
        'patch_repair.skip',
        fields: <String, Object?>{
          'reason': 'stale_after_service',
          'requested_reason': reason,
        },
      );
      return;
    }
    if (repair.version > _lastPatchVersion) {
      _lastPatchVersion = repair.version;
    }
    await _applyConversationRefresh(
      repair.conversations,
      generation: generation,
      label: 'conversation_list.patch_repair',
      keepLocalOnly: false,
      badgeSource: 'patch_repair',
    );
  }

  bool _canApplySnapshotBootstrap({
    required int generation,
    required String ownerDid,
  }) {
    return generation == _refreshGeneration &&
        _snapshotBootstrapAllowedGeneration == generation &&
        _refreshOperation != null &&
        _refreshOperationFastLocal &&
        state.conversations.isEmpty &&
        ref.read(sessionProvider).session?.did == ownerDid;
  }

  Future<void> _applyConversationRefresh(
    List<ConversationSummary> refreshed, {
    required int generation,
    required String label,
    bool keepLocalOnly = true,
    String? badgeSource,
  }) async {
    if (generation != _refreshGeneration) {
      return;
    }
    _snapshotBootstrapAllowedGeneration = null;
    final currentConversations = state.conversations;
    final nextConversations = AwikiPerformanceLogger.sync(
      '$label.merge',
      () => _filterLocallyHiddenConversations(
        _mergeConversationRefresh(
          refreshed: refreshed,
          local: currentConversations,
          keepLocalOnly: keepLocalOnly,
        ),
      ),
      fields: <String, Object?>{
        'refreshed': refreshed.length,
        'local': currentConversations.length,
        'indexed': true,
      },
    );
    final beforeUnread = state.unreadCount;
    final beforeItems = state.conversations.length;
    final beforeLoading = state.isLoading;
    if (!beforeLoading &&
        _sameConversationSummaryList(currentConversations, nextConversations)) {
      _snapshotBootstrapActive = false;
      _trace(
        'state.refresh_noop',
        fields: <String, Object?>{
          'label': label,
          'items': beforeItems,
          'unread': beforeUnread,
          'generation': generation,
        },
      );
      return;
    }
    state = state.copyWith(conversations: nextConversations, isLoading: false);
    _snapshotBootstrapActive = false;
    _trace(
      'state.refresh_apply',
      fields: <String, Object?>{
        'label': label,
        'before_items': beforeItems,
        'after_items': state.conversations.length,
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'generation': generation,
      },
    );
    await _updateBadgeCountBestEffort(
      state.unreadCount,
      source: badgeSource ?? label,
    );
  }

  void upsertConversation(ConversationSummary conversation) {
    if (_isLocallyHidden(conversation)) {
      return;
    }
    _upsertConversation(
      conversation,
      preferLocalTitle: true,
      source: 'upsert_public',
    );
    unawaited(_normalizeAndUpsertConversation(conversation).catchError((_) {}));
  }

  Future<void> _normalizeAndUpsertConversation(
    ConversationSummary conversation,
  ) async {
    final normalized = await _normalizeConversationForRecents(conversation);
    if (normalized == null) {
      _removeConversationLocally(conversation);
      return;
    }
    if (_isLocallyHidden(normalized)) {
      return;
    }
    _upsertConversation(normalized, source: 'upsert_normalized');
  }

  void upsertConversationBestEffort(ConversationSummary conversation) {
    try {
      upsertConversation(conversation);
    } catch (_) {
      // Background realtime/navigation paths should not fail foreground UI.
    }
  }

  void _upsertConversation(
    ConversationSummary conversation, {
    bool preferLocalTitle = false,
    String source = 'upsert',
  }) {
    if (_isLocallyHidden(conversation)) {
      return;
    }
    final existing = _matchingConversationForUpsert(
      state.conversations,
      conversation,
    );
    final titledConversation = _mergeConversationTitle(
      refreshed: conversation,
      local: existing,
      preferLocalTitle: preferLocalTitle,
    );
    final mergedConversation = _mergeConversationLifecycle(
      refreshed: _mergeConversationReadState(
        refreshed: _mergeConversationLastMessage(
          refreshed: titledConversation,
          local: existing,
        ),
        local: existing,
      ),
      local: existing,
    );
    final byThread = <String, ConversationSummary>{
      for (final item in state.conversations)
        if (item.threadId != existing?.threadId) item.threadId: item,
    };
    byThread[mergedConversation.threadId] = mergedConversation;
    final merged = byThread.values.toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    final beforeUnread = state.unreadCount;
    final beforeItems = state.conversations.length;
    if (_sameConversationSummaryList(state.conversations, merged)) {
      _trace(
        'state.upsert_noop',
        fields: <String, Object?>{
          'source': source,
          'matched': existing != null,
          'items': beforeItems,
          'unread': beforeUnread,
          'incoming_unread': conversation.unreadCount,
          'merged_unread': mergedConversation.unreadCount,
          'thread_hash': _safeHash(mergedConversation.threadId),
          'preview_hash': _safeHash(mergedConversation.lastMessagePreview),
          'last_at': mergedConversation.lastMessageAt,
        },
      );
      return;
    }
    state = state.copyWith(conversations: merged);
    _trace(
      'state.upsert',
      fields: <String, Object?>{
        'source': source,
        'matched': existing != null,
        'before_items': beforeItems,
        'after_items': state.conversations.length,
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'incoming_unread': conversation.unreadCount,
        'merged_unread': mergedConversation.unreadCount,
        'thread_hash': _safeHash(mergedConversation.threadId),
        'preview_hash': _safeHash(mergedConversation.lastMessagePreview),
        'last_at': mergedConversation.lastMessageAt,
      },
    );
    unawaited(_updateBadgeCountBestEffort(state.unreadCount, source: source));
  }

  Future<void> restoreConversation(ConversationSummary conversation) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return;
    }
    _removeHiddenKeysFor(conversation);
    await ref
        .read(conversationServiceProvider)
        .restoreConversationToRecents(
          ownerDid: session.did,
          conversation: conversation,
        );
  }

  void restoreConversationBestEffort(ConversationSummary conversation) {
    _removeHiddenKeysFor(conversation);
    unawaited(restoreConversation(conversation).catchError((_) {}));
  }

  Future<void> deleteFromRecents(ConversationSummary conversation) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    final hiddenAt = DateTime.now().toUtc();
    _addHiddenKeysFor(conversation, hiddenAt: hiddenAt);
    _removeConversationLocally(conversation);
    try {
      await ref
          .read(conversationServiceProvider)
          .hideConversationFromRecents(
            ownerDid: session.did,
            conversation: conversation,
            updatedAt: hiddenAt,
          );
    } catch (_) {
      _removeHiddenKeysFor(conversation);
      _upsertConversation(
        conversation,
        preferLocalTitle: true,
        source: 'delete_rollback',
      );
      rethrow;
    }
    final selected = ref.read(selectedConversationProvider);
    if (selected != null && sameConversationTarget(selected, conversation)) {
      ref.read(selectedConversationProvider.notifier).clearSelection();
    }
    await _updateBadgeCountBestEffort(
      state.unreadCount,
      source: 'delete_from_recents',
    );
  }

  void applyGroupNames(List<GroupSummary> groups) {
    final groupsById = <String, GroupSummary>{
      for (final group in groups)
        if (!GroupDisplayName.isIdLike(group.displayName, group.groupId))
          group.groupId: group,
    };
    if (groupsById.isEmpty || state.conversations.isEmpty) {
      return;
    }

    var changed = false;
    final next = state.conversations.map((conversation) {
      final groupId = conversation.groupId?.trim() ?? '';
      final group = groupsById[groupId];
      final groupName = group?.displayName;
      final groupAvatarUri = group?.avatarUri;
      if (!conversation.isGroup ||
          groupName == null ||
          (groupName == conversation.displayName &&
              groupAvatarUri == conversation.avatarUri)) {
        return conversation;
      }
      changed = true;
      return conversation.copyWith(
        displayName: groupName,
        avatarUri: groupAvatarUri ?? conversation.avatarUri,
      );
    }).toList();
    if (!changed) {
      return;
    }
    state = state.copyWith(conversations: next);
  }

  void markThreadReadLocal(String threadId) {
    final currentConversations = state.conversations;
    final beforeUnread = state.unreadCount;
    final next = currentConversations.map((item) {
      if (item.threadId != threadId ||
          (item.unreadCount == 0 && item.unreadMentionCount == 0)) {
        return item;
      }
      return item.copyWith(
        unreadCount: 0,
        unreadMentionCount: 0,
        firstUnreadMentionMessageId: null,
      );
    }).toList();
    if (_sameConversationSummaryList(currentConversations, next)) {
      _trace(
        'state.mark_thread_read.noop',
        fields: <String, Object?>{
          'unread': beforeUnread,
          'thread_hash': _safeHash(threadId),
        },
      );
      return;
    }
    state = state.copyWith(conversations: next);
    _trace(
      'state.mark_thread_read',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'thread_hash': _safeHash(threadId),
      },
    );
    unawaited(
      _updateBadgeCountBestEffort(
        state.unreadCount,
        source: 'mark_thread_read_local',
      ),
    );
  }

  void markConversationReadLocal(ConversationSummary conversation) {
    final currentConversations = state.conversations;
    final beforeUnread = state.unreadCount;
    final next = currentConversations.map((item) {
      if ((item.unreadCount == 0 && item.unreadMentionCount == 0) ||
          !_sameConversationForList(item, conversation)) {
        return item;
      }
      return item.copyWith(
        unreadCount: 0,
        unreadMentionCount: 0,
        firstUnreadMentionMessageId: null,
      );
    }).toList();
    if (_sameConversationSummaryList(currentConversations, next)) {
      _trace(
        'state.mark_conversation_read.noop',
        fields: <String, Object?>{
          'unread': beforeUnread,
          'thread_hash': _safeHash(conversation.threadId),
        },
      );
      return;
    }
    state = state.copyWith(conversations: next);
    _trace(
      'state.mark_conversation_read',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'thread_hash': _safeHash(conversation.threadId),
      },
    );
    unawaited(
      _updateBadgeCountBestEffort(
        state.unreadCount,
        source: 'mark_conversation_read_local',
      ),
    );
  }

  Future<void> clear() async {
    _refreshGeneration += 1;
    _refreshOperation = null;
    _refreshOperationFastLocal = false;
    _snapshotBootstrapActive = false;
    _snapshotBootstrapAllowedGeneration = null;
    await _cancelPatchSubscription();
    _locallyHiddenConversationKeys.clear();
    state = const ConversationListState();
    await _updateBadgeCountBestEffort(0, source: 'clear');
  }

  @override
  void dispose() {
    unawaited(_cancelPatchSubscription());
    super.dispose();
  }

  Future<ConversationSummary?> _normalizeConversationForRecents(
    ConversationSummary conversation,
  ) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return conversation;
    }
    return ref
        .read(conversationServiceProvider)
        .normalizeConversationForRecents(
          ownerDid: session.did,
          conversation: conversation,
        );
  }

  void _addHiddenKeysFor(
    ConversationSummary conversation, {
    required DateTime hiddenAt,
  }) {
    for (final key in _visibilityKeysFor(
      conversation,
      includeHandleAliasesForStrongIdentity: true,
    )) {
      _locallyHiddenConversationKeys[key] = hiddenAt;
    }
  }

  void _removeHiddenKeysFor(ConversationSummary conversation) {
    for (final key in _visibilityKeysFor(
      conversation,
      includeHandleAliasesForStrongIdentity: true,
    )) {
      _locallyHiddenConversationKeys.remove(key);
    }
  }

  bool _isLocallyHidden(ConversationSummary conversation) {
    final hiddenAt = _latestLocalHiddenAt(conversation);
    return hiddenAt != null && !conversation.lastMessageAt.isAfter(hiddenAt);
  }

  void _removeConversationLocally(ConversationSummary conversation) {
    final next = state.conversations
        .where((item) => !_sameConversationForList(item, conversation))
        .toList(growable: false);
    final beforeUnread = state.unreadCount;
    state = state.copyWith(conversations: next);
    _trace(
      'state.remove_local',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'thread_hash': _safeHash(conversation.threadId),
      },
    );
    unawaited(
      _updateBadgeCountBestEffort(state.unreadCount, source: 'remove_local'),
    );
  }

  List<ConversationSummary> _filterLocallyHiddenConversations(
    List<ConversationSummary> conversations,
  ) {
    if (_locallyHiddenConversationKeys.isEmpty) {
      return conversations;
    }
    return conversations
        .where((conversation) => !_isLocallyHidden(conversation))
        .toList(growable: false);
  }

  DateTime? _latestLocalHiddenAt(ConversationSummary conversation) {
    DateTime? latest;
    for (final key in _visibilityKeysFor(conversation)) {
      final hiddenAt = _locallyHiddenConversationKeys[key];
      if (hiddenAt == null) {
        continue;
      }
      if (latest == null || hiddenAt.isAfter(latest)) {
        latest = hiddenAt;
      }
    }
    return latest;
  }

  Future<void> _updateBadgeCountBestEffort(
    int count, {
    required String source,
  }) async {
    _trace(
      'badge.request',
      fields: <String, Object?>{
        'source': source,
        'unread': count,
        'items': state.conversations.length,
        'loading': state.isLoading,
        'generation': _refreshGeneration,
      },
    );
    try {
      await _notification.updateBadgeCount(count);
    } catch (_) {
      // Badge updates are OS integration; they should not make list data fail.
    }
  }
}

void _trace(String event, {Map<String, Object?> fields = const {}}) {
  if (!_conversationTraceEnabled) {
    return;
  }
  final details = <String>[];
  for (final entry in fields.entries) {
    final value = entry.value;
    if (value != null) {
      details.add('${entry.key}=${_formatTraceValue(value)}');
    }
  }
  debugPrint(
    details.isEmpty
        ? '[awiki_me][conversation_trace] event=$event'
        : '[awiki_me][conversation_trace] event=$event ${details.join(' ')}',
  );
}

String? _safeHash(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return AwikiPerformanceLogger.safeHash(normalized);
}

String _formatTraceValue(Object value) {
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  return _collapseTraceWhitespace(value.toString());
}

String _collapseTraceWhitespace(String value) {
  final buffer = StringBuffer();
  var lastWasWhitespace = false;
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      if (!lastWasWhitespace) {
        buffer.write('_');
      }
      lastWasWhitespace = true;
      continue;
    }
    buffer.write(char);
    lastWasWhitespace = false;
  }
  return buffer.toString();
}

bool _sameConversationSummaryList(
  List<ConversationSummary> first,
  List<ConversationSummary> second,
) {
  if (identical(first, second)) {
    return true;
  }
  if (first.length != second.length) {
    return false;
  }
  for (var i = 0; i < first.length; i += 1) {
    if (!_sameConversationSummaryValue(first[i], second[i])) {
      return false;
    }
  }
  return true;
}

bool _sameConversationSummaryValue(
  ConversationSummary first,
  ConversationSummary second,
) {
  return first.threadId == second.threadId &&
      first.displayName == second.displayName &&
      first.lastMessagePreview == second.lastMessagePreview &&
      first.lastMessageAt.isAtSameMomentAs(second.lastMessageAt) &&
      first.unreadCount == second.unreadCount &&
      first.unreadMentionCount == second.unreadMentionCount &&
      first.firstUnreadMentionMessageId == second.firstUnreadMentionMessageId &&
      first.isGroup == second.isGroup &&
      first.targetDid == second.targetDid &&
      first.targetPeer == second.targetPeer &&
      first.groupId == second.groupId &&
      first.avatarUri == second.avatarUri &&
      first.avatarSeed == second.avatarSeed &&
      first.lastMessagePayloadJson == second.lastMessagePayloadJson &&
      first.conversationKey == second.conversationKey &&
      first.peerLifecycleState == second.peerLifecycleState;
}

List<String> _visibilityKeysFor(
  ConversationSummary conversation, {
  bool includeHandleAliasesForStrongIdentity = false,
}) {
  return conversationVisibilityIdentity(
    conversation,
    includeHandleAliasesForStrongIdentity:
        includeHandleAliasesForStrongIdentity,
  ).keys;
}

List<ConversationSummary> _mergeConversationRefresh({
  required List<ConversationSummary> refreshed,
  required List<ConversationSummary> local,
  bool keepLocalOnly = true,
}) {
  final localIndex = _ConversationMergeIndex(local);
  final consumedLocalThreadIds = <String>{};
  final mergedRefreshed = refreshed.map((conversation) {
    final matchedLocal = localIndex.match(
      conversation,
      consumedThreadIds: consumedLocalThreadIds,
    );
    if (matchedLocal != null) {
      consumedLocalThreadIds.add(matchedLocal.threadId);
    }
    final titledConversation = _mergeConversationTitle(
      refreshed: conversation,
      local: matchedLocal,
    );
    return _mergeConversationLifecycle(
      refreshed: _mergeConversationReadState(
        refreshed: _mergeConversationLastMessage(
          refreshed: titledConversation,
          local: matchedLocal,
        ),
        local: matchedLocal,
      ),
      local: matchedLocal,
    );
  }).toList();
  final refreshedThreadIds = <String>{
    for (final conversation in refreshed) conversation.threadId,
  };
  final localOnly = keepLocalOnly
      ? local
            .where(
              (conversation) =>
                  !consumedLocalThreadIds.contains(conversation.threadId) &&
                  !refreshedThreadIds.contains(conversation.threadId) &&
                  conversation.lastMessagePreview.trim().isNotEmpty,
            )
            .toList()
      : const <ConversationSummary>[];
  if (localOnly.isEmpty) {
    return mergedRefreshed;
  }
  return <ConversationSummary>[...mergedRefreshed, ...localOnly]
    ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
}

class _ConversationMergeIndex {
  _ConversationMergeIndex(List<ConversationSummary> conversations) {
    for (final conversation in conversations) {
      final threadId = _nonEmptyKey(conversation.threadId);
      if (threadId != null) {
        _byThreadId.putIfAbsent(threadId, () => conversation);
      }
      for (final key in conversation.visibilityKeys) {
        final normalized = _nonEmptyKey(key);
        if (normalized != null) {
          _byVisibilityKey.putIfAbsent(normalized, () => conversation);
        }
      }
      for (final key in _directTargetKeys(conversation)) {
        _byDirectTarget.putIfAbsent(key, () => conversation);
      }
    }
  }

  final Map<String, ConversationSummary> _byThreadId =
      <String, ConversationSummary>{};
  final Map<String, ConversationSummary> _byVisibilityKey =
      <String, ConversationSummary>{};
  final Map<String, ConversationSummary> _byDirectTarget =
      <String, ConversationSummary>{};

  ConversationSummary? match(
    ConversationSummary incoming, {
    Set<String> consumedThreadIds = const <String>{},
  }) {
    ConversationSummary? candidate = _candidateIfAvailable(
      _byThreadId[_nonEmptyKey(incoming.threadId)],
      consumedThreadIds,
    );
    if (candidate != null) {
      return candidate;
    }
    for (final key in incoming.visibilityKeys) {
      candidate = _candidateIfAvailable(
        _byVisibilityKey[_nonEmptyKey(key)],
        consumedThreadIds,
      );
      if (candidate != null) {
        return candidate;
      }
    }
    if (incoming.isGroup) {
      return null;
    }
    for (final key in _directTargetKeys(incoming)) {
      candidate = _candidateIfAvailable(
        _byDirectTarget[key],
        consumedThreadIds,
      );
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }

  static ConversationSummary? _candidateIfAvailable(
    ConversationSummary? candidate,
    Set<String> consumedThreadIds,
  ) {
    if (candidate == null || consumedThreadIds.contains(candidate.threadId)) {
      return null;
    }
    return candidate;
  }

  static Iterable<String> _directTargetKeys(ConversationSummary conversation) {
    if (conversation.isGroup) {
      return const <String>[];
    }
    final keys = <String>[];
    final did = _nonEmptyKey(conversation.targetDid);
    if (did != null) {
      keys.add('did:$did');
    }
    final peer = normalizedDirectPeer(conversation.targetPeer);
    if (peer != null) {
      keys.add('peer:$peer');
    }
    return keys;
  }

  static String? _nonEmptyKey(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

ConversationSummary? _matchingConversationForUpsert(
  Iterable<ConversationSummary> conversations,
  ConversationSummary incoming,
) {
  if (conversations is List<ConversationSummary>) {
    return _ConversationMergeIndex(conversations).match(incoming);
  }
  for (final item in conversations) {
    if (item.threadId == incoming.threadId) {
      return item;
    }
  }
  final incomingKeys =
      incoming.visibilityKeys
          .map((key) => key.trim())
          .where((key) => key.isNotEmpty)
          .toSet()
        ..addAll(_visibilityKeysFor(incoming));
  if (incomingKeys.isNotEmpty) {
    for (final item in conversations) {
      if (_visibilityKeysFor(item).any(incomingKeys.contains)) {
        return item;
      }
    }
  }
  if (incoming.isGroup) {
    return null;
  }
  for (final item in conversations) {
    if (!item.isGroup && sameDirectConversationTarget(item, incoming)) {
      return item;
    }
  }
  return null;
}

bool _sameConversationForList(
  ConversationSummary first,
  ConversationSummary second,
) {
  return _matchingConversationForUpsert(<ConversationSummary>[first], second) !=
      null;
}

ConversationSummary _mergeConversationTitle({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
  bool preferLocalTitle = false,
}) {
  if (local == null) {
    return refreshed;
  }
  if (!refreshed.isGroup) {
    return _mergeDirectConversationTitle(
      refreshed: refreshed,
      local: local,
      preferLocalTitle: preferLocalTitle,
    );
  }
  if (local.groupId?.trim() != refreshed.groupId?.trim()) {
    return refreshed;
  }
  final groupId = refreshed.groupId?.trim() ?? '';
  final localName = local.displayName.trim();
  final refreshedName = refreshed.displayName.trim();
  if (localName.isEmpty ||
      !GroupDisplayName.isIdLike(refreshedName, groupId) ||
      GroupDisplayName.isIdLike(localName, groupId)) {
    return refreshed;
  }
  return refreshed.copyWith(
    displayName: local.displayName,
    avatarUri: refreshed.avatarUri ?? local.avatarUri,
    avatarSeed: refreshed.avatarSeed ?? local.avatarSeed,
    lastMessagePayloadJson: refreshed.lastMessagePayloadJson,
  );
}

ConversationSummary _mergeConversationReadState({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  if (local == null ||
      local.unreadCount != 0 ||
      refreshed.unreadCount == 0 ||
      refreshed.lastMessageAt.isAfter(local.lastMessageAt)) {
    return refreshed;
  }
  return refreshed.copyWith(
    unreadCount: 0,
    unreadMentionCount: 0,
    firstUnreadMentionMessageId: null,
  );
}

ConversationSummary _mergeConversationLifecycle({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  if (local?.isDeletedAgentConversation == true &&
      !refreshed.isDeletedAgentConversation) {
    return refreshed.copyWith(
      peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
    );
  }
  return refreshed;
}

ConversationSummary _mergeConversationLastMessage({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  if (local == null || !local.lastMessageAt.isAfter(refreshed.lastMessageAt)) {
    return refreshed;
  }
  if (local.lastMessagePreview.trim().isEmpty &&
      refreshed.lastMessagePreview.trim().isNotEmpty) {
    return refreshed;
  }
  return refreshed.copyWith(
    lastMessagePreview: local.lastMessagePreview,
    lastMessageAt: local.lastMessageAt,
    lastMessagePayloadJson: local.lastMessagePayloadJson,
  );
}

ConversationSummary _mergeDirectConversationTitle({
  required ConversationSummary refreshed,
  required ConversationSummary local,
  bool preferLocalTitle = false,
}) {
  if (local.isGroup || !sameDirectConversationTarget(local, refreshed)) {
    return refreshed;
  }
  final localName = local.displayName.trim();
  final refreshedName = refreshed.displayName.trim();
  if (preferLocalTitle &&
      localName.isNotEmpty &&
      _isBetterDirectConversationTitle(localName, refreshedName)) {
    return refreshed.copyWith(
      displayName: local.displayName,
      avatarSeed: refreshed.avatarSeed ?? local.avatarSeed,
      peerLifecycleState: local.peerLifecycleState,
    );
  }
  if (localName.isEmpty ||
      localName == refreshedName ||
      !_isBetterDirectConversationTitle(localName, refreshedName)) {
    return refreshed;
  }
  return refreshed.copyWith(
    displayName: local.displayName,
    avatarSeed: refreshed.avatarSeed ?? local.avatarSeed,
    peerLifecycleState: local.peerLifecycleState,
  );
}

bool _isBetterDirectConversationTitle(String localName, String refreshedName) {
  if (refreshedName.isEmpty || refreshedName.startsWith('did:')) {
    return true;
  }
  return AgentDisplayName.isUserVisibleName(localName) &&
      !AgentDisplayName.isUserVisibleName(refreshedName);
}

final conversationListProvider =
    StateNotifierProvider<ConversationListController, ConversationListState>(
      (ref) => ConversationListController(ref),
    );
