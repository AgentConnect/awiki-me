import 'chat_message.dart';
import 'conversation_summary.dart';
import 'group_summary.dart';

class RealtimeUpdate {
  const RealtimeUpdate({
    required this.message,
    required this.conversation,
    this.group,
  });

  final ChatMessage message;
  final ConversationSummary conversation;
  final GroupSummary? group;
}
