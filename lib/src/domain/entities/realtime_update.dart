import 'chat_message.dart';
import 'conversation_summary.dart';
import 'group_summary.dart';

enum SyncDomain {
  message,
  profile,
  agentInventory,
  agentStatus,
  deviceRegistry,
}

class RealtimeUpdate {
  const RealtimeUpdate({
    this.message,
    this.conversationHint,
    this.conversation,
    this.group,
    this.agentControlPayload,
    this.systemNotificationChanged = false,
    this.domains = const <SyncDomain>{},
    this.reason,
    this.syncDirty = false,
    this.gapDetected = false,
    this.hasUnknownDomain = false,
  });

  final ChatMessage? message;
  final ConversationSummary? conversationHint;
  final ConversationSummary? conversation;
  final GroupSummary? group;
  final Map<String, Object?>? agentControlPayload;
  final bool systemNotificationChanged;
  final Set<SyncDomain> domains;
  final String? reason;
  final bool syncDirty;
  final bool gapDetected;
  final bool hasUnknownDomain;

  bool get isAgentControl => agentControlPayload != null;
  bool get needsReliableSync =>
      systemNotificationChanged ||
      domains.isNotEmpty ||
      syncDirty ||
      gapDetected ||
      hasUnknownDomain;
}
