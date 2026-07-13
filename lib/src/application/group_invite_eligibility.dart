// [INPUT]: Agent inventory state, deletion progress, and conversation lifecycle projections.
// [OUTPUT]: Pure eligibility decisions for identities shown or submitted by group invite flows.
// [POS]: Application policy separating historical identity visibility from current group admission.
import '../domain/entities/agent/agent_status.dart';
import '../domain/entities/agent/agent_summary.dart';
import '../domain/entities/conversation_summary.dart';

class GroupInviteEligibilityPolicy {
  GroupInviteEligibilityPolicy._({required Set<String> excludedDids})
    : _excludedDids = Set<String>.unmodifiable(excludedDids);

  factory GroupInviteEligibilityPolicy.fromSources({
    required List<AgentSummary> agents,
    required Set<String> pendingDeletionAgentDids,
    required List<ConversationSummary> conversations,
  }) {
    final excludedDids = <String>{
      for (final did in pendingDeletionAgentDids)
        if (_normalizedDid(did).isNotEmpty) _normalizedDid(did),
      for (final conversation in conversations)
        if (conversation.isDeletedAgentConversation &&
            _normalizedDid(conversation.targetDid).isNotEmpty)
          _normalizedDid(conversation.targetDid),
    };
    for (final agent in agents) {
      if (_isArchivedAgent(agent)) {
        final did = _normalizedDid(agent.agentDid);
        if (did.isNotEmpty) {
          excludedDids.add(did);
        }
      }
    }
    return GroupInviteEligibilityPolicy._(excludedDids: excludedDids);
  }

  final Set<String> _excludedDids;

  bool allowsAgent(AgentSummary agent) {
    return agent.kind == AgentKind.runtime &&
        !_isArchivedAgent(agent) &&
        allowsIdentity(did: agent.agentDid);
  }

  bool allowsConversation(ConversationSummary conversation) {
    return !conversation.isGroup &&
        !conversation.isDeletedAgentConversation &&
        allowsIdentity(did: conversation.targetDid);
  }

  bool allowsIdentity({required String? did}) {
    final normalizedDid = _normalizedDid(did);
    return normalizedDid.isNotEmpty && !_excludedDids.contains(normalizedDid);
  }
}

bool _isArchivedAgent(AgentSummary agent) {
  final activeState = agent.activeState.trim().toLowerCase();
  final latestStatus = agent.latest.status.trim().toLowerCase();
  return activeState != 'active' ||
      latestStatus == 'archived' ||
      latestStatus == 'deleted';
}

String _normalizedDid(String? value) => value?.trim() ?? '';
