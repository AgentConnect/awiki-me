import 'dart:typed_data';
import '../../domain/entities/agent/agent_avatar.dart';

/// Inventory capability, separate from the human Core Profile contract.
abstract interface class AgentAvatarPort {
  Future<AgentAvatarCapabilities> loadAgentAvatar(String agentDid);
  Future<AgentAvatarMutation> setAgentAvatar({
    required String agentDid,
    required String requestId,
    required String expectedVersion,
    required String action,
    String? presetId,
    Uint8List? image,
    String? name,
    String? responsibility,
    String? imageDescription,
  });
}
