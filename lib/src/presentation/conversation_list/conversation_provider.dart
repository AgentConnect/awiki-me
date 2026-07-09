import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/agent/agent_control_projection.dart';
import '../../application/conversation_service.dart';
import '../../application/models/app_thread_read_watermark.dart';
import '../../application/models/conversation_patch.dart';
import '../../core/group_display_name.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/agent/agent_display_name.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/conversation_identity.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/services/notification_facade.dart';
import '../agents/agents_provider.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../app_shell/providers/session_provider.dart';
import 'conversation_list_ordering.dart';

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
  final _ConversationReadPresentationStore _readPresentation =
      _ConversationReadPresentationStore();

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
      _publishConversationListState(
        state.copyWith(isLoading: true),
        source: 'refresh.loading_request',
        updateBadge: false,
      );
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
      _publishConversationListState(
        state.copyWith(isLoading: true),
        source: 'refresh_fast_local.loading_request',
        updateBadge: false,
      );
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
        _publishConversationListState(
          state.copyWith(isLoading: false),
          source: 'refresh.timeout',
          updateBadge: false,
        );
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
    _publishConversationListState(
      state.copyWith(isLoading: true),
      source: 'refresh.loading',
      updateBadge: false,
    );
    try {
      final session = ref.read(sessionProvider).session;
      if (session == null) {
        await _cancelPatchSubscription();
        if (generation != _refreshGeneration) {
          return;
        }
        _publishConversationListState(
          state.copyWith(
            conversations: const <ConversationSummary>[],
            isLoading: false,
          ),
          source: 'refresh.no_session',
        );
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
        _publishConversationListState(
          state.copyWith(isLoading: false),
          source: 'refresh.error',
          updateBadge: false,
        );
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
    _publishConversationListState(
      state.copyWith(
        conversations: sortConversationsForPresentation(
          _filterLocallyHiddenConversations(conversations),
        ),
        isLoading: true,
      ),
      source: 'snapshot',
    );
    _snapshotBootstrapActive = true;
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

  Future<void> _cancelPatchSubscription() {
    final subscription = _patchSubscription;
    _patchSubscription = null;
    _patchSubscriptionOwnerDid = null;
    _patchSubscriptionToken += 1;
    _lastPatchVersion = 0;
    final cancelFuture = subscription?.cancel();
    if (cancelFuture != null) {
      unawaited(cancelFuture.catchError((_) {}));
    }
    return Future<void>.value();
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
          'expected_version': _lastPatchVersion + 1,
          'pending_version_advance': false,
        },
      );
      _schedulePatchRepair(
        ownerDid: ownerDid,
        generation: _refreshGeneration,
        token: token,
        reason: 'version_gap',
      );
      return;
    }
    var applied = false;
    switch (patch.kind) {
      case ConversationListPatchKind.reset:
        _applyPatchReset(patch);
        applied = true;
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
        applied = true;
      case ConversationListPatchKind.remove:
        _applyPatchRemove(patch);
        applied = true;
      case ConversationListPatchKind.reorder:
        applied = _applyPatchReorder(patch);
        if (!applied) {
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
        return;
    }
    if (applied) {
      _lastPatchVersion = patch.version;
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
      _applyReadPresentationAll(
        _mergeConversationRefresh(
          refreshed: patch.items,
          local: currentConversations,
          ownerDid: patch.ownerDid,
          keepLocalOnly: false,
        ),
        ownerDid: patch.ownerDid,
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
    _publishConversationListState(
      state.copyWith(
        conversations: sortConversationsForPresentation(nextConversations),
        isLoading: false,
      ),
      source: 'patch_reset',
    );
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
    final conversationId = patch.conversationId?.trim();
    final hasConversationId =
        conversationId != null && conversationId.isNotEmpty;
    final conversationKey = patch.conversationKey?.trim();
    final next = state.conversations
        .where((item) {
          if (hasConversationId &&
              _conversationIdentityKey(item) == conversationId) {
            return false;
          }
          if (threadId != null &&
              threadId.isNotEmpty &&
              !hasConversationId &&
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
    _publishConversationListState(
      state.copyWith(conversations: next),
      source: 'patch_remove',
    );
    _snapshotBootstrapActive = false;
    _trace(
      'state.patch_remove',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'thread_hash': _safeHash(threadId),
        'conversation_hash': _safeHash(conversationId),
        'conversation_key_hash': _safeHash(conversationKey),
      },
    );
  }

  bool _applyPatchReorder(ConversationListPatch patch) {
    final threadId = patch.threadId?.trim();
    final conversationId = patch.conversationId?.trim();
    final identity = conversationId != null && conversationId.isNotEmpty
        ? conversationId
        : threadId;
    if (identity == null || identity.isEmpty) {
      return false;
    }
    final current = state.conversations.toList(growable: true);
    final currentIndex = current.indexWhere(
      (item) => _conversationIdentityKey(item) == identity,
    );
    if (currentIndex < 0) {
      return false;
    }
    final item = current.removeAt(currentIndex);
    final targetIndex = (patch.index ?? 0).clamp(0, current.length);
    current.insert(targetIndex, item);
    _publishConversationListState(
      state.copyWith(conversations: sortConversationsForPresentation(current)),
      source: 'patch_reorder',
    );
    _snapshotBootstrapActive = false;
    _trace(
      'state.patch_reorder',
      fields: <String, Object?>{
        'unread': state.unreadCount,
        'thread_hash': _safeHash(threadId),
        'conversation_hash': _safeHash(conversationId),
        'from': currentIndex,
        'to': targetIndex,
      },
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
      _trace(
        'patch_repair.skip',
        fields: <String, Object?>{
          'reason': 'already_running',
          'requested_reason': reason,
          'last_version': _lastPatchVersion,
        },
      );
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
        'last_version': _lastPatchVersion,
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
    _trace(
      'patch_repair.success',
      fields: <String, Object?>{
        'reason': reason,
        'repair_version': repair.version,
        'last_version': _lastPatchVersion,
        'items': repair.conversations.length,
      },
    );
    final applied = await _applyConversationRefresh(
      repair.conversations,
      generation: generation,
      label: 'conversation_list.patch_repair',
      keepLocalOnly: false,
      badgeSource: 'patch_repair',
    );
    if (applied && repair.version > _lastPatchVersion) {
      _lastPatchVersion = repair.version;
    }
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

  Future<bool> _applyConversationRefresh(
    List<ConversationSummary> refreshed, {
    required int generation,
    required String label,
    bool keepLocalOnly = true,
    String? badgeSource,
  }) async {
    if (generation != _refreshGeneration) {
      return false;
    }
    _snapshotBootstrapAllowedGeneration = null;
    final currentConversations = state.conversations;
    final nextConversations = AwikiPerformanceLogger.sync(
      '$label.merge',
      () => _filterLocallyHiddenConversations(
        _applyReadPresentationAll(
          _mergeConversationRefresh(
            refreshed: refreshed,
            local: currentConversations,
            ownerDid: _currentOwnerDid,
            keepLocalOnly: keepLocalOnly,
          ),
          ownerDid: _currentOwnerDid,
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
      return true;
    }
    _publishConversationListState(
      state.copyWith(
        conversations: sortConversationsForPresentation(nextConversations),
        isLoading: false,
      ),
      source: badgeSource ?? label,
    );
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
    return true;
  }

  void upsertConversation(ConversationSummary conversation) {
    if (_isLocallyHidden(conversation)) {
      return;
    }
    if (_canUpsertConversationImmediately(conversation)) {
      _upsertConversation(
        conversation,
        preferLocalTitle: true,
        source: 'upsert_public',
      );
    }
    unawaited(
      _normalizeAndUpsertConversation(
        conversation,
        preferLocalTitle: true,
        source: 'upsert_public_normalized',
      ).catchError((_) {}),
    );
  }

  Future<void> _normalizeAndUpsertConversation(
    ConversationSummary conversation, {
    bool preferLocalTitle = false,
    String source = 'upsert_normalized',
  }) async {
    final normalized = await _normalizeConversationForRecents(conversation);
    if (normalized == null) {
      _removeConversationLocally(conversation);
      return;
    }
    if (_isLocallyHidden(normalized)) {
      return;
    }
    _upsertConversation(
      normalized,
      preferLocalTitle: preferLocalTitle,
      source: source,
    );
  }

  void upsertConversationBestEffort(ConversationSummary conversation) {
    try {
      upsertConversation(conversation);
    } catch (_) {
      // Background realtime/navigation paths should not fail foreground UI.
    }
  }

  bool _canUpsertConversationImmediately(ConversationSummary conversation) {
    final session = ref.read(sessionProvider).session;
    return shouldShowConversationForChatList(
      conversation,
      ownerDid: session?.did ?? '',
      daemonAgentDids: ref
          .read(agentsProvider)
          .daemonAgents
          .map((agent) => agent.agentDid),
    );
  }

  void upsertRealtimeMessageBestEffort(
    ConversationSummary conversation, {
    required ChatMessage message,
  }) {
    try {
      _trace(
        'realtime_message.refresh_hint',
        fields: <String, Object?>{
          'thread_hash': _safeHash(conversation.threadId),
          'message_thread_hash': _safeHash(message.threadId),
        },
      );
      unawaited(refreshFastLocal().catchError((_) {}));
    } catch (_) {
      // Background realtime paths must not fail message delivery or notification.
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
      ownerDid: _currentOwnerDid,
    );
    final titledConversation = _mergeConversationTitle(
      refreshed: conversation,
      local: existing,
      preferLocalTitle: preferLocalTitle,
    );
    final mergedConversation = _applyReadPresentation(
      _mergeConversationPresentationIdentity(
        refreshed: _mergeConversationLifecycle(
          refreshed: _mergeConversationReadState(
            refreshed: _mergeConversationLastMessage(
              refreshed: titledConversation,
              local: existing,
            ),
            local: existing,
          ),
          local: existing,
        ),
        local: existing,
        ownerDid: _currentOwnerDid,
      ),
      ownerDid: _currentOwnerDid,
    );
    final merged = _replaceConversationInPresentationList(
      current: state.conversations,
      incoming: mergedConversation,
      matchedLocal: existing,
      ownerDid: _currentOwnerDid,
    );
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
    _publishConversationListState(
      state.copyWith(conversations: merged),
      source: source,
    );
    _syncSelectedConversationAfterUpsert(
      incoming: mergedConversation,
      matchedLocal: existing,
    );
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
    if (selected != null && _sameConversationIdentity(selected, conversation)) {
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
    _publishConversationListState(
      state.copyWith(conversations: sortConversationsForPresentation(next)),
      source: 'apply_group_names',
      updateBadge: false,
    );
  }

  void markConversationReadLocal(
    ConversationSummary conversation, {
    AppThreadReadWatermark? watermark,
  }) {
    _readPresentation.markRead(
      conversation,
      ownerDid: _currentOwnerDid,
      watermark: watermark,
    );
    final currentConversations = state.conversations;
    final beforeUnread = state.unreadCount;
    final next = _applyReadPresentationAll(
      currentConversations,
      ownerDid: _currentOwnerDid,
    );
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
    _publishConversationListState(
      state.copyWith(conversations: sortConversationsForPresentation(next)),
      source: 'mark_conversation_read_local',
    );
    _trace(
      'state.mark_conversation_read',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'thread_hash': _safeHash(conversation.threadId),
      },
    );
  }

  void markConversationVisibleLocal(
    ConversationSummary conversation, {
    AppThreadReadWatermark? watermark,
  }) {
    _readPresentation.markVisible(
      conversation,
      ownerDid: _currentOwnerDid,
      watermark: watermark,
    );
    final currentConversations = state.conversations;
    final next = _applyReadPresentationAll(
      currentConversations,
      ownerDid: _currentOwnerDid,
    );
    if (_sameConversationSummaryList(currentConversations, next)) {
      return;
    }
    _publishConversationListState(
      state.copyWith(conversations: sortConversationsForPresentation(next)),
      source: 'mark_conversation_visible_local',
    );
  }

  void markConversationHiddenLocal(ConversationSummary conversation) {
    _readPresentation.markHidden(conversation, ownerDid: _currentOwnerDid);
  }

  Future<void> clear() {
    _refreshGeneration += 1;
    _refreshOperation = null;
    _refreshOperationFastLocal = false;
    _snapshotBootstrapActive = false;
    _snapshotBootstrapAllowedGeneration = null;
    unawaited(_cancelPatchSubscription());
    _locallyHiddenConversationKeys.clear();
    _readPresentation.clear();
    state = const ConversationListState();
    unawaited(_updateBadgeCountBestEffort(0, source: 'clear'));
    return Future<void>.value();
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
    final current = state.conversations;
    final next = current
        .where((item) => !_sameConversationIdentity(item, conversation))
        .toList(growable: false);
    if (next.length == current.length) {
      return;
    }
    final beforeUnread = state.unreadCount;
    _publishConversationListState(
      state.copyWith(conversations: next),
      source: 'remove_local',
    );
    _trace(
      'state.remove_local',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'thread_hash': _safeHash(conversation.threadId),
      },
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
    for (final key in _hiddenLookupKeysFor(conversation)) {
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

  void _syncSelectedConversationAfterUpsert({
    required ConversationSummary incoming,
    required ConversationSummary? matchedLocal,
  }) {
    final selected = ref.read(selectedConversationProvider);
    if (selected == null) {
      return;
    }
    if (_sameConversationIdentity(selected, incoming)) {
      ref
          .read(selectedConversationProvider.notifier)
          .selectConversation(
            _mergeSelectedConversation(selected: selected, incoming: incoming),
          );
      return;
    }
    if (matchedLocal != null &&
        _sameConversationIdentity(selected, matchedLocal)) {
      ref
          .read(selectedConversationProvider.notifier)
          .selectConversation(
            _mergeSelectedConversation(selected: selected, incoming: incoming),
          );
      return;
    }
    if (_shouldCollapsePresentationAlias(
      incoming,
      selected,
      ownerDid: _currentOwnerDid,
    )) {
      ref
          .read(selectedConversationProvider.notifier)
          .selectConversation(
            _mergeSelectedConversation(selected: selected, incoming: incoming),
          );
    }
  }

  String? get _currentOwnerDid => ref.read(sessionProvider).session?.did;

  ConversationSummary _applyReadPresentation(
    ConversationSummary conversation, {
    required String? ownerDid,
    Iterable<ConversationSummary>? presentationRows,
  }) {
    return _readPresentation.project(
      conversation,
      ownerDid: ownerDid,
      presentationRows: presentationRows,
    );
  }

  List<ConversationSummary> _applyReadPresentationAll(
    List<ConversationSummary> conversations, {
    required String? ownerDid,
  }) {
    var changed = false;
    final next = conversations
        .map((conversation) {
          final applied = _applyReadPresentation(
            conversation,
            ownerDid: ownerDid,
            presentationRows: conversations,
          );
          changed = changed || !identical(applied, conversation);
          return applied;
        })
        .toList(growable: false);
    return changed ? next : conversations;
  }

  void _publishConversationListState(
    ConversationListState nextState, {
    required String source,
    bool updateBadge = true,
  }) {
    final nextConversations = _applyReadPresentationAll(
      nextState.conversations,
      ownerDid: _currentOwnerDid,
    );
    final appliedState = nextConversations == nextState.conversations
        ? nextState
        : nextState.copyWith(conversations: nextConversations);
    state = appliedState;
    if (updateBadge) {
      unawaited(_updateBadgeCountBestEffort(state.unreadCount, source: source));
    }
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

String _conversationIdentityKey(ConversationSummary conversation) {
  final conversationId = _explicitConversationId(conversation);
  if (conversationId != null) {
    return conversationId;
  }
  final threadId = conversation.threadId.trim();
  if (threadId.isNotEmpty) {
    return threadId;
  }
  return conversation.visibilityKey;
}

String? _explicitConversationId(ConversationSummary conversation) {
  final conversationId = conversation.conversationId?.trim();
  if (conversationId != null && conversationId.isNotEmpty) {
    return conversationId;
  }
  return null;
}

bool _hasExplicitConversationId(ConversationSummary conversation) {
  return _explicitConversationId(conversation) != null;
}

bool _sameConversationIdentity(
  ConversationSummary first,
  ConversationSummary second,
) {
  final firstConversationId = _explicitConversationId(first);
  final secondConversationId = _explicitConversationId(second);
  if (firstConversationId != null || secondConversationId != null) {
    return firstConversationId != null &&
        secondConversationId != null &&
        firstConversationId == secondConversationId;
  }
  return sameConversationThread(first, second);
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
  return first.conversationId == second.conversationId &&
      first.threadId == second.threadId &&
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
      _sameLastMessageSnapshot(
        first.lastMessageSnapshot,
        second.lastMessageSnapshot,
      ) &&
      first.conversationKey == second.conversationKey &&
      first.peerLifecycleState == second.peerLifecycleState;
}

bool _sameLastMessageSnapshot(ChatMessage? first, ChatMessage? second) {
  if (identical(first, second)) {
    return true;
  }
  if (first == null || second == null) {
    return false;
  }
  return first.localId == second.localId &&
      first.remoteId == second.remoteId &&
      first.threadId == second.threadId &&
      first.senderDid == second.senderDid &&
      first.receiverDid == second.receiverDid &&
      first.groupId == second.groupId &&
      first.content == second.content &&
      first.originalType == second.originalType &&
      first.createdAt.isAtSameMomentAs(second.createdAt) &&
      first.isMine == second.isMine &&
      first.serverSequence == second.serverSequence &&
      first.sendState == second.sendState &&
      first.payloadJson == second.payloadJson &&
      _sameAttachmentSnapshot(first.attachment, second.attachment) &&
      _sameMentions(first.mentions, second.mentions);
}

bool _sameAttachmentSnapshot(ChatAttachment? first, ChatAttachment? second) {
  if (identical(first, second)) {
    return true;
  }
  if (first == null || second == null) {
    return false;
  }
  return first.attachmentId == second.attachmentId &&
      first.filename == second.filename &&
      first.mimeType == second.mimeType &&
      first.sizeBytes == second.sizeBytes &&
      first.caption == second.caption &&
      first.objectUri == second.objectUri &&
      first.localPath == second.localPath &&
      first.hasLocalSource == second.hasLocalSource;
}

bool _sameMentions(
  List<ChatMessageMention> first,
  List<ChatMessageMention> second,
) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    final firstMention = first[index];
    final secondMention = second[index];
    if (firstMention.id != secondMention.id ||
        firstMention.surface != secondMention.surface ||
        firstMention.start != secondMention.start ||
        firstMention.end != secondMention.end ||
        firstMention.role != secondMention.role ||
        !_sameMentionTarget(firstMention.target, secondMention.target)) {
      return false;
    }
  }
  return true;
}

bool _sameMentionTarget(
  ChatMentionTargetDraft first,
  ChatMentionTargetDraft second,
) {
  return first.kind == second.kind &&
      first.selector == second.selector &&
      first.did == second.did &&
      first.handle == second.handle &&
      first.displayName == second.displayName;
}

class _ConversationReadPresentationStore {
  static const int _maxStates = 512;

  final List<_ConversationReadPresentationState> _states =
      <_ConversationReadPresentationState>[];

  void markVisible(
    ConversationSummary conversation, {
    required String? ownerDid,
    AppThreadReadWatermark? watermark,
  }) {
    if (_isDidBackedLegacyDirectConversation(
      conversation,
      ownerDid: ownerDid,
    )) {
      return;
    }
    final state = _stateFor(conversation, ownerDid: ownerDid);
    state.isVisible = true;
    final readWatermark = _ReadWatermark.fromWatermark(
      conversation,
      ownerDid: ownerDid,
      watermark: watermark,
      allowConversationFallback: false,
    );
    if (readWatermark != null) {
      state.advanceRead(readWatermark);
    }
    state.recomputeUnread(conversation);
    _trim();
  }

  void markHidden(
    ConversationSummary conversation, {
    required String? ownerDid,
  }) {
    if (_isDidBackedLegacyDirectConversation(
      conversation,
      ownerDid: ownerDid,
    )) {
      return;
    }
    final state = _findStateFor(
      conversation,
      ownerDid: ownerDid,
      matchVisibilityBridge: false,
    );
    if (state == null) {
      return;
    }
    state.isVisible = false;
    _trim();
  }

  void markRead(
    ConversationSummary conversation, {
    required String? ownerDid,
    AppThreadReadWatermark? watermark,
  }) {
    final readWatermark = _ReadWatermark.fromWatermark(
      conversation,
      ownerDid: ownerDid,
      watermark: watermark,
      allowConversationFallback: false,
    );
    if (readWatermark == null) {
      return;
    }
    final state = _stateFor(conversation, ownerDid: ownerDid);
    state.advanceRead(readWatermark);
    state.recomputeUnread(conversation);
    _trim();
  }

  ConversationSummary project(
    ConversationSummary conversation, {
    required String? ownerDid,
    Iterable<ConversationSummary>? presentationRows,
  }) {
    final state = _stateFor(
      conversation,
      ownerDid: ownerDid,
      presentationRows: presentationRows,
    );
    final incoming = _UnreadWatermark.fromConversation(conversation);
    final hadLatest = state.latest != null;
    if (incoming.isAfter(state.latest)) {
      state.latest = incoming;
      state.displayUnreadMentionCount = _nonNegativeInt(
        conversation.unreadMentionCount,
      );
      state.displayUnreadCount = _displayUnreadCountForLatestAdvance(
        conversation,
        ownerDid: ownerDid,
        hadPreviousLatest: hadLatest,
        mentionUnreadCount: state.displayUnreadMentionCount,
      );
      state.displayFirstUnreadMentionMessageId =
          state.displayUnreadMentionCount > 0
          ? conversation.firstUnreadMentionMessageId
          : null;
    } else if (state.latest == null || incoming.sameMessageAs(state.latest)) {
      state.mergeSameLatestEvidence(conversation);
    } else {
      state.advanceVisibleRead(incoming, conversation: conversation);
      state.recomputeUnread(conversation);
      _trim();
      return state.projectOlderConversation(conversation, incoming);
    }
    state.advanceVisibleRead(incoming, conversation: conversation);
    state.recomputeUnread(conversation);
    _trim();
    return state.projectLatestConversation(conversation);
  }

  void clear() {
    _states.clear();
  }

  _ConversationReadPresentationState _stateFor(
    ConversationSummary conversation, {
    required String? ownerDid,
    Iterable<ConversationSummary>? presentationRows,
    bool matchVisibilityBridge = true,
  }) {
    final existing = _findStateFor(
      conversation,
      ownerDid: ownerDid,
      presentationRows: presentationRows,
      matchVisibilityBridge: matchVisibilityBridge,
    );
    if (existing != null) {
      return existing;
    }
    final state = _ConversationReadPresentationState(
      conversation: conversation,
      ownerDid: ownerDid,
    );
    _states.add(state);
    return state;
  }

  _ConversationReadPresentationState? _findStateFor(
    ConversationSummary conversation, {
    required String? ownerDid,
    Iterable<ConversationSummary>? presentationRows,
    bool matchVisibilityBridge = true,
  }) {
    for (var index = _states.length - 1; index >= 0; index -= 1) {
      final state = _states[index];
      if (state.matches(
        conversation,
        ownerDid: ownerDid,
        presentationRows: presentationRows,
        matchVisibilityBridge: matchVisibilityBridge,
      )) {
        return state;
      }
    }
    return null;
  }

  void _trim() {
    if (_states.length <= _maxStates) {
      return;
    }
    _states.removeRange(0, _states.length - _maxStates);
  }
}

class _ConversationReadPresentationState {
  _ConversationReadPresentationState({
    required this.conversation,
    required this.ownerDid,
  });

  final ConversationSummary conversation;
  final String? ownerDid;
  _UnreadWatermark? latest;
  _ReadWatermark? read;
  bool isVisible = false;
  int displayUnreadCount = 0;
  int displayUnreadMentionCount = 0;
  String? displayFirstUnreadMentionMessageId;

  bool matches(
    ConversationSummary candidate, {
    required String? ownerDid,
    Iterable<ConversationSummary>? presentationRows,
    bool matchVisibilityBridge = true,
  }) {
    final effectiveOwnerDid = ownerDid ?? this.ownerDid;
    if (!_sameReadOwner(effectiveOwnerDid, this.ownerDid)) {
      return false;
    }
    return _sameVisiblePresentationConversation(
      conversation,
      candidate,
      ownerDid: effectiveOwnerDid,
      presentationRows: presentationRows,
      matchVisibilityBridge: matchVisibilityBridge,
    );
  }

  void advanceRead(_ReadWatermark watermark) {
    if (read == null || watermark.isAfter(read!)) {
      read = watermark;
    }
  }

  void advanceVisibleRead(
    _UnreadWatermark watermark, {
    required ConversationSummary conversation,
  }) {
    if (!isVisible ||
        !watermark.hasStablePosition ||
        !_sameStrictReadPresentationConversation(
          this.conversation,
          conversation,
          ownerDid: ownerDid,
        )) {
      return;
    }
    advanceRead(_ReadWatermark.fromUnread(watermark));
  }

  void mergeSameLatestEvidence(ConversationSummary conversation) {
    final incomingUnread = _normalizedUnreadCount(conversation);
    if (incomingUnread <= 0 && displayUnreadCount > 0) {
      return;
    }
    displayUnreadMentionCount = _nonNegativeInt(
      conversation.unreadMentionCount,
    );
    displayUnreadCount = incomingUnread;
    displayFirstUnreadMentionMessageId = displayUnreadMentionCount > 0
        ? conversation.firstUnreadMentionMessageId
        : null;
  }

  void recomputeUnread(ConversationSummary conversation) {
    final latestMessage =
        latest ?? _UnreadWatermark.fromConversation(conversation);
    if (read?.covers(latestMessage) ?? false) {
      displayUnreadCount = 0;
      displayUnreadMentionCount = 0;
      displayFirstUnreadMentionMessageId = null;
      return;
    }
    displayUnreadCount = _nonNegativeInt(displayUnreadCount);
    displayUnreadMentionCount = _nonNegativeInt(displayUnreadMentionCount);
  }

  ConversationSummary projectLatestConversation(
    ConversationSummary conversation,
  ) {
    return _copyConversationUnreadIfNeeded(
      conversation,
      unreadCount: displayUnreadCount,
      unreadMentionCount: displayUnreadMentionCount,
      firstUnreadMentionMessageId: displayFirstUnreadMentionMessageId,
    );
  }

  ConversationSummary projectOlderConversation(
    ConversationSummary conversation,
    _UnreadWatermark incoming,
  ) {
    if (read?.covers(incoming) ?? false) {
      return _copyConversationUnreadIfNeeded(
        conversation,
        unreadCount: 0,
        unreadMentionCount: 0,
        firstUnreadMentionMessageId: null,
      );
    }
    return conversation;
  }
}

ConversationSummary _copyConversationUnreadIfNeeded(
  ConversationSummary conversation, {
  required int unreadCount,
  required int unreadMentionCount,
  required String? firstUnreadMentionMessageId,
}) {
  if (conversation.unreadCount == unreadCount &&
      conversation.unreadMentionCount == unreadMentionCount &&
      conversation.firstUnreadMentionMessageId == firstUnreadMentionMessageId) {
    return conversation;
  }
  return conversation.copyWith(
    unreadCount: unreadCount,
    unreadMentionCount: unreadMentionCount,
    firstUnreadMentionMessageId: firstUnreadMentionMessageId,
  );
}

int _displayUnreadCountForLatestAdvance(
  ConversationSummary conversation, {
  required String? ownerDid,
  required bool hadPreviousLatest,
  required int mentionUnreadCount,
}) {
  final providedUnread = _normalizedUnreadCount(conversation);
  if (providedUnread > 0 || !hadPreviousLatest) {
    return providedUnread;
  }
  return _latestMessageIsFromOtherParticipant(conversation, ownerDid: ownerDid)
      ? 1
      : 0;
}

int _normalizedUnreadCount(ConversationSummary conversation) {
  return _maxInt(
    _nonNegativeInt(conversation.unreadCount),
    _nonNegativeInt(conversation.unreadMentionCount),
  );
}

bool _latestMessageIsFromOtherParticipant(
  ConversationSummary conversation, {
  required String? ownerDid,
}) {
  final snapshot = conversation.lastMessageSnapshot;
  if (snapshot == null) {
    return false;
  }
  if (snapshot.isMine) {
    return false;
  }
  final owner = ownerDid?.trim();
  final sender = snapshot.senderDid.trim();
  if (owner != null && owner.isNotEmpty && sender.isNotEmpty) {
    return sender != owner;
  }
  return true;
}

int _maxInt(int first, int second) => first >= second ? first : second;

int _nonNegativeInt(int value) => value < 0 ? 0 : value;

class _UnreadWatermark {
  const _UnreadWatermark({
    required this.lastMessageAt,
    required this.lastMessagePreview,
    this.messageId,
    this.serverSequence,
  });

  final DateTime lastMessageAt;
  final String lastMessagePreview;
  final String? messageId;
  final int? serverSequence;

  static _UnreadWatermark fromConversation(ConversationSummary conversation) {
    return _UnreadWatermark(
      lastMessageAt: conversation.lastMessageAt.toUtc(),
      lastMessagePreview: conversation.lastMessagePreview,
      messageId: _lastMessageIdentity(conversation.lastMessageSnapshot),
      serverSequence: conversation.lastMessageSnapshot?.serverSequence,
    );
  }

  bool isAfter(_UnreadWatermark? other) {
    if (other == null) {
      return true;
    }
    if (serverSequence != null && other.serverSequence != null) {
      return serverSequence! > other.serverSequence!;
    }
    if (lastMessageAt.isAfter(other.lastMessageAt)) {
      return true;
    }
    if (lastMessageAt.isBefore(other.lastMessageAt)) {
      return false;
    }
    if (messageId != null &&
        other.messageId != null &&
        messageId != other.messageId) {
      return lastMessagePreview != other.lastMessagePreview;
    }
    return false;
  }

  bool sameMessageAs(_UnreadWatermark? other) {
    if (other == null) {
      return false;
    }
    if (serverSequence != null && other.serverSequence != null) {
      return serverSequence == other.serverSequence;
    }
    if (!lastMessageAt.isAtSameMomentAs(other.lastMessageAt)) {
      return false;
    }
    if (messageId != null && other.messageId != null) {
      return messageId == other.messageId;
    }
    return lastMessagePreview == other.lastMessagePreview;
  }

  bool get hasStablePosition => messageId != null || serverSequence != null;
}

class _ReadWatermark {
  const _ReadWatermark({
    required this.readAt,
    this.messageId,
    this.serverSequence,
  });

  final DateTime readAt;
  final String? messageId;
  final int? serverSequence;

  static _ReadWatermark? fromWatermark(
    ConversationSummary conversation, {
    required String? ownerDid,
    AppThreadReadWatermark? watermark,
    bool allowConversationFallback = true,
  }) {
    if (_isDidBackedLegacyDirectConversation(
      conversation,
      ownerDid: ownerDid,
    )) {
      return null;
    }
    if (watermark == null || watermark.isEmpty) {
      if (!allowConversationFallback) {
        return null;
      }
      return fromUnread(_UnreadWatermark.fromConversation(conversation));
    }
    final snapshot = conversation.lastMessageSnapshot;
    final watermarkSeq = _parseWatermarkSequence(watermark.lastReadThreadSeq);
    return _ReadWatermark(
      readAt:
          (watermark.readAt ??
                  snapshot?.createdAt ??
                  conversation.lastMessageAt)
              .toUtc(),
      messageId:
          _lastMessageIdentityFromParts(
            remoteId: watermark.lastReadMessageId,
            localId: snapshot?.localId,
          ) ??
          _lastMessageIdentity(snapshot),
      serverSequence: watermarkSeq ?? snapshot?.serverSequence,
    );
  }

  static _ReadWatermark fromUnread(_UnreadWatermark watermark) {
    return _ReadWatermark(
      readAt: watermark.lastMessageAt,
      messageId: watermark.messageId,
      serverSequence: watermark.serverSequence,
    );
  }

  bool isAfter(_ReadWatermark other) {
    if (serverSequence != null && other.serverSequence != null) {
      return serverSequence! > other.serverSequence!;
    }
    if (readAt.isAfter(other.readAt)) {
      return true;
    }
    if (readAt.isBefore(other.readAt)) {
      return false;
    }
    return messageId != null &&
        other.messageId != null &&
        messageId != other.messageId;
  }

  bool covers(_UnreadWatermark message) {
    if (serverSequence != null && message.serverSequence != null) {
      return serverSequence! >= message.serverSequence!;
    }
    if (readAt.isAfter(message.lastMessageAt)) {
      return true;
    }
    if (readAt.isBefore(message.lastMessageAt)) {
      return false;
    }
    if (messageId != null && message.messageId != null) {
      return messageId == message.messageId;
    }
    return true;
  }
}

String? _lastMessageIdentity(ChatMessage? message) {
  return _lastMessageIdentityFromParts(
    remoteId: message?.remoteId,
    localId: message?.localId,
  );
}

String? _lastMessageIdentityFromParts({String? remoteId, String? localId}) {
  final normalizedRemoteId = remoteId?.trim();
  if (normalizedRemoteId != null && normalizedRemoteId.isNotEmpty) {
    return 'remote:$normalizedRemoteId';
  }
  final normalizedLocalId = localId?.trim();
  if (normalizedLocalId != null && normalizedLocalId.isNotEmpty) {
    return 'local:$normalizedLocalId';
  }
  return null;
}

int? _parseWatermarkSequence(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return int.tryParse(normalized);
}

bool _sameReadOwner(String? first, String? second) {
  final firstOwner = first?.trim();
  final secondOwner = second?.trim();
  if (firstOwner == null ||
      firstOwner.isEmpty ||
      secondOwner == null ||
      secondOwner.isEmpty) {
    return true;
  }
  return firstOwner == secondOwner;
}

bool _sameStrictReadPresentationConversation(
  ConversationSummary first,
  ConversationSummary second, {
  required String? ownerDid,
}) {
  if (_sameConversationIdentity(first, second) ||
      sameConversationThread(first, second)) {
    return true;
  }
  if (first.isGroup || second.isGroup) {
    return first.isGroup &&
        second.isGroup &&
        sameNonEmpty(first.groupId, second.groupId);
  }
  if (isPeerScopedDirectConversation(first) &&
      isPeerScopedDirectConversation(second)) {
    return false;
  }
  if (isPeerScopedDirectConversation(first) &&
      _isDidBackedLegacyDirectConversation(second, ownerDid: ownerDid)) {
    return false;
  }
  if (isPeerScopedDirectConversation(second) &&
      _isDidBackedLegacyDirectConversation(first, ownerDid: ownerDid)) {
    return false;
  }
  if (isPeerScopedDirectConversation(first) &&
      isReplaceableLegacyDirectConversation(second, ownerDid: ownerDid)) {
    return sameDirectPresentationTarget(first, second);
  }
  if (isPeerScopedDirectConversation(second) &&
      isReplaceableLegacyDirectConversation(first, ownerDid: ownerDid)) {
    return sameDirectPresentationTarget(first, second);
  }
  if (_shouldCollapsePresentationAlias(first, second, ownerDid: ownerDid) ||
      _shouldCollapsePresentationAlias(second, first, ownerDid: ownerDid)) {
    return true;
  }
  if (_hasExplicitConversationId(first) || _hasExplicitConversationId(second)) {
    return false;
  }
  return sameDirectPresentationTarget(first, second);
}

bool _sameVisiblePresentationConversation(
  ConversationSummary visible,
  ConversationSummary candidate, {
  required String? ownerDid,
  Iterable<ConversationSummary>? presentationRows,
  bool matchVisibilityBridge = true,
}) {
  if (_sameStrictReadPresentationConversation(
    visible,
    candidate,
    ownerDid: ownerDid,
  )) {
    return true;
  }
  if (visible.isGroup || candidate.isGroup) {
    return false;
  }
  if (isPeerScopedDirectConversation(visible) &&
      isPeerScopedDirectConversation(candidate)) {
    return false;
  }
  if (!matchVisibilityBridge ||
      !_isUniquePeerScopedAliasBridge(
        visible,
        candidate,
        ownerDid: ownerDid,
        presentationRows: presentationRows,
      )) {
    return false;
  }
  return sameDirectPresentationTarget(visible, candidate);
}

bool _isUniquePeerScopedAliasBridge(
  ConversationSummary first,
  ConversationSummary second, {
  required String? ownerDid,
  Iterable<ConversationSummary>? presentationRows,
}) {
  final firstPeerScoped = isPeerScopedDirectConversation(first);
  final secondPeerScoped = isPeerScopedDirectConversation(second);
  if (firstPeerScoped == secondPeerScoped) {
    return false;
  }
  final peerScoped = firstPeerScoped ? first : second;
  final alias = firstPeerScoped ? second : first;
  if (_isDidBackedLegacyDirectConversation(alias, ownerDid: ownerDid)) {
    return false;
  }
  if (!isReplaceableLegacyDirectConversation(alias, ownerDid: ownerDid) ||
      !sameDirectPresentationTarget(peerScoped, alias)) {
    return false;
  }
  final rows = presentationRows;
  if (rows == null) {
    return false;
  }
  final matchingPeerRows = _matchingPeerScopedPresentationRows(
    rows,
    alias: alias,
  );
  return matchingPeerRows.length == 1 &&
      sameConversationThread(matchingPeerRows.single, peerScoped);
}

bool _isDidBackedLegacyDirectConversation(
  ConversationSummary conversation, {
  required String? ownerDid,
}) {
  if (conversation.isGroup || isPeerScopedDirectConversation(conversation)) {
    return false;
  }
  final targetDid = conversation.targetDid?.trim();
  if (targetDid == null || targetDid.isEmpty) {
    return false;
  }
  final targetPeer = normalizedDirectPeer(conversation.targetPeer);
  if (targetPeer == null || targetPeer != targetDid) {
    return false;
  }
  return isReplaceableLegacyDirectConversation(
    conversation,
    ownerDid: ownerDid,
  );
}

List<String> _visibilityKeysFor(
  ConversationSummary conversation, {
  bool includeHandleAliasesForStrongIdentity = false,
}) {
  final conversationId = _explicitConversationId(conversation);
  if (conversationId != null) {
    return <String>[conversationId];
  }
  if (isPeerScopedDirectConversation(conversation)) {
    final threadId = conversation.threadId.trim();
    return threadId.isEmpty ? const <String>[] : <String>[threadId];
  }
  return conversationVisibilityIdentity(
    conversation,
    includeHandleAliasesForStrongIdentity:
        includeHandleAliasesForStrongIdentity,
  ).keys;
}

List<String> _hiddenLookupKeysFor(ConversationSummary conversation) {
  if (!isPeerScopedDirectConversation(conversation)) {
    return _visibilityKeysFor(conversation);
  }
  final keys = <String>[];
  void add(String value) {
    final key = value.trim();
    if (key.isNotEmpty && !keys.contains(key)) {
      keys.add(key);
    }
  }

  for (final key in _visibilityKeysFor(conversation)) {
    add(key);
  }
  for (final key in conversationVisibilityIdentity(
    conversation,
    includeHandleAliasesForStrongIdentity: true,
  ).keys) {
    add(key);
  }
  return keys;
}

List<ConversationSummary> _mergeConversationRefresh({
  required List<ConversationSummary> refreshed,
  required List<ConversationSummary> local,
  required String? ownerDid,
  bool keepLocalOnly = true,
}) {
  final localIndex = _ConversationMergeIndex(local, ownerDid: ownerDid);
  final consumedLocalIdentityKeys = <String>{};
  final consumedLocalPresentationAliases = <String>{};
  final mergedRefreshed = refreshed.map((conversation) {
    final matchedLocal = localIndex.match(
      conversation,
      consumedIdentityKeys: consumedLocalIdentityKeys,
    );
    if (matchedLocal != null) {
      consumedLocalIdentityKeys.add(_conversationIdentityKey(matchedLocal));
    }
    for (final localConversation in local) {
      if (identical(localConversation, matchedLocal)) {
        continue;
      }
      if (_shouldCollapsePresentationListItem(
        incoming: conversation,
        item: localConversation,
        current: local,
        ownerDid: ownerDid,
      )) {
        consumedLocalPresentationAliases.add(localConversation.threadId);
      }
    }
    final titledConversation = _mergeConversationTitle(
      refreshed: conversation,
      local: matchedLocal,
    );
    return _mergeConversationPresentationIdentity(
      refreshed: _mergeConversationLifecycle(
        refreshed: _mergeConversationReadState(
          refreshed: _mergeConversationLastMessage(
            refreshed: titledConversation,
            local: matchedLocal,
          ),
          local: matchedLocal,
        ),
        local: matchedLocal,
      ),
      local: matchedLocal,
      ownerDid: ownerDid,
    );
  }).toList();
  final refreshedThreadIds = <String>{
    for (final conversation in refreshed) conversation.threadId,
  };
  final refreshedIdentityKeys = <String>{
    for (final conversation in refreshed)
      _conversationIdentityKey(conversation),
  };
  final localOnly = keepLocalOnly
      ? local
            .where(
              (conversation) =>
                  !consumedLocalIdentityKeys.contains(
                    _conversationIdentityKey(conversation),
                  ) &&
                  !consumedLocalPresentationAliases.contains(
                    conversation.threadId,
                  ) &&
                  !refreshedIdentityKeys.contains(
                    _conversationIdentityKey(conversation),
                  ) &&
                  !refreshedThreadIds.contains(conversation.threadId) &&
                  conversation.lastMessagePreview.trim().isNotEmpty,
            )
            .toList()
      : const <ConversationSummary>[];
  return sortConversationsForPresentation(
    localOnly.isEmpty
        ? mergedRefreshed
        : <ConversationSummary>[...mergedRefreshed, ...localOnly],
  );
}

List<ConversationSummary> _replaceConversationInPresentationList({
  required List<ConversationSummary> current,
  required ConversationSummary incoming,
  required ConversationSummary? matchedLocal,
  required String? ownerDid,
}) {
  final next = <ConversationSummary>[];
  var inserted = false;
  for (final item in current) {
    if (_sameConversationIdentity(item, incoming) ||
        (matchedLocal != null &&
            _sameConversationIdentity(item, matchedLocal)) ||
        _shouldCollapsePresentationListItem(
          incoming: incoming,
          item: item,
          current: current,
          ownerDid: ownerDid,
        )) {
      if (!inserted) {
        next.add(incoming);
        inserted = true;
      }
      continue;
    }
    next.add(item);
  }
  if (!inserted) {
    next.add(incoming);
  }
  return sortConversationsForPresentation(next);
}

class _ConversationMergeIndex {
  _ConversationMergeIndex(
    List<ConversationSummary> conversations, {
    required this.ownerDid,
  }) {
    for (final conversation in conversations) {
      final identity = _nonEmptyKey(_conversationIdentityKey(conversation));
      if (identity != null) {
        _byConversationId.putIfAbsent(identity, () => conversation);
      }
      final threadId = _nonEmptyKey(conversation.threadId);
      if (threadId != null) {
        _byThreadId.putIfAbsent(threadId, () => conversation);
      }
      for (final key in _visibilityKeysFor(conversation)) {
        final normalized = _nonEmptyKey(key);
        if (normalized != null) {
          _byVisibilityKey.putIfAbsent(normalized, () => conversation);
        }
      }
      for (final key in _directTargetKeys(conversation)) {
        _addDirectTarget(key, conversation);
      }
    }
  }

  final Map<String, ConversationSummary> _byConversationId =
      <String, ConversationSummary>{};
  final Map<String, ConversationSummary> _byThreadId =
      <String, ConversationSummary>{};
  final Map<String, ConversationSummary> _byVisibilityKey =
      <String, ConversationSummary>{};
  final Map<String, ConversationSummary> _byDirectTarget =
      <String, ConversationSummary>{};
  final Map<String, int> _directTargetPeerScopedCounts = <String, int>{};
  final Set<String> _ambiguousDirectTargetKeys = <String>{};
  final String? ownerDid;

  ConversationSummary? match(
    ConversationSummary incoming, {
    Set<String> consumedIdentityKeys = const <String>{},
  }) {
    ConversationSummary? candidate = _candidateIfAvailable(
      _byConversationId[_nonEmptyKey(_conversationIdentityKey(incoming))],
      consumedIdentityKeys,
    );
    if (candidate != null) {
      return candidate;
    }
    if (_hasExplicitConversationId(incoming) &&
        !isPeerScopedDirectConversation(incoming)) {
      return null;
    }
    candidate = _candidateIfAvailable(
      _byThreadId[_nonEmptyKey(incoming.threadId)],
      consumedIdentityKeys,
    );
    if (candidate != null) {
      return candidate;
    }
    if (!isPeerScopedDirectConversation(incoming)) {
      for (final key in incoming.visibilityKeys) {
        candidate = _aliasCandidateIfAvailable(
          _byVisibilityKey[_nonEmptyKey(key)],
          incoming,
          consumedIdentityKeys,
          ownerDid,
        );
        if (candidate != null) {
          return candidate;
        }
      }
    }
    if (incoming.isGroup) {
      return null;
    }
    for (final key in _directTargetKeys(incoming)) {
      candidate = _aliasCandidateIfAvailable(
        _directTargetCandidate(key),
        incoming,
        consumedIdentityKeys,
        ownerDid,
      );
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }

  void _addDirectTarget(String key, ConversationSummary conversation) {
    if (isPeerScopedDirectConversation(conversation)) {
      _directTargetPeerScopedCounts[key] =
          (_directTargetPeerScopedCounts[key] ?? 0) + 1;
    }
    final existing = _byDirectTarget[key];
    if (existing == null) {
      _byDirectTarget[key] = conversation;
      return;
    }
    if (!isPeerScopedDirectConversation(existing) &&
        isPeerScopedDirectConversation(conversation)) {
      _byDirectTarget[key] = conversation;
    }
    if (existing.threadId.trim() != conversation.threadId.trim()) {
      _ambiguousDirectTargetKeys.add(key);
    }
  }

  ConversationSummary? _directTargetCandidate(String key) {
    if ((_directTargetPeerScopedCounts[key] ?? 0) > 1) {
      return null;
    }
    final candidate = _byDirectTarget[key];
    if (candidate == null) {
      return null;
    }
    if (_ambiguousDirectTargetKeys.contains(key) &&
        !isPeerScopedDirectConversation(candidate)) {
      return null;
    }
    return candidate;
  }

  static ConversationSummary? _candidateIfAvailable(
    ConversationSummary? candidate,
    Set<String> consumedIdentityKeys,
  ) {
    if (candidate == null ||
        consumedIdentityKeys.contains(_conversationIdentityKey(candidate))) {
      return null;
    }
    return candidate;
  }

  static ConversationSummary? _aliasCandidateIfAvailable(
    ConversationSummary? candidate,
    ConversationSummary incoming,
    Set<String> consumedIdentityKeys,
    String? ownerDid,
  ) {
    candidate = _candidateIfAvailable(candidate, consumedIdentityKeys);
    if (candidate == null ||
        !_canAliasMatch(candidate, incoming, ownerDid: ownerDid)) {
      return null;
    }
    return candidate;
  }

  static bool _canAliasMatch(
    ConversationSummary candidate,
    ConversationSummary incoming, {
    required String? ownerDid,
  }) {
    if (candidate.threadId.trim() == incoming.threadId.trim()) {
      return true;
    }
    if (_isPeerScopedDirectThread(candidate) &&
        _isPeerScopedDirectThread(incoming)) {
      return false;
    }
    if (_isPeerScopedDirectThread(candidate) ||
        _isPeerScopedDirectThread(incoming)) {
      return _shouldCollapsePresentationAlias(
        incoming,
        candidate,
        ownerDid: ownerDid,
      );
    }
    if (_hasExplicitConversationId(candidate) ||
        _hasExplicitConversationId(incoming)) {
      return _sameConversationIdentity(candidate, incoming);
    }
    return true;
  }

  static bool _isPeerScopedDirectThread(ConversationSummary conversation) {
    return isPeerScopedDirectConversation(conversation);
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

bool _shouldCollapsePresentationAlias(
  ConversationSummary incoming,
  ConversationSummary candidate, {
  String? ownerDid,
}) {
  if (incoming.isGroup || candidate.isGroup) {
    return false;
  }
  final incomingConversationId = _explicitConversationId(incoming);
  final candidateConversationId = _explicitConversationId(candidate);
  if (incomingConversationId != null || candidateConversationId != null) {
    if (isPeerScopedDirectConversation(incoming) &&
        _isLegacyDirectConversationIdForTarget(
          candidateConversationId,
          candidate,
          ownerDid: ownerDid,
        )) {
      return isReplaceableLegacyDirectConversation(
            candidate,
            ownerDid: ownerDid,
          ) &&
          sameDirectPresentationTarget(incoming, candidate);
    }
    if (isPeerScopedDirectConversation(candidate) &&
        _isLegacyDirectConversationIdForTarget(
          incomingConversationId,
          incoming,
          ownerDid: ownerDid,
        )) {
      return isReplaceableLegacyDirectConversation(
            incoming,
            ownerDid: ownerDid,
          ) &&
          sameDirectPresentationTarget(incoming, candidate);
    }
    return incomingConversationId != null &&
        candidateConversationId != null &&
        incomingConversationId == candidateConversationId;
  }
  if (sameConversationThread(incoming, candidate)) {
    return true;
  }
  if (isPeerScopedDirectConversation(incoming) &&
      isPeerScopedDirectConversation(candidate)) {
    return false;
  }
  if (isPeerScopedDirectConversation(incoming)) {
    return isReplaceableLegacyDirectConversation(
          candidate,
          ownerDid: ownerDid,
        ) &&
        sameDirectPresentationTarget(incoming, candidate);
  }
  if (isPeerScopedDirectConversation(candidate)) {
    return isReplaceableLegacyDirectConversation(
          incoming,
          ownerDid: ownerDid,
        ) &&
        sameDirectPresentationTarget(incoming, candidate);
  }
  return false;
}

bool _isLegacyDirectConversationIdForTarget(
  String? conversationId,
  ConversationSummary conversation, {
  required String? ownerDid,
}) {
  final id = conversationId?.trim();
  if (id == null || id.isEmpty) {
    return false;
  }
  final targetDid = conversation.targetDid?.trim();
  if (targetDid == null || targetDid.isEmpty) {
    return false;
  }
  if (id == 'dm:$targetDid') {
    return true;
  }
  final owner = ownerDid?.trim();
  if (owner == null || owner.isEmpty) {
    return false;
  }
  if (id == 'dm:$owner:$targetDid' || id == 'dm:$targetDid:$owner') {
    return true;
  }
  final participants = <String>[owner, targetDid]..sort();
  return id == 'dm:${participants[0]}:${participants[1]}';
}

bool _shouldCollapsePresentationListItem({
  required ConversationSummary incoming,
  required ConversationSummary item,
  required List<ConversationSummary> current,
  required String? ownerDid,
}) {
  if (!_shouldCollapsePresentationAlias(incoming, item, ownerDid: ownerDid)) {
    return false;
  }
  if (isPeerScopedDirectConversation(incoming)) {
    return true;
  }
  if (!isPeerScopedDirectConversation(item)) {
    return false;
  }
  return _matchingPeerScopedPresentationRows(current, alias: incoming).length ==
      1;
}

List<ConversationSummary> _matchingPeerScopedPresentationRows(
  Iterable<ConversationSummary> conversations, {
  required ConversationSummary alias,
}) {
  return conversations
      .where(
        (conversation) =>
            isPeerScopedDirectConversation(conversation) &&
            sameDirectPresentationTarget(conversation, alias),
      )
      .toList(growable: false);
}

ConversationSummary _mergeSelectedConversation({
  required ConversationSummary selected,
  required ConversationSummary incoming,
}) {
  return _mergeConversationLifecycle(
    refreshed: _mergeConversationTitle(
      refreshed: incoming,
      local: selected,
      preferLocalTitle: true,
    ),
    local: selected,
  );
}

ConversationSummary? _matchingConversationForUpsert(
  Iterable<ConversationSummary> conversations,
  ConversationSummary incoming, {
  required String? ownerDid,
}) {
  return _ConversationMergeIndex(
    conversations.toList(),
    ownerDid: ownerDid,
  ).match(incoming);
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
    lastMessageSnapshot: refreshed.lastMessageSnapshot,
  );
}

ConversationSummary _mergeConversationReadState({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  return refreshed;
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

ConversationSummary _mergeConversationPresentationIdentity({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
  required String? ownerDid,
}) {
  if (local == null || sameConversationThread(refreshed, local)) {
    return refreshed;
  }
  if (isPeerScopedDirectConversation(refreshed)) {
    return refreshed;
  }
  if (isPeerScopedDirectConversation(local) &&
      _shouldCollapsePresentationAlias(local, refreshed, ownerDid: ownerDid)) {
    return refreshed.copyWith(
      threadId: local.threadId,
      conversationKey: local.conversationKey,
    );
  }
  return refreshed;
}

ConversationSummary _mergeConversationLastMessage({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  if (local == null) {
    return refreshed;
  }
  final localPreview = local.lastMessagePreview.trim();
  final refreshedPreview = refreshed.lastMessagePreview.trim();
  if (refreshedPreview.isEmpty && localPreview.isNotEmpty) {
    return refreshed.copyWith(
      lastMessagePreview: local.lastMessagePreview,
      lastMessageAt: local.lastMessageAt,
      lastMessagePayloadJson: local.lastMessagePayloadJson,
      lastMessageSnapshot: local.lastMessageSnapshot,
    );
  }
  if (!local.lastMessageAt.isAfter(refreshed.lastMessageAt)) {
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
    lastMessageSnapshot: local.lastMessageSnapshot,
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
