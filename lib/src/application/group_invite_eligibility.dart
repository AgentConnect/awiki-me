// [INPUT]: Agent inventory/lifecycle, structured identity type/capabilities, and server rollout state.
// [OUTPUT]: Pure eligibility decisions and stable denial reasons for group invite flows.
// [POS]: Application policy separating historical identity visibility from current group admission.
import '../domain/entities/agent/agent_status.dart';
import '../domain/entities/agent/agent_summary.dart';
import '../domain/entities/conversation_summary.dart';
import '../domain/entities/identity_type.dart';
import '../domain/entities/agent/skill_group_membership_capability.dart';

enum GroupInviteDenialReason {
  identityUnavailable,
  agentKindUnsupported,
  skillGroupMembershipDisabled,
  skillCapabilityMissing,
}

class GroupInviteEligibilityDecision {
  const GroupInviteEligibilityDecision.allowed()
    : allowed = true,
      denialReason = null;

  const GroupInviteEligibilityDecision.denied(this.denialReason)
    : allowed = false;

  final bool allowed;
  final GroupInviteDenialReason? denialReason;
}

class GroupInviteEligibilityPolicy {
  GroupInviteEligibilityPolicy._({
    required Set<String> excludedDids,
    required this.skillGroupMembership,
  }) : _excludedDids = Set<String>.unmodifiable(excludedDids);

  factory GroupInviteEligibilityPolicy.fromSources({
    required List<AgentSummary> agents,
    required Set<String> pendingDeletionAgentDids,
    required List<ConversationSummary> conversations,
    SkillGroupMembershipCapability skillGroupMembership =
        const SkillGroupMembershipCapability.disabled(),
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
    return GroupInviteEligibilityPolicy._(
      excludedDids: excludedDids,
      skillGroupMembership: skillGroupMembership,
    );
  }

  final Set<String> _excludedDids;
  final SkillGroupMembershipCapability skillGroupMembership;

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

  GroupInviteEligibilityDecision evaluateIdentity({
    required String? did,
    required IdentityType identityType,
    Set<String> agentCapabilities = const <String>{},
  }) {
    if (!allowsIdentity(did: did)) {
      return const GroupInviteEligibilityDecision.denied(
        GroupInviteDenialReason.identityUnavailable,
      );
    }
    if (!identityType.isAgent) {
      return const GroupInviteEligibilityDecision.allowed();
    }
    return switch (identityType.agentKind ?? IdentityAgentKind.unknown) {
      IdentityAgentKind.runtime =>
        const GroupInviteEligibilityDecision.allowed(),
      IdentityAgentKind.skill => _evaluateSkillAgent(agentCapabilities),
      IdentityAgentKind.daemon ||
      IdentityAgentKind.unknown => const GroupInviteEligibilityDecision.denied(
        GroupInviteDenialReason.agentKindUnsupported,
      ),
    };
  }

  GroupInviteEligibilityDecision _evaluateSkillAgent(
    Set<String> agentCapabilities,
  ) {
    if (!skillGroupMembership.supportsCurrentProtocol) {
      return const GroupInviteEligibilityDecision.denied(
        GroupInviteDenialReason.skillGroupMembershipDisabled,
      );
    }
    if (!agentCapabilities.contains(skillGroupMembership.requiredCapability)) {
      return const GroupInviteEligibilityDecision.denied(
        GroupInviteDenialReason.skillCapabilityMissing,
      );
    }
    return const GroupInviteEligibilityDecision.allowed();
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
