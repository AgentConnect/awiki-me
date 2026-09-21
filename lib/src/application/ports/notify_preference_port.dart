class NotifyPreference {
  const NotifyPreference({
    required this.enabled,
    required this.urgentEnabled,
    required this.version,
    this.mutedPeerDids = const [],
  });
  final bool enabled;
  final bool urgentEnabled;
  final int version;
  final List<String> mutedPeerDids;
  factory NotifyPreference.fromJson(Map<String, Object?> data) {
    if (data['enabled'] is! bool ||
        data['urgent_enabled'] is! bool ||
        data['version'] is! int ||
        (data['version'] as int) < 0 ||
        data['muted_peer_dids'] is! List) {
      throw const FormatException('Invalid Notify preference');
    }
    return NotifyPreference(
      enabled: data['enabled'] as bool,
      urgentEnabled: data['urgent_enabled'] as bool,
      version: data['version'] as int,
      mutedPeerDids: List<String>.from(data['muted_peer_dids'] as List),
    );
  }
  Map<String, Object?> get json => {
    'enabled': enabled,
    'urgent_enabled': urgentEnabled,
    'version': version,
    'muted_peer_dids': mutedPeerDids,
  };
}

abstract interface class NotifyPreferencePort {
  Future<NotifyPreference> load();
  Future<NotifyPreference> save(
    NotifyPreference previous, {
    required bool enabled,
    required bool urgentEnabled,
    List<String>? mutedPeerDids,
  });
}
