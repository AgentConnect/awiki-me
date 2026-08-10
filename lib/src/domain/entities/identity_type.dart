// [INPUT]: Structured subject_type/is_agent/agent_kind fields from trusted profile boundaries.
// [OUTPUT]: One shared identity classification for contacts, profiles, conversations, and groups.
// [POS]: Domain identity taxonomy; operational Agent inventory kinds remain a separate lifecycle model.
enum IdentitySubjectKind { user, agent, group, unknown }

enum IdentityAgentKind { daemon, runtime, skill, unknown }

class IdentityType {
  const IdentityType({required this.subjectKind, this.agentKind});

  const IdentityType.user()
    : subjectKind = IdentitySubjectKind.user,
      agentKind = null;

  const IdentityType.agent({this.agentKind = IdentityAgentKind.unknown})
    : subjectKind = IdentitySubjectKind.agent;

  const IdentityType.group()
    : subjectKind = IdentitySubjectKind.group,
      agentKind = null;

  const IdentityType.unknown()
    : subjectKind = IdentitySubjectKind.unknown,
      agentKind = null;

  final IdentitySubjectKind subjectKind;
  final IdentityAgentKind? agentKind;

  bool get isAgent => subjectKind == IdentitySubjectKind.agent;
  bool get isSkillAgent => isAgent && agentKind == IdentityAgentKind.skill;

  bool get isSpecific =>
      subjectKind != IdentitySubjectKind.unknown &&
      (!isAgent || agentKind != IdentityAgentKind.unknown);

  factory IdentityType.fromWire({
    Object? subjectType,
    Object? isAgent,
    Object? agentKind,
  }) {
    final kind = parseIdentityAgentKind(agentKind);
    final normalizedSubject = subjectType?.toString().trim().toLowerCase();
    if (isAgent == true || kind != null || normalizedSubject == 'agent') {
      return IdentityType.agent(agentKind: kind ?? IdentityAgentKind.unknown);
    }
    return switch (normalizedSubject) {
      'user' || 'human' || 'person' => const IdentityType.user(),
      'group' => const IdentityType.group(),
      _ => const IdentityType.unknown(),
    };
  }

  IdentityType merge(IdentityType other) {
    if (other.isSpecific) {
      return other;
    }
    if (isSpecific) {
      return this;
    }
    if (other.isAgent) {
      return other;
    }
    return this;
  }
}

IdentityAgentKind? parseIdentityAgentKind(Object? value) {
  return switch (value?.toString().trim().toLowerCase()) {
    'daemon' => IdentityAgentKind.daemon,
    'runtime' => IdentityAgentKind.runtime,
    'skill' => IdentityAgentKind.skill,
    'unknown' => IdentityAgentKind.unknown,
    _ => null,
  };
}

IdentityAgentKind? identityAgentKindFromDidHint(String did) {
  final normalized = did.trim().toLowerCase();
  if (normalized.contains(':agent:skill:') ||
      normalized.contains(':agents:skill:')) {
    return IdentityAgentKind.skill;
  }
  if (normalized.contains(':agent:daemon:') ||
      normalized.contains(':agents:daemon:')) {
    return IdentityAgentKind.daemon;
  }
  if (normalized.contains(':agent:runtime:') ||
      normalized.contains(':agents:runtime:') ||
      normalized.contains(':runtime_agent:')) {
    return IdentityAgentKind.runtime;
  }
  return null;
}

typedef PeerAgentKind = IdentityAgentKind;
