class SkillOnboardingGrant {
  const SkillOnboardingGrant({
    required this.token,
    required this.tokenId,
    required this.controllerHandle,
    required this.agentHandle,
    required this.serviceOrigin,
    required this.expiresAt,
  });

  final String token;
  final String tokenId;
  final String controllerHandle;
  final String agentHandle;
  final String serviceOrigin;
  final DateTime expiresAt;

  @override
  String toString() {
    return 'SkillOnboardingGrant(token: <redacted>, tokenId: $tokenId, '
        'controllerHandle: $controllerHandle, agentHandle: $agentHandle, '
        'serviceOrigin: $serviceOrigin, expiresAt: $expiresAt)';
  }
}

class SkillOnboardingInstruction {
  const SkillOnboardingInstruction({
    required this.controllerHandle,
    required this.agentHandle,
    required this.expiresAt,
    required this.prompt,
  });

  final String controllerHandle;
  final String agentHandle;
  final DateTime expiresAt;
  final String prompt;

  bool isExpired(DateTime now) => !expiresAt.toUtc().isAfter(now.toUtc());

  @override
  String toString() {
    return 'SkillOnboardingInstruction(controllerHandle: $controllerHandle, '
        'agentHandle: $agentHandle, expiresAt: $expiresAt, prompt: <redacted>)';
  }
}

SkillOnboardingInstruction buildSkillOnboardingInstruction({
  required SkillOnboardingGrant grant,
  required String expectedControllerDid,
  required String expectedControllerHandle,
  DateTime Function()? now,
}) {
  const domesticOrigin = 'https://awiki.info';
  final controllerDid = expectedControllerDid.trim();
  final controllerHandle = _normalizeHandle(expectedControllerHandle);
  final responseControllerHandle = _normalizeHandle(grant.controllerHandle);
  final agentHandle = _normalizeHandle(grant.agentHandle);
  final token = grant.token.trim();
  final expiresAt = grant.expiresAt.toUtc();
  final currentTime = (now ?? DateTime.now)().toUtc();

  if (grant.serviceOrigin.trim() != domesticOrigin ||
      controllerDid.isEmpty ||
      controllerHandle.isEmpty ||
      responseControllerHandle != controllerHandle ||
      !controllerHandle.endsWith('.awiki.info') ||
      agentHandle.isEmpty ||
      !agentHandle.endsWith('.awiki.info') ||
      token.isEmpty ||
      token.contains(RegExp(r'\s')) ||
      !expiresAt.isAfter(currentTime)) {
    throw const FormatException('invalid_skill_onboarding_scope');
  }

  final expiresAtText = expiresAt.toIso8601String();
  final prompt =
      '''Read https://awiki.info/cli/onboarding.md and follow the instructions to install AWiki CLI and Skill, initialize a new or empty workspace, then automatically claim the one-time Skill Agent registration below and complete first-use checks.

AWIKI_SKILL_ONBOARDING_V1
service_base_url=$domesticOrigin
token=$token
controller_handle=$controllerHandle
agent_handle=$agentHandle
expires_at=$expiresAtText
END_AWIKI_SKILL_ONBOARDING_V1

The token authorizes exactly one new Skill Agent DID and one fixed greeting to its controller. Do not print, persist, send, or reuse it. Stop and ask me if the workspace already has a usable identity, any field does not match verified token metadata, or any optional or uncertain step is required.''';

  return SkillOnboardingInstruction(
    controllerHandle: controllerHandle,
    agentHandle: agentHandle,
    expiresAt: expiresAt,
    prompt: prompt,
  );
}

String _normalizeHandle(String value) {
  return value.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
}
