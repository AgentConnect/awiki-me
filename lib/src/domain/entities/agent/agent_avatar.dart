import 'dart:convert';
import 'package:crypto/crypto.dart';

const agentAvatarPresetIds = <String>[
  'financing',
  'schedule',
  'bp',
  'legal',
  'research',
  'coding',
  'writing',
  'design',
  'data',
  'finance',
  'marketing',
  'sales',
  'support',
  'operations',
  'product',
  'strategy',
  'learning',
  'translation',
  'travel',
  'health',
  'security',
  'testing',
  'recruiting',
  'news',
  'music',
  'science',
  'food',
  'shopping',
  'planning',
  'knowledge',
  'creative',
  'assistant',
];

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

  static String defaultPreset(String stableId) {
    final digest = sha256.convert(utf8.encode(stableId)).bytes;
    final hash =
        (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
    return agentAvatarPresetIds[hash % agentAvatarPresetIds.length];
  }
}

class AgentAvatarCapabilities {
  const AgentAvatarCapabilities({
    required this.avatar,
    required this.uploadEnabled,
    required this.generationEnabled,
  });
  final AgentAvatar avatar;
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
