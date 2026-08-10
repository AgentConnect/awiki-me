// [INPUT]: User Service server-info Skill group-membership capability payload.
// [OUTPUT]: Fail-closed current-protocol support decision for group invite presentation.
// [POS]: Domain deployment capability; separate from Skill onboarding asset availability.
const int skillGroupMembershipProtocolVersion = 1;
const String skillGroupMembershipRequiredCapability = 'group_membership_v1';

class SkillGroupMembershipCapability {
  const SkillGroupMembershipCapability({
    required this.enabled,
    required this.protocolVersion,
    required this.requiredCapability,
  });

  const SkillGroupMembershipCapability.disabled()
    : enabled = false,
      protocolVersion = skillGroupMembershipProtocolVersion,
      requiredCapability = skillGroupMembershipRequiredCapability;

  final bool enabled;
  final int protocolVersion;
  final String requiredCapability;

  bool get supportsCurrentProtocol =>
      enabled &&
      protocolVersion == skillGroupMembershipProtocolVersion &&
      requiredCapability == skillGroupMembershipRequiredCapability;
}
