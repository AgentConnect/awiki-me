class SkillOnboardingGrant {
  const SkillOnboardingGrant({
    required this.token,
    required this.tokenId,
    required this.controllerHandle,
    required this.agentHandle,
    required this.displayName,
    required this.serviceOrigin,
    required this.expiresAt,
  });

  final String token;
  final String tokenId;
  final String controllerHandle;
  final String agentHandle;
  final String displayName;
  final String serviceOrigin;
  final DateTime expiresAt;

  @override
  String toString() {
    return 'SkillOnboardingGrant(token: <redacted>, tokenId: $tokenId, '
        'controllerHandle: $controllerHandle, agentHandle: $agentHandle, '
        'displayName: $displayName, '
        'serviceOrigin: $serviceOrigin, expiresAt: $expiresAt)';
  }
}

class SkillOnboardingInstruction {
  const SkillOnboardingInstruction({
    required this.controllerHandle,
    required this.agentHandle,
    required this.displayName,
    required this.expiresAt,
    required this.prompt,
  });

  final String controllerHandle;
  final String agentHandle;
  final String displayName;
  final DateTime expiresAt;
  final String prompt;

  bool isExpired(DateTime now) => !expiresAt.toUtc().isAfter(now.toUtc());

  @override
  String toString() {
    return 'SkillOnboardingInstruction(controllerHandle: $controllerHandle, '
        'agentHandle: $agentHandle, displayName: $displayName, '
        'expiresAt: $expiresAt, prompt: <redacted>)';
  }
}

const int skillOnboardingProtocolVersion = 1;
const String skillOnboardingDocumentPath = '/cli/onboarding.md';
const String skillOnboardingDisplayNameBinding = 'token_scope_v1';

class SkillOnboardingCapability {
  const SkillOnboardingCapability({
    required this.enabled,
    required this.protocolVersion,
    required this.onboardingPath,
    this.displayNameBinding = '',
  });

  const SkillOnboardingCapability.disabled()
    : enabled = false,
      protocolVersion = 0,
      onboardingPath = '',
      displayNameBinding = '';

  final bool enabled;
  final int protocolVersion;
  final String onboardingPath;
  final String displayNameBinding;

  bool get supportsCurrentProtocol =>
      enabled &&
      protocolVersion == skillOnboardingProtocolVersion &&
      onboardingPath == skillOnboardingDocumentPath;

  bool get supportsDisplayNameBinding =>
      supportsCurrentProtocol &&
      displayNameBinding == skillOnboardingDisplayNameBinding;
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
  final displayName = grant.displayName.trim();
  final token = grant.token.trim();
  final expiresAt = grant.expiresAt.toUtc();
  final currentTime = (now ?? DateTime.now)().toUtc();

  if (!capability.supportsDisplayNameBinding ||
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
      displayName.isEmpty ||
      displayName.length > 40 ||
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

The token authorizes exactly one new Skill Agent DID with the server-bound display name shown in AWiki Me, an automatic follow of its controller, and one fixed greeting to that controller. Do not print, persist, send, or reuse it. Stop and ask me if the workspace already has a usable identity, any field does not match verified token metadata, or any optional or uncertain step is required.''';

  return SkillOnboardingInstruction(
    controllerHandle: controllerHandle,
    agentHandle: agentHandle,
    displayName: displayName,
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
