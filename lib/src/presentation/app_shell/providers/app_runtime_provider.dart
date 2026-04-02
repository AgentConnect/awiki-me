import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../app/ui_feedback.dart';
import '../../../domain/entities/realtime_update.dart';
import '../../../domain/entities/session_identity.dart';
import '../../../l10n/app_message.dart';
import '../../chat/chat_provider.dart';
import '../../conversation_list/conversation_provider.dart';
import '../../friends/friends_provider.dart';
import '../../group/group_provider.dart';
import '../../profile/profile_provider.dart';
import 'session_provider.dart';

class AppRuntimeState {
  const AppRuntimeState({
    this.isInitialized = false,
    this.isBusy = false,
  });

  final bool isInitialized;
  final bool isBusy;

  AppRuntimeState copyWith({
    bool? isInitialized,
    bool? isBusy,
  }) {
    return AppRuntimeState(
      isInitialized: isInitialized ?? this.isInitialized,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

class AppRuntimeController extends StateNotifier<AppRuntimeState> {
  AppRuntimeController(this.ref) : super(const AppRuntimeState());

  final Ref ref;
  static const Duration _requestTimeout = Duration(seconds: 20);

  Future<void> initialize() async {
    if (state.isInitialized) {
      return;
    }
    state = state.copyWith(isBusy: true);
    try {
      final gateway = ref.read(awikiGatewayProvider);
      final capabilities = await gateway.loadCapabilities();
      final localCredentials = await gateway.listLocalCredentials();
      ref.read(sessionProvider.notifier).setCapabilities(capabilities);
      ref.read(sessionProvider.notifier).setLocalCredentials(localCredentials);

      final session = await gateway.restoreSession();
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
      await _refreshAuthenticatedData();
      if (!ref.read(realtimeGatewayProvider).isConnected) {
        await ref.read(realtimeGatewayProvider).connect(
              session: session,
              onMessage: _handleRealtimeMessage,
            );
      }
    } finally {
      state = state.copyWith(isBusy: false, isInitialized: true);
    }
  }

  Future<void> loginWithLocalCredential(String credentialName) async {
    await _runBusy(() async {
      final session =
          await ref.read(awikiGatewayProvider).loginWithLocalCredential(
                credentialName,
              );
      await activateSession(session);
    });
  }

  Future<void> logout() async {
    await _runBusy(() async {
      await ref.read(realtimeGatewayProvider).disconnect();
      await ref.read(awikiGatewayProvider).logout();
      final credentials =
          await ref.read(awikiGatewayProvider).listLocalCredentials();
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
          .read(awikiGatewayProvider)
          .deleteLocalCredential(current.credentialName);
      await ref.read(awikiGatewayProvider).logout();
      final credentials =
          await ref.read(awikiGatewayProvider).listLocalCredentials();
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
      final exportedPath =
          await ref.read(awikiGatewayProvider).exportCurrentCredentialAsZip();
      if (exportedPath != null && exportedPath.isNotEmpty) {
        ref.read(uiFeedbackProvider.notifier).showInfo(
              AppMessage.exportedTo(exportedPath),
            );
      }
    });
  }

  Future<void> importCredentialArchive() async {
    await _runBusy(() async {
      final imported =
          await ref.read(awikiGatewayProvider).importCredentialFromZip();
      if (imported == null) {
        return;
      }
      final credentials =
          await ref.read(awikiGatewayProvider).listLocalCredentials();
      ref.read(sessionProvider.notifier).setLocalCredentials(credentials);
      ref.read(uiFeedbackProvider.notifier).showInfo(
            AppMessage.importSuccessSelectCredential(),
          );
    });
  }

  Future<void> _refreshAuthenticatedData() async {
    await ref.read(profileProvider.notifier).refresh();
    await ref.read(conversationListProvider.notifier).refresh();
    await ref.read(friendsProvider.notifier).refresh();
    await ref.read(groupProvider.notifier).refresh();
  }

  Future<void> _handleRealtimeMessage(Map<String, Object?> event) async {
    final update =
        await ref.read(awikiGatewayProvider).consumeRealtimeEvent(event);
    if (update == null) {
      return;
    }
    _applyRealtimeUpdate(update);
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
      ref.read(notificationFacadeProvider).showInAppBanner(
            title: update.conversation.displayName,
            body: update.message.content.isNotEmpty
                ? update.message.content
                : AppMessage.newMessageArrived().resolveForFallback(),
          );
    }
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
}

final appRuntimeProvider =
    StateNotifierProvider<AppRuntimeController, AppRuntimeState>(
  (ref) => AppRuntimeController(ref),
);
