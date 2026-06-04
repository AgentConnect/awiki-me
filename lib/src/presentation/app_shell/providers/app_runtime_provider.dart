import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../app/ui_feedback.dart';
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
import '../../shared/formatters/display_formatters.dart';
import 'app_lifecycle_provider.dart';
import 'selected_conversation_provider.dart';
import 'session_provider.dart';

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
  bool _isRecoveringRealtimeSession = false;
  bool _isLoggingOut = false;
  late final ProviderSubscription<AppLifecycleState> _lifecycleSubscription;
  late final ProviderSubscription<AsyncValue<RealtimeConnectionStatus>>
  _realtimeStatusSubscription;
  late final StreamSubscription<RealtimeUpdate> _realtimeUpdateSubscription;

  Future<void> initialize() async {
    if (state.isInitialized) {
      return;
    }
    state = state.copyWith(isBusy: true);
    try {
      final sessions = ref.read(appSessionServiceProvider);
      final localIdentities = await sessions.listLocalIdentities();
      final localCredentials = _legacySessionsFromAppSessions(localIdentities);
      ref.read(sessionProvider.notifier).setCapabilities(_imCoreCapabilities);
      ref.read(sessionProvider.notifier).setLocalCredentials(localCredentials);

      final session = await sessions.restoreSession();
      if (session != null) {
        await activateSession(_legacySessionFromAppSession(session));
      }
      state = state.copyWith(isInitialized: true, isBusy: false);
    } on TimeoutException {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
      state = state.copyWith(isBusy: false, isInitialized: true);
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
      state = state.copyWith(isBusy: false, isInitialized: true);
    }
  }

  Future<void> activateSession(SessionIdentity session) async {
    state = state.copyWith(isBusy: true);
    try {
      ref.read(selectedConversationProvider.notifier).clearSelection();
      ref.read(sessionProvider.notifier).setSession(session);
      await ref.read(e2eeFacadeProvider).initialize(session);
      state = state.copyWith(isBusy: false, isInitialized: true);
      unawaited(_refreshAuthenticatedDataInBackground());
      _ensureRealtimeConnected();
    } finally {
      state = state.copyWith(isBusy: false, isInitialized: true);
    }
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
    await _runBusy(() async {
      _isLoggingOut = true;
      try {
        ref.read(sessionProvider.notifier).clear();
        ref.read(profileProvider.notifier).clear();
        ref.read(selectedConversationProvider.notifier).clearSelection();
        await ref.read(conversationListProvider.notifier).clear();
        ref.read(chatThreadsProvider.notifier).clear();
        ref.read(friendsProvider.notifier).clear();
        ref.read(groupProvider.notifier).clear();
        await ref.read(appSessionServiceProvider).logout();
        final credentials = await _localCredentialsFor(ref);
        ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      } finally {
        _isLoggingOut = false;
      }
    });
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
        ref.read(profileProvider.notifier).clear();
        ref.read(selectedConversationProvider.notifier).clearSelection();
        await ref.read(conversationListProvider.notifier).clear();
        ref.read(chatThreadsProvider.notifier).clear();
        ref.read(friendsProvider.notifier).clear();
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
    if (!mounted ||
        _isLoggingOut ||
        ref.read(sessionProvider).session == null) {
      return;
    }
    await ref.read(profileProvider.notifier).refresh();
    if (!mounted ||
        _isLoggingOut ||
        ref.read(sessionProvider).session == null) {
      return;
    }
    await ref.read(conversationListProvider.notifier).refresh();
    if (!mounted ||
        _isLoggingOut ||
        ref.read(sessionProvider).session == null) {
      return;
    }
    await ref.read(friendsProvider.notifier).refresh();
    if (!mounted ||
        _isLoggingOut ||
        ref.read(sessionProvider).session == null) {
      return;
    }
    await ref.read(groupProvider.notifier).refresh();
  }

  Future<void> _refreshAuthenticatedDataInBackground() async {
    try {
      await _refreshAuthenticatedData().timeout(_requestTimeout);
    } on TimeoutException {
      if (!mounted ||
          _isLoggingOut ||
          ref.read(sessionProvider).session == null) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_isLoggingOut || ref.read(sessionProvider).session == null) {
        return;
      }
      final message = AppMessage.fromError(error);
      ref.read(uiFeedbackProvider.notifier).showError(message);
      if (message == AppMessage.sessionExpiredRelogin()) {
        await logout();
      }
    }
  }

  void _handleLifecycleChanged(
    AppLifecycleState? previous,
    AppLifecycleState next,
  ) {
    if (previous == next || next != AppLifecycleState.resumed) {
      return;
    }
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return;
    }
    _ensureRealtimeConnected();
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
    final controlPayload = update.agentControlPayload;
    if (controlPayload != null) {
      ref.read(agentsProvider.notifier).applyControlPayload(controlPayload);
      ref.read(agentInboxProvider.notifier).applyControlPayload(controlPayload);
      return;
    }
    final message = update.message;
    final conversation = update.conversation;
    if (message == null || conversation == null) {
      return;
    }
    final shouldShow = _shouldShowRealtimeConversation(conversation);
    if (!shouldShow) {
      return;
    }
    ref.read(chatThreadsProvider.notifier).applyRealtimeUpdate(message);
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(conversation);
    if (update.group != null) {
      ref.read(groupProvider.notifier).upsertGroup(update.group!);
    }
    if (!message.isMine) {
      final title = _notificationTitle(update);
      final preview = message.previewText;
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

  bool _shouldShowRealtimeConversation(ConversationSummary conversation) {
    return shouldShowConversationForChatList(
      conversation,
      daemonAgentDids: ref
          .read(agentsProvider)
          .daemonAgents
          .map((agent) => agent.agentDid),
    );
  }

  String _notificationTitle(RealtimeUpdate update) {
    final message = update.message;
    final conversation = update.conversation;
    if (message == null || conversation == null) {
      return AppMessage.newMessageArrived().resolveForFallback();
    }
    final title = DidDisplayFormatter.compactDisplayName(
      displayName: message.senderName ?? '',
      fallbackDid: message.senderDid,
    ).trim();
    if (title.isNotEmpty) {
      return title;
    }
    return conversation.displayName;
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
  return SessionIdentity(
    did: session.did,
    credentialName: session.localAlias ?? session.identityId,
    displayName: session.displayName,
    handle: session.handle,
    jwtToken: session.jwtToken,
  );
}

final appRuntimeProvider =
    StateNotifierProvider<AppRuntimeController, AppRuntimeState>(
      (ref) => AppRuntimeController(ref),
    );
