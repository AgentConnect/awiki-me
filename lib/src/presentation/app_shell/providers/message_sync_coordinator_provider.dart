import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../application/message_sync_service.dart';
import '../../../application/models/app_conversation_read_ref.dart';
import '../../../core/performance_logger.dart';
import '../../chat/chat_provider.dart';
import '../../conversation_list/conversation_provider.dart';
import 'session_provider.dart';

const bool _messageSyncCoordinatorTraceEnabled = bool.fromEnvironment(
  'AWIKI_MESSAGE_SYNC_TRACE',
  defaultValue: false,
);

class MessageSyncCoordinatorState {
  const MessageSyncCoordinatorState({
    this.isSyncing = false,
    this.pendingReason,
    this.lastReason,
    this.lastError,
    this.snapshotRequired = false,
  });

  final bool isSyncing;
  final String? pendingReason;
  final String? lastReason;
  final Object? lastError;
  final bool snapshotRequired;

  MessageSyncCoordinatorState copyWith({
    bool? isSyncing,
    Object? pendingReason = _unset,
    Object? lastReason = _unset,
    Object? lastError = _unset,
    bool? snapshotRequired,
  }) {
    return MessageSyncCoordinatorState(
      isSyncing: isSyncing ?? this.isSyncing,
      pendingReason: identical(pendingReason, _unset)
          ? this.pendingReason
          : pendingReason as String?,
      lastReason: identical(lastReason, _unset)
          ? this.lastReason
          : lastReason as String?,
      lastError: identical(lastError, _unset) ? this.lastError : lastError,
      snapshotRequired: snapshotRequired ?? this.snapshotRequired,
    );
  }
}

const Object _unset = Object();

class MessageSyncCoordinator
    extends StateNotifier<MessageSyncCoordinatorState> {
  MessageSyncCoordinator(
    this.ref, {
    this.minInterval = const Duration(seconds: 2),
    this.failureBackoff = const Duration(seconds: 8),
  }) : _sessionEpoch = ref.read(sessionProvider).activeEpoch,
       super(const MessageSyncCoordinatorState()) {
    _sessionSubscription = ref.listen<SessionState>(
      sessionProvider,
      _handleSessionChanged,
    );
  }

  final Ref ref;
  final Duration minInterval;
  final Duration failureBackoff;

  late final ProviderSubscription<SessionState> _sessionSubscription;
  SessionEpoch? _sessionEpoch;
  _ActiveMessageSync? _activeSync;
  _QueuedMessageSync? _queuedAfterActive;
  Timer? _pendingTimer;
  final List<Completer<void>> _pendingCompleters = <Completer<void>>[];
  SessionEpoch? _pendingTimerEpoch;
  DateTime? _lastStartedAt;
  DateTime? _lastFailedAt;
  bool _disposed = false;

  Future<void> requestSync(String reason, {bool immediate = false}) {
    if (_disposed) {
      _messageSyncTrace(
        'request.ignored_disposed',
        fields: <String, Object?>{'reason': reason},
      );
      return Future<void>.value();
    }
    final epoch = _captureCurrentEpoch();
    if (epoch == null) {
      _messageSyncTrace(
        'request.ignored_no_session',
        fields: <String, Object?>{'reason': reason},
      );
      return Future<void>.value();
    }
    final active = _activeSync;
    _messageSyncTrace(
      'request',
      fields: <String, Object?>{
        'reason': reason,
        'immediate': immediate,
        'active': active != null,
        'active_current_epoch': active?.epoch == epoch,
        'pending': state.pendingReason,
      },
    );
    if (active != null) {
      state = state.copyWith(pendingReason: reason);
      final waitsForDifferentEpoch = active.epoch != epoch;
      final completer = waitsForDifferentEpoch ? Completer<void>() : null;
      _queueAfterActive(
        epoch: epoch,
        reason: reason,
        immediate: immediate,
        waiter: completer,
      );
      _messageSyncTrace(
        waitsForDifferentEpoch
            ? 'request.queued_after_stale_active'
            : 'request.coalesced_active',
        fields: <String, Object?>{'reason': reason},
      );
      return completer?.future ?? active.future;
    }
    final now = DateTime.now();
    var delay = Duration.zero;
    if (!immediate) {
      final lastStarted = _lastStartedAt;
      if (lastStarted != null) {
        final remaining = minInterval - now.difference(lastStarted);
        if (remaining > delay) {
          delay = remaining;
        }
      }
      final lastFailed = _lastFailedAt;
      if (lastFailed != null) {
        final remaining = failureBackoff - now.difference(lastFailed);
        if (remaining > delay) {
          delay = remaining;
        }
      }
    }
    if (delay <= Duration.zero) {
      _messageSyncTrace(
        'request.run_now',
        fields: <String, Object?>{'reason': reason},
      );
      return _runSync(reason, epoch);
    }
    _messageSyncTrace(
      'request.schedule',
      fields: <String, Object?>{
        'reason': reason,
        'delay_ms': delay.inMilliseconds,
      },
    );
    state = state.copyWith(pendingReason: reason);
    _pendingTimer?.cancel();
    _pendingTimerEpoch = epoch;
    final completer = Completer<void>();
    _pendingCompleters.add(completer);
    _pendingTimer = Timer(delay, () {
      _pendingTimer = null;
      final waiters = List<Completer<void>>.of(_pendingCompleters);
      _pendingCompleters.clear();
      final timerEpoch = _pendingTimerEpoch;
      _pendingTimerEpoch = null;
      if (_disposed || timerEpoch == null || !_isCurrentEpoch(timerEpoch)) {
        for (final waiter in waiters) {
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }
        return;
      }
      _runSync(reason, timerEpoch).whenComplete(() {
        for (final waiter in waiters) {
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }
      });
    });
    return completer.future;
  }

  Future<void> _runSync(String reason, SessionEpoch epoch) {
    if (_disposed || !_isCurrentEpoch(epoch)) {
      _messageSyncTrace(
        'run.ignored_disposed',
        fields: <String, Object?>{'reason': reason},
      );
      return Future<void>.value();
    }
    final active = _activeSync;
    if (active != null) {
      state = state.copyWith(pendingReason: reason);
      _queueAfterActive(epoch: epoch, reason: reason, immediate: true);
      _messageSyncTrace(
        'run.coalesced_active',
        fields: <String, Object?>{'reason': reason},
      );
      return active.future;
    }
    late final Future<void> operation;
    operation = (() async {
      _lastStartedAt = DateTime.now();
      _messageSyncTrace(
        'run.start',
        fields: <String, Object?>{'reason': reason},
      );
      if (!_isCurrentEpoch(epoch)) {
        return;
      }
      state = state.copyWith(
        isSyncing: true,
        pendingReason: null,
        lastReason: reason,
        lastError: null,
      );
      try {
        final result = await ref
            .read(messageSyncServiceProvider)
            .syncNow(reason: reason);
        if (!_isCurrentEpoch(epoch)) {
          return;
        }
        _messageSyncTrace(
          'run.sync_result',
          fields: <String, Object?>{
            'reason': reason,
            'snapshot_required': result.snapshotRequired,
          },
        );
        state = state.copyWith(
          snapshotRequired: result.snapshotRequired,
          lastError: null,
        );
        if (!result.snapshotRequired) {
          await _hydrateRequiredConversations(
            result.hydrationRequiredConversationIds,
            epoch: epoch,
          );
          if (!_isCurrentEpoch(epoch)) {
            return;
          }
          _messageSyncTrace(
            'run.refresh_fast_local.start',
            fields: <String, Object?>{'reason': reason},
          );
          await ref
              .read(conversationListProvider.notifier)
              .refreshFastLocalAfterCoreCommit();
          if (!_isCurrentEpoch(epoch)) {
            return;
          }
          final conversations = ref
              .read(conversationListProvider)
              .conversations;
          if (!_isCurrentEpoch(epoch)) {
            return;
          }
          _messageSyncTrace(
            'run.prewarm.start',
            fields: <String, Object?>{
              'reason': reason,
              'conversations': conversations.length,
            },
          );
          await ref
              .read(chatThreadsProvider.notifier)
              .prewarmLocalHistoryForConversations(conversations);
          if (!_isCurrentEpoch(epoch)) {
            return;
          }
          await ref
              .read(chatThreadsProvider.notifier)
              .refreshVisibleLocalProjections(force: true);
          if (!_isCurrentEpoch(epoch)) {
            return;
          }
          _messageSyncTrace(
            'run.prewarm.done',
            fields: <String, Object?>{
              'reason': reason,
              'conversations': conversations.length,
            },
          );
        }
      } catch (error) {
        _messageSyncTrace(
          'run.failed',
          fields: <String, Object?>{
            'reason': reason,
            'error_type': error.runtimeType,
          },
        );
        if (!_isCurrentEpoch(epoch)) {
          return;
        }
        _lastFailedAt = DateTime.now();
        state = state.copyWith(lastError: error);
      } finally {
        if (identical(_activeSync?.future, operation)) {
          _activeSync = null;
        }
        if (_disposed || !_isCurrentEpoch(epoch)) {
          _messageSyncTrace(
            _disposed ? 'run.finish_disposed' : 'run.finish_stale_epoch',
            fields: <String, Object?>{'reason': reason},
          );
        } else {
          state = state.copyWith(isSyncing: false);
          _messageSyncTrace(
            'run.finish',
            fields: <String, Object?>{
              'reason': reason,
              'pending': state.pendingReason,
            },
          );
        }
        _runQueuedAfterActive();
      }
    })();
    _activeSync = _ActiveMessageSync(epoch: epoch, future: operation);
    AwikiPerformanceLogger.log(
      'message_sync.coordinator.request',
      fields: <String, Object?>{'reason': reason},
      level: AwikiPerformanceLogLevel.verbose,
    );
    return operation;
  }

  Future<void> _hydrateRequiredConversations(
    Iterable<String> conversationIds, {
    required SessionEpoch epoch,
  }) async {
    final normalizedIds = <String>{
      for (final conversationId in conversationIds)
        if (conversationId.trim().isNotEmpty) conversationId.trim(),
    };
    if (normalizedIds.isEmpty) {
      return;
    }
    final sync = ref.read(messageSyncServiceProvider);
    if (sync is! ConversationMessageSyncService) {
      _messageSyncTrace(
        'run.hydration.unsupported',
        fields: <String, Object?>{'conversations': normalizedIds.length},
      );
      throw UnsupportedError(
        'Reliable message sync requires conversation hydration support.',
      );
    }
    final conversationSync = sync as ConversationMessageSyncService;
    _messageSyncTrace(
      'run.hydration.start',
      fields: <String, Object?>{'conversations': normalizedIds.length},
    );
    var completed = 0;
    for (final conversationId in normalizedIds) {
      if (!_isCurrentEpoch(epoch)) {
        return;
      }
      try {
        await _hydrateConversationUntilCurrent(
          conversationSync,
          conversationId,
          epoch: epoch,
        );
        completed += 1;
      } catch (error) {
        _messageSyncTrace(
          'run.hydration.failed',
          fields: <String, Object?>{
            'conversation_hash': AwikiPerformanceLogger.safeHash(
              conversationId,
            ),
            'error_type': error.runtimeType,
          },
        );
      }
    }
    _messageSyncTrace(
      'run.hydration.done',
      fields: <String, Object?>{
        'conversations': normalizedIds.length,
        'completed': completed,
      },
    );
  }

  Future<void> _hydrateConversationUntilCurrent(
    ConversationMessageSyncService sync,
    String conversationId, {
    required SessionEpoch epoch,
  }) async {
    String? afterServerSeq;
    while (_isCurrentEpoch(epoch)) {
      final page = await sync.syncConversationAfter(
        conversation: AppConversationReadRef.fromConversationId(conversationId),
        afterServerSeq: afterServerSeq,
      );
      if (!page.hasMore) {
        return;
      }
      final next = page.nextAfterServerSeq?.trim();
      if (next == null || next.isEmpty || next == afterServerSeq) {
        throw StateError('conversation_hydration_cursor_stalled');
      }
      afterServerSeq = next;
    }
  }

  SessionEpoch? _captureCurrentEpoch() {
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null || epoch != _sessionEpoch) {
      return null;
    }
    return epoch;
  }

  bool _isCurrentEpoch(SessionEpoch epoch) {
    return !_disposed &&
        epoch == _sessionEpoch &&
        epoch.matches(ref.read(sessionProvider));
  }

  void _handleSessionChanged(SessionState? previous, SessionState next) {
    final nextEpoch = next.activeEpoch;
    if (nextEpoch == _sessionEpoch) {
      return;
    }
    _sessionEpoch = nextEpoch;
    _lastStartedAt = null;
    _lastFailedAt = null;
    _cancelPendingTimerAndCompleteWaiters();
    _completeQueuedWaiters(_queuedAfterActive);
    _queuedAfterActive = null;
    if (!_disposed) {
      state = const MessageSyncCoordinatorState();
    }
  }

  void _queueAfterActive({
    required SessionEpoch epoch,
    required String reason,
    required bool immediate,
    Completer<void>? waiter,
  }) {
    final queued = _queuedAfterActive;
    if (queued == null || queued.epoch != epoch) {
      _completeQueuedWaiters(queued);
      _queuedAfterActive = _QueuedMessageSync(
        epoch: epoch,
        reason: reason,
        immediate: immediate,
        waiters: waiter == null
            ? <Completer<void>>[]
            : <Completer<void>>[waiter],
      );
      return;
    }
    queued.reason = reason;
    queued.immediate = queued.immediate || immediate;
    if (waiter != null) {
      queued.waiters.add(waiter);
    }
  }

  void _runQueuedAfterActive() {
    if (_disposed || _activeSync != null) {
      return;
    }
    final queued = _queuedAfterActive;
    _queuedAfterActive = null;
    if (queued == null) {
      return;
    }
    if (!_isCurrentEpoch(queued.epoch)) {
      _completeQueuedWaiters(queued);
      return;
    }
    final operation = requestSync(queued.reason, immediate: queued.immediate);
    operation.whenComplete(() => _completeQueuedWaiters(queued));
  }

  void _cancelPendingTimerAndCompleteWaiters() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingTimerEpoch = null;
    for (final waiter in _pendingCompleters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _pendingCompleters.clear();
  }

  void _completeQueuedWaiters(_QueuedMessageSync? queued) {
    if (queued == null) {
      return;
    }
    for (final waiter in queued.waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSubscription.close();
    _cancelPendingTimerAndCompleteWaiters();
    _completeQueuedWaiters(_queuedAfterActive);
    _queuedAfterActive = null;
    super.dispose();
  }
}

class _ActiveMessageSync {
  const _ActiveMessageSync({required this.epoch, required this.future});

  final SessionEpoch epoch;
  final Future<void> future;
}

class _QueuedMessageSync {
  _QueuedMessageSync({
    required this.epoch,
    required this.reason,
    required this.immediate,
    required this.waiters,
  });

  final SessionEpoch epoch;
  String reason;
  bool immediate;
  final List<Completer<void>> waiters;
}

void _messageSyncTrace(
  String event, {
  Map<String, Object?> fields = const <String, Object?>{},
}) {
  if (!_messageSyncCoordinatorTraceEnabled) {
    return;
  }
  final details = <String>[];
  for (final entry in fields.entries) {
    final value = entry.value;
    if (value != null) {
      details.add('${entry.key}=${_collapseMessageSyncTrace(value)}');
    }
  }
  debugPrint(
    details.isEmpty
        ? '[awiki_me][message_sync_trace] event=$event'
        : '[awiki_me][message_sync_trace] event=$event ${details.join(' ')}',
  );
}

String _collapseMessageSyncTrace(Object value) {
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

final messageSyncCoordinatorProvider =
    StateNotifierProvider<MessageSyncCoordinator, MessageSyncCoordinatorState>(
      (ref) => MessageSyncCoordinator(ref),
    );
