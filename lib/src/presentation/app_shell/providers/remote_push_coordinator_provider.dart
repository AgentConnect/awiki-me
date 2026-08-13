import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_lifecycle_provider.dart';

import '../../../app/app_services.dart';
import '../../../application/ports/remote_push_sync_port.dart';
import '../../../application/remote_push_installation_coordinator.dart';
import '../../../application/remote_push_message_sync_coordinator.dart';
import '../../../application/tenant/app_tenant.dart';
import '../../chat/chat_provider.dart';
import '../../conversation_list/conversation_provider.dart';
import 'message_sync_coordinator_provider.dart';
import 'navigation_provider.dart';
import 'selected_conversation_provider.dart';
import 'session_provider.dart';

RemotePushSessionContext? currentRemotePushSessionContext(Ref ref) {
  final epoch = ref.read(sessionProvider).activeEpoch;
  if (epoch == null) {
    return null;
  }
  return RemotePushSessionContext(
    storageScopeId: ref.read(activeAppTenantProvider).storageScopeId,
    ownerDid: epoch.ownerDid,
    generation: epoch.generation,
  );
}

final remotePushMessageSyncCoordinatorProvider =
    Provider<RemotePushMessageSyncCoordinator?>((ref) {
      final client = ref.watch(remotePushClientProvider);
      if (client == null) {
        return null;
      }
      late final RemotePushMessageSyncCoordinator coordinator;
      coordinator = RemotePushMessageSyncCoordinator(
        client: client,
        sync: ref.read(remotePushSyncPortProvider),
        navigation: ref.read(remotePushNavigationPortProvider),
        aliveUrgentClickBindings: ref.read(
          aliveUrgentClickBindingStoreProvider,
        ),
        refreshInstallation: (context) async {
          try {
            await _refreshRemotePushInstallation(ref, context);
          } finally {
            if (!_contextMatches(ref, context)) {
              coordinator.deactivateSession(context);
            }
          }
        },
      )..start();
      ref.listen<AppLifecycleState>(appLifecycleProvider, (previous, next) {
        if (next == AppLifecycleState.hidden ||
            next == AppLifecycleState.paused) {
          unawaited(coordinator.pullPendingAndDrain());
        }
      });
      ref.onDispose(() {
        unawaited(coordinator.dispose());
      });
      return coordinator;
    });

final remotePushSyncPortProvider = Provider<RemotePushSyncPort>(
  (ref) => ref.read(messageSyncCoordinatorProvider.notifier),
);

final remotePushNavigationPortProvider = Provider<RemotePushNavigationPort>(
  (ref) => _RiverpodRemotePushNavigation(ref),
);

final class RemotePushNavigationStaleSession implements Exception {
  const RemotePushNavigationStaleSession();

  @override
  String toString() => 'remote_push_navigation_stale_session';
}

Future<void> _refreshRemotePushInstallation(
  Ref ref,
  RemotePushSessionContext context,
) async {
  if (!_contextMatches(ref, context)) {
    return;
  }
  final coordinator = ref.read(remotePushInstallationCoordinatorProvider);
  final sessionState = ref.read(sessionProvider);
  final session = sessionState.session;
  if (coordinator == null || session == null) {
    return;
  }
  final binding = session.accountBinding;
  if (binding != null && binding.currentDid.trim() != context.ownerDid) {
    return;
  }
  final logicalDeviceId = binding?.protocolDeviceId.trim();
  await coordinator.refreshActiveSession(
    RemotePushInstallationSession(
      storageScopeId: context.storageScopeId,
      ownerDid: context.ownerDid,
      generation: context.generation,
      logicalDeviceId: logicalDeviceId == null || logicalDeviceId.isEmpty
          ? null
          : logicalDeviceId,
    ),
  );
}

final class _RiverpodRemotePushNavigation implements RemotePushNavigationPort {
  const _RiverpodRemotePushNavigation(this.ref);

  final Ref ref;

  @override
  Future<void> showConversationList(RemotePushSessionContext context) async {
    if (!_contextMatches(ref, context)) {
      throw const RemotePushNavigationStaleSession();
    }
    ref
        .read(shellDestinationProvider.notifier)
        .select(ShellDestination.messages);
    ref.read(selectedConversationProvider.notifier).clearSelection();
  }

  @override
  Future<void> openConversation(
    RemotePushSessionContext context,
    String conversationId,
  ) async {
    final epoch = _matchingEpoch(ref, context);
    if (epoch == null) {
      throw const RemotePushNavigationStaleSession();
    }
    final conversation = await ref
        .read(conversationListProvider.notifier)
        .commitConversationId(conversationId, expectedEpoch: epoch);
    if (!_epochMatches(ref, context, epoch)) {
      throw const RemotePushNavigationStaleSession();
    }
    await ref.read(chatThreadsProvider.notifier).openConversation(conversation);
    if (!_epochMatches(ref, context, epoch)) {
      throw const RemotePushNavigationStaleSession();
    }
    ref
        .read(selectedConversationProvider.notifier)
        .selectConversation(conversation);
  }
}

SessionEpoch? _matchingEpoch(Ref ref, RemotePushSessionContext context) {
  final tenant = ref.read(activeAppTenantProvider);
  final epoch = ref.read(sessionProvider).activeEpoch;
  if (tenant.storageScopeId != context.storageScopeId ||
      epoch == null ||
      epoch.ownerDid != context.ownerDid ||
      epoch.generation != context.generation) {
    return null;
  }
  return epoch;
}

bool _contextMatches(Ref ref, RemotePushSessionContext context) =>
    _matchingEpoch(ref, context) != null;

bool _epochMatches(
  Ref ref,
  RemotePushSessionContext context,
  SessionEpoch epoch,
) {
  final current = _matchingEpoch(ref, context);
  return current != null && current == epoch;
}
