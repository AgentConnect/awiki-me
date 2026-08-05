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

const int skillOnboardingProtocolVersion = 1;
const String skillOnboardingDocumentPath = '/cli/onboarding.md';

class SkillOnboardingCapability {
  const SkillOnboardingCapability({
    required this.enabled,
    required this.protocolVersion,
    required this.onboardingPath,
  });

  const SkillOnboardingCapability.disabled()
    : enabled = false,
      protocolVersion = 0,
      onboardingPath = '';

  final bool enabled;
  final int protocolVersion;
  final String onboardingPath;

  bool get supportsCurrentProtocol =>
      enabled &&
      protocolVersion == skillOnboardingProtocolVersion &&
      onboardingPath == skillOnboardingDocumentPath;
}

SkillOnboardingInstruction buildSkillOnboardingInstruction({
  required SkillOnboardingGrant grant,
  required SkillOnboardingCapability capability,
  required String expectedServiceOrigin,
  required String expectedControllerDid,
  required String expectedControllerHandle,
  DateTime Function()? now,
}) {
  final serviceOrigin = grant.serviceOrigin.trim();
  final serviceUri = Uri.tryParse(serviceOrigin);
  final serviceDomain = serviceUri?.host.trim().toLowerCase() ?? '';
  final expectedOrigin = expectedServiceOrigin.trim();
  final expectedUri = Uri.tryParse(expectedOrigin);
  final expectedDomain = expectedUri?.host.trim().toLowerCase() ?? '';
  final controllerDid = expectedControllerDid.trim();
  final controllerHandle = _normalizeHandle(expectedControllerHandle);
  final responseControllerHandle = _normalizeHandle(grant.controllerHandle);
  final agentHandle = _normalizeHandle(grant.agentHandle);
  final token = grant.token.trim();
  final expiresAt = grant.expiresAt.toUtc();
  final currentTime = (now ?? DateTime.now)().toUtc();

  if (!capability.supportsCurrentProtocol ||
      !_isCanonicalHttpsOrigin(expectedUri, expectedOrigin, expectedDomain) ||
      serviceUri == null ||
      serviceUri.scheme != 'https' ||
      serviceOrigin != 'https://$serviceDomain' ||
      serviceOrigin != expectedOrigin ||
      serviceDomain != expectedDomain ||
      controllerDid.isEmpty ||
      !_didUsesDomain(controllerDid, serviceDomain) ||
      controllerHandle.isEmpty ||
      responseControllerHandle != controllerHandle ||
      !controllerHandle.endsWith('.$serviceDomain') ||
      agentHandle.isEmpty ||
      !agentHandle.endsWith('.$serviceDomain') ||
      token.isEmpty ||
      token.contains(RegExp(r'\s')) ||
      !expiresAt.isAfter(currentTime)) {
    throw const FormatException('invalid_skill_onboarding_scope');
  }

  final expiresAtText = expiresAt.toIso8601String();
  final prompt =
      '''Read $serviceOrigin${capability.onboardingPath} and follow the instructions to install AWiki CLI and Skill, initialize a new or empty workspace, then automatically claim the one-time Skill Agent registration below and complete first-use checks.

AWIKI_SKILL_ONBOARDING_V1
service_base_url=$serviceOrigin
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

bool _isCanonicalHttpsOrigin(Uri? uri, String origin, String domain) {
  return uri != null &&
      uri.scheme == 'https' &&
      domain.isNotEmpty &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.path.isEmpty || uri.path == '/') &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      origin == 'https://$domain';
}

bool _didUsesDomain(String did, String domain) {
  final parts = did.split(':');
  return parts.length >= 4 &&
      parts[0] == 'did' &&
      parts[1] == 'wba' &&
      parts[2].toLowerCase() == domain;
}
