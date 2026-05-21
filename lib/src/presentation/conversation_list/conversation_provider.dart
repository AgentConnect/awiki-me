import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/services/notification_facade.dart';

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
    state = state.copyWith(isLoading: true);
    final conversations = await ref
        .read(awikiGatewayProvider)
        .listConversations();
    state = state.copyWith(conversations: conversations, isLoading: false);
    await _notification.updateBadgeCount(state.unreadCount);
  }

  void upsertConversation(ConversationSummary conversation) {
    final byThread = <String, ConversationSummary>{
      for (final item in state.conversations) item.threadId: item,
    };
    byThread[conversation.threadId] = conversation;
    final merged = byThread.values.toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    state = state.copyWith(conversations: merged);
    _notification.updateBadgeCount(state.unreadCount);
  }

  void applyGroupNames(List<GroupSummary> groups) {
    final groupNamesById = <String, String>{
      for (final group in groups)
        if (!GroupDisplayName.isIdLike(group.name, group.groupId))
          group.groupId: group.name,
    };
    if (groupNamesById.isEmpty || state.conversations.isEmpty) {
      return;
    }

    var changed = false;
    final next = state.conversations.map((conversation) {
      final groupId = conversation.groupId?.trim() ?? '';
      final groupName = groupNamesById[groupId];
      if (!conversation.isGroup ||
          groupName == null ||
          groupName == conversation.displayName) {
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
        avatarSeed: conversation.avatarSeed,
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
        avatarSeed: item.avatarSeed,
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

final conversationListProvider =
    StateNotifierProvider<ConversationListController, ConversationListState>(
      (ref) => ConversationListController(ref),
    );
