import 'dart:async';
import 'dart:ui' as ui;

import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../../app/app_services.dart';
import '../../../app/app_locale.dart';
import '../../../application/messaging_service.dart';
import '../../../application/models/message_sync_diagnostics.dart';
import '../../../application/models/remote_push_sync_receipt.dart';
import '../../../application/ports/message_sync_core_port.dart';
import '../../../application/ports/remote_push_sync_port.dart';
import '../../../application/tenant/app_tenant.dart';
import '../../../core/performance_logger.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/notification_target.dart';
import '../../../l10n/app_message.dart';
import '../../agents/agents_provider.dart';
import '../../conversation_list/conversation_peer_classifier.dart';
import '../../profile/peer_display_profile_provider.dart';
import '../../shared/formatters/display_formatters.dart';
import '../../shared/formatters/localized_ui_formatters.dart';
import '../../conversation_list/conversation_provider.dart';
import '../../devices/devices_provider.dart';
import 'agent_terminal_notification_provider.dart';
import 'app_lifecycle_provider.dart';
import 'session_provider.dart';

const bool _messageSyncCoordinatorTraceEnabled = bool.fromEnvironment(
  'AWIKI_MESSAGE_SYNC_TRACE',
  defaultValue: false,
);

enum MessageSyncCoordinatorStatus {
  idle,
  syncing,
  recoveryRequired,
  recovering,
  retryableFailure,
  projectionRefreshFailed,
  authRevoked,
}

class MessageSyncCoordinatorState {
  const MessageSyncCoordinatorState({
    this.status = MessageSyncCoordinatorStatus.idle,
    this.pendingReason,
    this.lastReason,
    this.lastError,
    this.lastStatus,
    this.lastSuccessAt,
    this.mode = AppMessageSyncMode.uninitialized,
    this.pendingMutationCount = 0,
    this.dirtyDomains = const <AppMessageSyncDirtyDomain>[],
    this.retryState = AppMessageSyncRetryState.none,
    this.nextRetryAt,
    this.diagnosticsRefreshAttemptSequence = 0,
    this.diagnosticsRefreshSuccessSequence = 0,
    this.diagnosticsRefreshedAt,
    this.firstRetryableFailureAt,
    this.lastFailureAt,
    this.lastFailureStage,
    this.lastFailureCategory,
    this.lastFailureCode,
    this.lastFailureHttpStatus,
    this.retryableFailureSurfaceAt,
    this.retryableFailureVisible = false,
    this.consecutiveRetryableFailures = 0,
    this.automaticRetryPending = false,
  });

  final MessageSyncCoordinatorStatus status;
  final String? pendingReason;
  final String? lastReason;
  final Object? lastError;
  final MessageSyncStatus? lastStatus;
  final DateTime? lastSuccessAt;
  final AppMessageSyncMode mode;
  final int pendingMutationCount;
  final List<AppMessageSyncDirtyDomain> dirtyDomains;
  final AppMessageSyncRetryState retryState;
  final DateTime? nextRetryAt;
  final int diagnosticsRefreshAttemptSequence;
  final int diagnosticsRefreshSuccessSequence;
  final DateTime? diagnosticsRefreshedAt;
  final DateTime? firstRetryableFailureAt;
  final DateTime? lastFailureAt;
  final AppMessageSyncFailureStage? lastFailureStage;
  final AppMessageSyncFailureCategory? lastFailureCategory;
  final String? lastFailureCode;
  final int? lastFailureHttpStatus;
  final DateTime? retryableFailureSurfaceAt;
  final bool retryableFailureVisible;
  final int consecutiveRetryableFailures;
  final bool automaticRetryPending;

  bool get isSyncing =>
      status == MessageSyncCoordinatorStatus.syncing ||
      status == MessageSyncCoordinatorStatus.recovering;

  bool get recoveryRequired =>
      status == MessageSyncCoordinatorStatus.recoveryRequired;

  bool get isAuthRevoked => status == MessageSyncCoordinatorStatus.authRevoked;

  bool get shouldSurfaceRetryableFailure =>
      status == MessageSyncCoordinatorStatus.retryableFailure &&
      retryableFailureVisible;

  AppMessageSyncSafeDiagnostics get safeDiagnostics =>
      AppMessageSyncSafeDiagnostics(
        refreshAttemptSequence: diagnosticsRefreshAttemptSequence,
        refreshSuccessSequence: diagnosticsRefreshSuccessSequence,
        refreshedAt: diagnosticsRefreshedAt,
        lastSuccessAt: lastSuccessAt,
        mode: mode,
        pendingMutationCount: pendingMutationCount,
        dirtyDomains: List<AppMessageSyncDirtyDomain>.unmodifiable(
          dirtyDomains,
        ),
        retryState: retryState,
        nextRetryAt: nextRetryAt,
        firstRetryableFailureAt: firstRetryableFailureAt,
        lastFailureAt: lastFailureAt,
        lastFailureStage: lastFailureStage,
        lastFailureCategory: lastFailureCategory,
        lastFailureCode: lastFailureCode,
        lastFailureHttpStatus: lastFailureHttpStatus,
        retryableFailureSurfaceAt: retryableFailureSurfaceAt,
        retryableFailureVisible: retryableFailureVisible,
        consecutiveRetryableFailures: consecutiveRetryableFailures,
        automaticRetryPending: automaticRetryPending,
      );

  @Deprecated('Use recoveryRequired.')
  bool get snapshotRequired => recoveryRequired;

  MessageSyncCoordinatorState copyWith({
    MessageSyncCoordinatorStatus? status,
    Object? pendingReason = _unset,
    Object? lastReason = _unset,
    Object? lastError = _unset,
    Object? lastStatus = _unset,
    Object? lastSuccessAt = _unset,
    AppMessageSyncMode? mode,
    int? pendingMutationCount,
    List<AppMessageSyncDirtyDomain>? dirtyDomains,
    AppMessageSyncRetryState? retryState,
    Object? nextRetryAt = _unset,
    int? diagnosticsRefreshAttemptSequence,
    int? diagnosticsRefreshSuccessSequence,
    Object? diagnosticsRefreshedAt = _unset,
    Object? firstRetryableFailureAt = _unset,
    Object? lastFailureAt = _unset,
    Object? lastFailureStage = _unset,
    Object? lastFailureCategory = _unset,
    Object? lastFailureCode = _unset,
    Object? lastFailureHttpStatus = _unset,
    Object? retryableFailureSurfaceAt = _unset,
    bool? retryableFailureVisible,
    int? consecutiveRetryableFailures,
    bool? automaticRetryPending,
  }) {
    return MessageSyncCoordinatorState(
      status: status ?? this.status,
      pendingReason: identical(pendingReason, _unset)
          ? this.pendingReason
          : pendingReason as String?,
      lastReason: identical(lastReason, _unset)
          ? this.lastReason
          : lastReason as String?,
      lastError: identical(lastError, _unset) ? this.lastError : lastError,
      lastStatus: identical(lastStatus, _unset)
          ? this.lastStatus
          : lastStatus as MessageSyncStatus?,
      lastSuccessAt: identical(lastSuccessAt, _unset)
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      mode: mode ?? this.mode,
      pendingMutationCount: pendingMutationCount ?? this.pendingMutationCount,
      dirtyDomains: dirtyDomains ?? this.dirtyDomains,
      retryState: retryState ?? this.retryState,
      nextRetryAt: identical(nextRetryAt, _unset)
          ? this.nextRetryAt
          : nextRetryAt as DateTime?,
      diagnosticsRefreshAttemptSequence:
          diagnosticsRefreshAttemptSequence ??
          this.diagnosticsRefreshAttemptSequence,
      diagnosticsRefreshSuccessSequence:
          diagnosticsRefreshSuccessSequence ??
          this.diagnosticsRefreshSuccessSequence,
      diagnosticsRefreshedAt: identical(diagnosticsRefreshedAt, _unset)
          ? this.diagnosticsRefreshedAt
          : diagnosticsRefreshedAt as DateTime?,
      firstRetryableFailureAt: identical(firstRetryableFailureAt, _unset)
          ? this.firstRetryableFailureAt
          : firstRetryableFailureAt as DateTime?,
      lastFailureAt: identical(lastFailureAt, _unset)
          ? this.lastFailureAt
          : lastFailureAt as DateTime?,
      lastFailureStage: identical(lastFailureStage, _unset)
          ? this.lastFailureStage
          : lastFailureStage as AppMessageSyncFailureStage?,
      lastFailureCategory: identical(lastFailureCategory, _unset)
          ? this.lastFailureCategory
          : lastFailureCategory as AppMessageSyncFailureCategory?,
      lastFailureCode: identical(lastFailureCode, _unset)
          ? this.lastFailureCode
          : lastFailureCode as String?,
      lastFailureHttpStatus: identical(lastFailureHttpStatus, _unset)
          ? this.lastFailureHttpStatus
          : lastFailureHttpStatus as int?,
      retryableFailureSurfaceAt: identical(retryableFailureSurfaceAt, _unset)
          ? this.retryableFailureSurfaceAt
          : retryableFailureSurfaceAt as DateTime?,
      retryableFailureVisible:
          retryableFailureVisible ?? this.retryableFailureVisible,
      consecutiveRetryableFailures:
          consecutiveRetryableFailures ?? this.consecutiveRetryableFailures,
      automaticRetryPending:
          automaticRetryPending ?? this.automaticRetryPending,
    );
  }
}

const Object _unset = Object();

class MessageSyncCoordinator extends StateNotifier<MessageSyncCoordinatorState>
    implements RemotePushSyncPort {
  MessageSyncCoordinator(
    this.ref, {
    this.minInterval = const Duration(seconds: 2),
    this.failureBackoff = const Duration(seconds: 8),
    this.failureSurfaceDelay = const Duration(seconds: 30),
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
  final Duration failureSurfaceDelay;

  late final ProviderSubscription<SessionState> _sessionSubscription;
  SessionEpoch? _sessionEpoch;
  _ActiveMessageSync? _activeSync;
  _QueuedMessageSync? _queuedAfterActive;
  Timer? _pendingTimer;
  final List<Completer<void>> _pendingCompleters = <Completer<void>>[];
  SessionEpoch? _pendingTimerEpoch;
  DateTime? _lastStartedAt;
  DateTime? _lastFailedAt;
  final Set<String> _notifiedCommittedEventIds = <String>{};
  final Set<String> _notifiedCommittedMessageIds = <String>{};
  bool _recoveryRetryPending = false;
  bool _runningRecoveryRetry = false;
  bool _patchReplacementRetryPending = false;
  Timer? _coreDirectedRetryTimer;
  SessionEpoch? _coreDirectedRetryEpoch;
  Timer? _failureSurfaceTimer;
  SessionEpoch? _failureSurfaceEpoch;
  bool _disposed = false;

  void resetForSession() {
    if (_disposed) {
      return;
    }
    _sessionEpoch = ref.read(sessionProvider).activeEpoch;
    _cancelPendingTimerAndCompleteWaiters();
    _completeQueuedWaiters(_queuedAfterActive);
    _queuedAfterActive = null;
    _recoveryRetryPending = false;
    _runningRecoveryRetry = false;
    _patchReplacementRetryPending = false;
    _cancelCoreDirectedRetry();
    _cancelFailureSurfaceTimer();
    _lastStartedAt = null;
    _lastFailedAt = null;
    _notifiedCommittedEventIds.clear();
    _notifiedCommittedMessageIds.clear();
    state = const MessageSyncCoordinatorState();
  }

  Future<void> requestSync(String reason, {bool immediate = false}) {
    return _requestSync(
      reason,
      immediate: immediate,
      policy: _MessageSyncRequestPolicy(),
      remotePushRequest: false,
    ).then<void>((_) {});
  }

  @override
  Future<RemotePushSyncReceipt> requestRemotePushSync() {
    return _requestSync(
      'remote_push',
      immediate: true,
      policy: _MessageSyncRequestPolicy(suppressNotificationPresentation: true),
      remotePushRequest: true,
    );
  }

  Future<RemotePushSyncReceipt> _requestSync(
    String reason, {
    required bool immediate,
    required _MessageSyncRequestPolicy policy,
    required bool remotePushRequest,
  }) {
    if (_disposed ||
        state.status == MessageSyncCoordinatorStatus.authRevoked ||
        ref.read(sessionProvider).session == null) {
      _messageSyncTrace(
        'request.ignored',
        fields: <String, Object?>{
          'reason': reason,
          'disposed': _disposed,
          'status': state.status.name,
          'has_session': ref.read(sessionProvider).session != null,
        },
      );
      return Future<RemotePushSyncReceipt>.value(
        const RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.ignored,
        ),
      );
    }
    final epoch = _captureCurrentEpoch();
    if (epoch == null) {
      _messageSyncTrace(
        'request.ignored_no_session',
        fields: <String, Object?>{'reason': reason},
      );
      return Future<RemotePushSyncReceipt>.value(
        const RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.ignored,
        ),
      );
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
      final sameActiveRun =
          active.epoch == epoch && !active.presentationFinalized;
      if (sameActiveRun) {
        active.policy.merge(
          suppressNotificationPresentation:
              policy.suppressNotificationPresentation,
        );
        if (remotePushRequest) {
          _messageSyncTrace(
            'request.remote_push_joined_active',
            fields: <String, Object?>{'reason': reason},
          );
          return active.future;
        }
      }
      state = state.copyWith(pendingReason: reason);
      final waitsForDifferentEpoch = active.epoch != epoch;
      final waitsForQueuedRun =
          waitsForDifferentEpoch || (remotePushRequest && !sameActiveRun);
      final queuedPolicy = policy.copy();
      if (!waitsForDifferentEpoch) {
        queuedPolicy.merge(
          suppressNotificationPresentation:
              active.policy.suppressNotificationPresentation,
        );
      }
      final queuedFuture = _queueAfterActive(
        epoch: epoch,
        reason: reason,
        immediate: immediate,
        policy: queuedPolicy,
        addWaiter: waitsForQueuedRun,
      );
      _messageSyncTrace(
        waitsForDifferentEpoch
            ? 'request.queued_after_stale_active'
            : 'request.coalesced_active',
        fields: <String, Object?>{'reason': reason},
      );
      return waitsForQueuedRun ? queuedFuture! : active.future;
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
      return _runSync(reason, epoch, policy);
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
      _runSync(reason, timerEpoch, policy).whenComplete(() {
        for (final waiter in waiters) {
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }
      });
    });
    return completer.future.then(
      (_) => const RemotePushSyncReceipt(
        disposition: RemotePushSyncDisposition.ignored,
      ),
    );
  }

  Future<RemotePushSyncReceipt> _runSync(
    String reason,
    SessionEpoch epoch,
    _MessageSyncRequestPolicy policy,
  ) {
    if (_disposed || !_isCurrentEpoch(epoch)) {
      _messageSyncTrace(
        'run.ignored_disposed',
        fields: <String, Object?>{'reason': reason},
      );
      return Future<RemotePushSyncReceipt>.value(
        const RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.staleSession,
        ),
      );
    }
    final active = _activeSync;
    if (active != null) {
      state = state.copyWith(pendingReason: reason);
      final queuedPolicy = policy.copy();
      if (active.epoch == epoch) {
        queuedPolicy.merge(
          suppressNotificationPresentation:
              active.policy.suppressNotificationPresentation,
        );
      }
      _queueAfterActive(
        epoch: epoch,
        reason: reason,
        immediate: true,
        policy: queuedPolicy,
      );
      _messageSyncTrace(
        'run.coalesced_active',
        fields: <String, Object?>{'reason': reason},
      );
      return active.future;
    }
    late final Future<RemotePushSyncReceipt> operation;
    late final _ActiveMessageSync activeSync;
    operation = (() async {
      final sessionFence = _MessageSyncSessionFence.capture(
        ref.read(sessionProvider),
      );
      if (sessionFence == null || !_isCurrentSync(epoch, sessionFence)) {
        return const RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.staleSession,
        );
      }
      final recovering = _runningRecoveryRetry;
      _lastStartedAt = DateTime.now();
      _messageSyncTrace(
        'run.start',
        fields: <String, Object?>{'reason': reason, 'recovering': recovering},
      );
      if (!_isCurrentSync(epoch, sessionFence)) {
        return const RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.staleSession,
        );
      }
      state = state.copyWith(
        status: recovering
            ? MessageSyncCoordinatorStatus.recovering
            : MessageSyncCoordinatorStatus.syncing,
        pendingReason: null,
        lastReason: reason,
        lastError: null,
      );
      var diagnosticsAttempted = false;
      AppMessageSyncDiagnostics? diagnostics;
      var failureStage = AppMessageSyncFailureStage.prepare;
      try {
        await ref.read(conversationListProvider.notifier).ensurePatchReady();
        if (!_isCurrentSync(epoch, sessionFence)) {
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.staleSession,
          );
        }
        _patchReplacementRetryPending = false;
        ref
            .read(conversationListProvider.notifier)
            .recordReliableSyncStartedForCurrentPatchGeneration();
        failureStage = AppMessageSyncFailureStage.coreSync;
        final result = await ref
            .read(messageSyncServiceProvider)
            .syncNow(reason: reason);
        if (!_isCurrentSync(epoch, sessionFence)) {
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.staleSession,
          );
        }
        diagnosticsAttempted = true;
        diagnostics = await _refreshDiagnosticsBestEffort(epoch, sessionFence);
        if (!_isCurrentSync(epoch, sessionFence)) {
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.staleSession,
          );
        }
        _messageSyncTrace(
          'run.sync_result',
          fields: <String, Object?>{
            'reason': reason,
            'status': result.status.name,
            'committed_incoming': result.committedIncomingMessages.length,
          },
        );
        state = state.copyWith(lastStatus: result.status, lastError: null);
        if (result.status != MessageSyncStatus.recoveryRequired) {
          _runningRecoveryRetry = false;
          _recoveryRetryPending = false;
        }
        if (result.status == MessageSyncStatus.retryableFailure) {
          final failureCode =
              result.errorCode ?? 'message_sync_retryable_failure';
          _cancelCoreDirectedRetry();
          _recordRetryableFailure(
            epoch: epoch,
            error: MessageSyncCoordinatorFailure(failureCode),
            policy: policy,
            stage: AppMessageSyncFailureStage.coreSync,
            category: _categoryForOutcomeCode(failureCode),
            code: failureCode,
          );
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.retryableFailure,
          );
        }
        if (result.status == MessageSyncStatus.authRevoked) {
          _recordAuthFailure(
            error: MessageSyncCoordinatorFailure(
              result.errorCode ?? 'message_sync_auth_revoked',
            ),
            stage: AppMessageSyncFailureStage.coreSync,
            code: result.errorCode ?? 'message_sync_auth_revoked',
          );
          _completeQueuedWaiters(
            _queuedAfterActive,
            const RemotePushSyncReceipt(
              disposition: RemotePushSyncDisposition.authRevoked,
            ),
          );
          _queuedAfterActive = null;
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.authRevoked,
          );
        }
        if (result.status == MessageSyncStatus.recoveryRequired) {
          _cancelCoreDirectedRetry();
          _resetRetryableFailureTracking();
          state = state.copyWith(
            status: MessageSyncCoordinatorStatus.recoveryRequired,
          );
          if (!recovering && ref.read(messageSyncV2ReadEnabledProvider)) {
            _recoveryRetryPending = true;
            state = state.copyWith(pendingReason: reason);
            _queueAfterActive(
              epoch: epoch,
              reason: reason,
              immediate: true,
              policy: policy,
            );
          } else {
            _runningRecoveryRetry = false;
          }
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.recoveryRequired,
          );
        }
        _resetRetryableFailureTracking();
        if (diagnostics != null) {
          _reconcileCoreDirectedRetry(epoch, diagnostics);
        }
        state = state.copyWith(lastError: null);

        try {
          activeSync.presentationFinalized = true;
          _dispatchCommittedIncomingNotifications(
            result,
            suppressPresentation: policy.suppressNotificationPresentation,
          );
          await ref.read(devicesProvider.notifier).refreshJoinInbox();
          if (!_isCurrentSync(epoch, sessionFence)) {
            return const RemotePushSyncReceipt(
              disposition: RemotePushSyncDisposition.staleSession,
            );
          }
          await ref
              .read(conversationListProvider.notifier)
              .refreshFastLocalAfterCoreCommit();
          if (!_isCurrentSync(epoch, sessionFence)) {
            return const RemotePushSyncReceipt(
              disposition: RemotePushSyncDisposition.staleSession,
            );
          }
        } catch (error) {
          if (!_isCurrentSync(epoch, sessionFence)) {
            return const RemotePushSyncReceipt(
              disposition: RemotePushSyncDisposition.staleSession,
            );
          }
          _recordProjectionFailure(error);
        }
        return RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.succeeded,
          committedIncomingMessages: result.committedIncomingMessages,
        );
      } catch (error) {
        _messageSyncTrace(
          'run.failed',
          fields: <String, Object?>{
            'reason': reason,
            'error_type': error.runtimeType,
            'error_code': switch (error) {
              MessageSyncCoreFailure(:final code) => code,
              _ => null,
            },
          },
        );
        if (!_isCurrentSync(epoch, sessionFence)) {
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.staleSession,
          );
        }
        if (error is ConversationPatchGenerationReplaced &&
            !_patchReplacementRetryPending) {
          _patchReplacementRetryPending = true;
          state = state.copyWith(lastError: null);
          _queueAfterActive(
            epoch: epoch,
            reason: 'patch_generation_replaced',
            immediate: true,
            policy: policy,
          );
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.retryableFailure,
          );
        }
        if (!diagnosticsAttempted) {
          await _refreshDiagnosticsBestEffort(epoch, sessionFence);
          if (!_isCurrentSync(epoch, sessionFence)) {
            return const RemotePushSyncReceipt(
              disposition: RemotePushSyncDisposition.staleSession,
            );
          }
        }
        _recoveryRetryPending = false;
        _runningRecoveryRetry = false;
        _patchReplacementRetryPending = false;
        _cancelCoreDirectedRetry();
        final failure = _classifyFailure(error, failureStage);
        if (failure.category == AppMessageSyncFailureCategory.auth) {
          _recordAuthFailure(
            error: error,
            stage: failure.stage,
            code: failure.code,
            httpStatus: failure.httpStatus,
          );
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.authRevoked,
          );
        } else {
          _recordRetryableFailure(
            epoch: epoch,
            error: error,
            policy: policy,
            stage: failure.stage,
            category: failure.category,
            code: failure.code,
            httpStatus: failure.httpStatus,
          );
          return const RemotePushSyncReceipt(
            disposition: RemotePushSyncDisposition.retryableFailure,
          );
        }
      } finally {
        if (identical(_activeSync?.future, operation)) {
          _activeSync = null;
        }
        if (_disposed || !_isCurrentEpoch(epoch)) {
          _messageSyncTrace(
            _disposed ? 'run.finish_disposed' : 'run.finish_stale_epoch',
            fields: <String, Object?>{'reason': reason},
          );
        } else if (_isCurrentSync(epoch, sessionFence)) {
          if (state.status == MessageSyncCoordinatorStatus.syncing ||
              state.status == MessageSyncCoordinatorStatus.recovering) {
            state = state.copyWith(status: MessageSyncCoordinatorStatus.idle);
          }
          _messageSyncTrace(
            'run.finish',
            fields: <String, Object?>{
              'reason': reason,
              'pending': state.pendingReason,
            },
          );
          if (_recoveryRetryPending) {
            _recoveryRetryPending = false;
            _runningRecoveryRetry = true;
          }
        }
        _runQueuedAfterActive();
      }
    })();
    activeSync = _ActiveMessageSync(
      epoch: epoch,
      future: operation,
      policy: policy,
    );
    _activeSync = activeSync;
    AwikiPerformanceLogger.log(
      'message_sync.coordinator.request',
      fields: <String, Object?>{'reason': reason},
      level: AwikiPerformanceLogLevel.verbose,
    );
    return operation;
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
    _recoveryRetryPending = false;
    _runningRecoveryRetry = false;
    _patchReplacementRetryPending = false;
    _cancelCoreDirectedRetry();
    _cancelFailureSurfaceTimer();
    _notifiedCommittedEventIds.clear();
    _notifiedCommittedMessageIds.clear();
    _cancelPendingTimerAndCompleteWaiters();
    _completeQueuedWaiters(_queuedAfterActive);
    _queuedAfterActive = null;
    if (!_disposed) {
      state = const MessageSyncCoordinatorState();
    }
  }

  Future<RemotePushSyncReceipt>? _queueAfterActive({
    required SessionEpoch epoch,
    required String reason,
    required bool immediate,
    required _MessageSyncRequestPolicy policy,
    bool addWaiter = false,
  }) {
    final waiter = addWaiter ? Completer<RemotePushSyncReceipt>() : null;
    final queued = _queuedAfterActive;
    if (queued == null || queued.epoch != epoch) {
      _completeQueuedWaiters(queued);
      _queuedAfterActive = _QueuedMessageSync(
        epoch: epoch,
        reason: reason,
        immediate: immediate,
        policy: policy.copy(),
        waiters: waiter == null
            ? <Completer<RemotePushSyncReceipt>>[]
            : <Completer<RemotePushSyncReceipt>>[waiter],
      );
      return waiter?.future;
    }
    queued.reason = reason;
    queued.immediate = queued.immediate || immediate;
    queued.policy.merge(
      suppressNotificationPresentation: policy.suppressNotificationPresentation,
    );
    if (waiter != null) {
      queued.waiters.add(waiter);
    }
    return waiter?.future;
  }

  void _recordRetryableFailure({
    required SessionEpoch epoch,
    required Object error,
    required _MessageSyncRequestPolicy policy,
    required AppMessageSyncFailureStage stage,
    required AppMessageSyncFailureCategory category,
    required String code,
    int? httpStatus,
  }) {
    final now = DateTime.now();
    _lastFailedAt = now;
    final firstFailureAt = state.firstRetryableFailureAt ?? now;
    final surfaceAt = firstFailureAt.add(failureSurfaceDelay);
    final failureVisible = !now.isBefore(surfaceAt);
    final failureCount = state.consecutiveRetryableFailures + 1;
    final scheduleAutomaticRetry = !failureVisible;
    state = state.copyWith(
      status: MessageSyncCoordinatorStatus.retryableFailure,
      lastError: error,
      firstRetryableFailureAt: firstFailureAt,
      lastFailureAt: now,
      lastFailureStage: stage,
      lastFailureCategory: category,
      lastFailureCode: _sanitizeFailureCode(code),
      lastFailureHttpStatus: httpStatus,
      retryableFailureSurfaceAt: surfaceAt,
      retryableFailureVisible: failureVisible,
      consecutiveRetryableFailures: failureCount,
      automaticRetryPending: scheduleAutomaticRetry,
    );
    _scheduleFailureSurface(epoch, firstFailureAt, surfaceAt);
    if (scheduleAutomaticRetry) {
      final queued = _queuedAfterActive;
      if (queued == null) {
        _queueAfterActive(
          epoch: epoch,
          reason: 'automatic_retry',
          immediate: false,
          policy: policy,
        );
      } else if (queued.epoch == epoch) {
        queued.policy.merge(
          suppressNotificationPresentation:
              policy.suppressNotificationPresentation,
        );
      }
    }
  }

  void _resetRetryableFailureTracking() {
    _cancelFailureSurfaceTimer();
    _lastFailedAt = null;
    state = state.copyWith(
      firstRetryableFailureAt: null,
      retryableFailureSurfaceAt: null,
      retryableFailureVisible: false,
      consecutiveRetryableFailures: 0,
      automaticRetryPending: false,
    );
  }

  void _recordAuthFailure({
    required Object error,
    required AppMessageSyncFailureStage stage,
    required String code,
    int? httpStatus,
  }) {
    final now = DateTime.now();
    _cancelPendingTimerAndCompleteWaiters();
    _cancelCoreDirectedRetry();
    _recoveryRetryPending = false;
    _runningRecoveryRetry = false;
    _resetRetryableFailureTracking();
    state = state.copyWith(
      status: MessageSyncCoordinatorStatus.authRevoked,
      pendingReason: null,
      lastError: error,
      lastFailureAt: now,
      lastFailureStage: stage,
      lastFailureCategory: AppMessageSyncFailureCategory.auth,
      lastFailureCode: _sanitizeFailureCode(code),
      lastFailureHttpStatus: httpStatus,
    );
    _completeQueuedWaiters(_queuedAfterActive);
    _queuedAfterActive = null;
  }

  void _recordProjectionFailure(Object error) {
    _messageSyncTrace(
      'run.projection_failed',
      fields: <String, Object?>{'error_type': error.runtimeType},
    );
    state = state.copyWith(
      status: MessageSyncCoordinatorStatus.projectionRefreshFailed,
      lastError: const MessageSyncCoordinatorFailure(
        'message_sync_projection_refresh_failed',
      ),
      lastFailureAt: DateTime.now(),
      lastFailureStage: AppMessageSyncFailureStage.postCommitProjection,
      lastFailureCategory: AppMessageSyncFailureCategory.projection,
      lastFailureCode: 'message_sync_projection_refresh_failed',
      lastFailureHttpStatus: null,
    );
  }

  void _scheduleFailureSurface(
    SessionEpoch epoch,
    DateTime firstFailureAt,
    DateTime surfaceAt,
  ) {
    _failureSurfaceTimer?.cancel();
    _failureSurfaceEpoch = epoch;
    final delay = surfaceAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      state = state.copyWith(retryableFailureVisible: true);
      return;
    }
    _failureSurfaceTimer = Timer(delay, () {
      _failureSurfaceTimer = null;
      final timerEpoch = _failureSurfaceEpoch;
      _failureSurfaceEpoch = null;
      if (_disposed ||
          timerEpoch != epoch ||
          !_isCurrentEpoch(epoch) ||
          state.firstRetryableFailureAt != firstFailureAt) {
        return;
      }
      state = state.copyWith(retryableFailureVisible: true);
    });
  }

  void _cancelFailureSurfaceTimer() {
    _failureSurfaceTimer?.cancel();
    _failureSurfaceTimer = null;
    _failureSurfaceEpoch = null;
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
    final operation = _requestSync(
      queued.reason,
      immediate: queued.immediate,
      policy: queued.policy,
      remotePushRequest: false,
    );
    operation.then(
      (receipt) => _completeQueuedWaiters(queued, receipt),
      onError: (Object _) => _completeQueuedWaiters(
        queued,
        const RemotePushSyncReceipt(
          disposition: RemotePushSyncDisposition.retryableFailure,
        ),
      ),
    );
  }

  void _cancelPendingTimerAndCompleteWaiters() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingTimerEpoch = null;
    _completePendingWaiters();
  }

  bool _isCurrentSession(_MessageSyncSessionFence fence) {
    return !_disposed && fence.matches(ref.read(sessionProvider));
  }

  bool _isCurrentSync(SessionEpoch epoch, _MessageSyncSessionFence fence) {
    return _isCurrentEpoch(epoch) && _isCurrentSession(fence);
  }

  Future<AppMessageSyncDiagnostics?> _refreshDiagnosticsBestEffort(
    SessionEpoch epoch,
    _MessageSyncSessionFence fence,
  ) async {
    if (!_isCurrentSync(epoch, fence)) {
      return null;
    }
    final service = ref.read(messagingServiceProvider);
    if (service is! MessageSyncDiagnosticsService) {
      return null;
    }
    final attemptSequence = state.diagnosticsRefreshAttemptSequence + 1;
    state = state.copyWith(diagnosticsRefreshAttemptSequence: attemptSequence);
    try {
      final diagnostics = await (service as MessageSyncDiagnosticsService)
          .syncDiagnostics();
      if (!_isCurrentSync(epoch, fence)) {
        return null;
      }
      state = state.copyWith(
        lastSuccessAt: diagnostics.lastSuccessAt,
        mode: diagnostics.mode,
        pendingMutationCount: diagnostics.pendingMutationCount,
        dirtyDomains: List<AppMessageSyncDirtyDomain>.unmodifiable(
          diagnostics.dirtyDomains,
        ),
        retryState: diagnostics.retryState,
        nextRetryAt: diagnostics.nextRetryAt,
        diagnosticsRefreshSuccessSequence: attemptSequence,
        diagnosticsRefreshedAt: DateTime.now(),
      );
      return diagnostics;
    } catch (error) {
      _messageSyncTrace(
        'diagnostics.refresh_failed',
        fields: <String, Object?>{'error_type': error.runtimeType},
      );
      return null;
    }
  }

  void _reconcileCoreDirectedRetry(
    SessionEpoch epoch,
    AppMessageSyncDiagnostics diagnostics,
  ) {
    final retryState = diagnostics.retryState;
    final shouldRetry =
        diagnostics.pendingMutationCount > 0 &&
        (retryState == AppMessageSyncRetryState.pending ||
            retryState == AppMessageSyncRetryState.scheduled);
    if (!shouldRetry) {
      _cancelCoreDirectedRetry();
      return;
    }

    final now = DateTime.now();
    final retryAt = retryState == AppMessageSyncRetryState.scheduled
        ? diagnostics.nextRetryAt
        : null;
    final delay = retryAt == null ? minInterval : retryAt.difference(now);
    _coreDirectedRetryTimer?.cancel();
    _coreDirectedRetryEpoch = epoch;
    state = state.copyWith(automaticRetryPending: true);
    _coreDirectedRetryTimer = Timer(
      delay > Duration.zero ? delay : Duration.zero,
      () {
        _coreDirectedRetryTimer = null;
        final retryEpoch = _coreDirectedRetryEpoch;
        _coreDirectedRetryEpoch = null;
        if (_disposed || retryEpoch == null || !_isCurrentEpoch(retryEpoch)) {
          return;
        }
        state = state.copyWith(automaticRetryPending: false);
        unawaited(requestSync('core_directed_retry', immediate: true));
      },
    );
  }

  void _cancelCoreDirectedRetry() {
    _coreDirectedRetryTimer?.cancel();
    _coreDirectedRetryTimer = null;
    _coreDirectedRetryEpoch = null;
  }

  void _dispatchCommittedIncomingNotifications(
    MessageSyncOutcome outcome, {
    required bool suppressPresentation,
  }) {
    if (!ref.read(messageSyncV2ReadEnabledProvider) ||
        outcome.status != MessageSyncStatus.changed) {
      return;
    }
    for (final committed in outcome.committedIncomingMessages) {
      final eventId = committed.eventId.trim();
      final logicalMessageId = committed.logicalMessageId.trim();
      final message = committed.message;
      if (eventId.isEmpty ||
          logicalMessageId.isEmpty ||
          message.isMine ||
          !message.hasRenderableContent) {
        continue;
      }
      if (_notifiedCommittedEventIds.contains(eventId) ||
          _notifiedCommittedMessageIds.contains(logicalMessageId)) {
        continue;
      }
      _rememberNotificationIdentity(
        eventId: eventId,
        logicalMessageId: logicalMessageId,
      );
      final messageIds = <String?>[
        logicalMessageId,
        message.remoteId,
        message.localId,
      ];
      final deduplicator = ref.read(
        agentTerminalNotificationDeduplicatorProvider,
      );
      if (suppressPresentation) {
        deduplicator.acceptMessageIds(messageIds);
        continue;
      }
      final isRuntimeAgentMessage = ref
          .read(agentsProvider)
          .agents
          .any(
            (agent) => agent.isRuntime && agent.agentDid == message.senderDid,
          );
      if (isRuntimeAgentMessage) {
        deduplicator.acceptRuntimeMessageIds(
          messageIds,
          releaseNotification: () {
            unawaited(
              _showCommittedMessageNotification(
                message,
                suppressWhenForeground: true,
              ),
            );
          },
        );
      } else if (deduplicator.acceptMessageIds(messageIds)) {
        unawaited(_showCommittedMessageNotification(message));
      }
    }
  }

  void _rememberNotificationIdentity({
    required String eventId,
    required String logicalMessageId,
  }) {
    _notifiedCommittedEventIds.add(eventId);
    _notifiedCommittedMessageIds.add(logicalMessageId);
    while (_notifiedCommittedEventIds.length > 512) {
      _notifiedCommittedEventIds.remove(_notifiedCommittedEventIds.first);
    }
    while (_notifiedCommittedMessageIds.length > 512) {
      _notifiedCommittedMessageIds.remove(_notifiedCommittedMessageIds.first);
    }
  }

  Future<void> _showCommittedMessageNotification(
    ChatMessage message, {
    bool suppressWhenForeground = false,
  }) async {
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (_disposed || epoch == null) {
      return;
    }
    final conversationId = message.conversationId?.trim() ?? '';
    if (conversationId.isNotEmpty) {
      try {
        final overlay = await ref
            .read(productLocalStoreProvider)
            .loadConversationOverlayByConversationId(
              ownerDid: epoch.ownerDid,
              conversationId: conversationId,
            );
        if (_disposed || !_isCurrentEpoch(epoch)) {
          return;
        }
        if (overlay?.muted == true) {
          return;
        }
      } catch (_) {
        // Notification preferences are best-effort when the local overlay
        // store is temporarily unavailable.
        if (_disposed || !_isCurrentEpoch(epoch)) {
          return;
        }
      }
    }
    final l10n = _currentLocalizations();
    final systemEvent = message.groupSystemEvent;
    final actorName = systemEvent == null
        ? null
        : ref.read(
            publicIdentityDisplayNameProvider(
              PublicIdentityDisplayNameRequest(
                did: systemEvent.actorDid,
                unknownLabel: l10n.commonUnknown,
              ),
            ),
          );
    final subjectName = systemEvent == null
        ? null
        : ref.read(
            publicIdentityDisplayNameProvider(
              PublicIdentityDisplayNameRequest(
                did: systemEvent.subjectDid,
                unknownLabel: l10n.commonUnknown,
              ),
            ),
          );
    final preview = localizeMessagePreview(
      l10n,
      message,
      groupEventActorName: actorName,
      groupEventSubjectName: subjectName,
    );
    final body = preview.isNotEmpty
        ? preview
        : AppMessage.newMessageArrived().resolveForFallback();
    var agentDisplayName = _agentDisplayNameForSender(l10n, message.senderDid);
    if (agentDisplayName == null &&
        conversationTargetDidLooksLikeAgent(message.senderDid)) {
      try {
        await ref.read(agentsProvider.notifier).ensureLoaded();
      } catch (_) {
        // Notification delivery remains best-effort when Agent inventory
        // refresh is unavailable.
      }
      if (_disposed || ref.read(sessionProvider).session == null) {
        return;
      }
      agentDisplayName = _agentDisplayNameForSender(l10n, message.senderDid);
    }
    final title = DidDisplayFormatter.compactDisplayName(
      displayName: agentDisplayName?.isNotEmpty == true
          ? agentDisplayName!
          : message.senderName ?? '',
      fallbackDid: message.senderDid,
    ).trim();
    final resolvedTitle = title.isNotEmpty
        ? title
        : AppMessage.newMessageArrived().resolveForFallback();
    final notifications = ref.read(notificationFacadeProvider);
    final lifecycle = ref.read(appLifecycleProvider);
    final nativePresentation = lifecycle == AppLifecycleState.resumed
        ? await ref.read(appPresentationServiceProvider).currentState()
        : null;
    if (_disposed || ref.read(sessionProvider).session == null) {
      return;
    }
    final isForeground =
        lifecycle == AppLifecycleState.resumed &&
        (nativePresentation?.isForeground ?? true);
    _messageSyncTrace(
      'notification.route',
      fields: <String, Object?>{
        'lifecycle': lifecycle.name,
        'native_state_available': nativePresentation != null,
        'application_active': nativePresentation?.applicationActive,
        'window_visible': nativePresentation?.windowVisible,
        'window_miniaturized': nativePresentation?.windowMiniaturized,
        'route': isForeground ? 'foreground' : 'system',
        'suppress_when_foreground': suppressWhenForeground,
      },
    );
    if (isForeground) {
      if (suppressWhenForeground) {
        return;
      }
      await notifications.showInAppBanner(title: resolvedTitle, body: body);
    } else {
      final session = ref.read(sessionProvider).session;
      final conversationId = message.conversationId?.trim();
      if (session == null || conversationId == null || conversationId.isEmpty) {
        return;
      }
      final target = NotificationTarget(
        storageScopeId: ref.read(activeAppTenantProvider).storageScopeId,
        ownerDid: session.did,
        conversationId: conversationId,
      );
      await notifications.showSystemNotification(
        title: resolvedTitle,
        body: body,
        target: target,
      );
    }
  }

  String? _agentDisplayNameForSender(AppLocalizations l10n, String senderDid) {
    final normalizedSenderDid = senderDid.trim();
    for (final agent in ref.read(agentsProvider).agents) {
      if (agent.agentDid.trim() == normalizedSenderDid) {
        final title = localizeAgentTitle(l10n, agent).trim();
        return title.isEmpty ? null : title;
      }
    }
    return null;
  }

  AppLocalizations _currentLocalizations() {
    final mode = ref.read(appLocaleModeProvider);
    final platformLocale = ui.PlatformDispatcher.instance.locale;
    final effective = resolveEffectiveAppLanguage(mode, platformLocale);
    return lookupAppLocalizations(effective.locale);
  }

  void _completePendingWaiters() {
    for (final waiter in _pendingCompleters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _pendingCompleters.clear();
  }

  void _completeQueuedWaiters(
    _QueuedMessageSync? queued, [
    RemotePushSyncReceipt receipt = const RemotePushSyncReceipt(
      disposition: RemotePushSyncDisposition.staleSession,
    ),
  ]) {
    if (queued == null) {
      return;
    }
    for (final waiter in queued.waiters) {
      if (!waiter.isCompleted) {
        waiter.complete(receipt);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSubscription.close();
    _cancelPendingTimerAndCompleteWaiters();
    _cancelCoreDirectedRetry();
    _cancelFailureSurfaceTimer();
    _completeQueuedWaiters(_queuedAfterActive);
    _queuedAfterActive = null;
    super.dispose();
  }
}

AppMessageSyncFailureCategory _categoryForOutcomeCode(String code) {
  return switch (code.trim().toLowerCase()) {
    'transport_unavailable' => AppMessageSyncFailureCategory.transport,
    'local_state_unavailable' => AppMessageSyncFailureCategory.localState,
    _ => AppMessageSyncFailureCategory.service,
  };
}

_MessageSyncFailureDiagnostic _classifyFailure(
  Object error,
  AppMessageSyncFailureStage stage,
) {
  if (error is! MessageSyncCoreFailure) {
    return _MessageSyncFailureDiagnostic(
      stage: stage,
      category: AppMessageSyncFailureCategory.unknown,
      code: stage == AppMessageSyncFailureStage.prepare
          ? 'message_sync_prepare_failed'
          : 'message_sync_core_failed',
    );
  }
  return _MessageSyncFailureDiagnostic(
    stage: stage,
    category: error.category,
    code: error.code,
    httpStatus: error.httpStatus,
  );
}

String _sanitizeFailureCode(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty ||
      trimmed.length > 96 ||
      !trimmed.codeUnits.every(
        (unit) =>
            (unit >= 48 && unit <= 57) ||
            (unit >= 65 && unit <= 90) ||
            (unit >= 97 && unit <= 122) ||
            unit == 45 ||
            unit == 46 ||
            unit == 95,
      )) {
    return 'message_sync_failure';
  }
  return trimmed;
}

class _MessageSyncFailureDiagnostic {
  const _MessageSyncFailureDiagnostic({
    required this.stage,
    required this.category,
    required this.code,
    this.httpStatus,
  });

  final AppMessageSyncFailureStage stage;
  final AppMessageSyncFailureCategory category;
  final String code;
  final int? httpStatus;
}

class MessageSyncCoordinatorFailure implements Exception {
  const MessageSyncCoordinatorFailure(this.code);

  final String code;

  @override
  String toString() => code;
}

class _MessageSyncSessionFence {
  const _MessageSyncSessionFence({
    required this.generation,
    required this.ownerIdentityId,
    required this.accountId,
    required this.deviceAuthGeneration,
    required this.did,
  });

  factory _MessageSyncSessionFence.from(SessionState sessionState) {
    final session = sessionState.session!;
    return _MessageSyncSessionFence(
      generation: sessionState.generation,
      ownerIdentityId: session.ownerIdentityId,
      accountId: session.accountId,
      deviceAuthGeneration: session.accountBinding?.deviceAuthGeneration,
      did: session.did,
    );
  }

  static _MessageSyncSessionFence? capture(SessionState sessionState) {
    return sessionState.session == null
        ? null
        : _MessageSyncSessionFence.from(sessionState);
  }

  final int generation;
  final String? ownerIdentityId;
  final String? accountId;
  final String? deviceAuthGeneration;
  final String did;

  bool matches(SessionState sessionState) {
    final session = sessionState.session;
    return session != null &&
        sessionState.generation == generation &&
        session.ownerIdentityId == ownerIdentityId &&
        session.accountId == accountId &&
        session.accountBinding?.deviceAuthGeneration == deviceAuthGeneration &&
        session.did == did;
  }
}

class _ActiveMessageSync {
  _ActiveMessageSync({
    required this.epoch,
    required this.future,
    required this.policy,
  });

  final SessionEpoch epoch;
  final Future<RemotePushSyncReceipt> future;
  final _MessageSyncRequestPolicy policy;
  bool presentationFinalized = false;
}

class _QueuedMessageSync {
  _QueuedMessageSync({
    required this.epoch,
    required this.reason,
    required this.immediate,
    required this.policy,
    required this.waiters,
  });

  final SessionEpoch epoch;
  String reason;
  bool immediate;
  final _MessageSyncRequestPolicy policy;
  final List<Completer<RemotePushSyncReceipt>> waiters;
}

class _MessageSyncRequestPolicy {
  _MessageSyncRequestPolicy({this.suppressNotificationPresentation = false});

  bool suppressNotificationPresentation;

  void merge({required bool suppressNotificationPresentation}) {
    this.suppressNotificationPresentation =
        this.suppressNotificationPresentation ||
        suppressNotificationPresentation;
  }

  _MessageSyncRequestPolicy copy() => _MessageSyncRequestPolicy(
    suppressNotificationPresentation: suppressNotificationPresentation,
  );
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
