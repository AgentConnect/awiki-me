enum ConversationPeerLifecycleState { active, deletedAgent }

class ConversationSummary {
  const ConversationSummary({
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
    this.groupId,
    this.avatarUri,
    this.avatarSeed,
    this.lastMessagePayloadJson,
    this.conversationKey,
    this.peerLifecycleState = ConversationPeerLifecycleState.active,
  });

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
  final String? groupId;
  final String? avatarUri;
  final String? avatarSeed;
  final String? lastMessagePayloadJson;
  final String? conversationKey;
  final ConversationPeerLifecycleState peerLifecycleState;

  bool get isDeletedAgentConversation =>
      peerLifecycleState == ConversationPeerLifecycleState.deletedAgent;

  bool get hasUnreadMention => unreadMentionCount > 0;

  String get visibilityKey {
    final explicitKey = conversationKey?.trim();
    if (explicitKey != null && explicitKey.isNotEmpty) {
      return explicitKey;
    }
    if (isGroup) {
      final group = groupId?.trim();
      if (group != null && group.isNotEmpty) {
        return 'group:$group';
      }
    } else {
      final peer = targetPeer?.trim();
      if (peer != null && peer.isNotEmpty) {
        return 'direct:${_normalizeDirectPeer(peer)}';
      }
      final did = targetDid?.trim();
      if (did != null && did.isNotEmpty) {
        return 'direct:$did';
      }
    }
    final thread = threadId.trim();
    return thread.isEmpty ? 'thread:' : 'thread:$thread';
  }

  List<String> get visibilityKeys {
    final keys = <String>[];
    void add(String value) {
      final key = value.trim();
      if (key.isNotEmpty && !keys.contains(key)) {
        keys.add(key);
      }
    }

    add(visibilityKey);
    if (isGroup) {
      final group = groupId?.trim();
      if (group != null && group.isNotEmpty) {
        add('group:$group');
      }
    } else {
      final peer = targetPeer?.trim();
      if (peer != null && peer.isNotEmpty) {
        add('direct:${_normalizeDirectPeer(peer)}');
      }
      final did = targetDid?.trim();
      if (did != null && did.isNotEmpty) {
        add('direct:$did');
      }
    }
    add(threadId);
    return keys;
  }

  ConversationSummary copyWith({
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
    Object? groupId = _conversationSummaryUnset,
    Object? avatarUri = _conversationSummaryUnset,
    Object? avatarSeed = _conversationSummaryUnset,
    Object? lastMessagePayloadJson = _conversationSummaryUnset,
    Object? conversationKey = _conversationSummaryUnset,
    ConversationPeerLifecycleState? peerLifecycleState,
  }) {
    return ConversationSummary(
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
      groupId: _resolveNullableString(groupId, this.groupId),
      avatarUri: _resolveNullableString(avatarUri, this.avatarUri),
      avatarSeed: _resolveNullableString(avatarSeed, this.avatarSeed),
      lastMessagePayloadJson: _resolveNullableString(
        lastMessagePayloadJson,
        this.lastMessagePayloadJson,
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

String _normalizeDirectPeer(String value) {
  final peer = value.trim();
  return peer.startsWith('did:') ? peer : peer.toLowerCase();
}
