import 'dart:async';
import 'dart:ui' as ui;

import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../../../app/app_services.dart';
import '../../../app/app_locale.dart';
import '../../../application/ports/message_sync_core_port.dart';
import '../../../core/performance_logger.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../l10n/app_message.dart';
import '../../profile/peer_display_profile_provider.dart';
import '../../shared/formatters/display_formatters.dart';
import '../../shared/formatters/localized_ui_formatters.dart';
import '../../chat/chat_provider.dart';
import '../../conversation_list/conversation_provider.dart';
import '../../devices/devices_provider.dart';
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
  });

  final MessageSyncCoordinatorStatus status;
  final String? pendingReason;
  final String? lastReason;
  final Object? lastError;
  final MessageSyncStatus? lastStatus;

  bool get isSyncing =>
      status == MessageSyncCoordinatorStatus.syncing ||
      status == MessageSyncCoordinatorStatus.recovering;

  bool get recoveryRequired =>
      status == MessageSyncCoordinatorStatus.recoveryRequired;

  bool get isAuthRevoked => status == MessageSyncCoordinatorStatus.authRevoked;

  @Deprecated('Use recoveryRequired.')
  bool get snapshotRequired => recoveryRequired;

  MessageSyncCoordinatorState copyWith({
    MessageSyncCoordinatorStatus? status,
    Object? pendingReason = _unset,
    Object? lastReason = _unset,
    Object? lastError = _unset,
    Object? lastStatus = _unset,
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
  final Set<String> _notifiedCommittedEventIds = <String>{};
  final Set<String> _notifiedCommittedMessageIds = <String>{};
  bool _recoveryRetryPending = false;
  bool _runningRecoveryRetry = false;
  bool _disposed = false;

  void resetForSession() {
    if (_disposed) {
      return;
    }
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _completePendingWaiters();
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
    final active = _activeSync;
    _messageSyncTrace(
      'request',
      fields: <String, Object?>{
        'reason': reason,
        'immediate': immediate,
        'active': active != null,
        'pending': state.pendingReason,
      },
    );
    if (active != null) {
      state = state.copyWith(pendingReason: reason);
      _messageSyncTrace(
        'request.coalesced_active',
        fields: <String, Object?>{'reason': reason},
      );
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
      _messageSyncTrace(
        'request.run_now',
        fields: <String, Object?>{'reason': reason},
      );
      return _runSync(reason);
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
    final completer = Completer<void>();
    _pendingCompleters.add(completer);
    _pendingTimer = Timer(delay, () {
      _pendingTimer = null;
      final waiters = List<Completer<void>>.of(_pendingCompleters);
      _pendingCompleters.clear();
      if (_disposed) {
        for (final waiter in waiters) {
          if (!waiter.isCompleted) {
            waiter.complete();
          }
        }
        return;
      }
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
    if (_disposed) {
      _messageSyncTrace(
        'run.ignored_disposed',
        fields: <String, Object?>{'reason': reason},
      );
      return Future<void>.value();
    }
    final active = _activeSync;
    if (active != null) {
      state = state.copyWith(pendingReason: reason);
      _messageSyncTrace(
        'run.coalesced_active',
        fields: <String, Object?>{'reason': reason},
      );
      return active;
    }
    late final Future<void> operation;
    operation = (() async {
      final sessionFence = _MessageSyncSessionFence.capture(
        ref.read(sessionProvider),
      );
      if (sessionFence == null) {
        return;
      }
      final recovering = _runningRecoveryRetry;
      _lastStartedAt = DateTime.now();
      _messageSyncTrace(
        'run.start',
        fields: <String, Object?>{'reason': reason, 'recovering': recovering},
      );
      state = state.copyWith(
        status: recovering
            ? MessageSyncCoordinatorStatus.recovering
            : MessageSyncCoordinatorStatus.syncing,
        pendingReason: null,
        lastReason: reason,
        lastError: null,
      );
      try {
        final result = await ref
            .read(messageSyncServiceProvider)
            .syncNow(reason: reason);
        if (!_isCurrentSession(sessionFence)) {
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
          _pendingTimer?.cancel();
          _pendingTimer = null;
          _completePendingWaiters();
          _recoveryRetryPending = false;
          _runningRecoveryRetry = false;
          state = state.copyWith(
            status: MessageSyncCoordinatorStatus.authRevoked,
            pendingReason: null,
            lastError: MessageSyncCoordinatorFailure(
              result.errorCode ?? 'message_sync_auth_revoked',
            ),
          );
          return;
        }
        if (result.status == MessageSyncStatus.recoveryRequired) {
          state = state.copyWith(
            status: MessageSyncCoordinatorStatus.recoveryRequired,
          );
          if (!recovering && ref.read(messageSyncV2ReadEnabledProvider)) {
            _recoveryRetryPending = true;
            state = state.copyWith(pendingReason: reason);
          } else {
            _runningRecoveryRetry = false;
          }
          return;
        }
        _dispatchCommittedIncomingNotifications(result);
        await ref.read(devicesProvider.notifier).refreshJoinInbox();
        if (!_isCurrentSession(sessionFence)) {
          return;
        }
        _messageSyncTrace(
          'run.refresh_fast_local.start',
          fields: <String, Object?>{'reason': reason},
        );
        await ref.read(conversationListProvider.notifier).refreshFastLocal();
        if (!_isCurrentSession(sessionFence)) {
          return;
        }
        final conversations = ref.read(conversationListProvider).conversations;
        if (!_isCurrentSession(sessionFence)) {
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
        if (!_isCurrentSession(sessionFence)) {
          return;
        }
        await ref
            .read(chatThreadsProvider.notifier)
            .refreshVisibleLocalProjections(force: true);
        if (!_isCurrentSession(sessionFence)) {
          return;
        }
        _messageSyncTrace(
          'run.prewarm.done',
          fields: <String, Object?>{
            'reason': reason,
            'conversations': conversations.length,
          },
        );
      } catch (error) {
        _lastFailedAt = DateTime.now();
        _messageSyncTrace(
          'run.failed',
          fields: <String, Object?>{
            'reason': reason,
            'error_type': error.runtimeType,
          },
        );
        if (!_isCurrentSession(sessionFence)) {
          return;
        }
        _recoveryRetryPending = false;
        _runningRecoveryRetry = false;
        state = state.copyWith(
          status: MessageSyncCoordinatorStatus.retryableFailure,
          lastError: error,
        );
      } finally {
        if (identical(_activeSync, operation)) {
          _activeSync = null;
        }
        if (_disposed) {
          _messageSyncTrace(
            'run.finish_disposed',
            fields: <String, Object?>{'reason': reason},
          );
        } else if (_isCurrentSession(sessionFence)) {
          if (state.status == MessageSyncCoordinatorStatus.syncing ||
              state.status == MessageSyncCoordinatorStatus.recovering) {
            state = state.copyWith(status: MessageSyncCoordinatorStatus.idle);
          }
          final pending = state.pendingReason;
          _messageSyncTrace(
            'run.finish',
            fields: <String, Object?>{'reason': reason, 'pending': pending},
          );
          if (pending != null) {
            if (_recoveryRetryPending) {
              _recoveryRetryPending = false;
              _runningRecoveryRetry = true;
              unawaited(requestSync(pending, immediate: true));
            } else if (state.status !=
                MessageSyncCoordinatorStatus.authRevoked) {
              unawaited(requestSync(pending));
            }
          }
        } else {
          final pending = state.pendingReason;
          if (pending != null &&
              state.status != MessageSyncCoordinatorStatus.authRevoked) {
            unawaited(requestSync(pending, immediate: true));
          }
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

  bool _isCurrentSession(_MessageSyncSessionFence fence) {
    return !_disposed && fence.matches(ref.read(sessionProvider));
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
      _showCommittedMessageNotification(message);
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

  void _showCommittedMessageNotification(ChatMessage message) {
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
      notifications.showInAppBanner(title: resolvedTitle, body: body);
    } else {
      notifications.showSystemNotification(title: resolvedTitle, body: body);
    }
  }

  AppLocalizations _currentLocalizations() {
    final mode = ref.read(appLocaleModeProvider);
    final platformLocale = ui.PlatformDispatcher.instance.locale;
    final effective = resolveEffectiveAppLanguage(mode, platformLocale);
    return lookupAppLocalizations(effective.locale);
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _completePendingWaiters();
    super.dispose();
  }

  void _completePendingWaiters() {
    for (final waiter in _pendingCompleters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _pendingCompleters.clear();
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
    required this.did,
  });

  factory _MessageSyncSessionFence.from(SessionState sessionState) {
    final session = sessionState.session!;
    return _MessageSyncSessionFence(
      generation: sessionState.generation,
      ownerIdentityId: session.ownerIdentityId,
      accountId: session.accountId,
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
  final String did;

  bool matches(SessionState sessionState) {
    final session = sessionState.session;
    return session != null &&
        sessionState.generation == generation &&
        session.ownerIdentityId == ownerIdentityId &&
        session.accountId == accountId &&
        session.did == did;
  }
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
