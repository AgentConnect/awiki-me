enum ConversationPeerLifecycleState { active, deletedAgent }

class ConversationSummary {
  const ConversationSummary({
    required this.threadId,
    required this.displayName,
    required this.lastMessagePreview,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.isGroup,
    this.targetDid,
    this.groupId,
    this.avatarSeed,
    this.lastMessagePayloadJson,
    this.peerLifecycleState = ConversationPeerLifecycleState.active,
  });

  final String threadId;
  final String displayName;
  final String lastMessagePreview;
  final DateTime lastMessageAt;
  final int unreadCount;
  final bool isGroup;
  final String? targetDid;
  final String? groupId;
  final String? avatarSeed;
  final String? lastMessagePayloadJson;
  final ConversationPeerLifecycleState peerLifecycleState;

  bool get isDeletedAgentConversation =>
      peerLifecycleState == ConversationPeerLifecycleState.deletedAgent;

  ConversationSummary copyWith({
    String? threadId,
    String? displayName,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    int? unreadCount,
    bool? isGroup,
    Object? targetDid = _conversationSummaryUnset,
    Object? groupId = _conversationSummaryUnset,
    Object? avatarSeed = _conversationSummaryUnset,
    Object? lastMessagePayloadJson = _conversationSummaryUnset,
    ConversationPeerLifecycleState? peerLifecycleState,
  }) {
    return ConversationSummary(
      threadId: threadId ?? this.threadId,
      displayName: displayName ?? this.displayName,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isGroup: isGroup ?? this.isGroup,
      targetDid: _resolveNullableString(targetDid, this.targetDid),
      groupId: _resolveNullableString(groupId, this.groupId),
      avatarSeed: _resolveNullableString(avatarSeed, this.avatarSeed),
      lastMessagePayloadJson: _resolveNullableString(
        lastMessagePayloadJson,
        this.lastMessagePayloadJson,
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
