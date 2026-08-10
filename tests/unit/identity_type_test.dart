import 'package:awiki_me/src/domain/entities/identity_type.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wire identity type preserves specific Agent kinds', () {
    final skill = IdentityType.fromWire(
      subjectType: 'agent',
      agentKind: 'skill',
    );

    expect(skill.subjectKind, IdentitySubjectKind.agent);
    expect(skill.agentKind, IdentityAgentKind.skill);
    expect(skill.isSkillAgent, isTrue);
  });

  test('specific structured identity wins when candidate sources merge', () {
    const genericAgent = IdentityType.agent();
    const skill = IdentityType.agent(agentKind: IdentityAgentKind.skill);

    expect(genericAgent.merge(skill).agentKind, IdentityAgentKind.skill);
    expect(skill.merge(genericAgent).agentKind, IdentityAgentKind.skill);
  });

  test('legacy public profile without classification remains a user', () {
    const profile = UserProfile(
      did: 'did:wba:awiki.ai:user:legacy:e1_user',
      displayName: 'Legacy user',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
    );

    expect(profile.identityType.subjectKind, IdentitySubjectKind.user);
  });

  test('DID hint identifies Agent kind without granting capabilities', () {
    expect(
      identityAgentKindFromDidHint(
        'did:wba:awiki.ai:agent:skill:legacy:e1_agent',
      ),
      IdentityAgentKind.skill,
    );
    expect(
      identityAgentKindFromDidHint('did:wba:awiki.ai:user:skillful:e1_user'),
      isNull,
    );
    expect(
      identityAgentKindFromDidHint('did:wba:awiki.ai:user:skill:e1_user'),
      isNull,
    );
  });
}
