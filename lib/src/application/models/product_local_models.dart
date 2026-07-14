class ProductConversationOverlay {
  const ProductConversationOverlay({
    required this.ownerDid,
    required this.threadId,
    required this.conversationId,
    this.pinned = false,
    this.muted = false,
    this.hidden = false,
    this.customTitle,
    this.avatarSeed,
    required this.updatedAt,
  });

  final String ownerDid;

  /// Canonical message-chain key owned by im-core.
  ///
  final String conversationId;
  final String threadId;
  final bool pinned;
  final bool muted;
  final bool hidden;
  final String? customTitle;
  final String? avatarSeed;
  final DateTime updatedAt;

  ProductConversationOverlay copyWith({
    String? threadId,
    String? conversationId,
    bool? pinned,
    bool? muted,
    bool? hidden,
    String? customTitle,
    String? avatarSeed,
    DateTime? updatedAt,
  }) {
    return ProductConversationOverlay(
      ownerDid: ownerDid,
      threadId: threadId ?? this.threadId,
      conversationId: conversationId ?? this.conversationId,
      pinned: pinned ?? this.pinned,
      muted: muted ?? this.muted,
      hidden: hidden ?? this.hidden,
      customTitle: customTitle ?? this.customTitle,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ProductConversationAliasMigration {
  const ProductConversationAliasMigration({
    required this.ownerDid,
    required this.legacyConversationId,
    required this.canonicalConversationId,
  });

  final String ownerDid;
  final String legacyConversationId;
  final String canonicalConversationId;
}

class MessageDraft {
  const MessageDraft({
    required this.ownerDid,
    required this.threadId,
    required this.draftText,
    required this.updatedAt,
  });

  final String ownerDid;
  final String threadId;
  final String draftText;
  final DateTime updatedAt;
}

class LocalUiPreference {
  const LocalUiPreference({
    required this.ownerDid,
    required this.key,
    required this.valueJson,
    required this.updatedAt,
  });

  final String ownerDid;
  final String key;
  final String valueJson;
  final DateTime updatedAt;
}

class LocalAgentState {
  const LocalAgentState({
    required this.ownerDid,
    required this.agentDid,
    required this.valueJson,
    required this.updatedAt,
  });

  final String ownerDid;
  final String agentDid;
  final String valueJson;
  final DateTime updatedAt;
}
