import '../../domain/entities/conversation_summary.dart';

class ConversationDraftSortState {
  const ConversationDraftSortState({this.updatedAt});

  final DateTime? updatedAt;
}

typedef ConversationDraftSortLookup =
    ConversationDraftSortState? Function(ConversationSummary conversation);

typedef ConversationPinnedSortLookup =
    bool Function(ConversationSummary conversation);

List<ConversationSummary> sortConversationsForPresentation(
  Iterable<ConversationSummary> conversations, {
  ConversationDraftSortLookup? draftFor,
  ConversationPinnedSortLookup? isPinned,
}) {
  final ordered = conversations.toList(growable: false);
  ordered.sort(
    (a, b) => compareConversationsForPresentation(
      a,
      b,
      draftFor: draftFor,
      isPinned: isPinned,
    ),
  );
  return ordered;
}

void sortConversationListForPresentation(
  List<ConversationSummary> conversations, {
  ConversationDraftSortLookup? draftFor,
  ConversationPinnedSortLookup? isPinned,
}) {
  conversations.sort(
    (a, b) => compareConversationsForPresentation(
      a,
      b,
      draftFor: draftFor,
      isPinned: isPinned,
    ),
  );
}

int compareConversationsForPresentation(
  ConversationSummary a,
  ConversationSummary b, {
  ConversationDraftSortLookup? draftFor,
  ConversationPinnedSortLookup? isPinned,
}) {
  final aDraft = draftFor?.call(a);
  final bDraft = draftFor?.call(b);
  final priority =
      _conversationSortPriority(
        a,
        draft: aDraft,
        pinned: isPinned?.call(a) ?? false,
      ).compareTo(
        _conversationSortPriority(
          b,
          draft: bDraft,
          pinned: isPinned?.call(b) ?? false,
        ),
      );
  if (priority != 0) {
    return priority;
  }

  final aActivity = _conversationSortActivity(a, draft: aDraft);
  final bActivity = _conversationSortActivity(b, draft: bDraft);
  final activity = bActivity.compareTo(aActivity);
  if (activity != 0) {
    return activity;
  }

  final key = _conversationStableSortKey(
    a,
  ).compareTo(_conversationStableSortKey(b));
  if (key != 0) {
    return key;
  }
  return a.threadId.compareTo(b.threadId);
}

int _conversationSortPriority(
  ConversationSummary conversation, {
  required ConversationDraftSortState? draft,
  required bool pinned,
}) {
  if (pinned) {
    return 0;
  }
  if (conversation.unreadMentionCount > 0) {
    return 1;
  }
  if (conversation.unreadCount > 0) {
    return 2;
  }
  if (draft != null) {
    return 3;
  }
  return 4;
}

DateTime _conversationSortActivity(
  ConversationSummary conversation, {
  required ConversationDraftSortState? draft,
}) {
  if (draft == null ||
      conversation.unreadCount > 0 ||
      conversation.unreadMentionCount > 0) {
    return conversation.lastMessageAt;
  }
  final draftUpdatedAt = draft.updatedAt;
  if (draftUpdatedAt == null) {
    return conversation.lastMessageAt;
  }
  return draftUpdatedAt.isAfter(conversation.lastMessageAt)
      ? draftUpdatedAt
      : conversation.lastMessageAt;
}

String _conversationStableSortKey(ConversationSummary conversation) {
  final visibilityKey = conversation.visibilityKey.trim();
  if (visibilityKey.isNotEmpty) {
    return visibilityKey;
  }
  return conversation.threadId.trim();
}
