import 'identity_type.dart';

export 'identity_type.dart' show IdentityAgentKind, PeerAgentKind;

class PeerAgentIdentity {
  const PeerAgentIdentity({
    required this.isAgent,
    this.agentKind,
    this.capabilities = const <String>{},
  });

  const PeerAgentIdentity.human()
    : isAgent = false,
      agentKind = null,
      capabilities = const <String>{};

  const PeerAgentIdentity.agent({
    this.agentKind = IdentityAgentKind.unknown,
    this.capabilities = const <String>{},
  }) : isAgent = true;

  final bool isAgent;
  final IdentityAgentKind? agentKind;
  final Set<String> capabilities;

  factory PeerAgentIdentity.fromJson(Map<String, Object?> json) {
    final isAgent = json['is_agent'] == true;
    if (!isAgent) {
      return const PeerAgentIdentity.human();
    }
    return PeerAgentIdentity.agent(
      agentKind: _parseAgentKind(json['agent_kind']),
      capabilities: _parseCapabilities(json['agent_capabilities']),
    );
  }
}

IdentityAgentKind _parseAgentKind(Object? value) =>
    parseIdentityAgentKind(value) ?? IdentityAgentKind.unknown;

Set<String> _parseCapabilities(Object? value) => value is List
    ? Set<String>.unmodifiable(
        value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      )
    : const <String>{};
