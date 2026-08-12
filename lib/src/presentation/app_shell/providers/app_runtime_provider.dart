// [INPUT]: Session, lifecycle, realtime, reliable-sync, push, local-store, and projection providers.
// [OUTPUT]: One fenced authenticated runtime, confirmed activation results,
// navigation-ready App state, and exact-owner deletion.
// [POS]: App-wide orchestration boundary; Core remains the message and identity truth.

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
import '../../../application/remote_push_installation_coordinator.dart';
import '../../../application/remote_push_message_sync_coordinator.dart';
import '../../../application/ports/remote_push_sync_port.dart';
import '../../../application/agent/agent_control_projection.dart';
import '../../../application/tenant/app_tenant.dart';
import '../../../domain/entities/bridge_capabilities.dart';
import '../../../domain/entities/conversation_summary.dart';
import '../../../domain/entities/notification_target.dart';
import '../../../domain/entities/agent/agent_terminal_notification.dart';
import '../../../domain/entities/realtime_update.dart';
import '../../../domain/entities/session_identity.dart';
import '../../../domain/services/realtime_gateway.dart';
import '../../../l10n/app_message.dart';
import '../../agents/agent_inbox_provider.dart';
import '../../agents/agents_provider.dart';
import '../../agents/personal_agent_feature_visibility.dart';
import '../../chat/chat_provider.dart';
import '../../conversation_list/conversation_provider.dart';
import '../../friends/friends_navigation_provider.dart';
import '../../devices/devices_provider.dart';
import '../../friends/friends_provider.dart';
import '../../group/group_provider.dart';
import '../../profile/peer_display_profile_provider.dart';
import '../../profile/peer_profile_provider.dart';
import '../../profile/profile_provider.dart';
import '../../shared/formatters/localized_ui_formatters.dart';
import '../../shared/realtime_conversation_identity_projection.dart';
import 'app_lifecycle_provider.dart';
import 'account_state_sync_coordinator_provider.dart';
import 'agent_terminal_notification_provider.dart';
import 'message_sync_coordinator_provider.dart';
import 'navigation_provider.dart';
import 'ordinary_message_presentation_policy.dart';
import 'remote_push_coordinator_provider.dart';
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

RemotePushInstallationSession? resolveRemotePushInstallationSession({
  required StorageScopeId? storageScopeId,
  required SessionState sessionState,
}) {
  final session = sessionState.session;
  final epoch = sessionState.activeEpoch;
  final binding = session?.accountBinding;
  if (storageScopeId == null || session == null || epoch == null) {
    return null;
  }
  if (binding != null && binding.currentDid.trim() != epoch.ownerDid) {
    return null;
  }
  final protocolDeviceId = binding?.protocolDeviceId.trim();
  return RemotePushInstallationSession(
    storageScopeId: storageScopeId,
    ownerDid: epoch.ownerDid,
    generation: epoch.generation,
    logicalDeviceId: protocolDeviceId == null || protocolDeviceId.isEmpty
        ? null
        : protocolDeviceId,
  );
}

class AppRuntimeController extends StateNotifier<AppRuntimeState> {
  AppRuntimeController(
    this.ref, {
    Duration requestTimeout = const Duration(seconds: 20),
    Duration foregroundCatchUpInterval = const Duration(seconds: 30),
    Duration realtimeSyncRetryBaseDelay = const Duration(seconds: 2),
    int realtimeSyncRetryLimit = 3,
  }) : _requestTimeout = requestTimeout,
       _foregroundCatchUpInterval = foregroundCatchUpInterval,
       _realtimeSyncRetryBaseDelay = realtimeSyncRetryBaseDelay,
       _realtimeSyncRetryLimit = realtimeSyncRetryLimit,
       super(const AppRuntimeState()) {
    _agentTerminalNotificationDeduplicator = ref.read(
      agentTerminalNotificationDeduplicatorProvider,
    );
    _remotePushMessageSyncCoordinator = ref.read(
      remotePushMessageSyncCoordinatorProvider,
    );
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
    _messageSyncSubscription = ref.listen<MessageSyncCoordinatorState>(
      messageSyncCoordinatorProvider,
      _handleMessageSyncChanged,
    );
  }

  final Ref ref;
  final Duration _requestTimeout;
  final Duration _foregroundCatchUpInterval;
  final Duration _realtimeSyncRetryBaseDelay;
  final int _realtimeSyncRetryLimit;
  static const Duration _refreshDebounceWindow = Duration(seconds: 2);
  bool _isLoggingOut = false;
  bool _syncAuthRevoked = false;
  Future<void>? _authRevocationFenceOperation;
  _SessionEpochOperation? _authenticatedRefreshOperation;
  _SessionEpochOperation? _realtimeRecoveryOperation;
  _SessionEpochBarrierOperation? _sessionEpochBarrierOperation;
  int _busyOperationCount = 0;
  Future<void> _e2eeInitializationTail = Future<void>.value();
  SessionEpoch? _lastAuthenticatedRefreshEpoch;
  late final AgentTerminalNotificationDeduplicator
  _agentTerminalNotificationDeduplicator;
  Future<void>? _joinedMemberActivation;
  String? _joinedMemberActivationDid;
  String? _deletingLocalIdentitySelector;
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
  StreamSubscription<RealtimeUpdate>? _realtimeUpdateSubscription;
  late final StreamSubscription<NotificationActivation>
  _notificationActivationSubscription;
  late final ProviderSubscription<MessageSyncCoordinatorState>
  _messageSyncSubscription;
  late final RemotePushMessageSyncCoordinator?
  _remotePushMessageSyncCoordinator;
  RemotePushSessionContext? _activeRemotePushMessageSyncContext;

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
    await _authRevocationFenceOperation;
    final lease = await _currentSessionLeaseMatching(requestedLease);
    if (lease == null || !mounted) {
      return;
    }
    final session = _legacySessionFromAppSession(lease.session);
    final totalWatch = Stopwatch()..start();
    _agentTerminalNotificationDeduplicator.clear();
    _beginBusyOperation();
    state = state.copyWith(activatedDid: null);
    try {
      _clearRealtimeSyncHints();
      final currentSession = ref.read(sessionProvider).session;
      if (currentSession != null) {
        ref
            .read(sessionProvider.notifier)
            .upsertLocalCredential(currentSession);
        _clearAuthenticatedUiState();
      }
      ref.read(selectedConversationProvider.notifier).clearSelection();
      ref.read(friendsWorkspaceNavigationProvider.notifier).reset();
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
      ref.read(messageSyncCoordinatorProvider.notifier).resetForSession();
      ref.read(accountStateSyncCoordinatorProvider.notifier).resetForSession();
      _syncAuthRevoked = false;
      _isLoggingOut = false;
      if (!_isSessionLeaseTransitionCurrent(lease)) {
        if (_isSessionEpochActive(epoch)) {
          _clearAuthenticatedUiState();
        }
        return;
      }
      if (!_isSessionEpochActive(epoch)) {
        return;
      }
      await ref
          .read(conversationListProvider.notifier)
          .preparePatchGeneration();
      if (!_isSessionLeaseTransitionCurrent(lease) ||
          !_isSessionEpochActive(epoch)) {
        return;
      }
      state = state.copyWith(
        isInitialized: true,
        activatedDid: session.did,
        authRevoked: false,
      );
      final remotePushActivation = _activateRemotePushMessageSyncBestEffort(
        epoch,
      );
      await Future<void>.microtask(() {});
      unawaited(remotePushActivation);
      if (!_isSessionEpochActive(epoch)) {
        return;
      }
      unawaited(
        _refreshAuthenticatedDataInBackground(epoch: epoch, debounce: false),
      );
      _scheduleReliableSync('startup', immediate: true);
      _startForegroundCatchUp();
      _ensureRealtimeConnected(epoch);
      unawaited(_bindRemotePushBestEffort(epoch));
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

  Future<void> prepareIdentityActivation() async {
    _isLoggingOut = true;
    _syncAuthRevoked = false;
    final pushSession = _currentRemotePushInstallationSession();
    _deactivateRemotePushLocally(pushSession);
    await _disableRemotePushBestEffort(pushSession);
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
    await loginWithLocalCredentialAndConfirm(credentialName);
  }

  /// Activates one local identity and reports whether the authenticated App
  /// projection committed. Recovery uses this result as a navigation gate.
  Future<bool> loginWithLocalCredentialAndConfirm(String credentialName) async {
    final currentSession = ref.read(sessionProvider).session;
    if (currentSession != null) {
      ref.read(sessionProvider.notifier).upsertLocalCredential(currentSession);
      final pushSession = _currentRemotePushInstallationSession();
      _deactivateRemotePushLocally(pushSession);
      await _disableRemotePushBestEffort(pushSession);
      _clearAuthenticatedUiState();
    }
    AppSession? session;
    AppSessionLease? restoredLease;
    final sessions = ref.read(appSessionServiceProvider);
    final transition = sessions.beginSessionTransition();
    final loginCompleted = await _runBusy(
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
    if (!loginCompleted || committed == null) {
      final predecessor = restoredLease;
      if (predecessor != null) {
        await _runBusy(
          () => _activateSession(predecessor),
          enforceTimeout: false,
        );
      }
      return false;
    }
    final activationCompleted = await _runBusy(
      () => activateCommittedSession(committed),
      enforceTimeout: false,
    );
    if (!activationCompleted || !mounted) {
      return false;
    }
    final active = ref.read(sessionProvider).session;
    return active != null &&
        active.localIdentityId == committed.identityId &&
        active.did == committed.did &&
        state.activatedDid == committed.did;
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
          await activateCommittedSession(session);
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
    final pushSession = _currentRemotePushInstallationSession();
    _deactivateRemotePushLocally(pushSession);
    await _disableRemotePushBestEffort(pushSession);
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
      await deleteLocalCredential(current);
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }

  Future<void> deleteCurrentData() async {
    final current = ref.read(sessionProvider).session;
    if (current == null) return;
    _beginBusyOperation();
    try {
      await _deleteCurrentIdentityData(current);
    } finally {
      _endBusyOperation();
    }
  }

  Future<bool> _deleteCurrentIdentityData(SessionIdentity identity) async {
    final selector = identity.localIdentitySelector;
    final ownerIdentityId = identity.localIdentityId?.trim();
    if (selector.isEmpty ||
        ownerIdentityId == null ||
        ownerIdentityId.isEmpty ||
        _deletingLocalIdentitySelector != null) {
      return false;
    }
    final sessions = ref.read(appSessionServiceProvider);
    if (sessions is! LocalIdentityDataDeletionSessionService) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.featureNotImplemented());
      return false;
    }
    final deletionSessions =
        sessions as LocalIdentityDataDeletionSessionService;
    final productLocalStore = ref.read(productLocalStoreProvider);
    _deletingLocalIdentitySelector = selector;
    _isLoggingOut = true;
    try {
      _agentTerminalNotificationDeduplicator.clear();
      final pushSession = _currentRemotePushInstallationSession();
      _deactivateRemotePushLocally(pushSession);
      await _disableRemotePushBestEffort(pushSession);
      await productLocalStore.deleteOwnerData(
        ownerIdentityId: ownerIdentityId,
        currentDid: identity.did,
      );
      await deletionSessions.deleteLocalIdentityData(selector);
      if (mounted) {
        state = state.copyWith(activatedDid: null);
        _clearAuthenticatedUiState();
        final credentials = await _localCredentialsFor(ref);
        if (mounted) {
          ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
        }
      }
      return true;
    } catch (error) {
      if (mounted) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(error));
      }
      return false;
    } finally {
      _isLoggingOut = false;
      _deletingLocalIdentitySelector = null;
    }
  }

  /// Removes one exact local identity. It is valid both for the active session
  /// and for a signed-out identity chooser; only the active case tears down
  /// authenticated projections and remote push state.
  Future<bool> deleteLocalCredential(SessionIdentity identity) async {
    final selector = identity.localIdentitySelector;
    if (selector.isEmpty || _deletingLocalIdentitySelector != null) {
      return false;
    }
    _deletingLocalIdentitySelector = selector;
    final current = ref.read(sessionProvider).session;
    final deletingCurrent =
        current != null && _sameLocalIdentity(current, identity);
    try {
      if (deletingCurrent) {
        _isLoggingOut = true;
        _agentTerminalNotificationDeduplicator.clear();
        state = state.copyWith(activatedDid: null);
        final pushSession = _currentRemotePushInstallationSession();
        _deactivateRemotePushLocally(pushSession);
        await _disableRemotePushBestEffort(pushSession);
        _clearAuthenticatedUiState();
      }
      await ref.read(appSessionServiceProvider).deleteLocalIdentity(selector);
      final credentials = await _localCredentialsFor(ref);
      ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      return true;
    } catch (error) {
      final message = AppMessage.fromError(error);
      ref.read(uiFeedbackProvider.notifier).showError(message);
      if (message == AppMessage.sessionExpiredRelogin()) {
        await logout();
      }
      return false;
    } finally {
      if (deletingCurrent) {
        _isLoggingOut = false;
      }
      _deletingLocalIdentitySelector = null;
    }
  }

  void _clearAuthenticatedUiState() {
    _deactivateRemotePushMessageSync();
    _stopForegroundCatchUp();
    _clearRealtimeSyncHints();
    _agentTerminalNotificationDeduplicator.clear();
    ref.read(sessionProvider.notifier).clear();
    _invalidateSessionOperations();
    _cancelRealtimeUpdates();
    ref.read(agentInboxProvider.notifier).clear();
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
    ref.read(friendsWorkspaceNavigationProvider.notifier).reset();
    ref.read(peerDisplayProfileProvider.notifier).clear();
    ref.invalidate(peerProfileProvider);
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
    _deactivateRemotePushLocally(_currentRemotePushInstallationSession());
    _clearAuthenticatedUiState();
    state = state.copyWith(
      isBusy: false,
      isInitialized: true,
      activatedDid: null,
      authRevoked: true,
    );
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

  Future<void> _refreshAuthenticatedData(SessionEpoch epoch) async {
    final totalWatch = Stopwatch()..start();
    if (!_isSessionEpochActive(epoch)) {
      return;
    }
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
      label: 'app_refresh.conversation_patch_ready',
      action: () =>
          ref.read(conversationListProvider.notifier).ensurePatchReady(),
      clearStale: _clearAuthenticatedProjection,
    );
    if (!conversationCurrent || !_isSessionEpochActive(epoch)) {
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
        !_isCurrentAuthenticatedRefresh(sessionFence) ||
        !_isSessionEpochActive(epoch)) {
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
      if (!_isCurrentAuthenticatedRefresh(fence) &&
          mounted &&
          ref.read(sessionProvider).session == null) {
        clearStale();
      }
    }
    return _isCurrentAuthenticatedRefresh(fence);
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
          if (mounted && _syncAuthRevoked) {
            _clearAuthenticatedProjection();
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
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch == null) {
      return;
    }
    unawaited(_resumeForegroundAfterBarrier(epoch));
  }

  void _handleRealtimeStatusChanged(
    AsyncValue<RealtimeConnectionStatus>? previous,
    AsyncValue<RealtimeConnectionStatus> next,
  ) {
    final status = next.valueOrNull;
    final previousStatus = previous?.valueOrNull;
    if (status == RealtimeConnectionStatus.reconnecting ||
        status == RealtimeConnectionStatus.failed ||
        status == RealtimeConnectionStatus.disconnected) {
      if (!_isLoggingOut && !_syncAuthRevoked) {
        _scheduleReliableSync(
          'realtime_connection_interrupted',
          immediate: true,
        );
      }
    }
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
    if (ref.read(sessionProvider).activeEpoch == null) {
      return;
    }
    if (_syncAuthRevoked) {
      return;
    }
    final epoch = ref.read(sessionProvider).activeEpoch;
    if (epoch != null) {
      unawaited(_resumeRealtimeAfterBarrier(epoch));
    }
  }

  Future<void> _resumeForegroundAfterBarrier(SessionEpoch epoch) async {
    if (!await _refreshSessionEpochBarrier(epoch) ||
        !_isSessionEpochActive(epoch) ||
        ref.read(appLifecycleProvider) != AppLifecycleState.resumed) {
      return;
    }
    _startForegroundCatchUp();
    _ensureRealtimeConnected(epoch);
    unawaited(_refreshRemotePushBestEffort(epoch));
    unawaited(_resumeRemotePushMessageSyncBestEffort(epoch));
    _scheduleReliableSync('app_resumed');
    unawaited(_refreshAuthenticatedDataInBackground(epoch: epoch));
  }

  Future<void> _resumeRealtimeAfterBarrier(SessionEpoch epoch) async {
    if (!await _refreshSessionEpochBarrier(epoch) ||
        !_isSessionEpochActive(epoch) ||
        ref.read(realtimeConnectionStatusProvider).valueOrNull !=
            RealtimeConnectionStatus.connected) {
      return;
    }
    _scheduleReliableSync('realtime_reconnected');
    unawaited(_refreshAuthenticatedDataInBackground(epoch: epoch));
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
    if (!await _refreshSessionEpochBarrier(epoch) ||
        !_isSessionEpochActive(epoch)) {
      return;
    }
    await _refreshAuthenticatedDataInBackground(epoch: epoch);
    if (_isSessionEpochActive(epoch)) {
      _ensureRealtimeConnected(epoch);
    }
  }

  Future<bool> _refreshSessionEpochBarrier(SessionEpoch epoch) {
    if (!_isSessionEpochActive(epoch)) {
      return Future<bool>.value(false);
    }
    final active = _sessionEpochBarrierOperation;
    if (active != null && active.epoch == epoch) {
      return active.operation;
    }
    late final Future<bool> operation;
    operation =
        (() async {
          try {
            final refreshed = await ref
                .read(appSessionServiceProvider)
                .refreshSession();
            if (refreshed == null || !_isSessionEpochActive(epoch)) {
              return false;
            }
            final updated = ref
                .read(sessionProvider.notifier)
                .updateSessionMetadataIfCurrent(
                  _legacySessionFromAppSession(refreshed),
                );
            return updated && _isSessionEpochActive(epoch);
          } on Object {
            return false;
          }
        })().whenComplete(() {
          if (identical(_sessionEpochBarrierOperation?.operation, operation)) {
            _sessionEpochBarrierOperation = null;
          }
        });
    _sessionEpochBarrierOperation = _SessionEpochBarrierOperation(
      epoch: epoch,
      operation: operation,
    );
    return operation;
  }

  bool _isSessionEpochActive(SessionEpoch epoch) {
    return mounted &&
        !_isLoggingOut &&
        !_syncAuthRevoked &&
        epoch.matches(ref.read(sessionProvider));
  }

  RemotePushInstallationSession? _currentRemotePushInstallationSession() {
    return resolveRemotePushInstallationSession(
      storageScopeId: ref.read(remotePushStorageScopeIdProvider),
      sessionState: ref.read(sessionProvider),
    );
  }

  Future<void> _bindRemotePushBestEffort(SessionEpoch epoch) async {
    final coordinator = ref.read(remotePushInstallationCoordinatorProvider);
    final session = _currentRemotePushInstallationSession();
    final skipReason = coordinator == null
        ? 'coordinator_missing'
        : session == null
        ? 'session_missing'
        : !_isSessionEpochActive(epoch)
        ? 'inactive_epoch'
        : session.generation != epoch.generation
        ? 'generation_mismatch'
        : session.ownerDid != epoch.ownerDid
        ? 'owner_mismatch'
        : null;
    if (skipReason != null) {
      debugPrint(
        '[awiki_me][remote-push][installation-bind-skipped] '
        'reason=$skipReason',
      );
      return;
    }
    try {
      debugPrint('[awiki_me][remote-push][installation-bind-start]');
      await coordinator!.bindActiveSession(session!);
      debugPrint('[awiki_me][remote-push][installation-bind-succeeded]');
    } catch (error) {
      debugPrint(
        '[awiki_me][remote-push][installation-bind-failed] '
        'type=${error.runtimeType}',
      );
      // Push registration must never fail an authenticated activation.
    }
  }

  Future<void> _refreshRemotePushBestEffort(SessionEpoch epoch) async {
    final coordinator = ref.read(remotePushInstallationCoordinatorProvider);
    final session = _currentRemotePushInstallationSession();
    if (coordinator == null ||
        session == null ||
        !_isSessionEpochActive(epoch) ||
        session.generation != epoch.generation ||
        session.ownerDid != epoch.ownerDid) {
      return;
    }
    try {
      await coordinator.refreshActiveSession(session);
    } catch (_) {
      // Foreground Push refresh is best-effort.
    }
  }

  Future<void> _disableRemotePushBestEffort(
    RemotePushInstallationSession? session,
  ) async {
    final coordinator = ref.read(remotePushInstallationCoordinatorProvider);
    if (coordinator == null || session == null) {
      return;
    }
    try {
      await coordinator
          .disableActiveInstallation(session)
          .timeout(_requestTimeout);
    } catch (_) {
      // Local session fencing remains authoritative if Push teardown fails.
    }
  }

  void _deactivateRemotePushLocally(RemotePushInstallationSession? session) {
    final coordinator = ref.read(remotePushInstallationCoordinatorProvider);
    if (coordinator == null || session == null) {
      return;
    }
    coordinator.deactivateLocally(session);
  }

  Future<void> _activateRemotePushMessageSyncBestEffort(
    SessionEpoch epoch,
  ) async {
    final coordinator = _remotePushMessageSyncCoordinator;
    final context = currentRemotePushSessionContext(ref);
    if (coordinator == null ||
        context == null ||
        !_isSessionEpochActive(epoch) ||
        context.ownerDid != epoch.ownerDid ||
        context.generation != epoch.generation) {
      return;
    }
    _activeRemotePushMessageSyncContext = context;
    try {
      await coordinator.activateSession(context);
    } catch (_) {
      // A Push event must never fail an authenticated activation.
    }
  }

  Future<void> _resumeRemotePushMessageSyncBestEffort(
    SessionEpoch epoch,
  ) async {
    final coordinator = _remotePushMessageSyncCoordinator;
    if (coordinator == null || !_isSessionEpochActive(epoch)) {
      return;
    }
    try {
      await coordinator.resume();
    } catch (_) {
      // Pending Push replay is retried by the next real lifecycle trigger.
    }
  }

  void _deactivateRemotePushMessageSync() {
    final coordinator = _remotePushMessageSyncCoordinator;
    final context = _activeRemotePushMessageSyncContext;
    _activeRemotePushMessageSyncContext = null;
    if (coordinator == null || context == null) {
      return;
    }
    coordinator.deactivateSession(context);
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
      final terminalNotification = _agentTerminalNotificationDeduplicator
          .acceptStatus(controlPayload);
      final hiddenPersonalAgentStatus =
          !ref.read(personalAgentFeatureVisibleProvider) &&
          isPersonalAgentControlPayload(
            controlPayload,
            ref.read(agentsProvider).agents,
          );
      if (terminalNotification != null && !hiddenPersonalAgentStatus) {
        _showAgentTerminalNotification(terminalNotification);
      }
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
    if (message.isMine) {
      return;
    }
    final messageIds = <String?>[message.remoteId, message.localId];
    final isRuntimeAgentMessage = ref
        .read(agentsProvider)
        .agents
        .any((agent) => agent.isRuntime && agent.agentDid == message.senderDid);
    if (isRuntimeAgentMessage) {
      _agentTerminalNotificationDeduplicator.acceptRuntimeMessageIds(
        messageIds,
        releaseNotification: () {
          if (!mounted ||
              _isLoggingOut ||
              ref.read(sessionProvider).session == null) {
            return;
          }
          _showOrdinaryMessageNotification(
            expectedEpoch,
            update,
            normalizedConversationHint,
          );
        },
      );
      return;
    }
    if (_agentTerminalNotificationDeduplicator.acceptMessageIds(messageIds)) {
      _showOrdinaryMessageNotification(
        expectedEpoch,
        update,
        normalizedConversationHint,
      );
    }
  }

  void _showOrdinaryMessageNotification(
    SessionEpoch expectedEpoch,
    RealtimeUpdate update,
    ConversationSummary conversationHint,
  ) {
    final message = update.message;
    if (message == null || !isOrdinaryMessagePresentationEligible(message)) {
      return;
    }
    if (ref.read(appLifecycleProvider) == AppLifecycleState.resumed) {
      return;
    }
    final title = _notificationTitle(update, conversationHint);
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
    final target = NotificationTarget(
      storageScopeId: ref.read(activeAppTenantProvider).storageScopeId,
      ownerDid: expectedEpoch.ownerDid,
      conversationId: conversationHint.conversationId,
    );
    ref
        .read(notificationFacadeProvider)
        .showSystemNotification(title: title, body: body, target: target);
  }

  void _showAgentTerminalNotification(AgentTerminalNotification notification) {
    final isForeground =
        ref.read(appLifecycleProvider) == AppLifecycleState.resumed;
    if (isForeground) {
      return;
    }
    final l10n = _currentLocalizations();
    final message = switch (notification.kind) {
      AgentTerminalKind.completed => AppMessage.agentTerminalCompleted(
        notification.summary!,
      ),
      AgentTerminalKind.blocked => AppMessage.agentTerminalBlocked(
        notification.summary!,
        notification.nextStep!,
      ),
      AgentTerminalKind.actionRequired =>
        AppMessage.agentTerminalActionRequired(
          notification.summary!,
          notification.nextStep!,
        ),
      AgentTerminalKind.runtimeFailed =>
        AppMessage.agentTerminalRuntimeFailed(),
    };
    final body = message.resolve(l10n);
    unawaited(
      ref
          .read(notificationFacadeProvider)
          .showSystemNotification(
            title: l10n.agentTerminalNotificationTitle,
            body: body,
          ),
    );
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
    if (epoch == null ||
        !await _refreshSessionEpochBarrier(epoch) ||
        !_isNotificationEpochCurrent(epoch)) {
      return;
    }
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.messages);
    ref.read(selectedConversationProvider.notifier).clearSelection();
    final target = activation.target;
    if (target == null ||
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
                  .requestSync(reason, immediate: true);
              if (ref
                  .read(messageSyncCoordinatorProvider)
                  .shouldSurfaceRetryableFailure) {
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
      if (!mounted) {
        return;
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
    final title = ref
        .read(
          peerDisplayNameProvider(
            PeerDisplayNameRequest(
              did: message.senderDid,
              senderNameSnapshot: message.senderName,
            ),
          ),
        )
        .trim();
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

  Future<bool> _runBusy(
    Future<void> Function() action, {
    bool enforceTimeout = true,
    Future<void> Function()? onFailure,
    bool Function()? shouldReportFailure,
  }) async {
    _beginBusyOperation();
    try {
      final operation = action();
      await (enforceTimeout ? operation.timeout(_requestTimeout) : operation);
      return true;
    } on TimeoutException {
      await onFailure?.call();
      if (shouldReportFailure?.call() == false) {
        return false;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
      return false;
    } on AppSessionTransitionSuperseded {
      await onFailure?.call();
      return false;
    } catch (error) {
      await onFailure?.call();
      if (shouldReportFailure?.call() == false) {
        return false;
      }
      final message = AppMessage.fromError(error);
      ref.read(uiFeedbackProvider.notifier).showError(message);
      if (message == AppMessage.sessionExpiredRelogin()) {
        await logout();
      }
      return false;
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
    _deactivateRemotePushMessageSync();
    _invalidateSessionOperations();
    _stopForegroundCatchUp();
    _clearRealtimeSyncHints();
    _agentTerminalNotificationDeduplicator.clear();
    _lifecycleSubscription.close();
    _realtimeStatusSubscription.close();
    _cancelRealtimeUpdates();
    _notificationActivationSubscription.cancel();
    _messageSyncSubscription.close();
    super.dispose();
  }
}

class _SessionEpochOperation {
  const _SessionEpochOperation({required this.epoch, required this.operation});

  final SessionEpoch epoch;
  final Future<void> operation;
}

class _SessionEpochBarrierOperation {
  const _SessionEpochBarrierOperation({
    required this.epoch,
    required this.operation,
  });

  final SessionEpoch epoch;
  final Future<bool> operation;
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

bool _sameLocalIdentity(SessionIdentity first, SessionIdentity second) {
  final firstId = first.localIdentityId?.trim();
  final secondId = second.localIdentityId?.trim();
  if (firstId != null &&
      firstId.isNotEmpty &&
      secondId != null &&
      secondId.isNotEmpty) {
    return firstId == secondId;
  }
  final firstDid = first.did.trim();
  final secondDid = second.did.trim();
  if (firstDid.isNotEmpty && secondDid.isNotEmpty) {
    return firstDid == secondDid;
  }
  return first.credentialName.trim() == second.credentialName.trim();
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
