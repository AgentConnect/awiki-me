enum PeerAgentKind { daemon, runtime, unknown }

class PeerAgentIdentity {
  const PeerAgentIdentity({required this.isAgent, this.agentKind});

  const PeerAgentIdentity.human() : isAgent = false, agentKind = null;

  const PeerAgentIdentity.agent({this.agentKind}) : isAgent = true;

  final bool isAgent;
  final PeerAgentKind? agentKind;

  factory PeerAgentIdentity.fromJson(Map<String, Object?> json) {
    final isAgent = json['is_agent'] == true;
    if (!isAgent) {
      return const PeerAgentIdentity.human();
    }
    return PeerAgentIdentity.agent(
      agentKind: _parseAgentKind(json['agent_kind']),
    );
  }
}

PeerAgentKind? _parseAgentKind(Object? value) {
  final text = value?.toString().trim().toLowerCase();
  return switch (text) {
    'daemon' => PeerAgentKind.daemon,
    'runtime' => PeerAgentKind.runtime,
    _ => null,
  };
}
