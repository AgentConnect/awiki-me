import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_services.dart';
import '../../../application/agent_message_presentation_store.dart';
import '../../../application/models/agent_notification_preference.dart';
import '../../../application/ports/agent_notification_preference_port.dart';
import '../../../domain/entities/session_identity.dart';
import 'session_provider.dart';

final agentMessagePresentationClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// One scope-runtime instance owns every presentation-ledger read/modify/write.
/// Settings and MessageSyncCoordinator must reuse this provider so their
/// operations share the same serialization tail.
final agentMessagePresentationStoreProvider =
    Provider<AgentMessagePresentationStore>(
      (ref) =>
          AgentMessagePresentationStore(ref.watch(productLocalStoreProvider)),
    );

final agentUrgentOptInProvider =
    StateNotifierProvider<AgentUrgentOptInController, AgentUrgentOptInState>((
      ref,
    ) {
      final session = ref.watch(sessionProvider).session;
      final owner = _validatedOwnerScope(session);
      return AgentUrgentOptInController(
        preferences: ref.watch(agentNotificationPreferencePortProvider),
        owner: owner,
      );
    });

final class AgentUrgentOptInState {
  const AgentUrgentOptInState({
    required this.enabled,
    required this.available,
    required this.loading,
    this.hasError = false,
  });

  const AgentUrgentOptInState.unavailable()
    : enabled = false,
      available = false,
      loading = false,
      hasError = false;

  final bool enabled;
  final bool available;
  final bool loading;
  final bool hasError;

  bool get canChange => available && !loading;
}

final class AgentUrgentOptInController
    extends StateNotifier<AgentUrgentOptInState> {
  AgentUrgentOptInController({
    required AgentNotificationPreferencePort? preferences,
    required AgentMessagePresentationOwnerScope? owner,
  }) : _preferences = preferences,
       _owner = owner,
       super(
         owner == null || preferences == null
             ? const AgentUrgentOptInState.unavailable()
             : const AgentUrgentOptInState(
                 enabled: false,
                 available: true,
                 loading: true,
               ),
       ) {
    if (owner != null && preferences != null) {
      unawaited(_load());
    }
  }

  final AgentNotificationPreferencePort? _preferences;
  final AgentMessagePresentationOwnerScope? _owner;

  Future<void> _load() async {
    try {
      final preference = await _preferences!.getAgentNotificationPreference();
      if (!mounted) return;
      state = AgentUrgentOptInState(
        enabled: preference.urgentEnabled,
        available: true,
        loading: false,
      );
    } on Object {
      if (!mounted) return;
      state = const AgentUrgentOptInState(
        enabled: false,
        available: false,
        loading: false,
        hasError: true,
      );
    }
  }

  Future<void> setEnabled(bool enabled) async {
    final owner = _owner;
    if (owner == null || !state.canChange || state.enabled == enabled) {
      return;
    }
    state = const AgentUrgentOptInState(
      enabled: false,
      available: true,
      loading: true,
    );
    try {
      final preference = await _preferences!.setAgentNotificationPreference(
        urgent: enabled
            ? AgentNotificationUrgentPreference.enabled
            : AgentNotificationUrgentPreference.disabled,
      );
      if (!mounted) return;
      state = AgentUrgentOptInState(
        enabled: preference.urgentEnabled,
        available: true,
        loading: false,
      );
    } on Object {
      if (!mounted) return;
      state = const AgentUrgentOptInState(
        enabled: false,
        available: false,
        loading: false,
        hasError: true,
      );
    }
  }
}

AgentMessagePresentationOwnerScope? _validatedOwnerScope(
  SessionIdentity? session,
) {
  final binding = session?.accountBinding;
  if (session == null ||
      binding == null ||
      binding.currentDid.trim() != session.did.trim() ||
      binding.ownerIdentityId.trim().isEmpty ||
      binding.accountId.trim().isEmpty ||
      binding.protocolDeviceId.trim().isEmpty ||
      binding.protocolDeviceId == 'default' ||
      !_isCanonicalPositive(binding.identityGeneration) ||
      !_isCanonicalPositive(binding.deviceAuthGeneration)) {
    return null;
  }
  try {
    return AgentMessagePresentationOwnerScope(
      ownerIdentityId: binding.ownerIdentityId,
      accountId: binding.accountId,
    );
  } on ArgumentError {
    return null;
  }
}

bool _isCanonicalPositive(String value) =>
    RegExp(r'^[1-9][0-9]*$').hasMatch(value);
