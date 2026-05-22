import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../app/ui_feedback.dart';
import '../../../domain/entities/realtime_update.dart';
import '../../../domain/entities/session_identity.dart';
import '../../../domain/services/realtime_gateway.dart';
import '../../../l10n/app_message.dart';
import '../../chat/chat_provider.dart';
import '../../conversation_list/conversation_provider.dart';
import '../../friends/friends_provider.dart';
import '../../group/group_provider.dart';
import '../../profile/profile_provider.dart';
import '../../shared/formatters/display_formatters.dart';
import 'app_lifecycle_provider.dart';
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
  }

  final Ref ref;
  static const Duration _requestTimeout = Duration(seconds: 20);
  bool _isRecoveringRealtimeSession = false;
  late final ProviderSubscription<AppLifecycleState> _lifecycleSubscription;
  late final ProviderSubscription<AsyncValue<RealtimeConnectionStatus>>
  _realtimeStatusSubscription;

  Future<void> initialize() async {
    if (state.isInitialized) {
      return;
    }
    state = state.copyWith(isBusy: true);
    try {
      final gateway = ref.read(awikiGatewayProvider);
      final accountGateway = ref.read(awikiAccountGatewayProvider);
      final capabilities = await gateway.loadCapabilities();
      final localCredentials = await accountGateway.listLocalCredentials();
      ref.read(sessionProvider.notifier).setCapabilities(capabilities);
      ref.read(sessionProvider.notifier).setLocalCredentials(localCredentials);

      final session = await accountGateway.restoreSession();
      if (session != null) {
        await activateSession(session);
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
      ref.read(sessionProvider.notifier).setSession(session);
      await ref.read(e2eeFacadeProvider).initialize(session);
      state = state.copyWith(isBusy: false, isInitialized: true);
      unawaited(_refreshAuthenticatedDataInBackground());
      _ensureRealtimeConnected(session);
    } finally {
      state = state.copyWith(isBusy: false, isInitialized: true);
    }
  }

  Future<void> loginWithLocalCredential(String credentialName) async {
    await _runBusy(() async {
      final session = await ref
          .read(awikiAccountGatewayProvider)
          .loginWithLocalCredential(credentialName);
      await activateSession(session);
    });
  }

  Future<void> refreshLocalCredentials() async {
    await _runBusy(() async {
      final credentials = await ref
          .read(awikiAccountGatewayProvider)
          .listLocalCredentials();
      ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      final feedback = credentials.isEmpty
          ? AppMessage.noLocalCredentialsFound()
          : AppMessage.localCredentialsRefreshed(credentials.length);
      ref.read(uiFeedbackProvider.notifier).showInfo(feedback);
    });
  }

  Future<void> logout() async {
    await _runBusy(() async {
      await ref.read(realtimeGatewayProvider).disconnect();
      await ref.read(awikiAccountGatewayProvider).logout();
      final credentials = await ref
          .read(awikiAccountGatewayProvider)
          .listLocalCredentials();
      ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      ref.read(sessionProvider.notifier).clear();
      ref.read(profileProvider.notifier).clear();
      await ref.read(conversationListProvider.notifier).clear();
      ref.read(chatThreadsProvider.notifier).clear();
      ref.read(friendsProvider.notifier).clear();
      ref.read(groupProvider.notifier).clear();
    });
  }

  Future<void> deleteCurrentCredential() async {
    final current = ref.read(sessionProvider).session;
    if (current == null) {
      return;
    }
    await _runBusy(() async {
      await ref.read(realtimeGatewayProvider).disconnect();
      await ref
          .read(awikiAccountGatewayProvider)
          .deleteLocalCredential(current.credentialName);
      await ref.read(awikiAccountGatewayProvider).logout();
      final credentials = await ref
          .read(awikiAccountGatewayProvider)
          .listLocalCredentials();
      ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      ref.read(sessionProvider.notifier).clear();
      ref.read(profileProvider.notifier).clear();
      await ref.read(conversationListProvider.notifier).clear();
      ref.read(chatThreadsProvider.notifier).clear();
      ref.read(friendsProvider.notifier).clear();
      ref.read(groupProvider.notifier).clear();
    });
  }

  Future<void> exportCurrentCredential() async {
    await _runBusy(() async {
      final exportedPath = await ref
          .read(awikiAccountGatewayProvider)
          .exportCurrentCredentialAsZip();
      if (exportedPath != null && exportedPath.isNotEmpty) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showInfo(AppMessage.exportedTo(exportedPath));
      }
    });
  }

  Future<void> importCredentialArchive() async {
    await _runBusy(() async {
      final imported = await ref
          .read(awikiAccountGatewayProvider)
          .importCredentialFromZip();
      if (imported == null) {
        return;
      }
      final credentials = await ref
          .read(awikiAccountGatewayProvider)
          .listLocalCredentials();
      ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.importSuccessSelectCredential());
    });
  }

  Future<void> _refreshAuthenticatedData() async {
    if (!mounted) {
      return;
    }
    await ref.read(profileProvider.notifier).refresh();
    if (!mounted) {
      return;
    }
    await ref.read(conversationListProvider.notifier).refresh();
    if (!mounted) {
      return;
    }
    await ref.read(friendsProvider.notifier).refresh();
    if (!mounted) {
      return;
    }
    await ref.read(groupProvider.notifier).refresh();
  }

  Future<void> _refreshAuthenticatedDataInBackground() async {
    try {
      await _refreshAuthenticatedData().timeout(_requestTimeout);
    } on TimeoutException {
      if (!mounted) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = AppMessage.fromError(error);
      ref.read(uiFeedbackProvider.notifier).showError(message);
      if (message == AppMessage.sessionExpiredRelogin()) {
        await logout();
      }
    }
  }

  Future<void> _handleRealtimeMessage(Map<String, Object?> event) async {
    final update = await ref
        .read(awikiGatewayProvider)
        .consumeRealtimeEvent(event);
    if (update == null) {
      return;
    }
    _applyRealtimeUpdate(update);
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
    _ensureRealtimeConnected(session);
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
      final session = ref.read(sessionProvider).session;
      if (session != null) {
        unawaited(_recoverRealtimeSession(session));
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

  void _ensureRealtimeConnected(SessionIdentity session) {
    final gateway = ref.read(realtimeGatewayProvider);
    final status = gateway.connectionStatus;
    if (gateway.isConnected ||
        status == RealtimeConnectionStatus.connecting ||
        status == RealtimeConnectionStatus.reconnecting) {
      return;
    }
    unawaited(
      gateway
          .connect(session: session, onMessage: _handleRealtimeMessage)
          .catchError((_) {}),
    );
  }

  Future<void> _recoverRealtimeSession(SessionIdentity session) async {
    if (_isRecoveringRealtimeSession) {
      return;
    }
    _isRecoveringRealtimeSession = true;
    try {
      final refreshed = await ref
          .read(awikiAccountGatewayProvider)
          .refreshSession();
      if (!mounted) {
        return;
      }
      final effectiveSession = refreshed ?? session;
      if (effectiveSession.jwtToken?.isNotEmpty == true) {
        ref.read(sessionProvider.notifier).setSession(effectiveSession);
      }
      await _refreshAuthenticatedDataInBackground();
      if (!mounted) {
        return;
      }
      if (effectiveSession.jwtToken == session.jwtToken) {
        return;
      }
      _ensureRealtimeConnected(effectiveSession);
    } catch (_) {
      if (mounted) {
        await _refreshAuthenticatedDataInBackground();
      }
    } finally {
      _isRecoveringRealtimeSession = false;
    }
  }

  void _applyRealtimeUpdate(RealtimeUpdate update) {
    ref.read(chatThreadsProvider.notifier).applyRealtimeUpdate(update.message);
    ref
        .read(conversationListProvider.notifier)
        .upsertConversation(update.conversation);
    if (update.group != null) {
      ref.read(groupProvider.notifier).upsertGroup(update.group!);
    }
    if (!update.message.isMine) {
      final title = _notificationTitle(update);
      final body = update.message.content.isNotEmpty
          ? update.message.content
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

  String _notificationTitle(RealtimeUpdate update) {
    final title = DidDisplayFormatter.compactDisplayName(
      displayName: update.message.senderName ?? '',
      fallbackDid: update.message.senderDid,
    ).trim();
    if (title.isNotEmpty) {
      return title;
    }
    return update.conversation.displayName;
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
    super.dispose();
  }
}

final appRuntimeProvider =
    StateNotifierProvider<AppRuntimeController, AppRuntimeState>(
      (ref) => AppRuntimeController(ref),
    );
