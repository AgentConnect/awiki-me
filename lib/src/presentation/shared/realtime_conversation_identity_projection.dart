import '../../application/config/awiki_environment_config.dart';
import '../../domain/entities/agent/agent_display_name.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/conversation_identity.dart';
import '../../domain/entities/conversation_summary.dart';

ConversationSummary normalizeRealtimeConversationPresentationIdentity(
  ConversationSummary conversation,
  Iterable<AgentSummary> agents, {
  String? didDomain,
}) {
  if (conversation.isGroup) {
    return conversation;
  }
  final agent = resolveRealtimeRuntimeAgent(
    conversation,
    agents,
    didDomain: didDomain,
  );
  if (agent == null) {
    return conversation;
  }
  final title = AgentDisplayName.title(agent);
  final normalizedHandle = runtimeAgentPresentationHandleForDomain(
    agent,
    didDomain: didDomain,
  );
  final targetPeer = _preferredRealtimeAgentTargetPeer(
    conversation,
    normalizedHandle,
  );
  return conversation.copyWith(
    displayName: title,
    targetDid: agent.agentDid,
    targetPeer: targetPeer,
    avatarSeed: conversation.avatarSeed ?? agent.handle ?? agent.agentDid,
  );
}

AgentSummary? resolveRealtimeRuntimeAgent(
  ConversationSummary conversation,
  Iterable<AgentSummary> agents, {
  String? didDomain,
}) {
  if (conversation.isGroup) {
    return null;
  }
  final index = _RuntimeAgentIdentityIndex(agents, didDomain: didDomain);
  if (index.isEmpty) {
    return null;
  }

  final candidateDids = _candidateDids(conversation).toList(growable: false);
  final candidateHandles = _candidateHandles(
    conversation,
  ).toList(growable: false);

  for (final did in candidateDids) {
    final agent = index.byDid[did];
    if (agent != null) {
      return agent;
    }
  }

  for (final handle in candidateHandles.where(
    (handle) => handle.contains('.'),
  )) {
    final exact = index.uniqueByExactHandle(handle);
    if (exact != null && _canUseHandleMatch(exact, candidateDids)) {
      return exact;
    }
  }

  for (final handle in candidateHandles) {
    final local = _handleLocalPart(handle);
    if (local == null) {
      continue;
    }
    final agent = index.uniqueByLocalHandle(local);
    if (agent != null && _canUseHandleMatch(agent, candidateDids)) {
      return agent;
    }
  }
  return null;
}

String? normalizedRuntimeAgentHandle(AgentSummary agent) {
  final handle = normalizedDirectPeer(agent.handle);
  if (handle == null || handle.startsWith('did:')) {
    return null;
  }
  return handle;
}

String? runtimeAgentPresentationHandle(AgentSummary agent) {
  return runtimeAgentPresentationHandleForDomain(agent);
}

String? runtimeAgentPresentationHandleForDomain(
  AgentSummary agent, {
  String? didDomain,
}) {
  final handle = normalizedRuntimeAgentHandle(agent);
  if (handle == null) {
    return null;
  }
  if (handle.contains('.')) {
    return handle;
  }
  final domain =
      didDomain?.trim() ??
      AwikiEnvironmentConfig.fromEnvironment().didDomain.trim();
  if (domain.isEmpty) {
    return handle;
  }
  return '$handle.${domain.toLowerCase()}';
}

bool _canUseHandleMatch(AgentSummary agent, List<String> candidateDids) {
  return candidateDids.isEmpty;
}

String? _preferredRealtimeAgentTargetPeer(
  ConversationSummary conversation,
  String? agentPresentationHandle,
) {
  final peer = normalizedDirectPeer(conversation.targetPeer);
  if (peer != null && !peer.startsWith('did:') && peer.contains('.')) {
    return peer;
  }
  return agentPresentationHandle ?? peer;
}

Iterable<String> _candidateDids(ConversationSummary conversation) sync* {
  for (final value in <String?>[
    conversation.targetDid,
    conversation.targetPeer,
  ]) {
    final did = value?.trim();
    if (did != null && did.startsWith('did:')) {
      yield did;
    }
  }
}

Iterable<String> _candidateHandles(ConversationSummary conversation) sync* {
  for (final value in <String?>[
    conversation.targetPeer,
    conversation.targetDid,
  ]) {
    final peer = normalizedDirectPeer(value);
    if (peer != null && !peer.startsWith('did:')) {
      yield peer;
    }
  }
}

class _RuntimeAgentIdentityIndex {
  _RuntimeAgentIdentityIndex(
    Iterable<AgentSummary> agents, {
    String? didDomain,
  }) {
    for (final agent in agents) {
      if (!agent.isRuntime) {
        continue;
      }
      final agentDid = agent.agentDid.trim();
      if (agentDid.isEmpty) {
        continue;
      }
      byDid[agentDid] = agent;
      final exactHandles = <String>{
        if (normalizedRuntimeAgentHandle(agent) case final handle?) handle,
        if (runtimeAgentPresentationHandleForDomain(agent, didDomain: didDomain)
            case final handle?)
          handle,
      };
      for (final handle in exactHandles) {
        _byExactHandle.putIfAbsent(handle, () => <AgentSummary>[]).add(agent);
      }
      final localParts = <String>{
        for (final handle in exactHandles)
          if (_handleLocalPart(handle) case final localPart?) localPart,
      };
      for (final localPart in localParts) {
        _byLocalHandle
            .putIfAbsent(localPart, () => <AgentSummary>[])
            .add(agent);
      }
    }
  }

  final Map<String, AgentSummary> byDid = <String, AgentSummary>{};
  final Map<String, List<AgentSummary>> _byExactHandle =
      <String, List<AgentSummary>>{};
  final Map<String, List<AgentSummary>> _byLocalHandle =
      <String, List<AgentSummary>>{};

  bool get isEmpty => byDid.isEmpty;

  AgentSummary? uniqueByExactHandle(String handle) {
    return _unique(_byExactHandle[handle]);
  }

  AgentSummary? uniqueByLocalHandle(String handle) {
    return _unique(_byLocalHandle[handle]);
  }

  AgentSummary? _unique(List<AgentSummary>? matches) {
    if (matches == null) {
      return null;
    }
    final byDid = <String, AgentSummary>{
      for (final match in matches) match.agentDid.trim(): match,
    }..remove('');
    if (byDid.length != 1) {
      return null;
    }
    return byDid.values.single;
  }
}

String? _handleLocalPart(String value) {
  final normalized = normalizedDirectPeer(value);
  if (normalized == null || normalized.startsWith('did:')) {
    return null;
  }
  final dotIndex = normalized.indexOf('.');
  if (dotIndex <= 0) {
    return normalized;
  }
  return normalized.substring(0, dotIndex);
}
