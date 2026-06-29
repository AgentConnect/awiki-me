import 'chat_message.dart';
import 'conversation_summary.dart';
import 'group_summary.dart';

class RealtimeUpdate {
  const RealtimeUpdate({
    this.message,
    this.conversationHint,
    this.conversation,
    this.group,
    this.agentControlPayload,
    this.syncDirty = false,
    this.gapDetected = false,
    this.syncEventSeq,
    this.syncEventType,
  });

  final ChatMessage? message;
  final ConversationSummary? conversationHint;
  final ConversationSummary? conversation;
  final GroupSummary? group;
  final Map<String, Object?>? agentControlPayload;
  final bool syncDirty;
  final bool gapDetected;
  final String? syncEventSeq;
  final String? syncEventType;

  bool get isAgentControl => agentControlPayload != null;
  bool get needsReliableSync => syncDirty || gapDetected;
}
