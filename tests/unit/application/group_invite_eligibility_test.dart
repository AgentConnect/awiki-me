import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/application/group_invite_eligibility.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';

void main() {
  const activeRuntime = AgentSummary(
    agentDid: 'did:agent:runtime:active',
    kind: AgentKind.runtime,
    displayName: 'Active runtime',
    activeState: 'active',
    latest: AgentLatestStatus(status: 'ready'),
  );
  const archivedRuntime = AgentSummary(
    agentDid: 'did:agent:runtime:archived',
    kind: AgentKind.runtime,
    displayName: 'Archived runtime',
    activeState: 'archived',
    latest: AgentLatestStatus(status: 'archived'),
  );
  const daemon = AgentSummary(
    agentDid: 'did:agent:daemon',
    kind: AgentKind.daemon,
    displayName: 'Daemon',
    activeState: 'active',
    latest: AgentLatestStatus(status: 'ready'),
  );

  test('only active non-deleting runtime agents are invitable', () {
    final policy = GroupInviteEligibilityPolicy.fromSources(
      agents: const <AgentSummary>[activeRuntime, archivedRuntime, daemon],
      pendingDeletionAgentDids: const <String>{'did:agent:runtime:active'},
      conversations: const <ConversationSummary>[],
    );

    expect(policy.allowsAgent(activeRuntime), isFalse);
    expect(policy.allowsAgent(archivedRuntime), isFalse);
    expect(policy.allowsAgent(daemon), isFalse);

    final activePolicy = GroupInviteEligibilityPolicy.fromSources(
      agents: const <AgentSummary>[activeRuntime],
      pendingDeletionAgentDids: const <String>{},
      conversations: const <ConversationSummary>[],
    );
    expect(activePolicy.allowsAgent(activeRuntime), isTrue);
  });

  test(
    'deleted agent conversations remain historical but are never invitable',
    () {
      final deletedConversation = ConversationSummary(
        threadId: 'dm:deleted-agent',
        conversationId: 'dm:deleted-agent',
        displayName: 'Deleted agent',
        lastMessagePreview: 'history',
        lastMessageAt: DateTime(2026, 7, 13),
        unreadCount: 0,
        isGroup: false,
        targetDid: 'did:agent:runtime:deleted',
        peerLifecycleState: ConversationPeerLifecycleState.deletedAgent,
      );
      final policy = GroupInviteEligibilityPolicy.fromSources(
        agents: const <AgentSummary>[],
        pendingDeletionAgentDids: const <String>{},
        conversations: <ConversationSummary>[deletedConversation],
      );

      expect(policy.allowsConversation(deletedConversation), isFalse);
      expect(policy.allowsIdentity(did: 'did:agent:runtime:deleted'), isFalse);
      expect(policy.allowsIdentity(did: 'did:user:active'), isTrue);
    },
  );
}
