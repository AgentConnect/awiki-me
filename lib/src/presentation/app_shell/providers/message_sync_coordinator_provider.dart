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

class MessageSyncCoordinatorState {
  const MessageSyncCoordinatorState({
    this.isSyncing = false,
    this.pendingReason,
    this.lastReason,
    this.lastError,
    this.lastStatus,
    this.recoveryRequired = false,
  });

  final bool isSyncing;
  final String? pendingReason;
  final String? lastReason;
  final Object? lastError;
  final MessageSyncStatus? lastStatus;
  final bool recoveryRequired;

  @Deprecated('Use recoveryRequired.')
  bool get snapshotRequired => recoveryRequired;

  MessageSyncCoordinatorState copyWith({
    bool? isSyncing,
    Object? pendingReason = _unset,
    Object? lastReason = _unset,
    Object? lastError = _unset,
    Object? lastStatus = _unset,
    bool? recoveryRequired,
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
      lastStatus: identical(lastStatus, _unset)
          ? this.lastStatus
          : lastStatus as MessageSyncStatus?,
      recoveryRequired: recoveryRequired ?? this.recoveryRequired,
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
  bool _disposed = false;

  Future<void> requestSync(String reason, {bool immediate = false}) {
    if (_disposed) {
      _messageSyncTrace(
        'request.ignored_disposed',
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
      _lastStartedAt = DateTime.now();
      _messageSyncTrace(
        'run.start',
        fields: <String, Object?>{'reason': reason},
      );
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
        if (_disposed) {
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
        state = state.copyWith(
          lastStatus: result.status,
          recoveryRequired: result.recoveryRequired,
          lastError: null,
        );
        if (result.status == MessageSyncStatus.retryableFailure) {
          _lastFailedAt = DateTime.now();
          state = state.copyWith(
            lastError: MessageSyncCoordinatorFailure(
              result.errorCode ?? 'message_sync_retryable_failure',
            ),
          );
          return;
        }
        if (result.status == MessageSyncStatus.authRevoked) {
          state = state.copyWith(
            lastError: MessageSyncCoordinatorFailure(
              result.errorCode ?? 'message_sync_auth_revoked',
            ),
          );
          return;
        }
        _dispatchCommittedIncomingNotifications(result);
        await ref.read(devicesProvider.notifier).refreshJoinInbox();
        if (_disposed) {
          return;
        }
        if (!result.recoveryRequired) {
          _messageSyncTrace(
            'run.refresh_fast_local.start',
            fields: <String, Object?>{'reason': reason},
          );
          await ref.read(conversationListProvider.notifier).refreshFastLocal();
          if (_disposed) {
            return;
          }
          final conversations = ref
              .read(conversationListProvider)
              .conversations;
          if (_disposed) {
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
          await ref
              .read(chatThreadsProvider.notifier)
              .refreshVisibleLocalProjections(force: true);
          if (_disposed) {
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
        _lastFailedAt = DateTime.now();
        _messageSyncTrace(
          'run.failed',
          fields: <String, Object?>{
            'reason': reason,
            'error_type': error.runtimeType,
          },
        );
        if (_disposed) {
          return;
        }
        state = state.copyWith(lastError: error);
      } finally {
        if (identical(_activeSync, operation)) {
          _activeSync = null;
        }
        if (_disposed) {
          _messageSyncTrace(
            'run.finish_disposed',
            fields: <String, Object?>{'reason': reason},
          );
        } else {
          state = state.copyWith(isSyncing: false);
          final pending = state.pendingReason;
          _messageSyncTrace(
            'run.finish',
            fields: <String, Object?>{'reason': reason, 'pending': pending},
          );
          if (pending != null) {
            unawaited(requestSync(pending));
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
    for (final waiter in _pendingCompleters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _pendingCompleters.clear();
    super.dispose();
  }
}

class MessageSyncCoordinatorFailure implements Exception {
  const MessageSyncCoordinatorFailure(this.code);

  final String code;

  @override
  String toString() => code;
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
