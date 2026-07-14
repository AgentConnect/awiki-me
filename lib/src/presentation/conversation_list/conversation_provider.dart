import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/agent/agent_control_projection.dart';
import '../../application/conversation_service.dart';
import '../../application/models/app_thread_read_watermark.dart';
import '../../application/models/conversation_patch.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/services/notification_facade.dart';
import '../agents/agents_provider.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../profile/peer_display_profile_provider.dart';
import 'conversation_list_ordering.dart';

const bool _conversationTraceEnabled = bool.fromEnvironment(
  'AWIKI_CONVERSATION_TRACE',
  defaultValue: false,
);

enum ConversationListLoadState { initializing, ready, stale, error }

class ConversationListState {
  factory ConversationListState({
    List<ConversationSummary> conversations = const <ConversationSummary>[],
    ConversationListLoadState loadState = ConversationListLoadState.ready,
    int version = 0,
    String? errorCode,
  }) {
    final entitiesById = <String, ConversationSummary>{};
    final orderedIds = <String>[];
    for (final conversation in conversations) {
      final conversationId = conversation.conversationId.trim();
      if (conversationId.isEmpty) {
        throw StateError('canonical_conversation_id_missing');
      }
      if (entitiesById.containsKey(conversationId)) {
        throw StateError('duplicate_canonical_conversation_id');
      }
      entitiesById[conversationId] = conversation;
      orderedIds.add(conversationId);
    }
    return ConversationListState._(
      entitiesById: Map<String, ConversationSummary>.unmodifiable(entitiesById),
      orderedIds: List<String>.unmodifiable(orderedIds),
      conversations: List<ConversationSummary>.unmodifiable(conversations),
      loadState: loadState,
      version: version,
      errorCode: errorCode,
    );
  }

  const ConversationListState._({
    required this.entitiesById,
    required this.orderedIds,
    required List<ConversationSummary> conversations,
    required this.loadState,
    required this.version,
    required this.errorCode,
  }) : _conversations = conversations;

  final Map<String, ConversationSummary> entitiesById;
  final List<String> orderedIds;
  final List<ConversationSummary> _conversations;
  final ConversationListLoadState loadState;
  final int version;
  final String? errorCode;

  List<ConversationSummary> get conversations => _conversations;

  bool get isLoading =>
      loadState == ConversationListLoadState.initializing ||
      loadState == ConversationListLoadState.stale;

  int get unreadCount =>
      conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);

  ConversationListState copyWith({
    List<ConversationSummary>? conversations,
    bool? isLoading,
    ConversationListLoadState? loadState,
    int? version,
    Object? errorCode = _conversationListStateUnset,
  }) {
    final nextConversations = conversations ?? this.conversations;
    final nextLoadState =
        loadState ??
        (isLoading == null
            ? this.loadState
            : isLoading
            ? (nextConversations.isEmpty
                  ? ConversationListLoadState.initializing
                  : ConversationListLoadState.stale)
            : ConversationListLoadState.ready);
    return ConversationListState(
      conversations: nextConversations,
      loadState: nextLoadState,
      version: version ?? this.version,
      errorCode: identical(errorCode, _conversationListStateUnset)
          ? this.errorCode
          : errorCode as String?,
    );
  }
}

const Object _conversationListStateUnset = Object();

class ConversationListController extends StateNotifier<ConversationListState> {
  ConversationListController(
    this.ref, {
    this.refreshTimeout = _defaultRefreshTimeout,
  }) : super(
         ConversationListState(
           loadState: ConversationListLoadState.initializing,
         ),
       );

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
        state.copyWith(isLoading: true, errorCode: null),
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
        state.copyWith(isLoading: true, errorCode: null),
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
          state.copyWith(
            loadState: ConversationListLoadState.error,
            errorCode: 'conversation_load_timeout',
          ),
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
      state.copyWith(isLoading: true, errorCode: null),
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
            loadState: ConversationListLoadState.ready,
            errorCode: null,
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
        await _loadCachedPeerProfiles(session.did, conversations);
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
      await _loadCachedPeerProfiles(session.did, conversations);
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
          state.copyWith(
            loadState: ConversationListLoadState.error,
            errorCode: 'conversation_load_failed',
          ),
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
    await _loadCachedPeerProfiles(ownerDid, enriched);
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
    await _loadCachedPeerProfiles(ownerDid, conversations);
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
        loadState: ConversationListLoadState.stale,
        errorCode: null,
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

  Future<void> _loadCachedPeerProfiles(
    String ownerDid,
    Iterable<ConversationSummary> conversations,
  ) async {
    final items = conversations.toList(growable: false);
    final controller = ref.read(peerDisplayProfileProvider.notifier);
    await controller.loadCached(
      ownerDid: ownerDid,
      dids: items
          .where((conversation) => !conversation.isGroup)
          .map((conversation) => conversation.targetDid ?? ''),
      peerPersonaIdsByDid: <String, String>{
        for (final conversation in items)
          if (!conversation.isGroup &&
              (conversation.targetDid?.trim().isNotEmpty ?? false) &&
              (conversation.peerPersonaId?.trim().isNotEmpty ?? false))
            conversation.targetDid!.trim(): conversation.peerPersonaId!.trim(),
      },
    );
    controller.registerLocalNotes(
      ownerDid: ownerDid,
      localNotesByPersonaId: <String, String>{
        for (final conversation in items)
          if (!conversation.isGroup &&
              (conversation.peerPersonaId?.trim().isNotEmpty ?? false))
            conversation.peerPersonaId!.trim():
                conversation.peerLocalNote?.trim() ?? '',
      },
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
        _applyPatchUpsert(item, version: patch.version);
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
      _lastPatchVersion = state.version;
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
      _publishConversationListState(
        state.copyWith(version: patch.version),
        source: 'patch_reset.version',
        updateBadge: false,
      );
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
        loadState: ConversationListLoadState.ready,
        version: patch.version,
        errorCode: null,
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

  void _applyPatchUpsert(
    ConversationSummary conversation, {
    required int version,
  }) {
    if (_isLocallyHidden(conversation)) {
      _publishConversationListState(
        state.copyWith(version: version),
        source: 'patch_upsert.hidden_version',
        updateBadge: false,
      );
      return;
    }
    _snapshotBootstrapActive = false;
    _upsertConversation(conversation, source: 'patch_upsert', version: version);
  }

  void _applyPatchRemove(ConversationListPatch patch) {
    final conversationId = patch.conversationId?.trim();
    if (conversationId == null || conversationId.isEmpty) {
      return;
    }
    final next = state.conversations
        .where((item) => item.conversationId != conversationId)
        .toList(growable: false);
    if (next.length == state.conversations.length) {
      _publishConversationListState(
        state.copyWith(version: patch.version),
        source: 'patch_remove.version',
        updateBadge: false,
      );
      return;
    }
    final beforeUnread = state.unreadCount;
    _publishConversationListState(
      state.copyWith(
        conversations: next,
        loadState: ConversationListLoadState.ready,
        version: patch.version,
        errorCode: null,
      ),
      source: 'patch_remove',
    );
    _snapshotBootstrapActive = false;
    _trace(
      'state.patch_remove',
      fields: <String, Object?>{
        'before_unread': beforeUnread,
        'after_unread': state.unreadCount,
        'conversation_hash': _safeHash(conversationId),
      },
    );
    if (ref.read(selectedConversationProvider) == conversationId) {
      ref.read(selectedConversationProvider.notifier).clearSelection();
    }
  }

  bool _applyPatchReorder(ConversationListPatch patch) {
    final conversationId = patch.conversationId?.trim();
    if (conversationId == null || conversationId.isEmpty) {
      return false;
    }
    final current = state.conversations.toList(growable: true);
    final currentIndex = current.indexWhere(
      (item) => item.conversationId == conversationId,
    );
    if (currentIndex < 0) {
      return false;
    }
    final item = current.removeAt(currentIndex);
    final targetIndex = (patch.index ?? 0).clamp(0, current.length);
    current.insert(targetIndex, item);
    _publishConversationListState(
      state.copyWith(
        conversations: sortConversationsForPresentation(current),
        loadState: ConversationListLoadState.ready,
        version: patch.version,
        errorCode: null,
      ),
      source: 'patch_reorder',
    );
    _snapshotBootstrapActive = false;
    _trace(
      'state.patch_reorder',
      fields: <String, Object?>{
        'unread': state.unreadCount,
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
      version: repair.version,
    );
    if (applied && repair.version > _lastPatchVersion) {
      _lastPatchVersion = state.version;
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
    int? version,
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
      if (version != null && version != state.version) {
        _publishConversationListState(
          state.copyWith(version: version),
          source: '${badgeSource ?? label}.version',
          updateBadge: false,
        );
      }
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
        loadState: ConversationListLoadState.ready,
        version: version,
        errorCode: null,
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

  Future<ConversationSummary> commitConversationId(
    String conversationId,
  ) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    final canonicalId = conversationId.trim();
    if (canonicalId.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'must not be empty',
      );
    }

    _locallyHiddenConversationKeys.remove(canonicalId);
    final conversationService = ref.read(conversationServiceProvider);
    await conversationService.ensureConversationInRecents(
      ownerDid: session.did,
      conversationId: canonicalId,
    );
    final conversations = await conversationService
        .listConversationSummariesFast(ownerDid: session.did);
    final matches = conversations
        .where((item) => item.conversationId == canonicalId)
        .toList(growable: false);
    if (matches.length != 1) {
      throw StateError('canonical_conversation_projection_missing');
    }
    final conversation = matches.single;
    await _loadCachedPeerProfiles(session.did, <ConversationSummary>[
      conversation,
    ]);
    _upsertConversation(
      conversation,
      source: 'canonical_conversation_committed',
    );
    return conversation;
  }

  Future<void> restoreConversation(ConversationSummary conversation) async {
    await commitConversationId(conversation.conversationId);
  }

  void restoreConversationBestEffort(ConversationSummary conversation) {
    unawaited(
      commitConversationId(
        conversation.conversationId,
      ).then<void>((_) {}, onError: (_) {}),
    );
  }

  void upsertConversation(ConversationSummary conversation) {
    if (_isLocallyHidden(conversation)) {
      return;
    }
    if (_canUpsertConversationImmediately(conversation)) {
      _upsertConversation(conversation, source: 'upsert_public');
    }
    unawaited(
      _normalizeAndUpsertConversation(
        conversation,
        source: 'upsert_public_normalized',
      ).catchError((_) {}),
    );
  }

  Future<void> _normalizeAndUpsertConversation(
    ConversationSummary conversation, {
    String source = 'upsert_normalized',
  }) async {
    final normalized = await _normalizeConversationForRecents(conversation);
    if (normalized == null) {
      return;
    }
    if (_isLocallyHidden(normalized)) {
      return;
    }
    _upsertConversation(normalized, source: source);
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
    String source = 'upsert',
    int? version,
  }) {
    if (_isLocallyHidden(conversation)) {
      return;
    }
    final existing = _matchingConversationForUpsert(
      state.conversations,
      conversation,
      ownerDid: _currentOwnerDid,
    );
    final mergedConversation = _applyReadPresentation(
      _mergeConversationLifecycle(
        refreshed: _mergeConversationReadState(
          refreshed: _mergeConversationLastMessage(
            refreshed: conversation,
            local: existing,
          ),
          local: existing,
        ),
        local: existing,
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
      if (version != null && version != state.version) {
        _publishConversationListState(
          state.copyWith(version: version),
          source: '$source.version',
          updateBadge: false,
        );
      }
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
      state.copyWith(
        conversations: merged,
        loadState: ConversationListLoadState.ready,
        version: version,
        errorCode: null,
      ),
      source: source,
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
      _upsertConversation(conversation, source: 'delete_rollback');
      rethrow;
    }
    final selected = ref.read(selectedConversationProvider);
    if (selected == conversation.conversationId) {
      ref.read(selectedConversationProvider.notifier).clearSelection();
    }
    await _updateBadgeCountBestEffort(
      state.unreadCount,
      source: 'delete_from_recents',
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

  Future<void> clear() async {
    _resetLocalState();
    await _cancelPatchSubscription();
    await _updateBadgeCountBestEffort(0, source: 'clear');
  }

  void clearLocal() {
    _resetLocalState();
    unawaited(_cancelPatchSubscription());
    unawaited(_updateBadgeCountBestEffort(0, source: 'clear'));
  }

  void _resetLocalState() {
    _refreshGeneration += 1;
    _refreshOperation = null;
    _refreshOperationFastLocal = false;
    _snapshotBootstrapActive = false;
    _snapshotBootstrapAllowedGeneration = null;
    _locallyHiddenConversationKeys.clear();
    _readPresentation.clear();
    state = ConversationListState();
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
    _locallyHiddenConversationKeys[conversation.conversationId] = hiddenAt;
  }

  void _removeHiddenKeysFor(ConversationSummary conversation) {
    _locallyHiddenConversationKeys.remove(conversation.conversationId);
  }

  bool _isLocallyHidden(ConversationSummary conversation) {
    final hiddenAt = _latestLocalHiddenAt(conversation);
    return hiddenAt != null && !conversation.lastMessageAt.isAfter(hiddenAt);
  }

  void _removeConversationLocally(ConversationSummary conversation) {
    final current = state.conversations;
    final next = current
        .where((item) => item.conversationId != conversation.conversationId)
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
    return _locallyHiddenConversationKeys[conversation.conversationId];
  }

  String? get _currentOwnerDid => ref.read(sessionProvider).session?.did;

  ConversationSummary _applyReadPresentation(
    ConversationSummary conversation, {
    required String? ownerDid,
  }) {
    return _readPresentation.project(conversation, ownerDid: ownerDid);
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
      first.peerPersonaId == second.peerPersonaId &&
      first.peerLocalNote == second.peerLocalNote &&
      first.canonicalGroupDid == second.canonicalGroupDid &&
      first.groupId == second.groupId &&
      first.avatarUri == second.avatarUri &&
      first.avatarSeed == second.avatarSeed &&
      first.lastMessagePayloadJson == second.lastMessagePayloadJson &&
      _sameLastMessageSnapshot(
        first.lastMessageSnapshot,
        second.lastMessageSnapshot,
      ) &&
      first.conversationKey == second.conversationKey &&
      first.peerLifecycleState == second.peerLifecycleState &&
      first.resolutionState == second.resolutionState;
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
      first.senderPeerPersonaId == second.senderPeerPersonaId &&
      first.senderDidSnapshot == second.senderDidSnapshot &&
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
    final state = _findStateFor(conversation, ownerDid: ownerDid);
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
  }) {
    final state = _stateFor(conversation, ownerDid: ownerDid);
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
  }) {
    final existing = _findStateFor(conversation, ownerDid: ownerDid);
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
  }) {
    for (var index = _states.length - 1; index >= 0; index -= 1) {
      final state = _states[index];
      if (state.matches(conversation, ownerDid: ownerDid)) {
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

  bool matches(ConversationSummary candidate, {required String? ownerDid}) {
    return _sameReadOwner(ownerDid ?? this.ownerDid, this.ownerDid) &&
        conversation.conversationId == candidate.conversationId;
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
        this.conversation.conversationId != conversation.conversationId) {
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

List<ConversationSummary> _mergeConversationRefresh({
  required List<ConversationSummary> refreshed,
  required List<ConversationSummary> local,
  required String? ownerDid,
  bool keepLocalOnly = true,
}) {
  final localById = <String, ConversationSummary>{
    for (final conversation in local) conversation.conversationId: conversation,
  };
  final refreshedIds = <String>{};
  final merged = <ConversationSummary>[];
  for (final conversation in refreshed) {
    refreshedIds.add(conversation.conversationId);
    final previous = localById[conversation.conversationId];
    merged.add(
      _mergeConversationLifecycle(
        refreshed: _mergeConversationReadState(
          refreshed: _mergeConversationLastMessage(
            refreshed: conversation,
            local: previous,
          ),
          local: previous,
        ),
        local: previous,
      ),
    );
  }
  if (keepLocalOnly) {
    for (final conversation in local) {
      if (!refreshedIds.contains(conversation.conversationId) &&
          conversation.lastMessagePreview.trim().isNotEmpty) {
        merged.add(conversation);
      }
    }
  }
  return sortConversationsForPresentation(merged);
}

List<ConversationSummary> _replaceConversationInPresentationList({
  required List<ConversationSummary> current,
  required ConversationSummary incoming,
  required ConversationSummary? matchedLocal,
  required String? ownerDid,
}) {
  final next = <ConversationSummary>[
    for (final item in current)
      if (item.conversationId != incoming.conversationId) item,
    incoming,
  ];
  return sortConversationsForPresentation(next);
}

ConversationSummary? _matchingConversationForUpsert(
  Iterable<ConversationSummary> conversations,
  ConversationSummary incoming, {
  required String? ownerDid,
}) {
  for (final conversation in conversations) {
    if (conversation.conversationId == incoming.conversationId) {
      return conversation;
    }
  }
  return null;
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

final conversationListProvider =
    StateNotifierProvider<ConversationListController, ConversationListState>(
      (ref) => ConversationListController(ref),
    );
