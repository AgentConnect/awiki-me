import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/l10n/app_localizations.dart';

import '../../../app/app_locale.dart';
import '../../../app/app_services.dart';
import '../../../app/ui_feedback.dart';
import '../../../core/performance_logger.dart';
import '../../../application/models/app_session.dart';
import '../../../application/agent/agent_control_projection.dart';
import '../../../domain/entities/bridge_capabilities.dart';
import '../../../domain/entities/conversation_summary.dart';
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
import '../../profile/profile_provider.dart';
import '../../profile/peer_display_profile_provider.dart';
import '../../shared/formatters/display_formatters.dart';
import '../../shared/formatters/localized_ui_formatters.dart';
import '../../shared/realtime_conversation_identity_projection.dart';
import 'app_lifecycle_provider.dart';
import 'message_sync_coordinator_provider.dart';
import 'selected_conversation_provider.dart';
import 'session_provider.dart';

const bool _runtimeTraceEnabled = bool.fromEnvironment(
  'AWIKI_RUNTIME_TRACE',
  defaultValue: false,
);

const Object _unsetActivatedDid = Object();

class AppRuntimeState {
  const AppRuntimeState({
    this.isInitialized = false,
    this.isBusy = false,
    this.activatedDid,
  });

  final bool isInitialized;
  final bool isBusy;
  final String? activatedDid;

  AppRuntimeState copyWith({
    bool? isInitialized,
    bool? isBusy,
    Object? activatedDid = _unsetActivatedDid,
  }) {
    return AppRuntimeState(
      isInitialized: isInitialized ?? this.isInitialized,
      isBusy: isBusy ?? this.isBusy,
      activatedDid: identical(activatedDid, _unsetActivatedDid)
          ? this.activatedDid
          : activatedDid as String?,
    );
  }
}

class AppRuntimeController extends StateNotifier<AppRuntimeState> {
  AppRuntimeController(this.ref) : super(const AppRuntimeState()) {
    _lifecycleSubscription = ref.listen<AppLifecycleState>(
      appLifecycleProvider,
      _handleLifecycleChanged,
    );
    _realtimeStatusSubscription = ref
        .listen<AsyncValue<RealtimeConnectionStatus>>(
          realtimeConnectionStatusProvider,
          _handleRealtimeStatusChanged,
        );
    _realtimeUpdateSubscription = ref
        .read(realtimeApplicationServiceProvider)
        .updates
        .listen(_applyRealtimeUpdate);
  }

  final Ref ref;
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _refreshDebounceWindow = Duration(seconds: 2);
  bool _isRecoveringRealtimeSession = false;
  bool _isLoggingOut = false;
  Future<void>? _authenticatedRefreshOperation;
  DateTime? _lastAuthenticatedRefreshStartedAt;
  late final ProviderSubscription<AppLifecycleState> _lifecycleSubscription;
  late final ProviderSubscription<AsyncValue<RealtimeConnectionStatus>>
  _realtimeStatusSubscription;
  late final StreamSubscription<RealtimeUpdate> _realtimeUpdateSubscription;

  Future<void> initialize() async {
    if (state.isInitialized) {
      return;
    }
    state = state.copyWith(isBusy: true);
    var restoreStarted = false;
    var runtimeActivationStarted = false;
    try {
      final sessions = ref.read(appSessionServiceProvider);
      final localIdentities = await sessions.listLocalIdentities();
      final localCredentials = _legacySessionsFromAppSessions(localIdentities);
      ref.read(sessionProvider.notifier).setCapabilities(_imCoreCapabilities);
      ref.read(sessionProvider.notifier).setLocalCredentials(localCredentials);

      restoreStarted = true;
      final session = await sessions.restoreSession();
      if (session != null) {
        runtimeActivationStarted = true;
        await activateSession(_legacySessionFromAppSession(session));
      }
      state = state.copyWith(isInitialized: true, isBusy: false);
    } on TimeoutException {
      if (restoreStarted && !runtimeActivationStarted) {
        await _rollbackSessionActivationBestEffort();
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
      state = state.copyWith(isBusy: false, isInitialized: true);
    } catch (error) {
      if (restoreStarted && !runtimeActivationStarted) {
        await _rollbackSessionActivationBestEffort();
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
      state = state.copyWith(isBusy: false, isInitialized: true);
    }
  }

  Future<void> activateSession(SessionIdentity session) async {
    final totalWatch = Stopwatch()..start();
    state = state.copyWith(isBusy: true, activatedDid: null);
    try {
      ref.read(selectedConversationProvider.notifier).clearSelection();
      ref.read(sessionProvider.notifier).setSession(session);
      await AwikiPerformanceLogger.async(
        'app_runtime.activate_session.e2ee',
        () => ref.read(e2eeFacadeProvider).initialize(session),
      );
      _isLoggingOut = false;
      state = state.copyWith(
        isBusy: false,
        isInitialized: true,
        activatedDid: session.did,
      );
      unawaited(_refreshAuthenticatedDataInBackground(debounce: false));
      _scheduleReliableSync('startup', immediate: true);
      _ensureRealtimeConnected();
    } catch (error, stackTrace) {
      await _rollbackSessionActivationBestEffort();
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      state = state.copyWith(isBusy: false, isInitialized: true);
      totalWatch.stop();
      AwikiPerformanceLogger.log(
        'app_runtime.activate_session',
        elapsed: totalWatch.elapsed,
      );
    }
  }

  Future<void> prepareIdentityActivation() async {
    _isLoggingOut = true;
    _clearAuthenticatedUiState();
    state = state.copyWith(
      isBusy: true,
      isInitialized: true,
      activatedDid: null,
    );
    try {
      await ref.read(realtimeApplicationServiceProvider).stop();
    } catch (error, stackTrace) {
      await _rollbackSessionActivationBestEffort();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> rollbackIdentityActivation() {
    return _rollbackSessionActivationBestEffort();
  }

  Future<void> loginWithLocalCredential(String credentialName) async {
    await _runBusy(() async {
      final session = await ref
          .read(appSessionServiceProvider)
          .loginWithIdentity(credentialName);
      await activateSession(_legacySessionFromAppSession(session));
    });
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
    state = state.copyWith(
      isBusy: false,
      isInitialized: true,
      activatedDid: null,
    );
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
        state = state.copyWith(activatedDid: null);
        ref.read(sessionProvider.notifier).clear();
        ref.read(profileProvider.notifier).clear();
        ref.read(agentsProvider.notifier).clear();
        ref.read(selectedConversationProvider.notifier).clearSelection();
        await ref.read(conversationListProvider.notifier).clear();
        ref.read(chatThreadsProvider.notifier).clear();
        ref.read(friendsProvider.notifier).clear();
        ref.read(peerDisplayProfileProvider.notifier).clear();
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
    ref.read(profileProvider.notifier).clear();
    ref.read(agentsProvider.notifier).clear();
    ref.read(selectedConversationProvider.notifier).clearSelection();
    ref.read(conversationListProvider.notifier).clearLocal();
    ref.read(chatThreadsProvider.notifier).clear();
    ref.read(friendsProvider.notifier).clear();
    ref.read(peerDisplayProfileProvider.notifier).clear();
    ref.read(groupProvider.notifier).clear();
  }

  Future<void> _rollbackSessionActivationBestEffort() async {
    _clearAuthenticatedUiState();
    state = state.copyWith(
      isBusy: false,
      isInitialized: true,
      activatedDid: null,
    );
    try {
      await ref.read(appSessionServiceProvider).logout();
    } catch (_) {
      // Keep the original activation failure authoritative.
    } finally {
      _isLoggingOut = false;
    }
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

  Future<void> _refreshAuthenticatedData() async {
    final totalWatch = Stopwatch()..start();
    if (!_canRefreshAuthenticatedData) {
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
    if (!_canRefreshAuthenticatedData) {
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
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'app_refresh.authenticated_data',
      elapsed: totalWatch.elapsed,
    );
  }

  bool get _canRefreshAuthenticatedData =>
      mounted && !_isLoggingOut && ref.read(sessionProvider).session != null;

  Future<void> _refreshAuthenticatedDataInBackground({bool debounce = true}) {
    final active = _authenticatedRefreshOperation;
    if (active != null) {
      AwikiPerformanceLogger.log(
        'app_refresh.authenticated_data.request',
        fields: const <String, Object?>{'reused': true},
      );
      return active;
    }
    final now = DateTime.now();
    final lastStarted = _lastAuthenticatedRefreshStartedAt;
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
          _lastAuthenticatedRefreshStartedAt = DateTime.now();
          try {
            await _refreshAuthenticatedData().timeout(_requestTimeout);
          } on TimeoutException {
            return;
          } catch (error) {
            if (!mounted) {
              return;
            }
            if (_isLoggingOut || ref.read(sessionProvider).session == null) {
              return;
            }
            final message = AppMessage.fromError(error);
            if (message == AppMessage.sessionExpiredRelogin()) {
              ref.read(uiFeedbackProvider.notifier).showError(message);
              await logout();
            }
          }
        })().whenComplete(() {
          if (identical(_authenticatedRefreshOperation, operation)) {
            _authenticatedRefreshOperation = null;
          }
        });
    _authenticatedRefreshOperation = operation;
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
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return;
    }
    _ensureRealtimeConnected();
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
    if (ref.read(sessionProvider).session == null) {
      return;
    }
    _scheduleReliableSync('realtime_reconnected');
    unawaited(_refreshAuthenticatedDataInBackground());
  }

  void _ensureRealtimeConnected() {
    if (_isLoggingOut || ref.read(sessionProvider).session == null) {
      return;
    }
    final realtime = ref.read(realtimeApplicationServiceProvider);
    if (realtime.isRunning) {
      return;
    }
    unawaited(realtime.start().catchError((_) {}));
  }

  Future<void> _recoverRealtimeSession() async {
    if (_isLoggingOut || _isRecoveringRealtimeSession) {
      return;
    }
    _isRecoveringRealtimeSession = true;
    try {
      if (ref.read(sessionProvider).session == null) {
        return;
      }
      final refreshed = await ref
          .read(appSessionServiceProvider)
          .refreshSession();
      if (!mounted ||
          _isLoggingOut ||
          ref.read(sessionProvider).session == null) {
        return;
      }
      if (refreshed != null) {
        ref
            .read(sessionProvider.notifier)
            .setSession(_legacySessionFromAppSession(refreshed));
      }
      await _refreshAuthenticatedDataInBackground();
      if (!mounted ||
          _isLoggingOut ||
          ref.read(sessionProvider).session == null) {
        return;
      }
      if (refreshed != null) {
        _ensureRealtimeConnected();
      }
    } catch (_) {
      if (mounted &&
          !_isLoggingOut &&
          ref.read(sessionProvider).session != null) {
        await _refreshAuthenticatedDataInBackground();
      }
    } finally {
      _isRecoveringRealtimeSession = false;
    }
  }

  void _applyRealtimeUpdate(RealtimeUpdate update) {
    if (_isLoggingOut || ref.read(sessionProvider).session == null) return;
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
          .applyPersonalAgentControlPayload(controlPayload);
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
        ref
            .read(notificationFacadeProvider)
            .showSystemNotification(title: title, body: body);
      }
    }
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

  Future<void> _runBusy(Future<void> Function() action) async {
    state = state.copyWith(isBusy: true);
    try {
      await action().timeout(_requestTimeout);
    } on TimeoutException {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
    } catch (error) {
      final message = AppMessage.fromError(error);
      ref.read(uiFeedbackProvider.notifier).showError(message);
      if (message == AppMessage.sessionExpiredRelogin()) {
        await logout();
      }
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  @override
  void dispose() {
    _lifecycleSubscription.close();
    _realtimeStatusSubscription.close();
    _realtimeUpdateSubscription.cancel();
    super.dispose();
  }
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
