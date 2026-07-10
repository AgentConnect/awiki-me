import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';

/// Strict, reusable product oracles for the UI-driven App + CLI E2E flows.
///
/// These helpers deliberately reject zero and duplicate matches. A visible
/// string, a non-empty history, or an outer process exit code is not enough to
/// prove that the intended message reached the intended conversation.
ChatMessage requireExactlyOneMessage({
  required Iterable<ChatMessage> messages,
  required String content,
  String? messageId,
  String? senderDid,
  String? receiverDid,
  String? groupDid,
  MessageSendState? sendState,
  bool requireCanonicalRemoteId = true,
}) {
  final matches = messages
      .where((message) {
        final canonicalId = message.remoteId ?? message.localId;
        return message.content == content &&
            (messageId == null || canonicalId == messageId);
      })
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one message with content "$content"'
      '${messageId == null ? '' : ' and id "$messageId"'}, '
      'found ${matches.length}.',
    );
  }
  final message = matches.single;
  final remoteId = message.remoteId?.trim() ?? '';
  if (requireCanonicalRemoteId && remoteId.isEmpty) {
    throw StateError('Message "$content" has no canonical remote id.');
  }
  if (senderDid != null && message.senderDid.trim() != senderDid.trim()) {
    throw StateError(
      'Message "$content" sender ${message.senderDid} != $senderDid.',
    );
  }
  if (receiverDid != null &&
      (message.receiverDid?.trim() ?? '') != receiverDid.trim()) {
    throw StateError(
      'Message "$content" receiver ${message.receiverDid} != $receiverDid.',
    );
  }
  if (groupDid != null && (message.groupId?.trim() ?? '') != groupDid.trim()) {
    throw StateError(
      'Message "$content" group ${message.groupId} != $groupDid.',
    );
  }
  if (sendState != null && message.sendState != sendState) {
    throw StateError(
      'Message "$content" send state ${message.sendState} != $sendState.',
    );
  }
  return message;
}

ConversationSummary requireExactlyOneConversation({
  required Iterable<ConversationSummary> conversations,
  required String conversationId,
  required int unreadCount,
  String? lastMessage,
}) {
  final normalizedId = conversationId.trim();
  final matches = conversations
      .where(
        (conversation) =>
            conversation.effectiveConversationId.trim() == normalizedId,
      )
      .toList(growable: false);
  if (matches.length != 1) {
    throw StateError(
      'Expected exactly one conversation "$normalizedId", '
      'found ${matches.length}.',
    );
  }
  final conversation = matches.single;
  if (conversation.unreadCount != unreadCount) {
    throw StateError(
      'Conversation "$normalizedId" unread ${conversation.unreadCount} '
      '!= $unreadCount.',
    );
  }
  if (lastMessage != null &&
      conversation.lastMessagePreview.trim() != lastMessage.trim()) {
    throw StateError(
      'Conversation "$normalizedId" preview '
      '"${conversation.lastMessagePreview}" != "$lastMessage".',
    );
  }
  return conversation;
}

void requireUnreadTotal({required int actual, required int expected}) {
  if (actual != expected) {
    throw StateError('Unread total $actual != $expected.');
  }
}

void requireSingleMentionTarget({
  required ChatMessage message,
  required String targetDid,
}) {
  if (message.mentions.length != 1) {
    throw StateError(
      'Message "${message.content}" has ${message.mentions.length} mentions, '
      'expected exactly one.',
    );
  }
  final mention = message.mentions.single;
  if (!mention.rangeMatches(message.content)) {
    throw StateError(
      'Message "${message.content}" has an invalid mention range.',
    );
  }
  final mentionDid = mention.target.did?.trim() ?? '';
  if (mentionDid != targetDid.trim()) {
    throw StateError('Mention target ${mention.target.did} != $targetDid.');
  }
}
