import 'conversation_summary.dart';

/// True when [threadId] is the Core storage reference used by peer-scoped
/// Direct conversations.
///
/// This classification is retained only at the Core history compatibility
/// boundary. It must not be used to merge, select, hide, or identify an App
/// conversation; those paths use [ConversationSummary.conversationId].
bool isPeerScopedDirectConversation(ConversationSummary conversation) {
  return !conversation.isGroup &&
      isPeerScopedDirectThreadId(conversation.threadId);
}

bool isPeerScopedDirectThreadId(String threadId) {
  return threadId.trim().startsWith('dm:peer-scope:');
}

/// Normalizes a routing/display peer value without assigning conversation
/// identity to it.
String? normalizedDirectPeer(String? value) {
  var normalized = value?.trim() ?? '';
  while (normalized.startsWith('@')) {
    normalized = normalized.substring(1).trimLeft();
  }
  if (normalized.isEmpty) {
    return null;
  }
  return normalized.startsWith('did:') ? normalized : normalized.toLowerCase();
}
