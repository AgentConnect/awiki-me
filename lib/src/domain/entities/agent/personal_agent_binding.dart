class PersonalAgentBinding {
  const PersonalAgentBinding({
    required this.id,
    required this.userDid,
    required this.daemonAgentDid,
    required this.personalAgentDid,
    required this.runtimeProvider,
    required this.runtimeProfile,
    required this.delegatedKeyVerificationMethod,
    required this.status,
  });

  final String id;
  final String userDid;
  final String daemonAgentDid;
  final String personalAgentDid;
  final String runtimeProvider;
  final Map<String, Object?> runtimeProfile;
  final String delegatedKeyVerificationMethod;
  final String status;

  bool get isActive => status.trim().toLowerCase() == 'active';

  factory PersonalAgentBinding.fromJson(Map<String, Object?> json) {
    return PersonalAgentBinding(
      id: json['id']?.toString() ?? '',
      userDid: json['user_did']?.toString() ?? '',
      daemonAgentDid: json['daemon_agent_did']?.toString() ?? '',
      personalAgentDid:
          json['personal_agent_did']?.toString() ??
          json['message_agent_did']?.toString() ??
          '',
      runtimeProvider: json['runtime_provider']?.toString() ?? '',
      runtimeProfile: _readMap(json['runtime_profile']),
      delegatedKeyVerificationMethod:
          json['delegated_key_verification_method']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'user_did': userDid,
      'daemon_agent_did': daemonAgentDid,
      'personal_agent_did': personalAgentDid,
      'runtime_provider': runtimeProvider,
      'runtime_profile': runtimeProfile,
      'delegated_key_verification_method': delegatedKeyVerificationMethod,
      'status': status,
    };
  }
}

Map<String, Object?> _readMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}
