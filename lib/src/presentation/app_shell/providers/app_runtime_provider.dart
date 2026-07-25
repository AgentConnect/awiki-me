import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/l10n/app_localizations.dart';

import '../../../app/app_locale.dart';
import '../../../app/app_services.dart';
import '../../../app/ui_feedback.dart';
import '../../../application/app_session_service.dart';
import '../../../core/performance_logger.dart';
import '../../../application/models/app_session.dart';
import '../../../application/agent/agent_control_projection.dart';
import '../../../application/tenant/app_tenant.dart';
import '../../../domain/entities/bridge_capabilities.dart';
import '../../../domain/entities/conversation_summary.dart';
import '../../../domain/entities/notification_target.dart';
import '../../../domain/entities/realtime_update.dart';
import '../../../domain/entities/session_identity.dart';
import '../../../domain/services/realtime_gateway.dart';
import '../../../l10n/app_message.dart';
import '../../agents/agent_inbox_provider.dart';
import '../../agents/agents_provider.dart';
import '../../chat/chat_provider.dart';
import '../../conversation_list/conversation_provider.dart';
import '../../friends/friends_provider.dart';
import '../../group/group_provider.dart';
import '../../profile/peer_display_profile_provider.dart';
import '../../profile/peer_profile_provider.dart';
import '../../profile/profile_provider.dart';
import '../../shared/formatters/display_formatters.dart';
import '../../shared/formatters/localized_ui_formatters.dart';
import '../../shared/realtime_conversation_identity_projection.dart';
import 'app_lifecycle_provider.dart';
import 'message_sync_coordinator_provider.dart';
import 'navigation_provider.dart';
import 'selected_conversation_provider.dart';
import 'session_provider.dart';

const bool _runtimeTraceEnabled = bool.fromEnvironment(
  'AWIKI_RUNTIME_TRACE',
  defaultValue: false,
);

class AppRuntimeState {
  const AppRuntimeState({this.isInitialized = false, this.isBusy = false});

  final bool isInitialized;
  final bool isBusy;

  AppRuntimeState copyWith({bool? isInitialized, bool? isBusy}) {
    return AppRuntimeState(
      isInitialized: isInitialized ?? this.isInitialized,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

class AppRuntimeController extends StateNotifier<AppRuntimeState> {
  AppRuntimeController(
    this.ref, {
    Duration requestTimeout = const Duration(seconds: 20),
  }) : _requestTimeout = requestTimeout,
       super(const AppRuntimeState()) {
    _lifecycleSubscription = ref.listen<AppLifecycleState>(
      appLifecycleProvider,
      _handleLifecycleChanged,
    );
    _realtimeStatusSubscription = ref
        .listen<AsyncValue<RealtimeConnectionStatus>>(
          realtimeConnectionStatusProvider,
          _handleRealtimeStatusChanged,
        );
    _notificationActivationSubscription = ref
        .read(notificationFacadeProvider)
        .activations
        .listen(
          (activation) => unawaited(_handleNotificationActivation(activation)),
        );
  }

  final Ref ref;
  final Duration _requestTimeout;
  static const Duration _refreshDebounceWindow = Duration(seconds: 2);
  bool _isLoggingOut = false;
  _SessionEpochOperation? _authenticatedRefreshOperation;
  _SessionEpochOperation? _realtimeRecoveryOperation;
  int _busyOperationCount = 0;
  Future<void> _e2eeInitializationTail = Future<void>.value();
  SessionEpoch? _lastAuthenticatedRefreshEpoch;
  DateTime? _lastAuthenticatedRefreshStartedAt;
  late final ProviderSubscription<AppLifecycleState> _lifecycleSubscription;
  late final ProviderSubscription<AsyncValue<RealtimeConnectionStatus>>
  _realtimeStatusSubscription;
  StreamSubscription<RealtimeUpdate>? _realtimeUpdateSubscription;
  late final StreamSubscription<NotificationActivation>
  _notificationActivationSubscription;

  Future<void> initialize() async {
    if (state.isInitialized) {
      return;
    }
    _beginBusyOperation();
    try {
      final sessions = ref.read(appSessionServiceProvider);
      final localIdentities = await sessions.listLocalIdentities();
      final localCredentials = _legacySessionsFromAppSessions(localIdentities);
      ref.read(sessionProvider.notifier).setCapabilities(_imCoreCapabilities);
      ref.read(sessionProvider.notifier).setLocalCredentials(localCredentials);

      final session = await sessions.restoreSession();
      if (session != null) {
        await activateCommittedSession(session);
      }
      final initialActivation = await ref
          .read(notificationFacadeProvider)
          .initialActivation();
      if (initialActivation != null) {
        await _handleNotificationActivation(initialActivation);
      }
      state = state.copyWith(isInitialized: true);
    } on TimeoutException {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
      state = state.copyWith(isInitialized: true);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
      state = state.copyWith(isInitialized: true);
    } finally {
      _endBusyOperation();
    }
  }

  Future<void> _activateSession(AppSessionLease requestedLease) async {
    final lease = await _currentSessionLeaseMatching(requestedLease);
    if (lease == null || !mounted) {
      return;
    }
    final session = _legacySessionFromAppSession(lease.session);
    final totalWatch = Stopwatch()..start();
    _beginBusyOperation();
    try {
      final currentSession = ref.read(sessionProvider).session;
      if (currentSession != null) {
        ref
            .read(sessionProvider.notifier)
            .upsertLocalCredential(currentSession);
        _clearAuthenticatedUiState();
      }
      ref.read(selectedConversationProvider.notifier).clearSelection();
      final initialized = await _enqueueE2eeInitialization(
        lease,
        session,
      ).timeout(_requestTimeout);
      if (!initialized || !_isSessionLeaseTransitionCurrent(lease)) {
        return;
      }
      ref.read(sessionProvider.notifier).activateSession(session);
      final epoch = ref.read(sessionProvider).activeEpoch!;
      _adoptSessionEpoch(epoch);
      _bindRealtimeUpdates(epoch);
      if (!_isSessionLeaseTransitionCurrent(lease)) {
        if (_isSessionEpochActive(epoch)) {
          _clearAuthenticatedUiState();
        }
        return;
      }
      if (!_isSessionEpochActive(epoch)) {
        return;
      }
      state = state.copyWith(isInitialized: true);
      unawaited(
        _refreshAuthenticatedDataInBackground(epoch: epoch, debounce: false),
      );
      _scheduleReliableSync('startup', immediate: true);
      _ensureRealtimeConnected(epoch);
    } on TimeoutException {
      if (!_isSessionLeaseTransitionCurrent(lease)) {
        return;
      }
      await ref.read(appSessionServiceProvider).abortSessionIfCurrent(lease);
      rethrow;
    } catch (_) {
      if (!_isSessionLeaseTransitionCurrent(lease)) {
        return;
      }
      await ref.read(appSessionServiceProvider).abortSessionIfCurrent(lease);
      rethrow;
    } finally {
      if (mounted) {
        state = state.copyWith(isInitialized: true);
      }
      _endBusyOperation();
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'app_runtime.activate_session',
        elapsed: totalWatch.elapsed,
      );
    }
  }

  Future<void> loginWithLocalCredential(String credentialName) async {
    final currentSession = ref.read(sessionProvider).session;
    if (currentSession != null) {
      ref.read(sessionProvider.notifier).upsertLocalCredential(currentSession);
      _clearAuthenticatedUiState();
    }
    AppSession? session;
    AppSessionLease? restoredLease;
    final sessions = ref.read(appSessionServiceProvider);
    final transition = sessions.beginSessionTransition();
    await _runBusy(
      () async {
        session = await sessions.loginWithIdentity(
          credentialName,
          transition: transition,
        );
      },
      onFailure: () async {
        restoredLease = await _cancelOrAbortSessionTransition(transition);
      },
      shouldReportFailure: () => sessions.isLatestSessionTransition(transition),
    );
    final committed = session;
    if (committed == null) {
      final predecessor = restoredLease;
      if (predecessor != null) {
        await _runBusy(
          () => _activateSession(predecessor),
          enforceTimeout: false,
        );
      }
      return;
    }
    await _runBusy(
      () => activateCommittedSession(committed),
      enforceTimeout: false,
    );
  }

  Future<void> activateCommittedSession(
    AppSession session, {
    AppSessionTransition? expectedTransition,
  }) async {
    final lease = await ref
        .read(appSessionServiceProvider)
        .currentSessionLease();
    if (lease == null ||
        lease.session.identityId != session.identityId ||
        lease.session.did != session.did ||
        (expectedTransition != null &&
            !identical(lease.transition, expectedTransition))) {
      if (expectedTransition != null) {
        throw const AppSessionTransitionSuperseded();
      }
      return;
    }
    await _activateSession(lease);
  }

  Future<AppSessionLease?> _currentSessionLeaseMatching(
    AppSessionLease requested,
  ) async {
    final current = await ref
        .read(appSessionServiceProvider)
        .currentSessionLease();
    if (current == null ||
        !identical(current.transition, requested.transition) ||
        current.session.identityId != requested.session.identityId) {
      return null;
    }
    return current;
  }

  bool _isSessionLeaseTransitionCurrent(AppSessionLease lease) {
    return mounted &&
        ref
            .read(appSessionServiceProvider)
            .isSessionTransitionCurrent(lease.transition);
  }

  Future<bool> _enqueueE2eeInitialization(
    AppSessionLease lease,
    SessionIdentity session,
  ) {
    final previous = _e2eeInitializationTail;
    final completed = Completer<void>();
    _e2eeInitializationTail = completed.future;

    return () async {
      await previous;
      try {
        if (!_isSessionLeaseTransitionCurrent(lease)) {
          return false;
        }
        await AwikiPerformanceLogger.async(
          'app_runtime.activate_session.e2ee',
          () => ref.read(e2eeFacadeProvider).initialize(session),
        );
        return _isSessionLeaseTransitionCurrent(lease);
      } finally {
        if (!completed.isCompleted) {
          completed.complete();
        }
      }
    }();
  }

  Future<void> refreshLocalCredentials() async {
    await _runBusy(() async {
      final credentials = await _localCredentialsFor(ref);
      ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      final feedback = credentials.isEmpty
          ? AppMessage.noLocalCredentialsFound()
          : AppMessage.localCredentialsRefreshed(credentials.length);
      ref.read(uiFeedbackProvider.notifier).showInfo(feedback);
    });
  }

  Future<void> logout() async {
    final currentSession = ref.read(sessionProvider).session;
    if (currentSession != null) {
      ref.read(sessionProvider.notifier).upsertLocalCredential(currentSession);
    }
    _isLoggingOut = true;
    _clearAuthenticatedUiState();
    state = state.copyWith(isInitialized: true);
    try {
      await ref.read(appSessionServiceProvider).logout();
    } finally {
      _isLoggingOut = false;
    }
  }

  Future<void> deleteCurrentCredential() async {
    final current = ref.read(sessionProvider).session;
    if (current == null) {
      return;
    }
    await _runBusy(() async {
      _isLoggingOut = true;
      try {
        ref.read(sessionProvider.notifier).clear();
        _invalidateSessionOperations();
        _cancelRealtimeUpdates();
        ref.read(profileProvider.notifier).clear();
        ref.read(agentsProvider.notifier).clear();
        ref.read(agentInboxProvider.notifier).clear();
        ref.read(selectedConversationProvider.notifier).clearSelection();
        await ref.read(conversationListProvider.notifier).clear();
        ref.read(chatThreadsProvider.notifier).clear();
        ref.read(friendsProvider.notifier).clear();
        ref.read(peerDisplayProfileProvider.notifier).clear();
        ref.invalidate(peerProfileProvider);
        ref.read(groupProvider.notifier).clear();
        await ref
            .read(appSessionServiceProvider)
            .deleteLocalIdentity(current.credentialName);
        final credentials = await _localCredentialsFor(ref);
        ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      } finally {
        _isLoggingOut = false;
      }
    });
  }

  void _clearAuthenticatedUiState() {
    ref.read(sessionProvider.notifier).clear();
    _invalidateSessionOperations();
    _cancelRealtimeUpdates();
    ref.read(profileProvider.notifier).clear();
    ref.read(agentsProvider.notifier).clear();
    ref.read(agentInboxProvider.notifier).clear();
    ref.read(selectedConversationProvider.notifier).clearSelection();
    ref.read(conversationListProvider.notifier).clearLocal();
    ref.read(chatThreadsProvider.notifier).clear();
    ref.read(friendsProvider.notifier).clear();
    ref.read(peerDisplayProfileProvider.notifier).clear();
    ref.invalidate(peerProfileProvider);
    ref.read(groupProvider.notifier).clear();
  }

  Future<void> exportCurrentCredential() async {
    ref
        .read(uiFeedbackProvider.notifier)
        .showInfo(AppMessage.featureNotImplemented());
  }

  Future<void> importCredentialArchive() async {
    ref
        .read(uiFeedbackProvider.notifier)
        .showInfo(AppMessage.featureNotImplemented());
  }

  Future<void> _refreshAuthenticatedData(SessionEpoch epoch) async {
    final totalWatch = Stopwatch()..start();
    if (!_isSessionEpochActive(epoch)) {
      return;
    }

    unawaited(
      AwikiPerformanceLogger.async(
        'app_refresh.product_store_warm_up',
        () => ref.read(productLocalStoreProvider).warmUp(),
      ).catchError((_) {}),
    );

    await AwikiPerformanceLogger.async(
      'app_refresh.conversation_fast_local',
      () => ref.read(conversationListProvider.notifier).refreshFastLocal(),
    );
    if (!_isSessionEpochActive(epoch)) {
      return;
    }

    await Future.wait<void>(<Future<void>>[
      AwikiPerformanceLogger.async(
        'app_refresh.profile',
        () => ref.read(profileProvider.notifier).refresh(),
      ),
      AwikiPerformanceLogger.async(
        'app_refresh.agents',
        () => ref.read(agentsProvider.notifier).syncRemoteInventory(),
      ),
      AwikiPerformanceLogger.async(
        'app_refresh.friends',
        () => ref.read(friendsProvider.notifier).refresh(),
      ),
      AwikiPerformanceLogger.async(
        'app_refresh.groups',
        () => ref.read(groupProvider.notifier).refresh(),
      ),
    ]);
    if (!_isSessionEpochActive(epoch)) {
      return;
    }
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'app_refresh.authenticated_data',
      elapsed: totalWatch.elapsed,
    );
  }

  Future<void> _refreshAuthenticatedDataInBackground({
    SessionEpoch? epoch,
    bool debounce = true,
  }) {
    final requestedEpoch = epoch ?? ref.read(sessionProvider).activeEpoch;
    if (requestedEpoch == null || !_isSessionEpochActive(requestedEpoch)) {
      return Future<void>.value();
    }
    final active = _authenticatedRefreshOperation;
    if (active != null && active.epoch == requestedEpoch) {
      AwikiPerformanceLogger.log(
        'app_refresh.authenticated_data.request',
        fields: const <String, Object?>{'reused': true},
      );
      return active.operation;
    }
    final now = DateTime.now();
    final lastStarted = _lastAuthenticatedRefreshEpoch == requestedEpoch
        ? _lastAuthenticatedRefreshStartedAt
        : null;
    final delay = debounce && lastStarted != null
        ? _refreshDebounceWindow - now.difference(lastStarted)
        : Duration.zero;
    late final Future<void> operation;
    operation =
        (() async {
          if (delay > Duration.zero) {
            AwikiPerformanceLogger.log(
              'app_refresh.authenticated_data.debounce',
              fields: <String, Object?>{'delay_ms': delay.inMilliseconds},
            );
            await Future<void>.delayed(delay);
          }
          if (!_isSessionEpochActive(requestedEpoch)) {
            return;
          }
          _lastAuthenticatedRefreshEpoch = requestedEpoch;
          _lastAuthenticatedRefreshStartedAt = DateTime.now();
          try {
            await _refreshAuthenticatedData(
              requestedEpoch,
            ).timeout(_requestTimeout);
          } on TimeoutException {
            return;
          } catch (error) {
            if (!_isSessionEpochActive(requestedEpoch)) {
              return;
            }
            final message = AppMessage.fromError(error);
            if (message == AppMessage.sessionExpiredRelogin()) {
              ref.read(uiFeedbackProvider.notifier).showError(message);
              await logout();
            }
          }
        })().whenComplete(() {
          if (identical(_authenticatedRefreshOperation?.operation, operation)) {
            _authenticatedRefreshOperation = null;
          }
        });
    _authenticatedRefreshOperation = _SessionEpochOperation(
      epoch: requestedEpoch,
      operation: operation,
    );
    AwikiPerformanceLogger.log(
      'app_refresh.authenticated_data.request',
      fields: <String, Object?>{
        'reused': false,
        'debounce_ms': delay > Duration.zero ? delay.inMilliseconds : 0,
      },
    );
    return operation;
  }

  void _handleLifecycleChanged(
    AppLifecycleState? previous,
    AppLifecycleState next,
  ) {
    if (previous == next) {
      return;
    }
    if (next == AppLifecycleState.paused ||
        next == AppLifecycleState.inactive ||
        next == AppLifecycleState.hidden) {
      ref.read(chatThreadsProvider.notifier).trimForAppBackground();
      return;
    }
    if (next != AppLifecycleState.resumed) {
      return;
    }
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null) {
      return;
    }
    _ensureRealtimeConnected(epoch);
    _scheduleReliableSync('app_resumed');
    unawaited(_refreshAuthenticatedDataInBackground());
  }

  void _handleRealtimeStatusChanged(
    AsyncValue<RealtimeConnectionStatus>? previous,
    AsyncValue<RealtimeConnectionStatus> next,
  ) {
    final status = next.valueOrNull;
    final previousStatus = previous?.valueOrNull;
    if (status == RealtimeConnectionStatus.failed ||
        status == RealtimeConnectionStatus.disconnected) {
      if (_isLoggingOut) {
        return;
      }
      final session = ref.read(sessionProvider).session;
      if (session != null) {
        unawaited(_recoverRealtimeSession());
      }
      return;
    }
    if (status != RealtimeConnectionStatus.connected) {
      return;
    }
    if (previousStatus != RealtimeConnectionStatus.reconnecting &&
        previousStatus != RealtimeConnectionStatus.disconnected &&
        previousStatus != RealtimeConnectionStatus.failed) {
      return;
    }
    if (ref.read(sessionProvider).activeEpoch == null) {
      return;
    }
    _scheduleReliableSync('realtime_reconnected');
    unawaited(_refreshAuthenticatedDataInBackground());
  }

  void _ensureRealtimeConnected(SessionEpoch epoch) {
    if (!_isSessionEpochActive(epoch)) {
      return;
    }
    final realtime = ref.read(realtimeApplicationServiceProvider);
    if (realtime.isRunning) {
      return;
    }
    unawaited(realtime.start().catchError((_) {}));
  }

  Future<void> _recoverRealtimeSession() {
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null || !_isSessionEpochActive(epoch)) {
      return Future<void>.value();
    }
    final active = _realtimeRecoveryOperation;
    if (active != null && active.epoch == epoch) {
      return active.operation;
    }
    late final Future<void> operation;
    operation = _runRealtimeRecovery(epoch).whenComplete(() {
      if (identical(_realtimeRecoveryOperation?.operation, operation)) {
        _realtimeRecoveryOperation = null;
      }
    });
    _realtimeRecoveryOperation = _SessionEpochOperation(
      epoch: epoch,
      operation: operation,
    );
    return operation;
  }

  Future<void> _runRealtimeRecovery(SessionEpoch epoch) async {
    try {
      if (!_isSessionEpochActive(epoch)) {
        return;
      }
      final refreshed = await ref
          .read(appSessionServiceProvider)
          .refreshSession();
      if (!_isSessionEpochActive(epoch)) {
        return;
      }
      if (refreshed != null) {
        ref
            .read(sessionProvider.notifier)
            .updateSessionMetadataIfCurrent(
              _legacySessionFromAppSession(refreshed),
            );
        if (!_isSessionEpochActive(epoch)) {
          return;
        }
      }
      await _refreshAuthenticatedDataInBackground(epoch: epoch);
      if (!_isSessionEpochActive(epoch)) {
        return;
      }
      if (refreshed != null) {
        _ensureRealtimeConnected(epoch);
      }
    } catch (_) {
      if (_isSessionEpochActive(epoch)) {
        await _refreshAuthenticatedDataInBackground(epoch: epoch);
      }
    }
  }

  bool _isSessionEpochActive(SessionEpoch epoch) {
    return mounted &&
        !_isLoggingOut &&
        epoch.matches(ref.read(sessionProvider));
  }

  void _adoptSessionEpoch(SessionEpoch epoch) {
    final refresh = _authenticatedRefreshOperation;
    if (refresh != null && refresh.epoch != epoch) {
      _authenticatedRefreshOperation = null;
    }
    final recovery = _realtimeRecoveryOperation;
    if (recovery != null && recovery.epoch != epoch) {
      _realtimeRecoveryOperation = null;
    }
    if (_lastAuthenticatedRefreshEpoch != epoch) {
      _lastAuthenticatedRefreshEpoch = null;
      _lastAuthenticatedRefreshStartedAt = null;
    }
  }

  void _invalidateSessionOperations() {
    _authenticatedRefreshOperation = null;
    _realtimeRecoveryOperation = null;
    _lastAuthenticatedRefreshEpoch = null;
    _lastAuthenticatedRefreshStartedAt = null;
  }

  void _bindRealtimeUpdates(SessionEpoch epoch) {
    _cancelRealtimeUpdates();
    _realtimeUpdateSubscription = ref
        .read(realtimeApplicationServiceProvider)
        .updates
        .listen((update) => _applyRealtimeUpdate(epoch, update));
  }

  void _cancelRealtimeUpdates() {
    final subscription = _realtimeUpdateSubscription;
    _realtimeUpdateSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel().catchError((_) {}));
    }
  }

  void _applyRealtimeUpdate(SessionEpoch expectedEpoch, RealtimeUpdate update) {
    if (!_isSessionEpochActive(expectedEpoch) ||
        update.ownerDid.trim() != expectedEpoch.ownerDid) {
      return;
    }
    final traceConversation = update.conversation ?? update.conversationHint;
    _runtimeTrace(
      'realtime.update',
      fields: <String, Object?>{
        'control': update.agentControlPayload != null,
        'message': update.message != null,
        'conversation': traceConversation != null,
        'conversation_hint': update.conversationHint != null,
        'sync_dirty': update.syncDirty,
        'gap': update.gapDetected,
        'event_seq': update.syncEventSeq,
        'event_type': update.syncEventType,
        'thread_hash': _runtimeSafeHash(
          traceConversation?.threadId ?? update.message?.threadId,
        ),
        'preview_hash': _runtimeSafeHash(
          traceConversation?.lastMessagePreview ?? update.message?.previewText,
        ),
        'unread': traceConversation?.unreadCount,
      },
    );
    final reliableSyncReason = _reliableSyncReasonFor(update);
    if (reliableSyncReason != null) {
      _runtimeTrace(
        'reliable_sync.schedule',
        fields: <String, Object?>{
          'reason': reliableSyncReason,
          'event_seq': update.syncEventSeq,
        },
      );
      _scheduleReliableSync(reliableSyncReason);
    }
    final controlPayload = update.agentControlPayload;
    if (controlPayload != null) {
      ref.read(agentsProvider.notifier).applyControlPayload(controlPayload);
      ref.read(agentInboxProvider.notifier).applyControlPayload(controlPayload);
      ref
          .read(chatThreadsProvider.notifier)
          .applyAgentRunStatusPayload(controlPayload);
      ref
          .read(chatThreadsProvider.notifier)
          .applyMessageAgentControlPayload(controlPayload);
      _runtimeTrace(
        'realtime.control_applied',
        fields: <String, Object?>{
          'conversation': update.conversation != null,
          'thread_hash': _runtimeSafeHash(update.conversation?.threadId),
          'preview_hash': _runtimeSafeHash(
            update.conversation?.lastMessagePreview,
          ),
          'unread': update.conversation?.unreadCount,
        },
      );
      return;
    }
    if (update.group != null) {
      ref.read(groupProvider.notifier).upsertGroup(update.group!);
    }
    final message = update.message;
    final conversationHint = update.conversationHint;
    if (message == null || conversationHint == null) {
      return;
    }
    final normalizedConversationHint =
        normalizeRealtimeConversationPresentationIdentity(
          conversationHint,
          ref.read(agentsProvider).agents,
          didDomain: ref.read(awikiEnvironmentConfigProvider).didDomain,
        );
    final shouldShow = _shouldAcceptRealtimeConversationHint(
      normalizedConversationHint,
    );
    if (!shouldShow) {
      _runtimeTrace(
        'realtime.message.hidden',
        fields: <String, Object?>{
          'thread_hash': _runtimeSafeHash(normalizedConversationHint.threadId),
          'sender_hash': _runtimeSafeHash(message.senderDid),
        },
      );
      return;
    }
    _runtimeTrace(
      'realtime.message_sync_hint',
      fields: <String, Object?>{
        'thread_hash': _runtimeSafeHash(normalizedConversationHint.threadId),
        'message_hash': _runtimeSafeHash(message.remoteId ?? message.localId),
        'is_mine': message.isMine,
        'unread': normalizedConversationHint.unreadCount,
        'preview_hash': _runtimeSafeHash(
          normalizedConversationHint.lastMessagePreview,
        ),
      },
    );
    if (!message.isMine) {
      final title = _notificationTitle(update, normalizedConversationHint);
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
      final isForeground =
          ref.read(appLifecycleProvider) == AppLifecycleState.resumed;
      if (isForeground) {
        ref
            .read(notificationFacadeProvider)
            .showInAppBanner(title: title, body: body);
      } else {
        final target = NotificationTarget(
          storageScopeId: ref.read(activeAppTenantProvider).storageScopeId,
          ownerDid: expectedEpoch.ownerDid,
          conversationId: normalizedConversationHint.conversationId,
        );
        ref
            .read(notificationFacadeProvider)
            .showSystemNotification(title: title, body: body, target: target);
      }
    }
  }

  Future<void> _handleNotificationActivation(
    NotificationActivation activation,
  ) async {
    final epoch = ref.read(sessionProvider).activeEpoch;
    try {
      await ref.read(desktopShellServiceProvider).showWindow();
    } on Object {
      // Routing remains available even when a platform shell is absent.
    }
    if (!_isNotificationEpochCurrent(epoch)) {
      return;
    }
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.messages);
    ref.read(selectedConversationProvider.notifier).clearSelection();
    final target = activation.target;
    if (epoch == null ||
        target == null ||
        target.storageScopeId !=
            ref.read(activeAppTenantProvider).storageScopeId ||
        target.ownerDid != epoch.ownerDid) {
      return;
    }
    try {
      final conversation = await ref
          .read(conversationListProvider.notifier)
          .commitConversationId(target.conversationId, expectedEpoch: epoch);
      if (!_isNotificationEpochCurrent(epoch)) {
        return;
      }
      await ref
          .read(chatThreadsProvider.notifier)
          .openConversation(conversation);
      if (!_isNotificationEpochCurrent(epoch)) {
        return;
      }
      ref
          .read(selectedConversationProvider.notifier)
          .selectConversation(conversation);
    } on Object {
      // A stale/deleted conversation target degrades to the message list.
    }
  }

  bool _isNotificationEpochCurrent(SessionEpoch? epoch) {
    return mounted &&
        !_isLoggingOut &&
        ref.read(sessionProvider).activeEpoch == epoch;
  }

  void _scheduleReliableSync(String reason, {bool immediate = false}) {
    if (!mounted ||
        _isLoggingOut ||
        ref.read(sessionProvider).session == null) {
      return;
    }
    unawaited(
      ref
          .read(messageSyncCoordinatorProvider.notifier)
          .requestSync(reason, immediate: immediate)
          .catchError((_) {}),
    );
  }

  String? _reliableSyncReasonFor(RealtimeUpdate update) {
    if (update.gapDetected) {
      return 'realtime_gap';
    }
    if (update.syncDirty) {
      return 'realtime_dirty';
    }
    if (update.message != null) {
      return 'realtime_message';
    }
    return null;
  }

  bool _shouldAcceptRealtimeConversationHint(ConversationSummary conversation) {
    return shouldShowConversationForChatList(
      conversation,
      ownerDid: ref.read(sessionProvider).session?.did ?? '',
      daemonAgentDids: ref
          .read(agentsProvider)
          .daemonAgents
          .map((agent) => agent.agentDid),
    );
  }

  String _notificationTitle(
    RealtimeUpdate update,
    ConversationSummary conversationHint,
  ) {
    final message = update.message;
    if (message == null) {
      return AppMessage.newMessageArrived().resolveForFallback();
    }
    final title = DidDisplayFormatter.compactDisplayName(
      displayName: message.senderName ?? '',
      fallbackDid: message.senderDid,
    ).trim();
    if (title.isNotEmpty) {
      return title;
    }
    return conversationHint.displayName;
  }

  AppLocalizations _currentLocalizations() {
    final mode = ref.read(appLocaleModeProvider);
    final platformLocale = ui.PlatformDispatcher.instance.locale;
    final effective = resolveEffectiveAppLanguage(mode, platformLocale);
    return lookupAppLocalizations(effective.locale);
  }

  Future<void> _runBusy(
    Future<void> Function() action, {
    bool enforceTimeout = true,
    Future<void> Function()? onFailure,
    bool Function()? shouldReportFailure,
  }) async {
    _beginBusyOperation();
    try {
      final operation = action();
      await (enforceTimeout ? operation.timeout(_requestTimeout) : operation);
    } on TimeoutException {
      await onFailure?.call();
      if (shouldReportFailure?.call() == false) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
    } on AppSessionTransitionSuperseded {
      await onFailure?.call();
    } catch (error) {
      await onFailure?.call();
      if (shouldReportFailure?.call() == false) {
        return;
      }
      final message = AppMessage.fromError(error);
      ref.read(uiFeedbackProvider.notifier).showError(message);
      if (message == AppMessage.sessionExpiredRelogin()) {
        await logout();
      }
    } finally {
      _endBusyOperation();
    }
  }

  Future<AppSessionLease?> _cancelOrAbortSessionTransition(
    AppSessionTransition transition,
  ) async {
    final sessions = ref.read(appSessionServiceProvider);
    sessions.cancelPendingSessionTransition(transition);
    final lease = await sessions.currentSessionLease();
    if (lease != null && identical(lease.transition, transition)) {
      await sessions.abortSessionIfCurrent(lease);
      return null;
    }
    return lease != null && transition.isPredecessorLease(lease) ? lease : null;
  }

  void _beginBusyOperation() {
    _busyOperationCount += 1;
    if (mounted && !state.isBusy) {
      state = state.copyWith(isBusy: true);
    }
  }

  void _endBusyOperation() {
    if (_busyOperationCount > 0) {
      _busyOperationCount -= 1;
    }
    if (mounted && state.isBusy && _busyOperationCount == 0) {
      state = state.copyWith(isBusy: false);
    }
  }

  @override
  void dispose() {
    _invalidateSessionOperations();
    _lifecycleSubscription.close();
    _realtimeStatusSubscription.close();
    _cancelRealtimeUpdates();
    _notificationActivationSubscription.cancel();
    super.dispose();
  }
}

class _SessionEpochOperation {
  const _SessionEpochOperation({required this.epoch, required this.operation});

  final SessionEpoch epoch;
  final Future<void> operation;
}

void _runtimeTrace(String event, {Map<String, Object?> fields = const {}}) {
  if (!_runtimeTraceEnabled) {
    return;
  }
  final details = <String>[];
  for (final entry in fields.entries) {
    final value = entry.value;
    if (value != null) {
      details.add('${entry.key}=${_runtimeFormat(value)}');
    }
  }
  debugPrint(
    details.isEmpty
        ? '[awiki_me][runtime_trace] event=$event'
        : '[awiki_me][runtime_trace] event=$event ${details.join(' ')}',
  );
}

String? _runtimeSafeHash(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return AwikiPerformanceLogger.safeHash(normalized);
}

String _runtimeFormat(Object value) {
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  return _runtimeCollapseWhitespace(value.toString());
}

String _runtimeCollapseWhitespace(String value) {
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

Future<List<SessionIdentity>> _localCredentialsFor(Ref ref) async {
  final identities = await ref
      .read(appSessionServiceProvider)
      .listLocalIdentities();
  return _legacySessionsFromAppSessions(identities);
}

List<SessionIdentity> _legacySessionsFromAppSessions(
  List<AppSession> identities,
) {
  return identities.map(_legacySessionFromAppSession).toList()
    ..sort((a, b) => a.credentialName.compareTo(b.credentialName));
}

const _imCoreCapabilities = BridgeCapabilities(
  profileMarkdown: true,
  localDeleteOnly: true,
  systemPushStub: true,
  e2ee: E2eeCapability(
    supported: false,
    pluginRequired: false,
    enabledByDefault: false,
  ),
);

SessionIdentity _legacySessionFromAppSession(AppSession session) {
  return session.toLegacySessionIdentity();
}

final appRuntimeProvider =
    StateNotifierProvider<AppRuntimeController, AppRuntimeState>(
      (ref) => AppRuntimeController(ref),
    );
