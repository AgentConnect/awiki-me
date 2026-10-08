class AgentAvatar {
  const AgentAvatar({
    required this.agentId,
    required this.source,
    required this.posterUri,
    required this.version,
    required this.status,
    this.animatedUri,
    this.presetId,
    this.updatedAt,
    this.errorCode,
  });
  final String agentId;
  final String source;
  final String? animatedUri;
  final String posterUri;
  final String? presetId;
  final String status;
  final String version;
  final DateTime? updatedAt;
  final String? errorCode;
  bool get isGenerating => status == 'generating';

  factory AgentAvatar.fromJson(Map<String, Object?> value) => AgentAvatar(
    agentId: value['agent_id'] as String? ?? '',
    source: value['source'] as String? ?? 'default',
    posterUri: value['poster_uri'] as String? ?? '',
    animatedUri: value['animated_uri'] as String?,
    presetId: value['preset_id'] as String?,
    status: value['status'] as String? ?? 'ready',
    version: value['version']?.toString() ?? '0',
    updatedAt: DateTime.tryParse(value['updated_at']?.toString() ?? ''),
    errorCode: value['error_code'] as String?,
  );
  Map<String, Object?> toJson() => {
    'agent_id': agentId,
    'source': source,
    'animated_uri': animatedUri,
    'poster_uri': posterUri,
    'preset_id': presetId,
    'status': status,
    'version': version,
    'updated_at': updatedAt?.toIso8601String(),
    'error_code': errorCode,
  };
}

class AgentAvatarCapabilities {
  const AgentAvatarCapabilities({
    required this.avatar,
    required this.uploadEnabled,
    required this.generationEnabled,
    this.presetCatalog = const [],
    this.defaultAvatar,
  });
  final AgentAvatar avatar;
  final List<AgentAvatarPreset> presetCatalog;
  final AgentAvatar? defaultAvatar;
  final bool uploadEnabled;
  final bool generationEnabled;
}

class AgentAvatarMutation {
  const AgentAvatarMutation({
    required this.avatar,
    required this.inventoryVersion,
  });
  final AgentAvatar avatar;
  final String inventoryVersion;
}

class AgentAvatarPreset {
  const AgentAvatarPreset({
    required this.id,
    required this.displayName,
    required this.posterUri,
    this.animatedUri,
    this.sortOrder = 0,
    this.selectable = true,
  });
  final String id, displayName, posterUri;
  final String? animatedUri;
  final int sortOrder;
  final bool selectable;
  factory AgentAvatarPreset.fromJson(Map<String, Object?> value) =>
      AgentAvatarPreset(
        id: value['id'] as String,
        displayName: value['display_name'] as String,
        posterUri: value['poster_uri'] as String,
        animatedUri: value['animated_uri'] as String?,
        sortOrder: value['sort_order'] as int? ?? 0,
        selectable: value['selectable'] == true,
      );
}
