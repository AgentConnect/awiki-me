import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../core/performance_logger.dart';
import '../../conversation_list/conversation_provider.dart';

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
  }) : super(const MessageSyncCoordinatorState());

  final Ref ref;
  final Duration minInterval;
  final Duration failureBackoff;

  Future<void>? _activeSync;
  Timer? _pendingTimer;
  final List<Completer<void>> _pendingCompleters = <Completer<void>>[];
  DateTime? _lastStartedAt;
  DateTime? _lastFailedAt;

  Future<void> requestSync(String reason, {bool immediate = false}) {
    final active = _activeSync;
    if (active != null) {
      state = state.copyWith(pendingReason: reason);
      return active;
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
      return _runSync(reason);
    }
    state = state.copyWith(pendingReason: reason);
    _pendingTimer?.cancel();
    final completer = Completer<void>();
    _pendingCompleters.add(completer);
    _pendingTimer = Timer(delay, () {
      _pendingTimer = null;
      final waiters = List<Completer<void>>.of(_pendingCompleters);
      _pendingCompleters.clear();
      _runSync(reason).whenComplete(() {
        for (final waiter in waiters) {
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }
      });
    });
    return completer.future;
  }

  Future<void> _runSync(String reason) {
    final active = _activeSync;
    if (active != null) {
      state = state.copyWith(pendingReason: reason);
      return active;
    }
    late final Future<void> operation;
    operation = (() async {
      _lastStartedAt = DateTime.now();
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
        state = state.copyWith(
          snapshotRequired: result.snapshotRequired,
          lastError: null,
        );
        if (!result.snapshotRequired) {
          await ref.read(conversationListProvider.notifier).refreshFastLocal();
        }
      } catch (error) {
        _lastFailedAt = DateTime.now();
        state = state.copyWith(lastError: error);
      } finally {
        state = state.copyWith(isSyncing: false);
        if (identical(_activeSync, operation)) {
          _activeSync = null;
        }
        final pending = state.pendingReason;
        if (pending != null) {
          unawaited(requestSync(pending));
        }
      }
    })();
    _activeSync = operation;
    AwikiPerformanceLogger.log(
      'message_sync.coordinator.request',
      fields: <String, Object?>{'reason': reason},
      level: AwikiPerformanceLogLevel.verbose,
    );
    return operation;
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    for (final waiter in _pendingCompleters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _pendingCompleters.clear();
    super.dispose();
  }
}

final messageSyncCoordinatorProvider =
    StateNotifierProvider<MessageSyncCoordinator, MessageSyncCoordinatorState>(
      (ref) => MessageSyncCoordinator(ref),
    );
