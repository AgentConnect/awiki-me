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
import '../../devices/devices_provider.dart';
import '../../friends/friends_provider.dart';
import '../../group/group_provider.dart';
import '../../profile/profile_provider.dart';
import '../../profile/peer_display_profile_provider.dart';
import '../../shared/formatters/display_formatters.dart';
import '../../shared/formatters/localized_ui_formatters.dart';
import '../../shared/realtime_conversation_identity_projection.dart';
import 'app_lifecycle_provider.dart';
import 'account_state_sync_coordinator_provider.dart';
import 'message_sync_coordinator_provider.dart';
import 'selected_conversation_provider.dart';
import 'session_provider.dart';

const bool _runtimeTraceEnabled = bool.fromEnvironment(
  'AWIKI_RUNTIME_TRACE',
  defaultValue: false,
);
const Set<SyncDomain> _accountStateRealtimeDomains = <SyncDomain>{
  SyncDomain.profile,
  SyncDomain.agentInventory,
  SyncDomain.agentStatus,
  SyncDomain.deviceRegistry,
};

const Object _unsetActivatedDid = Object();

class AppRuntimeState {
  const AppRuntimeState({
    this.isInitialized = false,
    this.isBusy = false,
    this.activatedDid,
    this.authRevoked = false,
  });

  final bool isInitialized;
  final bool isBusy;
  final String? activatedDid;
  final bool authRevoked;

  AppRuntimeState copyWith({
    bool? isInitialized,
    bool? isBusy,
    Object? activatedDid = _unsetActivatedDid,
    bool? authRevoked,
  }) {
    return AppRuntimeState(
      isInitialized: isInitialized ?? this.isInitialized,
      isBusy: isBusy ?? this.isBusy,
      activatedDid: identical(activatedDid, _unsetActivatedDid)
          ? this.activatedDid
          : activatedDid as String?,
      authRevoked: authRevoked ?? this.authRevoked,
    );
  }
}

class AppRuntimeController extends StateNotifier<AppRuntimeState> {
  AppRuntimeController(
    this.ref, {
    Duration foregroundCatchUpInterval = const Duration(seconds: 30),
    Duration realtimeSyncRetryBaseDelay = const Duration(seconds: 2),
    int realtimeSyncRetryLimit = 3,
  }) : _foregroundCatchUpInterval = foregroundCatchUpInterval,
       _realtimeSyncRetryBaseDelay = realtimeSyncRetryBaseDelay,
       _realtimeSyncRetryLimit = realtimeSyncRetryLimit,
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
    _messageSyncSubscription = ref.listen<MessageSyncCoordinatorState>(
      messageSyncCoordinatorProvider,
      _handleMessageSyncChanged,
    );
    _realtimeUpdateSubscription = ref
        .read(realtimeApplicationServiceProvider)
        .updates
        .listen(_applyRealtimeUpdate);
  }

  final Ref ref;
  final Duration _foregroundCatchUpInterval;
  final Duration _realtimeSyncRetryBaseDelay;
  final int _realtimeSyncRetryLimit;
  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _refreshDebounceWindow = Duration(seconds: 2);
  bool _isRecoveringRealtimeSession = false;
  bool _isLoggingOut = false;
  bool _syncAuthRevoked = false;
  Future<void>? _authRevocationFenceOperation;
  Future<void>? _joinedMemberActivation;
  String? _joinedMemberActivationDid;
  Future<void>? _authenticatedRefreshOperation;
  int? _authenticatedRefreshOperationSessionGeneration;
  int? _authenticatedRefreshFollowUpSessionGeneration;
  DateTime? _lastAuthenticatedRefreshStartedAt;
  Timer? _foregroundCatchUpTimer;
  final Set<SyncDomain> _pendingRealtimeSyncDomains = <SyncDomain>{};
  bool _pendingRealtimeUnknownDomain = false;
  String? _pendingRealtimeSyncReason;
  _RealtimeSyncSessionFence? _pendingRealtimeSyncFence;
  Future<void>? _realtimeSyncDispatch;
  Timer? _realtimeSyncRetryTimer;
  int _realtimeSyncRetryAttempt = 0;
  late final ProviderSubscription<AppLifecycleState> _lifecycleSubscription;
  late final ProviderSubscription<AsyncValue<RealtimeConnectionStatus>>
  _realtimeStatusSubscription;
  late final ProviderSubscription<MessageSyncCoordinatorState>
  _messageSyncSubscription;
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
    await _authRevocationFenceOperation;
    final totalWatch = Stopwatch()..start();
    state = state.copyWith(isBusy: true, activatedDid: null);
    try {
      _clearRealtimeSyncHints();
      ref.read(selectedConversationProvider.notifier).clearSelection();
      ref.read(sessionProvider.notifier).setSession(session);
      ref.read(messageSyncCoordinatorProvider.notifier).resetForSession();
      ref.read(accountStateSyncCoordinatorProvider.notifier).resetForSession();
      _syncAuthRevoked = false;
      await AwikiPerformanceLogger.async(
        'app_runtime.activate_session.e2ee',
        () => ref.read(e2eeFacadeProvider).initialize(session),
      );
      _isLoggingOut = false;
      state = state.copyWith(
        isBusy: false,
        isInitialized: true,
        activatedDid: session.did,
        authRevoked: false,
      );
      unawaited(_refreshAuthenticatedDataInBackground(debounce: false));
      _scheduleReliableSync('startup', immediate: true);
      _startForegroundCatchUp();
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
    _syncAuthRevoked = false;
    _clearAuthenticatedUiState();
    state = state.copyWith(
      isBusy: true,
      isInitialized: true,
      activatedDid: null,
      authRevoked: false,
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

  Future<void> activateJoinedMember(String expectedDid) {
    final normalizedDid = expectedDid.trim();
    if (normalizedDid.isEmpty) {
      return Future<void>.error(StateError('joined_identity_did_missing'));
    }
    if (state.activatedDid == normalizedDid &&
        ref.read(sessionProvider).session?.did == normalizedDid) {
      return Future<void>.value();
    }
    final active = _joinedMemberActivation;
    if (active != null) {
      if (_joinedMemberActivationDid != normalizedDid) {
        return Future<void>.error(
          StateError('joined_identity_activation_conflict'),
        );
      }
      return active;
    }

    late final Future<void> operation;
    operation =
        (() async {
          final sessions = ref.read(appSessionServiceProvider);
          final session = await sessions.loginWithIdentity(normalizedDid);
          if (session.did.trim() != normalizedDid) {
            await sessions.logout();
            throw StateError('joined_identity_did_mismatch');
          }
          await activateSession(_legacySessionFromAppSession(session));
          if (state.activatedDid != normalizedDid ||
              ref.read(sessionProvider).session?.did != normalizedDid) {
            throw StateError('joined_identity_activation_incomplete');
          }
        })().whenComplete(() {
          if (identical(_joinedMemberActivation, operation)) {
            _joinedMemberActivation = null;
            _joinedMemberActivationDid = null;
          }
        });
    _joinedMemberActivationDid = normalizedDid;
    _joinedMemberActivation = operation;
    return operation;
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
    _syncAuthRevoked = false;
    _clearAuthenticatedUiState();
    state = state.copyWith(
      isBusy: false,
      isInitialized: true,
      activatedDid: null,
      authRevoked: false,
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
    state = state.copyWith(isBusy: true);
    try {
      _isLoggingOut = true;
      try {
        state = state.copyWith(activatedDid: null);
        _clearAuthenticatedUiState();
        await ref
            .read(appSessionServiceProvider)
            .deleteLocalIdentity(current.credentialName);
        final credentials = await _localCredentialsFor(ref);
        ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      } finally {
        _isLoggingOut = false;
      }
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

  void _clearAuthenticatedUiState() {
    _stopForegroundCatchUp();
    _clearRealtimeSyncHints();
    ref.read(sessionProvider.notifier).clear();
    _clearAuthenticatedProjection();
  }

  void _clearAuthenticatedProjection() {
    ref.read(accountStateSyncCoordinatorProvider.notifier).resetForSession();
    ref.read(profileProvider.notifier).clear();
    ref.read(agentsProvider.notifier).clear();
    ref.read(devicesProvider.notifier).clearAccountStateProjection();
    ref.read(selectedConversationProvider.notifier).clearSelection();
    ref.read(conversationListProvider.notifier).clearLocal();
    ref.read(chatThreadsProvider.notifier).clear();
    ref.read(friendsProvider.notifier).clear();
    ref.read(peerDisplayProfileProvider.notifier).clear();
    ref.read(groupProvider.notifier).clear();
  }

  Future<void> reauthenticateAfterAuthRevoked() => logout();

  void _handleMessageSyncChanged(
    MessageSyncCoordinatorState? previous,
    MessageSyncCoordinatorState next,
  ) {
    if (next.status != MessageSyncCoordinatorStatus.authRevoked ||
        previous?.status == MessageSyncCoordinatorStatus.authRevoked) {
      return;
    }
    late final Future<void> operation;
    operation = _fenceAuthRevokedSession().whenComplete(() {
      if (identical(_authRevocationFenceOperation, operation)) {
        _authRevocationFenceOperation = null;
      }
    });
    _authRevocationFenceOperation = operation;
    unawaited(operation);
  }

  Future<void> _fenceAuthRevokedSession() async {
    if (_syncAuthRevoked || ref.read(sessionProvider).session == null) {
      return;
    }
    _syncAuthRevoked = true;
    _stopForegroundCatchUp();
    _clearAuthenticatedUiState();
    state = state.copyWith(
      isBusy: false,
      isInitialized: true,
      activatedDid: null,
      authRevoked: true,
    );
    ref
        .read(uiFeedbackProvider.notifier)
        .showError(AppMessage.sessionExpiredRelogin());
    try {
      await ref.read(realtimeApplicationServiceProvider).stop();
    } catch (_) {
      // The local auth fence remains authoritative even if transport teardown
      // reports a best-effort failure.
    }
    try {
      await ref.read(appSessionServiceProvider).logout();
    } catch (_) {
      // The in-memory session and projections are already fenced. A later
      // explicit sign-in can replace any stale host session pointer.
    }
    if (mounted && _syncAuthRevoked) {
      _clearAuthenticatedProjection();
    }
  }

  Future<void> _rollbackSessionActivationBestEffort() async {
    _syncAuthRevoked = false;
    _clearAuthenticatedUiState();
    state = state.copyWith(
      isBusy: false,
      isInitialized: true,
      activatedDid: null,
      authRevoked: false,
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
    final sessionFence = _AuthenticatedRefreshSessionFence.capture(
      ref.read(sessionProvider),
    );
    if (sessionFence == null || !_isCurrentAuthenticatedRefresh(sessionFence)) {
      return;
    }

    unawaited(
      AwikiPerformanceLogger.async(
        'app_refresh.product_store_warm_up',
        () => ref.read(productLocalStoreProvider).warmUp(),
      ).catchError((_) {}),
    );

    final conversationCurrent = await _runAuthenticatedRefreshDomain(
      sessionFence,
      label: 'app_refresh.conversation_fast_local',
      action: () =>
          ref.read(conversationListProvider.notifier).refreshFastLocal(),
      clearStale: _clearAuthenticatedProjection,
    );
    if (!conversationCurrent) {
      return;
    }

    final hasStableAccountBinding =
        sessionFence.ownerIdentityId != null && sessionFence.accountId != null;
    final domainsCurrent = await Future.wait<bool>(<Future<bool>>[
      if (hasStableAccountBinding)
        _runAuthenticatedRefreshDomain(
          sessionFence,
          label: 'app_refresh.account_state',
          action: () => ref
              .read(accountStateSyncCoordinatorProvider.notifier)
              .request('authenticated_refresh'),
          clearStale: () {
            ref.read(profileProvider.notifier).clear();
            ref.read(agentsProvider.notifier).clear();
            ref.read(devicesProvider.notifier).clearAccountStateProjection();
          },
        )
      else ...<Future<bool>>[
        _runAuthenticatedRefreshDomain(
          sessionFence,
          label: 'app_refresh.profile_legacy_unbound',
          action: () => ref.read(profileProvider.notifier).refresh(),
          clearStale: () => ref.read(profileProvider.notifier).clear(),
        ),
        _runAuthenticatedRefreshDomain(
          sessionFence,
          label: 'app_refresh.agents_legacy_unbound',
          action: () => ref.read(agentsProvider.notifier).syncRemoteInventory(),
          clearStale: () => ref.read(agentsProvider.notifier).clear(),
        ),
      ],
      _runAuthenticatedRefreshDomain(
        sessionFence,
        label: 'app_refresh.friends',
        action: () => ref.read(friendsProvider.notifier).refresh(),
        clearStale: () => ref.read(friendsProvider.notifier).clear(),
      ),
      _runAuthenticatedRefreshDomain(
        sessionFence,
        label: 'app_refresh.groups',
        action: () => ref.read(groupProvider.notifier).refresh(),
        clearStale: () => ref.read(groupProvider.notifier).clear(),
      ),
    ]);
    if (domainsCurrent.any((current) => !current) ||
        !_isCurrentAuthenticatedRefresh(sessionFence)) {
      return;
    }
    totalWatch.stop();
    AwikiPerformanceLogger.log(
      'app_refresh.authenticated_data',
      elapsed: totalWatch.elapsed,
    );
  }

  bool get _canRefreshAuthenticatedData =>
      mounted &&
      !_isLoggingOut &&
      !_syncAuthRevoked &&
      ref.read(sessionProvider).session != null;

  bool _isCurrentAuthenticatedRefresh(_AuthenticatedRefreshSessionFence fence) {
    return _canRefreshAuthenticatedData &&
        fence.matches(ref.read(sessionProvider));
  }

  Future<bool> _runAuthenticatedRefreshDomain(
    _AuthenticatedRefreshSessionFence fence, {
    required String label,
    required Future<void> Function() action,
    required void Function() clearStale,
  }) async {
    if (!_isCurrentAuthenticatedRefresh(fence)) {
      return false;
    }
    try {
      await AwikiPerformanceLogger.async(label, action);
    } finally {
      if (!_isCurrentAuthenticatedRefresh(fence) && mounted) {
        clearStale();
      }
    }
    return _isCurrentAuthenticatedRefresh(fence);
  }

  Future<void> _refreshAuthenticatedDataInBackground({bool debounce = true}) {
    final active = _authenticatedRefreshOperation;
    if (active != null) {
      final requestedGeneration = ref.read(sessionProvider).generation;
      if (requestedGeneration !=
          _authenticatedRefreshOperationSessionGeneration) {
        _authenticatedRefreshFollowUpSessionGeneration = requestedGeneration;
      }
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
    final operationSessionGeneration = ref.read(sessionProvider).generation;
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
            await _refreshAuthenticatedData();
          } on TimeoutException {
            return;
          } catch (error) {
            if (!mounted) {
              return;
            }
            if (_isLoggingOut ||
                _syncAuthRevoked ||
                ref.read(sessionProvider).session == null) {
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
            _authenticatedRefreshOperationSessionGeneration = null;
          }
          if (mounted && _syncAuthRevoked) {
            _clearAuthenticatedProjection();
          }
          final followUpGeneration =
              _authenticatedRefreshFollowUpSessionGeneration;
          _authenticatedRefreshFollowUpSessionGeneration = null;
          if (followUpGeneration != null &&
              mounted &&
              ref.read(sessionProvider).generation == followUpGeneration &&
              _canRefreshAuthenticatedData) {
            unawaited(_refreshAuthenticatedDataInBackground(debounce: false));
          }
        });
    _authenticatedRefreshOperation = operation;
    _authenticatedRefreshOperationSessionGeneration =
        operationSessionGeneration;
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
      _stopForegroundCatchUp();
      ref.read(chatThreadsProvider.notifier).trimForAppBackground();
      return;
    }
    if (next != AppLifecycleState.resumed) {
      return;
    }
    if (_syncAuthRevoked) {
      return;
    }
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return;
    }
    _startForegroundCatchUp();
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
      if (_isLoggingOut || _syncAuthRevoked) {
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
    if (_syncAuthRevoked) {
      return;
    }
    _scheduleReliableSync('realtime_reconnected');
    unawaited(_refreshAuthenticatedDataInBackground());
  }

  void _ensureRealtimeConnected() {
    if (_isLoggingOut ||
        _syncAuthRevoked ||
        ref.read(sessionProvider).session == null) {
      return;
    }
    final realtime = ref.read(realtimeApplicationServiceProvider);
    if (realtime.isRunning) {
      return;
    }
    unawaited(realtime.start().catchError((_) {}));
  }

  void _startForegroundCatchUp() {
    _foregroundCatchUpTimer?.cancel();
    _foregroundCatchUpTimer = null;
    if (_foregroundCatchUpInterval <= Duration.zero ||
        _isLoggingOut ||
        _syncAuthRevoked ||
        ref.read(sessionProvider).session == null ||
        ref.read(appLifecycleProvider) != AppLifecycleState.resumed) {
      return;
    }
    _foregroundCatchUpTimer = Timer.periodic(_foregroundCatchUpInterval, (_) {
      if (!mounted ||
          _isLoggingOut ||
          _syncAuthRevoked ||
          ref.read(sessionProvider).session == null ||
          ref.read(appLifecycleProvider) != AppLifecycleState.resumed) {
        _stopForegroundCatchUp();
        return;
      }
      _scheduleReliableSync('foreground_catch_up');
      unawaited(
        ref
            .read(accountStateSyncCoordinatorProvider.notifier)
            .request('foreground_catch_up'),
      );
    });
  }

  void _stopForegroundCatchUp() {
    _foregroundCatchUpTimer?.cancel();
    _foregroundCatchUpTimer = null;
  }

  Future<void> _recoverRealtimeSession() async {
    if (_isLoggingOut || _syncAuthRevoked || _isRecoveringRealtimeSession) {
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
          _syncAuthRevoked ||
          ref.read(sessionProvider).session == null) {
        return;
      }
      if (refreshed != null) {
        ref
            .read(sessionProvider.notifier)
            .setSession(_legacySessionFromAppSession(refreshed));
        ref.read(messageSyncCoordinatorProvider.notifier).resetForSession();
      }
      await _refreshAuthenticatedDataInBackground();
      if (!mounted ||
          _isLoggingOut ||
          _syncAuthRevoked ||
          ref.read(sessionProvider).session == null) {
        return;
      }
      if (refreshed != null) {
        _ensureRealtimeConnected();
      }
    } catch (_) {
      if (mounted &&
          !_isLoggingOut &&
          !_syncAuthRevoked &&
          ref.read(sessionProvider).session != null) {
        await _refreshAuthenticatedDataInBackground();
      }
    } finally {
      _isRecoveringRealtimeSession = false;
    }
  }

  void _applyRealtimeUpdate(RealtimeUpdate update) {
    if (_isLoggingOut ||
        _syncAuthRevoked ||
        ref.read(sessionProvider).session == null) {
      return;
    }
    final traceConversation = update.conversation ?? update.conversationHint;
    _runtimeTrace(
      'realtime.update',
      fields: <String, Object?>{
        'control': update.agentControlPayload != null,
        'system_notification': update.systemNotificationChanged,
        'message': update.message != null,
        'conversation': traceConversation != null,
        'conversation_hint': update.conversationHint != null,
        'sync_dirty': update.syncDirty,
        'gap': update.gapDetected,
        'unknown_domain': update.hasUnknownDomain,
        'domains': update.domains.map((domain) => domain.name).join(','),
        'reason': update.reason,
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
    if (update.systemNotificationChanged) {
      unawaited(
        ref
            .read(devicesProvider.notifier)
            .refreshJoinInbox()
            .catchError((_) {}),
      );
    }
    if (reliableSyncReason != null) {
      _runtimeTrace(
        'reliable_sync.schedule',
        fields: <String, Object?>{
          'reason': reliableSyncReason,
          'domains': update.domains.map((domain) => domain.name).join(','),
          'unknown_domain': update.hasUnknownDomain,
        },
      );
      _scheduleRealtimeSync(update, reliableSyncReason);
    }
    final controlPayload = update.agentControlPayload;
    if (controlPayload != null) {
      ref.read(agentInboxProvider.notifier).applyControlPayload(controlPayload);
      ref
          .read(chatThreadsProvider.notifier)
          .applyAgentRunStatusPayload(controlPayload);
      ref
          .read(chatThreadsProvider.notifier)
          .applyPersonalAgentControlPayload(controlPayload);
      _runtimeTrace(
        'realtime.control_hint',
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
    final v2MessageReadEnabled = ref.read(messageSyncV2ReadEnabledProvider);
    if (v2MessageReadEnabled && _isStageTwoPersistentRealtimeFact(update)) {
      _runtimeTrace(
        'realtime.persistent_fact_pull_only',
        fields: <String, Object?>{
          'message': update.message != null,
          'group': update.group != null,
          'conversation_hint': update.conversationHint != null,
          'domains': update.domains.map((domain) => domain.name).join(','),
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
        _syncAuthRevoked ||
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

  void _scheduleRealtimeSync(RealtimeUpdate update, String fallbackReason) {
    final sessionState = ref.read(sessionProvider);
    final fence = _RealtimeSyncSessionFence.capture(sessionState);
    if (fence == null) {
      _scheduleReliableSync(fallbackReason);
      return;
    }

    final domains = <SyncDomain>{...update.domains};
    if (domains.isEmpty &&
        !update.hasUnknownDomain &&
        (update.syncDirty ||
            update.gapDetected ||
            update.systemNotificationChanged ||
            update.message != null ||
            update.group != null ||
            update.conversationHint != null ||
            update.agentControlPayload != null)) {
      domains.add(SyncDomain.message);
    }
    if (domains.isEmpty && !update.hasUnknownDomain) {
      return;
    }

    final pendingFence = _pendingRealtimeSyncFence;
    if (pendingFence != null && !pendingFence.sameSession(fence)) {
      _clearRealtimeSyncHints();
    }
    _pendingRealtimeSyncFence = fence;
    _pendingRealtimeSyncDomains.addAll(domains);
    _pendingRealtimeUnknownDomain =
        _pendingRealtimeUnknownDomain || update.hasUnknownDomain;
    _realtimeSyncRetryAttempt = 0;
    _pendingRealtimeSyncReason = update.reason?.trim().isNotEmpty == true
        ? update.reason!.trim()
        : fallbackReason;
    _startRealtimeSyncDrain();
  }

  void _startRealtimeSyncDrain() {
    if (_realtimeSyncDispatch != null ||
        _realtimeSyncRetryTimer != null ||
        _pendingRealtimeSyncFence == null ||
        (_pendingRealtimeSyncDomains.isEmpty &&
            !_pendingRealtimeUnknownDomain)) {
      return;
    }
    late final Future<void> operation;
    operation = Future<void>.microtask(_drainRealtimeSyncHints).whenComplete(
      () {
        if (identical(_realtimeSyncDispatch, operation)) {
          _realtimeSyncDispatch = null;
        }
        if (mounted &&
            _pendingRealtimeSyncFence != null &&
            (_pendingRealtimeSyncDomains.isNotEmpty ||
                _pendingRealtimeUnknownDomain)) {
          _startRealtimeSyncDrain();
        }
      },
    );
    _realtimeSyncDispatch = operation;
  }

  Future<void> _drainRealtimeSyncHints() async {
    while (mounted) {
      final fence = _pendingRealtimeSyncFence;
      if (fence == null) {
        _clearRealtimeSyncHints();
        return;
      }
      if (!fence.matches(ref.read(sessionProvider))) {
        _clearRealtimeSyncHints(expectedFence: fence);
        return;
      }
      if (_pendingRealtimeSyncDomains.isEmpty &&
          !_pendingRealtimeUnknownDomain) {
        return;
      }

      final domains = Set<SyncDomain>.of(_pendingRealtimeSyncDomains);
      final hasUnknownDomain = _pendingRealtimeUnknownDomain;
      final reason = _pendingRealtimeSyncReason ?? 'realtime_domain_changed';
      _pendingRealtimeSyncDomains.clear();
      _pendingRealtimeUnknownDomain = false;
      _pendingRealtimeSyncReason = null;

      final actions = <Future<void>>[];
      final failedDomains = <SyncDomain>{};
      var unknownDomainFailed = false;
      if (domains.contains(SyncDomain.message)) {
        actions.add(
          (() async {
            try {
              await ref
                  .read(messageSyncCoordinatorProvider.notifier)
                  .requestSync(reason);
              if (ref.read(messageSyncCoordinatorProvider).status ==
                  MessageSyncCoordinatorStatus.retryableFailure) {
                failedDomains.add(SyncDomain.message);
              }
            } on Object {
              failedDomains.add(SyncDomain.message);
            }
          })(),
        );
      }
      final accountDomains = domains
          .where(_accountStateRealtimeDomains.contains)
          .toSet();
      if (hasUnknownDomain || accountDomains.isNotEmpty) {
        actions.add(
          (() async {
            try {
              await ref
                  .read(accountStateSyncRequestBusProvider)
                  .request(reason);
            } on Object {
              failedDomains.addAll(accountDomains);
              unknownDomainFailed = hasUnknownDomain;
            }
          })(),
        );
      }
      if (actions.isNotEmpty) {
        await Future.wait(actions);
      }
      if (!fence.matches(ref.read(sessionProvider))) {
        _clearRealtimeSyncHints(expectedFence: fence);
        return;
      }
      if (failedDomains.isNotEmpty || unknownDomainFailed) {
        _scheduleRealtimeSyncRetry(
          fence: fence,
          domains: failedDomains,
          hasUnknownDomain: unknownDomainFailed,
          reason: reason,
        );
        return;
      }
      _realtimeSyncRetryAttempt = 0;
      if (_pendingRealtimeSyncDomains.isEmpty &&
          !_pendingRealtimeUnknownDomain) {
        _clearRealtimeSyncHints(expectedFence: fence);
        return;
      }
    }
  }

  void _scheduleRealtimeSyncRetry({
    required _RealtimeSyncSessionFence fence,
    required Set<SyncDomain> domains,
    required bool hasUnknownDomain,
    required String reason,
  }) {
    if (_realtimeSyncRetryAttempt >= _realtimeSyncRetryLimit) {
      _clearRealtimeSyncHints(expectedFence: fence);
      return;
    }
    final pendingFence = _pendingRealtimeSyncFence;
    if (pendingFence != null && !pendingFence.sameSession(fence)) {
      return;
    }
    _pendingRealtimeSyncFence = fence;
    _pendingRealtimeSyncDomains.addAll(domains);
    _pendingRealtimeUnknownDomain =
        _pendingRealtimeUnknownDomain || hasUnknownDomain;
    _pendingRealtimeSyncReason ??= reason;
    _realtimeSyncRetryAttempt += 1;
    final multiplier = 1 << (_realtimeSyncRetryAttempt - 1);
    final delay = _realtimeSyncRetryBaseDelay * multiplier;
    _realtimeSyncRetryTimer ??= Timer(delay, () {
      _realtimeSyncRetryTimer = null;
      if (!mounted || !fence.matches(ref.read(sessionProvider))) {
        _clearRealtimeSyncHints(expectedFence: fence);
        return;
      }
      _startRealtimeSyncDrain();
    });
  }

  void _clearRealtimeSyncHints({_RealtimeSyncSessionFence? expectedFence}) {
    final pendingFence = _pendingRealtimeSyncFence;
    if (expectedFence != null &&
        pendingFence != null &&
        !pendingFence.sameSession(expectedFence)) {
      return;
    }
    _pendingRealtimeSyncDomains.clear();
    _pendingRealtimeUnknownDomain = false;
    _pendingRealtimeSyncReason = null;
    _pendingRealtimeSyncFence = null;
    _realtimeSyncRetryTimer?.cancel();
    _realtimeSyncRetryTimer = null;
    _realtimeSyncRetryAttempt = 0;
  }

  String? _reliableSyncReasonFor(RealtimeUpdate update) {
    if (update.agentControlPayload != null) {
      return 'realtime_agent_control';
    }
    if (update.systemNotificationChanged) {
      return 'system_notification_changed';
    }
    if (update.gapDetected) {
      return 'realtime_gap';
    }
    if (update.syncDirty) {
      return update.reason?.trim().isNotEmpty == true
          ? update.reason!.trim()
          : 'realtime_dirty';
    }
    if (update.domains.isNotEmpty || update.hasUnknownDomain) {
      return update.reason?.trim().isNotEmpty == true
          ? update.reason!.trim()
          : 'realtime_domain_changed';
    }
    if (update.message != null) {
      return 'realtime_message';
    }
    if (update.group != null || update.conversationHint != null) {
      return 'realtime_persistent_fact';
    }
    return null;
  }

  bool _isStageTwoPersistentRealtimeFact(RealtimeUpdate update) {
    final message = update.message;
    if (message != null) {
      return !message.isEncrypted;
    }
    return update.domains.contains(SyncDomain.message);
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
    _stopForegroundCatchUp();
    _clearRealtimeSyncHints();
    _lifecycleSubscription.close();
    _realtimeStatusSubscription.close();
    _messageSyncSubscription.close();
    _realtimeUpdateSubscription.cancel();
    super.dispose();
  }
}

class _RealtimeSyncSessionFence {
  const _RealtimeSyncSessionFence({
    required this.generation,
    required this.ownerIdentityId,
    required this.accountId,
    required this.did,
  });

  static _RealtimeSyncSessionFence? capture(SessionState state) {
    final session = state.session;
    final ownerIdentityId = session?.ownerIdentityId?.trim();
    final accountId = session?.accountId?.trim();
    if (session == null ||
        ownerIdentityId == null ||
        ownerIdentityId.isEmpty ||
        accountId == null ||
        accountId.isEmpty) {
      return null;
    }
    return _RealtimeSyncSessionFence(
      generation: state.generation,
      ownerIdentityId: ownerIdentityId,
      accountId: accountId,
      did: session.did,
    );
  }

  final int generation;
  final String ownerIdentityId;
  final String accountId;
  final String did;

  bool matches(SessionState state) {
    final next = capture(state);
    return next != null && sameSession(next);
  }

  bool sameSession(_RealtimeSyncSessionFence other) =>
      other.generation == generation &&
      other.ownerIdentityId == ownerIdentityId &&
      other.accountId == accountId &&
      other.did == did;
}

class _AuthenticatedRefreshSessionFence {
  const _AuthenticatedRefreshSessionFence({
    required this.generation,
    required this.ownerIdentityId,
    required this.accountId,
    required this.did,
  });

  static _AuthenticatedRefreshSessionFence? capture(SessionState state) {
    final session = state.session;
    if (session == null) {
      return null;
    }
    return _AuthenticatedRefreshSessionFence(
      generation: state.generation,
      ownerIdentityId: session.ownerIdentityId,
      accountId: session.accountId,
      did: session.did,
    );
  }

  final int generation;
  final String? ownerIdentityId;
  final String? accountId;
  final String did;

  bool matches(SessionState state) {
    final session = state.session;
    return session != null &&
        state.generation == generation &&
        session.ownerIdentityId == ownerIdentityId &&
        session.accountId == accountId &&
        session.did == did;
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
