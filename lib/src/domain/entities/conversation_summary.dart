import 'chat_message.dart';

enum ConversationPeerLifecycleState { active, deletedAgent }

class ConversationSummary {
  const ConversationSummary({
    required this.conversationId,
    required this.threadId,
    required this.displayName,
    required this.lastMessagePreview,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.isGroup,
    this.unreadMentionCount = 0,
    this.firstUnreadMentionMessageId,
    this.targetDid,
    this.targetPeer,
    this.peerPersonaId,
    this.peerLocalNote,
    this.canonicalGroupDid,
    this.groupId,
    this.avatarUri,
    this.avatarSeed,
    this.lastMessagePayloadJson,
    this.lastMessageSnapshot,
    this.conversationKey,
    this.peerLifecycleState = ConversationPeerLifecycleState.active,
  });

  /// Required canonical message-chain key owned by im-core.
  final String conversationId;
  final String threadId;
  final String displayName;
  final String lastMessagePreview;
  final DateTime lastMessageAt;
  final int unreadCount;
  final int unreadMentionCount;
  final String? firstUnreadMentionMessageId;
  final bool isGroup;
  final String? targetDid;
  final String? targetPeer;
  final String? peerPersonaId;
  final String? peerLocalNote;
  final String? canonicalGroupDid;
  final String? groupId;
  final String? avatarUri;
  final String? avatarSeed;
  final String? lastMessagePayloadJson;
  final ChatMessage? lastMessageSnapshot;
  final String? conversationKey;
  final ConversationPeerLifecycleState peerLifecycleState;

  bool get isDeletedAgentConversation =>
      peerLifecycleState == ConversationPeerLifecycleState.deletedAgent;

  bool get hasUnreadMention => unreadMentionCount > 0;

  ConversationSummary copyWith({
    String? conversationId,
    String? threadId,
    String? displayName,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    int? unreadCount,
    int? unreadMentionCount,
    Object? firstUnreadMentionMessageId = _conversationSummaryUnset,
    bool? isGroup,
    Object? targetDid = _conversationSummaryUnset,
    Object? targetPeer = _conversationSummaryUnset,
    Object? peerPersonaId = _conversationSummaryUnset,
    Object? peerLocalNote = _conversationSummaryUnset,
    Object? canonicalGroupDid = _conversationSummaryUnset,
    Object? groupId = _conversationSummaryUnset,
    Object? avatarUri = _conversationSummaryUnset,
    Object? avatarSeed = _conversationSummaryUnset,
    Object? lastMessagePayloadJson = _conversationSummaryUnset,
    Object? lastMessageSnapshot = _conversationSummaryUnset,
    Object? conversationKey = _conversationSummaryUnset,
    ConversationPeerLifecycleState? peerLifecycleState,
  }) {
    return ConversationSummary(
      conversationId: conversationId ?? this.conversationId,
      threadId: threadId ?? this.threadId,
      displayName: displayName ?? this.displayName,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      unreadMentionCount: unreadMentionCount ?? this.unreadMentionCount,
      firstUnreadMentionMessageId: _resolveNullableString(
        firstUnreadMentionMessageId,
        this.firstUnreadMentionMessageId,
      ),
      isGroup: isGroup ?? this.isGroup,
      targetDid: _resolveNullableString(targetDid, this.targetDid),
      targetPeer: _resolveNullableString(targetPeer, this.targetPeer),
      peerPersonaId: _resolveNullableString(peerPersonaId, this.peerPersonaId),
      peerLocalNote: _resolveNullableString(peerLocalNote, this.peerLocalNote),
      canonicalGroupDid: _resolveNullableString(
        canonicalGroupDid,
        this.canonicalGroupDid,
      ),
      groupId: _resolveNullableString(groupId, this.groupId),
      avatarUri: _resolveNullableString(avatarUri, this.avatarUri),
      avatarSeed: _resolveNullableString(avatarSeed, this.avatarSeed),
      lastMessagePayloadJson: _resolveNullableString(
        lastMessagePayloadJson,
        this.lastMessagePayloadJson,
      ),
      lastMessageSnapshot: _resolveNullableChatMessage(
        lastMessageSnapshot,
        this.lastMessageSnapshot,
      ),
      conversationKey: _resolveNullableString(
        conversationKey,
        this.conversationKey,
      ),
      peerLifecycleState: peerLifecycleState ?? this.peerLifecycleState,
    );
  }
}

const Object _conversationSummaryUnset = Object();

String? _resolveNullableString(Object? value, String? current) {
  if (identical(value, _conversationSummaryUnset)) {
    return current;
  }
  return value as String?;
}

ChatMessage? _resolveNullableChatMessage(Object? value, ChatMessage? current) {
  if (identical(value, _conversationSummaryUnset)) {
    return current;
  }
  return value as ChatMessage?;
}
