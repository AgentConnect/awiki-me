import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/ports/remote_push_sync_port.dart';
import '../../../application/tenant/app_tenant.dart';
import '../../../domain/entities/agent/agent_message_v1.dart';
import '../../chat/parts/agent_message_card.dart';
import 'remote_push_coordinator_provider.dart';
import 'session_provider.dart';
import 'package:awiki_me/l10n/app_localizations.dart';

final class AgentUrgentOverlayState {
  const AgentUrgentOverlayState({
    required this.fence,
    required this.navigationContext,
    required this.conversationId,
    required this.senderLabel,
    required this.message,
    this.authoritativeReceivedAt,
  });

  final AgentUrgentOverlaySessionFence fence;
  final RemotePushSessionContext navigationContext;
  final String conversationId;
  final String senderLabel;
  final AgentMessageV1 message;
  final DateTime? authoritativeReceivedAt;
}

/// Stable, secret-free session fence carried by the UI-only overlay state.
/// It prevents an overlay accepted for one authenticated account/device
/// generation from surviving an identity or binding transition.
final class AgentUrgentOverlaySessionFence {
  const AgentUrgentOverlaySessionFence._({
    required this.epoch,
    required this.ownerIdentityId,
    required this.accountId,
    required this.protocolDeviceId,
    required this.identityGeneration,
    required this.deviceAuthGeneration,
    required this.currentDid,
  });

  static AgentUrgentOverlaySessionFence? capture(SessionState state) {
    final epoch = state.activeEpoch;
    final session = state.session;
    final binding = session?.accountBinding;
    if (epoch == null ||
        session == null ||
        binding == null ||
        !_exactNonEmpty(binding.ownerIdentityId) ||
        !_exactNonEmpty(binding.accountId) ||
        !_exactNonEmpty(binding.protocolDeviceId) ||
        binding.protocolDeviceId == 'default' ||
        !_canonicalPositive(binding.identityGeneration) ||
        !_canonicalPositive(binding.deviceAuthGeneration) ||
        !_exactNonEmpty(binding.currentDid) ||
        session.localIdentityId != binding.ownerIdentityId ||
        binding.currentDid != session.did) {
      return null;
    }
    return AgentUrgentOverlaySessionFence._(
      epoch: epoch,
      ownerIdentityId: binding.ownerIdentityId,
      accountId: binding.accountId,
      protocolDeviceId: binding.protocolDeviceId,
      identityGeneration: binding.identityGeneration,
      deviceAuthGeneration: binding.deviceAuthGeneration,
      currentDid: binding.currentDid,
    );
  }

  final SessionEpoch epoch;
  final String ownerIdentityId;
  final String accountId;
  final String protocolDeviceId;
  final String identityGeneration;
  final String deviceAuthGeneration;
  final String currentDid;

  bool matches(SessionState state) => this == capture(state);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentUrgentOverlaySessionFence &&
          other.epoch == epoch &&
          other.ownerIdentityId == ownerIdentityId &&
          other.accountId == accountId &&
          other.protocolDeviceId == protocolDeviceId &&
          other.identityGeneration == identityGeneration &&
          other.deviceAuthGeneration == deviceAuthGeneration &&
          other.currentDid == currentDid;

  @override
  int get hashCode => Object.hash(
    epoch,
    ownerIdentityId,
    accountId,
    protocolDeviceId,
    identityGeneration,
    deviceAuthGeneration,
    currentDid,
  );

  static bool _exactNonEmpty(String value) =>
      value.isNotEmpty && value.trim() == value;

  static bool _canonicalPositive(String value) =>
      RegExp(r'^[1-9][0-9]*$').hasMatch(value);
}

class AgentUrgentOverlayController
    extends StateNotifier<AgentUrgentOverlayState?> {
  AgentUrgentOverlayController() : super(null);

  bool tryShow(AgentUrgentOverlayState next) {
    if (state != null ||
        next.message.kind != AgentMessageKind.alert ||
        next.message.level != AgentMessageLevel.urgent) {
      return false;
    }
    state = next;
    return true;
  }

  void clear() => state = null;
}

final agentUrgentOverlayProvider =
    StateNotifierProvider<
      AgentUrgentOverlayController,
      AgentUrgentOverlayState?
    >((ref) => AgentUrgentOverlayController());

class AgentUrgentOverlayHost extends ConsumerWidget {
  const AgentUrgentOverlayHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overlay = ref.watch(agentUrgentOverlayProvider);
    if (overlay == null) return const SizedBox.shrink();
    final sessionState = ref.watch(sessionProvider);
    final epoch = sessionState.activeEpoch;
    final storageScopeId = ref.watch(activeAppTenantProvider).storageScopeId;
    final currentNavigationContext = epoch == null
        ? null
        : RemotePushSessionContext(
            storageScopeId: storageScopeId,
            ownerDid: epoch.ownerDid,
            generation: epoch.generation,
          );
    if (!overlay.fence.matches(sessionState) ||
        !overlay.navigationContext.matches(currentNavigationContext)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(agentUrgentOverlayProvider.notifier).clear();
      });
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final receivedAt = overlay.authoritativeReceivedAt?.toLocal();
    final metaLabel = receivedAt == null
        ? l10n.agentMessageJustNow
        : '${l10n.agentMessageJustNow} · '
              '${DateFormat.MMMd(localeName).add_Hm().format(receivedAt)}';
    return AgentUrgentCalloutOverlay(
      message: overlay.message,
      senderLabel: overlay.senderLabel,
      copy: AgentUrgentCalloutCopy(
        urgentCall: l10n.agentMessageUrgentCall,
        back: l10n.commonBack,
        trustedAgent: l10n.agentMessageTrustedAgent,
        notAVoipNotice: l10n.agentMessageNotVoiceCall,
        cueStops: l10n.agentMessageCueStops,
        ignore: l10n.agentMessageIgnore,
        act: l10n.agentMessageActNow,
      ),
      metaLabel: metaLabel,
      onIgnore: () => ref.read(agentUrgentOverlayProvider.notifier).clear(),
      onAct: () {
        final currentState = ref.read(sessionProvider);
        final currentEpoch = currentState.activeEpoch;
        final currentContext = currentEpoch == null
            ? null
            : RemotePushSessionContext(
                storageScopeId: ref
                    .read(activeAppTenantProvider)
                    .storageScopeId,
                ownerDid: currentEpoch.ownerDid,
                generation: currentEpoch.generation,
              );
        if (!overlay.fence.matches(currentState) ||
            !overlay.navigationContext.matches(currentContext)) {
          ref.read(agentUrgentOverlayProvider.notifier).clear();
          return;
        }
        final navigation = ref.read(remotePushNavigationPortProvider);
        final navigationContext = overlay.navigationContext;
        final conversationId = overlay.conversationId;
        ref.read(agentUrgentOverlayProvider.notifier).clear();
        unawaited(() async {
          try {
            await navigation.showConversationList(navigationContext);
            await navigation.openConversation(
              navigationContext,
              conversationId,
            );
          } on RemotePushNavigationStaleSession {
            // Session changes are an expected fail-closed navigation outcome.
          }
        }());
      },
    );
  }
}
