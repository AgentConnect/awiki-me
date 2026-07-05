class AppConversationReadRef {
  const AppConversationReadRef._(this.conversationId);

  factory AppConversationReadRef.fromConversationId(String conversationId) {
    final normalized = conversationId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'Conversation id must not be empty.',
      );
    }
    return AppConversationReadRef._(normalized);
  }

  final String conversationId;
}
