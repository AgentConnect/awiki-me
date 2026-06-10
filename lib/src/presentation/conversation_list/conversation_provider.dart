import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/services/notification_facade.dart';
import '../app_shell/providers/session_provider.dart';

class ConversationListState {
  const ConversationListState({
    this.conversations = const <ConversationSummary>[],
    this.isLoading = false,
  });

  final List<ConversationSummary> conversations;
  final bool isLoading;

  int get unreadCount =>
      conversations.fold<int>(0, (sum, item) => sum + item.unreadCount);

  ConversationListState copyWith({
    List<ConversationSummary>? conversations,
    bool? isLoading,
  }) {
    return ConversationListState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ConversationListController extends StateNotifier<ConversationListState> {
  ConversationListController(this.ref) : super(const ConversationListState());

  final Ref ref;

  NotificationFacade get _notification => ref.read(notificationFacadeProvider);

  Future<void> refresh() async {
    final previousConversations = state.conversations;
    state = state.copyWith(isLoading: true);
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      state = state.copyWith(
        conversations: const <ConversationSummary>[],
        isLoading: false,
      );
      await _notification.updateBadgeCount(0);
      return;
    }
    final conversations = await ref
        .read(conversationServiceProvider)
        .listConversations(ownerDid: session.did);
    state = state.copyWith(
      conversations: _mergeConversationRefresh(
        refreshed: conversations,
        local: previousConversations,
      ),
      isLoading: false,
    );
    await _notification.updateBadgeCount(state.unreadCount);
  }

  void upsertConversation(ConversationSummary conversation) {
    final byThread = <String, ConversationSummary>{
      for (final item in state.conversations) item.threadId: item,
    };
    byThread[conversation.threadId] = _mergeConversationTitle(
      refreshed: conversation,
      local: byThread[conversation.threadId],
    );
    final merged = byThread.values.toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    state = state.copyWith(conversations: merged);
    _notification.updateBadgeCount(state.unreadCount);
  }

  void applyGroupNames(List<GroupSummary> groups) {
    final groupsById = <String, GroupSummary>{
      for (final group in groups)
        if (!GroupDisplayName.isIdLike(group.displayName, group.groupId))
          group.groupId: group,
    };
    if (groupsById.isEmpty || state.conversations.isEmpty) {
      return;
    }

    var changed = false;
    final next = state.conversations.map((conversation) {
      final groupId = conversation.groupId?.trim() ?? '';
      final group = groupsById[groupId];
      final groupName = group?.displayName;
      final groupAvatarUri = group?.avatarUri;
      if (!conversation.isGroup ||
          groupName == null ||
          (groupName == conversation.displayName &&
              groupAvatarUri == conversation.avatarUri)) {
        return conversation;
      }
      changed = true;
      return ConversationSummary(
        threadId: conversation.threadId,
        displayName: groupName,
        lastMessagePreview: conversation.lastMessagePreview,
        lastMessageAt: conversation.lastMessageAt,
        unreadCount: conversation.unreadCount,
        isGroup: conversation.isGroup,
        targetDid: conversation.targetDid,
        groupId: conversation.groupId,
        avatarUri: groupAvatarUri ?? conversation.avatarUri,
        avatarSeed: conversation.avatarSeed,
        lastMessagePayloadJson: conversation.lastMessagePayloadJson,
      );
    }).toList();
    if (!changed) {
      return;
    }
    state = state.copyWith(conversations: next);
  }

  void markThreadReadLocal(String threadId) {
    final next = state.conversations.map((item) {
      if (item.threadId != threadId || item.unreadCount == 0) {
        return item;
      }
      return ConversationSummary(
        threadId: item.threadId,
        displayName: item.displayName,
        lastMessagePreview: item.lastMessagePreview,
        lastMessageAt: item.lastMessageAt,
        unreadCount: 0,
        isGroup: item.isGroup,
        targetDid: item.targetDid,
        groupId: item.groupId,
        avatarUri: item.avatarUri,
        avatarSeed: item.avatarSeed,
        lastMessagePayloadJson: item.lastMessagePayloadJson,
      );
    }).toList();
    state = state.copyWith(conversations: next);
    _notification.updateBadgeCount(state.unreadCount);
  }

  Future<void> clear() async {
    state = const ConversationListState();
    await _notification.updateBadgeCount(0);
  }
}

List<ConversationSummary> _mergeConversationRefresh({
  required List<ConversationSummary> refreshed,
  required List<ConversationSummary> local,
}) {
  final localByThread = <String, ConversationSummary>{
    for (final conversation in local) conversation.threadId: conversation,
  };
  final mergedRefreshed = refreshed
      .map(
        (conversation) => _mergeConversationTitle(
          refreshed: conversation,
          local: localByThread[conversation.threadId],
        ),
      )
      .toList();
  final refreshedThreadIds = <String>{
    for (final conversation in refreshed) conversation.threadId,
  };
  final localOnly = local
      .where(
        (conversation) =>
            !refreshedThreadIds.contains(conversation.threadId) &&
            conversation.lastMessagePreview.trim().isNotEmpty,
      )
      .toList();
  if (localOnly.isEmpty) {
    return mergedRefreshed;
  }
  return <ConversationSummary>[...mergedRefreshed, ...localOnly]
    ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
}

ConversationSummary _mergeConversationTitle({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  if (local == null ||
      !refreshed.isGroup ||
      local.groupId?.trim() != refreshed.groupId?.trim()) {
    return refreshed;
  }
  final groupId = refreshed.groupId?.trim() ?? '';
  final localName = local.displayName.trim();
  final refreshedName = refreshed.displayName.trim();
  if (localName.isEmpty ||
      !GroupDisplayName.isIdLike(refreshedName, groupId) ||
      GroupDisplayName.isIdLike(localName, groupId)) {
    return refreshed;
  }
  return ConversationSummary(
    threadId: refreshed.threadId,
    displayName: local.displayName,
    lastMessagePreview: refreshed.lastMessagePreview,
    lastMessageAt: refreshed.lastMessageAt,
    unreadCount: refreshed.unreadCount,
    isGroup: refreshed.isGroup,
    targetDid: refreshed.targetDid,
    groupId: refreshed.groupId,
    avatarUri: refreshed.avatarUri ?? local.avatarUri,
    avatarSeed: refreshed.avatarSeed ?? local.avatarSeed,
    lastMessagePayloadJson: refreshed.lastMessagePayloadJson,
  );
}

final conversationListProvider =
    StateNotifierProvider<ConversationListController, ConversationListState>(
      (ref) => ConversationListController(ref),
    );
