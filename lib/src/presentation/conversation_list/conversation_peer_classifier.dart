import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/agent/agent_summary.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/peer_agent_identity.dart';
import '../agents/agents_provider.dart';

class ConversationPeerTarget {
  const ConversationPeerTarget({
    required this.isGroup,
    required this.threadId,
    required this.isDeletedAgentConversation,
    this.targetDid,
    this.groupId,
  });

  factory ConversationPeerTarget.fromConversation(
    ConversationSummary conversation,
  ) {
    return ConversationPeerTarget(
      isGroup: conversation.isGroup,
      threadId: conversation.threadId,
      isDeletedAgentConversation: conversation.isDeletedAgentConversation,
      targetDid: conversation.targetDid,
      groupId: conversation.groupId,
    );
  }

  final bool isGroup;
  final String threadId;
  final bool isDeletedAgentConversation;
  final String? targetDid;
  final String? groupId;

  @override
  bool operator ==(Object other) {
    return other is ConversationPeerTarget &&
        other.isGroup == isGroup &&
        other.threadId == threadId &&
        other.isDeletedAgentConversation == isDeletedAgentConversation &&
        other.targetDid == targetDid &&
        other.groupId == groupId;
  }

  @override
  int get hashCode => Object.hash(
    isGroup,
    threadId,
    isDeletedAgentConversation,
    targetDid,
    groupId,
  );
}

enum ConversationPeerKind { group, human, agent, myRuntimeAgent, unknown }

class ConversationPeerClassification {
  const ConversationPeerClassification({
    required this.kind,
    this.agentKind,
    this.localRuntimeAgent,
  });

  const ConversationPeerClassification.group()
    : kind = ConversationPeerKind.group,
      agentKind = null,
      localRuntimeAgent = null;

  const ConversationPeerClassification.human()
    : kind = ConversationPeerKind.human,
      agentKind = null,
      localRuntimeAgent = null;

  const ConversationPeerClassification.unknown()
    : kind = ConversationPeerKind.unknown,
      agentKind = null,
      localRuntimeAgent = null;

  const ConversationPeerClassification.agent({
    this.agentKind,
    this.localRuntimeAgent,
  }) : kind = localRuntimeAgent == null
           ? ConversationPeerKind.agent
           : ConversationPeerKind.myRuntimeAgent;

  final ConversationPeerKind kind;
  final PeerAgentKind? agentKind;
  final AgentSummary? localRuntimeAgent;

  bool get isGroup => kind == ConversationPeerKind.group;
  bool get isAgent =>
      kind == ConversationPeerKind.agent ||
      kind == ConversationPeerKind.myRuntimeAgent;
  bool get isMyRuntimeAgent => kind == ConversationPeerKind.myRuntimeAgent;

  String? get compactBadgeLabel {
    if (isGroup) {
      return '群';
    }
    if (isAgent) {
      return 'AI';
    }
    return null;
  }

  String? get chatBadgeLabel {
    if (isMyRuntimeAgent) {
      return '我的智能体';
    }
    if (isAgent) {
      return '智能体';
    }
    return null;
  }

  String get detailTypeLabel {
    return switch (kind) {
      ConversationPeerKind.group => '群聊',
      ConversationPeerKind.myRuntimeAgent => '我的智能体',
      ConversationPeerKind.agent => '智能体',
      ConversationPeerKind.human => '用户',
      ConversationPeerKind.unknown => '用户',
    };
  }

  String get detailOwnerLabel {
    return switch (kind) {
      ConversationPeerKind.group => 'AWiki 群组',
      ConversationPeerKind.myRuntimeAgent => '本机 Runtime Agent',
      ConversationPeerKind.agent => 'AWiki 智能体',
      ConversationPeerKind.human => 'AWiki 用户',
      ConversationPeerKind.unknown => 'AWiki 用户',
    };
  }
}

final conversationPeerClassificationProvider =
    FutureProvider.family<
      ConversationPeerClassification,
      ConversationPeerTarget
    >((ref, target) async {
      if (target.isGroup) {
        return const ConversationPeerClassification.group();
      }
      final targetDid = target.targetDid?.trim();
      if (targetDid == null || targetDid.isEmpty) {
        return const ConversationPeerClassification.unknown();
      }
      if (target.isDeletedAgentConversation) {
        return const ConversationPeerClassification.agent(
          agentKind: PeerAgentKind.runtime,
        );
      }

      final agents = ref.watch(agentsProvider).agents;
      final localRuntime = localRuntimeAgentForConversationTarget(
        targetDid,
        agents,
      );
      if (localRuntime != null) {
        return ConversationPeerClassification.agent(
          agentKind: PeerAgentKind.runtime,
          localRuntimeAgent: localRuntime,
        );
      }
      if (conversationTargetDidLooksLikeAgent(targetDid)) {
        return ConversationPeerClassification.agent(
          agentKind: _agentKindFromDid(targetDid),
        );
      }

      try {
        final identity = await ref
            .read(peerIdentityServiceProvider)
            .resolveAgentIdentity(targetDid);
        if (identity.isAgent) {
          return ConversationPeerClassification.agent(
            agentKind: identity.agentKind,
          );
        }
        return const ConversationPeerClassification.human();
      } catch (_) {
        return const ConversationPeerClassification.unknown();
      }
    });

AgentSummary? localRuntimeAgentForConversationTarget(
  String targetDid,
  List<AgentSummary> agents,
) {
  for (final agent in agents) {
    if (agent.isRuntime && agent.agentDid == targetDid) {
      return agent;
    }
  }
  return null;
}

bool conversationTargetDidLooksLikeAgent(String? did) {
  final normalizedDid = did?.trim().toLowerCase();
  if (normalizedDid == null || normalizedDid.isEmpty) {
    return false;
  }
  return normalizedDid.startsWith('did:agent:') ||
      normalizedDid.contains(':agent:') ||
      normalizedDid.contains(':agents:') ||
      normalizedDid.contains(':runtime_agent:');
}

PeerAgentKind? _agentKindFromDid(String did) {
  final normalizedDid = did.trim().toLowerCase();
  if (normalizedDid.contains(':daemon:')) {
    return PeerAgentKind.daemon;
  }
  if (normalizedDid.contains(':runtime:') ||
      normalizedDid.contains(':runtime_agent:')) {
    return PeerAgentKind.runtime;
  }
  return null;
}
