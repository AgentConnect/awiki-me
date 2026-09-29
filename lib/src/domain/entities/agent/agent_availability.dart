enum AgentAvailabilityState { available, unavailable, unknown }

/// Public lifecycle fact, independent of connectivity and model configuration.
class AgentAvailability {
  const AgentAvailability({
    required this.agentDid,
    required this.state,
    this.reason,
    this.version = '0',
    this.changedAt,
  });

  final String agentDid;
  final AgentAvailabilityState state;
  final String? reason;
  final String version;
  final DateTime? changedAt;

  factory AgentAvailability.fromLifecycle({
    required String agentDid,
    required String activeState,
    required String version,
  }) {
    final reason = switch (activeState) {
      'archived' => 'agent_deleted',
      'retired' => 'agent_retired',
      'revoked' => 'agent_revoked',
      'inactive' => 'agent_inactive',
      _ => null,
    };
    return AgentAvailability(
      agentDid: agentDid,
      state: reason != null
          ? AgentAvailabilityState.unavailable
          : activeState == 'active'
          ? AgentAvailabilityState.available
          : AgentAvailabilityState.unknown,
      reason: reason,
      version: version,
    );
  }

  bool get unavailable => state == AgentAvailabilityState.unavailable;
  bool get terminal =>
      unavailable &&
      const {
        'agent_deleted',
        'agent_revoked',
        'agent_retired',
      }.contains(reason);

  static AgentAvailability? parse(Map<String, Object?> json) {
    final did = json['agent_did'];
    final version = json['version'];
    final rawState = json['state'];
    if (did is! String ||
        !did.startsWith('did:') ||
        did.length > 256 ||
        version is! String ||
        !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(version)) {
      return null;
    }
    final state = switch (rawState) {
      'available' => AgentAvailabilityState.available,
      'unavailable' => AgentAvailabilityState.unavailable,
      'unknown' => AgentAvailabilityState.unknown,
      _ => null,
    };
    if (state == null) return null;
    return AgentAvailability(
      agentDid: did,
      state: state,
      reason: json['reason'] is String ? json['reason'] as String : null,
      version: version,
      changedAt: DateTime.tryParse(json['changed_at']?.toString() ?? ''),
    );
  }

  Map<String, Object?> toJson() => {
    'agent_did': agentDid,
    'state': state.name,
    'reason': reason,
    'version': version,
    'changed_at': changedAt?.toUtc().toIso8601String(),
  };

  bool supersedes(AgentAvailability previous) {
    if (agentDid != previous.agentDid) return false;
    if (state == AgentAvailabilityState.unknown &&
        previous.state != AgentAvailabilityState.unknown) {
      return false;
    }
    if (previous.terminal && !terminal) return false;
    final comparison = BigInt.parse(
      version,
    ).compareTo(BigInt.parse(previous.version));
    if (previous.state == AgentAvailabilityState.unknown &&
        state != AgentAvailabilityState.unknown) {
      return comparison >= 0;
    }
    return comparison > 0 ||
        (comparison == 0 &&
            state == previous.state &&
            reason == previous.reason);
  }
}
