import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/presentation/group/group_member_invite_dialog.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const did = 'did:wba:awiki.info:user:alice:e1_key';

  test('relationship Display Name is current data, not a history snapshot', () {
    final candidate = GroupInviteCandidate.fromRelationship(
      const RelationshipSummary(
        did: did,
        displayName: 'Current Alice',
        relationship: 'following',
        handle: 'alice.awiki.info',
      ),
      source: GroupInviteCandidateSource.following,
    ).withPeerDisplayProfile(const PeerDisplayProfileState());

    expect(candidate.displayName, 'Current Alice');
  });

  test(
    'conversation title is used only after Profile and Handle are absent',
    () {
      final withHandle = GroupInviteCandidate.fromConversation(
        ConversationSummary(
          conversationId: 'dm:alice',
          threadId: 'dm:alice',
          displayName: 'Historical Alice',
          lastMessagePreview: '',
          lastMessageAt: DateTime(2026, 8, 11),
          unreadCount: 0,
          isGroup: false,
          targetDid: did,
          targetPeer: 'alice.awiki.info',
        ),
      ).withPeerDisplayProfile(const PeerDisplayProfileState());
      final snapshotOnly = GroupInviteCandidate.fromConversation(
        ConversationSummary(
          conversationId: 'dm:alice-snapshot',
          threadId: 'dm:alice-snapshot',
          displayName: 'Historical Alice',
          lastMessagePreview: '',
          lastMessageAt: DateTime(2026, 8, 11),
          unreadCount: 0,
          isGroup: false,
          targetDid: did,
        ),
      ).withPeerDisplayProfile(const PeerDisplayProfileState());

      expect(withHandle.displayName, 'alice');
      expect(snapshotOnly.displayName, 'Historical Alice');
    },
  );

  test('authoritative Profile replaces a historical conversation title', () {
    final candidate =
        GroupInviteCandidate.fromConversation(
          ConversationSummary(
            conversationId: 'dm:alice',
            threadId: 'dm:alice',
            displayName: 'Historical Alice',
            lastMessagePreview: '',
            lastMessageAt: DateTime(2026, 8, 11),
            unreadCount: 0,
            isGroup: false,
            targetDid: did,
            targetPeer: 'alice.awiki.info',
          ),
        ).withPeerDisplayProfile(
          const PeerDisplayProfileState(
            unresolvedProfilesByDid: <String, PeerDisplayProfile>{
              did: PeerDisplayProfile(
                did: did,
                displayName: 'Current Alice',
                handle: 'alice.awiki.info',
              ),
            },
          ),
        );

    expect(candidate.displayName, 'Current Alice');
  });

  test('Agent Inventory name is not overridden by a generic peer profile', () {
    final candidate =
        GroupInviteCandidate.fromAgent(
          const AgentSummary(
            agentDid: 'did:wba:awiki.info:agent:runtime:codex:e1_key',
            kind: AgentKind.runtime,
            handle: 'codex.awiki.info',
            displayName: 'My Codex',
            activeState: 'active',
            latest: AgentLatestStatus(status: 'ready'),
          ),
        ).withPeerDisplayProfile(
          const PeerDisplayProfileState(
            unresolvedProfilesByDid: <String, PeerDisplayProfile>{
              'did:wba:awiki.info:agent:runtime:codex:e1_key':
                  PeerDisplayProfile(
                    did: 'did:wba:awiki.info:agent:runtime:codex:e1_key',
                    displayName: 'Stale Generic Name',
                    handle: 'codex.awiki.info',
                  ),
            },
          ),
        );

    expect(candidate.displayName, 'My Codex');
  });

  test('Agent Inventory falls back to Handle without a placeholder name', () {
    final candidate = GroupInviteCandidate.fromAgent(
      const AgentSummary(
        agentDid: 'did:wba:awiki.info:agent:runtime:codex:e1_key',
        kind: AgentKind.runtime,
        handle: 'codex.awiki.info',
        displayName: '',
        activeState: 'active',
        latest: AgentLatestStatus(status: 'ready'),
      ),
    );

    expect(candidate.displayName, 'codex.awiki.info');
  });
}
