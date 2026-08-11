import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/peer_display_profile.dart';
import 'package:awiki_me/src/presentation/chat/chat_mention_presentation.dart';
import 'package:awiki_me/src/presentation/profile/peer_display_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owned Agent mention uses Inventory name by exact DID', () {
    const agentDid = 'did:wba:awiki.info:agent:runtime:codex:e1_key';
    const member = GroupMemberSummary(
      userId: agentDid,
      did: agentDid,
      handle: 'codex.awiki.info',
      role: 'member',
      displayName: 'Roster Agent Name',
      subjectType: GroupMemberSubjectType.agent,
    );
    final resolver = ChatMentionPresentationResolver(
      session: null,
      currentProfile: null,
      peerProfiles: const PeerDisplayProfileState(
        unresolvedProfilesByDid: <String, PeerDisplayProfile>{
          agentDid: PeerDisplayProfile(
            did: agentDid,
            displayName: 'Generic Profile Name',
            handle: 'codex.awiki.info',
          ),
        },
      ),
      groupMembers: const <GroupMemberSummary>[member],
      agentInventory: const <AgentSummary>[
        AgentSummary(
          agentDid: agentDid,
          kind: AgentKind.runtime,
          handle: 'codex.awiki.info',
          displayName: 'Inventory Agent Name',
          activeState: 'active',
          latest: AgentLatestStatus(status: 'ready'),
        ),
      ],
    );

    expect(
      resolver.projectGroupMember(member).displayName,
      'Inventory Agent Name',
    );
  });
}
