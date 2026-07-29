import 'dart:async';
import 'dart:ui' as ui;

import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../../app/app_services.dart';
import '../../../app/app_locale.dart';
import '../../../application/messaging_service.dart';
import '../../../application/models/message_sync_diagnostics.dart';
import '../../../application/ports/message_sync_core_port.dart';
import '../../../application/tenant/app_tenant.dart';
import '../../../core/performance_logger.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/notification_target.dart';
import '../../../l10n/app_message.dart';
import '../../agents/agents_provider.dart';
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

  bool get isSyncing =>
      status == MessageSyncCoordinatorStatus.syncing ||
      status == MessageSyncCoordinatorStatus.recovering;

  bool get recoveryRequired =>
      status == MessageSyncCoordinatorStatus.recoveryRequired;

  bool get isAuthRevoked => status == MessageSyncCoordinatorStatus.authRevoked;

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
  final Set<String> _notifiedCommittedEventIds = <String>{};
  final Set<String> _notifiedCommittedMessageIds = <String>{};
  bool _recoveryRetryPending = false;
  bool _runningRecoveryRetry = false;
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
    _lastStartedAt = null;
    _lastFailedAt = null;
    _notifiedCommittedEventIds.clear();
    _notifiedCommittedMessageIds.clear();
    state = const MessageSyncCoordinatorState();
  }

  Future<void> requestSync(String reason, {bool immediate = false}) {
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
      final sessionFence = _MessageSyncSessionFence.capture(
        ref.read(sessionProvider),
      );
      if (sessionFence == null || !_isCurrentSync(epoch, sessionFence)) {
        return;
      }
      final recovering = _runningRecoveryRetry;
      _lastStartedAt = DateTime.now();
      _messageSyncTrace(
        'run.start',
        fields: <String, Object?>{'reason': reason, 'recovering': recovering},
      );
      if (!_isCurrentSync(epoch, sessionFence)) {
        return;
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
      try {
        await ref.read(conversationListProvider.notifier).ensurePatchReady();
        if (!_isCurrentSync(epoch, sessionFence)) {
          return;
        }
        ref
            .read(conversationListProvider.notifier)
            .recordReliableSyncStartedForCurrentPatchGeneration();
        final result = await ref
            .read(messageSyncServiceProvider)
            .syncNow(reason: reason);
        if (!_isCurrentSync(epoch, sessionFence)) {
          return;
        }
        diagnosticsAttempted = true;
        await _refreshDiagnosticsBestEffort(epoch, sessionFence);
        if (!_isCurrentSync(epoch, sessionFence)) {
          return;
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
          _lastFailedAt = DateTime.now();
          state = state.copyWith(
            status: MessageSyncCoordinatorStatus.retryableFailure,
            lastError: MessageSyncCoordinatorFailure(
              result.errorCode ?? 'message_sync_retryable_failure',
            ),
          );
          return;
        }
        if (result.status == MessageSyncStatus.authRevoked) {
          _cancelPendingTimerAndCompleteWaiters();
          _recoveryRetryPending = false;
          _runningRecoveryRetry = false;
          state = state.copyWith(
            status: MessageSyncCoordinatorStatus.authRevoked,
            pendingReason: null,
            lastError: MessageSyncCoordinatorFailure(
              result.errorCode ?? 'message_sync_auth_revoked',
            ),
          );
          _completeQueuedWaiters(_queuedAfterActive);
          _queuedAfterActive = null;
          return;
        }
        if (result.status == MessageSyncStatus.recoveryRequired) {
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
            );
          } else {
            _runningRecoveryRetry = false;
          }
          return;
        }
        _dispatchCommittedIncomingNotifications(result);
        await ref.read(devicesProvider.notifier).refreshJoinInbox();
        if (!_isCurrentSync(epoch, sessionFence)) {
          return;
        }
        await ref
            .read(conversationListProvider.notifier)
            .refreshFastLocalAfterCoreCommit();
        if (!_isCurrentSync(epoch, sessionFence)) {
          return;
        }
      } catch (error) {
        _messageSyncTrace(
          'run.failed',
          fields: <String, Object?>{
            'reason': reason,
            'error_type': error.runtimeType,
          },
        );
        if (!_isCurrentSync(epoch, sessionFence)) {
          return;
        }
        if (!diagnosticsAttempted) {
          await _refreshDiagnosticsBestEffort(epoch, sessionFence);
          if (!_isCurrentSync(epoch, sessionFence)) {
            return;
          }
        }
        _lastFailedAt = DateTime.now();
        _recoveryRetryPending = false;
        _runningRecoveryRetry = false;
        state = state.copyWith(
          status: MessageSyncCoordinatorStatus.retryableFailure,
          lastError: error,
        );
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
    _activeSync = _ActiveMessageSync(epoch: epoch, future: operation);
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
    _notifiedCommittedEventIds.clear();
    _notifiedCommittedMessageIds.clear();
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
    _completePendingWaiters();
  }

  bool _isCurrentSession(_MessageSyncSessionFence fence) {
    return !_disposed && fence.matches(ref.read(sessionProvider));
  }

  bool _isCurrentSync(
    SessionEpoch epoch,
    _MessageSyncSessionFence fence,
  ) {
    return _isCurrentEpoch(epoch) && _isCurrentSession(fence);
  }

  Future<void> _refreshDiagnosticsBestEffort(
    SessionEpoch epoch,
    _MessageSyncSessionFence fence,
  ) async {
    if (!_isCurrentSync(epoch, fence)) {
      return;
    }
    final service = ref.read(messagingServiceProvider);
    if (service is! MessageSyncDiagnosticsService) {
      return;
    }
    final attemptSequence = state.diagnosticsRefreshAttemptSequence + 1;
    state = state.copyWith(diagnosticsRefreshAttemptSequence: attemptSequence);
    try {
      final diagnostics = await (service as MessageSyncDiagnosticsService)
          .syncDiagnostics();
      if (!_isCurrentSync(epoch, fence)) {
        return;
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
    } catch (error) {
      _messageSyncTrace(
        'diagnostics.refresh_failed',
        fields: <String, Object?>{'error_type': error.runtimeType},
      );
    }
  }

  void _dispatchCommittedIncomingNotifications(MessageSyncOutcome outcome) {
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
      final isRuntimeAgentMessage = ref
          .read(agentsProvider)
          .agents
          .any(
            (agent) => agent.isRuntime && agent.agentDid == message.senderDid,
          );
      if (isRuntimeAgentMessage) {
        deduplicator.acceptRuntimeMessageIds(
          messageIds,
          releaseNotification: () => _showCommittedMessageNotification(
            message,
            suppressWhenForeground: true,
          ),
        );
      } else if (deduplicator.acceptMessageIds(messageIds)) {
        _showCommittedMessageNotification(message);
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

  void _showCommittedMessageNotification(
    ChatMessage message, {
    bool suppressWhenForeground = false,
  }) {
    if (_disposed || ref.read(sessionProvider).session == null) {
      return;
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
    final title = DidDisplayFormatter.compactDisplayName(
      displayName: message.senderName ?? '',
      fallbackDid: message.senderDid,
    ).trim();
    final resolvedTitle = title.isNotEmpty
        ? title
        : AppMessage.newMessageArrived().resolveForFallback();
    final notifications = ref.read(notificationFacadeProvider);
    if (ref.read(appLifecycleProvider) == AppLifecycleState.resumed) {
      if (suppressWhenForeground) {
        return;
      }
      notifications.showInAppBanner(title: resolvedTitle, body: body);
    } else {
      final session = ref.read(sessionProvider).session;
      final conversationId = message.conversationId?.trim();
      if (session == null ||
          conversationId == null ||
          conversationId.isEmpty) {
        return;
      }
      final target = NotificationTarget(
        storageScopeId: ref.read(activeAppTenantProvider).storageScopeId,
        ownerDid: session.did,
        conversationId: conversationId,
      );
      notifications.showSystemNotification(
        title: resolvedTitle,
        body: body,
        target: target,
      );
    }
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
