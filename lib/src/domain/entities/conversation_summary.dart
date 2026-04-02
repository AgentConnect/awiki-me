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
}
