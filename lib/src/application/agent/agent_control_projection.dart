import '../../domain/entities/agent/agent_control_payloads.dart';
import '../../domain/entities/conversation_summary.dart';

bool isAgentControlPayloadJson(String? payloadJson) =>
    AgentControlPayloads.isControl(payloadJson);

bool shouldShowConversationForChatList(
  ConversationSummary conversation, {
  Iterable<String> daemonAgentDids = const [],
}) {
  if (AgentControlPayloads.isControl(conversation.lastMessagePayloadJson)) {
    return false;
  }
  final targetDid = conversation.targetDid?.trim();
  if (targetDid == null || targetDid.isEmpty) {
    return true;
  }
  final daemonDids = daemonAgentDids
      .map((did) => did.trim())
      .where((did) => did.isNotEmpty)
      .toSet();
  return !daemonDids.contains(targetDid);
}
