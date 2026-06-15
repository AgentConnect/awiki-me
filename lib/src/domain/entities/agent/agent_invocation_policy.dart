enum AgentInvocationPolicyMode {
  whitelist('whitelist'),
  blacklist('blacklist');

  const AgentInvocationPolicyMode(this.wireValue);

  final String wireValue;

  static AgentInvocationPolicyMode parse(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'blacklist' => AgentInvocationPolicyMode.blacklist,
      _ => AgentInvocationPolicyMode.whitelist,
    };
  }
}

class AgentInvocationPolicy {
  const AgentInvocationPolicy({
    this.schema = 'awiki.agent_invocation_policy.v1',
    this.activeMode = AgentInvocationPolicyMode.whitelist,
    this.whitelistHandles = const <String>[],
    this.blacklistHandles = const <String>[],
  });

  final String schema;
  final AgentInvocationPolicyMode activeMode;
  final List<String> whitelistHandles;
  final List<String> blacklistHandles;

  factory AgentInvocationPolicy.fromJson(Map<String, Object?> json) {
    return AgentInvocationPolicy(
      schema: json['schema']?.toString() ?? 'awiki.agent_invocation_policy.v1',
      activeMode: AgentInvocationPolicyMode.parse(
        json['active_mode']?.toString(),
      ),
      whitelistHandles: _stringList(json['whitelist_handles']),
      blacklistHandles: _stringList(json['blacklist_handles']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'active_mode': activeMode.wireValue,
    'whitelist_handles': whitelistHandles,
    'blacklist_handles': blacklistHandles,
  };

  AgentInvocationPolicy copyWith({
    AgentInvocationPolicyMode? activeMode,
    List<String>? whitelistHandles,
    List<String>? blacklistHandles,
  }) {
    return AgentInvocationPolicy(
      schema: schema,
      activeMode: activeMode ?? this.activeMode,
      whitelistHandles: whitelistHandles ?? this.whitelistHandles,
      blacklistHandles: blacklistHandles ?? this.blacklistHandles,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentInvocationPolicy &&
          runtimeType == other.runtimeType &&
          schema == other.schema &&
          activeMode == other.activeMode &&
          _stringListEquals(whitelistHandles, other.whitelistHandles) &&
          _stringListEquals(blacklistHandles, other.blacklistHandles);

  @override
  int get hashCode => Object.hash(
    schema,
    activeMode,
    Object.hashAll(whitelistHandles),
    Object.hashAll(blacklistHandles),
  );
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

bool _stringListEquals(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
