import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/conversation_summary.dart';

bool isAgentControlPayloadJson(String? payloadJson) =>
    AgentControlPayloads.isControl(payloadJson);

bool shouldShowConversationForChatList(
  ConversationSummary conversation, {
  required String ownerDid,
  Iterable<String> daemonAgentDids = const [],
}) {
  if (_isSelfDirectConversation(conversation, ownerDid: ownerDid)) {
    return false;
  }
  if (AgentControlPayloads.isControl(conversation.lastMessagePayloadJson)) {
    return false;
  }
  final targetDid = conversation.targetDid?.trim();
  final targetPeer = conversation.targetPeer?.trim();
  if (_looksLikeDaemonDirectTarget(targetDid) ||
      _looksLikeDaemonDirectTarget(targetPeer)) {
    return false;
  }
  final daemonDids = daemonAgentDids
      .map((did) => did.trim())
      .where((did) => did.isNotEmpty)
      .toSet();
  return targetDid == null ||
      targetDid.isEmpty ||
      !daemonDids.contains(targetDid);
}

bool _isSelfDirectConversation(
  ConversationSummary conversation, {
  required String ownerDid,
}) {
  if (conversation.isGroup) {
    return false;
  }
  final owner = ownerDid.trim();
  if (owner.isEmpty) {
    return false;
  }
  final targetDid = conversation.targetDid?.trim();
  final targetPeer = conversation.targetPeer?.trim();
  return targetDid == owner || targetPeer == owner;
}

bool _looksLikeDaemonDirectTarget(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  return normalized.contains(':agent:daemon:') ||
      normalized.startsWith('edgehost-');
}
