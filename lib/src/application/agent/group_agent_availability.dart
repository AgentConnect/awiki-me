import '../../domain/entities/agent/acp_task.dart';
import '../../domain/entities/agent/agent_availability.dart';
import '../../domain/entities/chat_mention.dart';
import '../../domain/entities/chat_message.dart';

/// Only explicit, valid addressees are checked. Broadcasts have no skip notices.
Map<String, String> explicitGroupAgentTargets(ChatMessage message) {
  if (!message.isMine ||
      message.sendState != MessageSendState.sent ||
      message.groupId?.isNotEmpty != true) {
    return const {};
  }
  final mentions = message.mentions.where(
    (mention) =>
        mention.role == ChatMentionRole.addressee &&
        mention.rangeMatches(message.content),
  );
  if (mentions.any(
    (mention) => mention.target.kind == ChatMentionTargetKind.groupSelector,
  )) {
    return const {};
  }
  return {
    for (final mention in mentions)
      if (mention.target.kind == ChatMentionTargetKind.agent &&
          mention.target.did?.isNotEmpty == true)
        mention.target.did!: mention.surface,
  };
}

/// A lifecycle notice is not an execution rejection and never rewrites history.
Map<String, String> unavailableGroupAgentNotices({
  required ChatMessage message,
  required String conversationId,
  required Map<String, AgentAvailability> availability,
  required Iterable<AcpTask> tasks,
  Set<String> rejectedAgentDids = const {},
}) {
  if (message.conversationId != null &&
      message.conversationId != conversationId) {
    return const {};
  }
  final sourceIds = {
    message.localId,
    if (message.remoteId != null) message.remoteId!,
  };
  final ended = {
    for (final task in tasks)
      if (task.group &&
          task.conversationId == conversationId &&
          task.terminal &&
          sourceIds.contains(task.sourceMessageId))
        task.agentDid,
  };
  return {
    for (final entry in explicitGroupAgentTargets(message).entries)
      if (availability[entry.key]?.unavailable == true &&
          !ended.contains(entry.key) &&
          !rejectedAgentDids.contains(entry.key))
        entry.key: entry.value,
  };
}
