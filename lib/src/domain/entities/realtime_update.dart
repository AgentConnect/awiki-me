import 'chat_message.dart';
import 'conversation_summary.dart';
import 'group_summary.dart';

class RealtimeUpdate {
  const RealtimeUpdate({
    this.message,
    this.conversation,
    this.group,
    this.agentControlPayload,
  });

  final ChatMessage? message;
  final ConversationSummary? conversation;
  final GroupSummary? group;
  final Map<String, Object?>? agentControlPayload;

  bool get isAgentControl => agentControlPayload != null;
}
