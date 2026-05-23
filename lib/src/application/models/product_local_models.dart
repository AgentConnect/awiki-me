class ProductConversationOverlay {
  const ProductConversationOverlay({
    required this.ownerDid,
    required this.threadId,
    this.pinned = false,
    this.muted = false,
    this.hidden = false,
    this.customTitle,
    this.avatarSeed,
    required this.updatedAt,
  });

  final String ownerDid;
  final String threadId;
  final bool pinned;
  final bool muted;
  final bool hidden;
  final String? customTitle;
  final String? avatarSeed;
  final DateTime updatedAt;

  ProductConversationOverlay copyWith({
    bool? pinned,
    bool? muted,
    bool? hidden,
    String? customTitle,
    String? avatarSeed,
    DateTime? updatedAt,
  }) {
    return ProductConversationOverlay(
      ownerDid: ownerDid,
      threadId: threadId,
      pinned: pinned ?? this.pinned,
      muted: muted ?? this.muted,
      hidden: hidden ?? this.hidden,
      customTitle: customTitle ?? this.customTitle,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
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
