// [INPUT]: Product rollout policy, Agent inventory, conversations, and controls.
// [OUTPUT]: One gate and classifier for every user-facing Personal Agent surface.
// [POS]: Presentation policy only; runtime state and control data remain intact.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/agent/personal_agent_runtime_provider.dart';
import '../../domain/entities/conversation_summary.dart';

const bool personalAgentFeatureVisibleByDefault = false;

final personalAgentFeatureVisibleProvider = Provider<bool>(
  (ref) => personalAgentFeatureVisibleByDefault,
);

bool isPersonalAgentRuntime(AgentSummary agent) {
  if (!agent.isRuntime) {
    return false;
  }
  final display = agent.displayName.trim().toLowerCase();
  return display.contains('personal agent') ||
      display.contains('个人助理') ||
      display == legacyPersonalAgentRuntimeDisplayName.toLowerCase() ||
      display.contains(legacyPersonalAgentChineseDisplayMarker) ||
      PersonalAgentRuntimeProviders.all.any(
        (provider) => provider.matchesHandle(agent.handle),
      );
}

bool isEnabledPersonalAgentRuntime(AgentSummary agent) {
  if (!isPersonalAgentRuntime(agent)) return false;
  final provider = PersonalAgentRuntimeProviders.byRuntime(agent.runtime);
  if (provider != null) return provider.enabled;
  for (final candidate in PersonalAgentRuntimeProviders.all) {
    if (candidate.matchesHandle(agent.handle)) return candidate.enabled;
  }
  return true;
}

bool isPersonalAgentConversation(
  ConversationSummary conversation,
  Iterable<AgentSummary> agents,
) {
  if (conversation.isGroup) {
    return false;
  }
  final targetDid = conversation.targetDid?.trim();
  if (targetDid != null && targetDid.isNotEmpty) {
    for (final agent in agents) {
      if (agent.agentDid == targetDid && isPersonalAgentRuntime(agent)) {
        return true;
      }
    }
  }

  final displayName = conversation.displayName.trim().toLowerCase();
  if (_looksLikeAgentDid(targetDid) &&
      (displayName.contains('personal agent') ||
          displayName.contains('个人助理') ||
          displayName == legacyPersonalAgentRuntimeDisplayName.toLowerCase() ||
          displayName.contains(legacyPersonalAgentChineseDisplayMarker))) {
    return true;
  }

  final targetPeer = conversation.targetPeer?.trim();
  return PersonalAgentRuntimeProviders.all.any(
    (provider) => provider.matchesHandle(targetPeer),
  );
}

bool isPersonalAgentControlPayload(
  Map<String, Object?> payload,
  Iterable<AgentSummary> agents,
) {
  final agentDids = <String>{
    if (_nonEmptyString(payload['agent_did']) case final did?) did,
    if (_nonEmptyString(payload['runtime_agent_did']) case final did?) did,
  };
  final runtime = payload['runtime'];
  if (runtime is Map) {
    final did = _nonEmptyString(runtime['agent_did']);
    if (did != null) {
      agentDids.add(did);
    }
  }
  final runs = payload['runs'];
  if (runs is List) {
    for (final run in runs.whereType<Map>()) {
      final did =
          _nonEmptyString(run['agent_did']) ??
          _nonEmptyString(run['runtime_agent_did']);
      if (did != null) {
        agentDids.add(did);
      }
    }
  }
  if (agentDids.isEmpty) {
    return false;
  }
  return agents.any(
    (agent) =>
        agentDids.contains(agent.agentDid) && isPersonalAgentRuntime(agent),
  );
}

List<ConversationSummary> personalAgentVisibleConversations({
  required Iterable<ConversationSummary> conversations,
  required Iterable<AgentSummary> agents,
  required bool personalAgentVisible,
}) {
  if (personalAgentVisible) {
    return conversations.toList(growable: false);
  }
  return conversations
      .where(
        (conversation) => !isPersonalAgentConversation(conversation, agents),
      )
      .toList(growable: false);
}

bool _looksLikeAgentDid(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  return normalized.startsWith('did:agent:') ||
      normalized.contains(':agent:') ||
      normalized.contains(':agents:') ||
      normalized.contains(':runtime_agent:');
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
