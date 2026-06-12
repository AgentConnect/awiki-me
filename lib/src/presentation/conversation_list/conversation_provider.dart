import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/agent/agent_display_name.dart';
import '../../domain/entities/conversation_identity.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/services/notification_facade.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
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
    final existing = _matchingConversationForUpsert(
      state.conversations,
      conversation,
    );
    final mergedConversation = _mergeConversationReadState(
      refreshed: _mergeConversationTitle(
        refreshed: conversation,
        local: existing,
      ),
      local: existing,
    );
    final byThread = <String, ConversationSummary>{
      for (final item in state.conversations)
        if (item.threadId != existing?.threadId) item.threadId: item,
    };
    byThread[mergedConversation.threadId] = mergedConversation;
    final merged = byThread.values.toList()
      ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
    state = state.copyWith(conversations: merged);
    _notification.updateBadgeCount(state.unreadCount);
  }

  Future<void> restoreConversation(ConversationSummary conversation) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      return;
    }
    await ref
        .read(conversationServiceProvider)
        .restoreConversationToRecents(
          ownerDid: session.did,
          conversation: conversation,
        );
  }

  Future<void> deleteFromRecents(ConversationSummary conversation) async {
    final session = ref.read(sessionProvider).session;
    if (session == null) {
      throw StateError('No active awiki session. Please sign in first.');
    }
    await ref
        .read(conversationServiceProvider)
        .hideConversationFromRecents(
          ownerDid: session.did,
          conversation: conversation,
        );
    final next = state.conversations
        .where((item) => !sameConversationTarget(item, conversation))
        .toList(growable: false);
    state = state.copyWith(conversations: next);
    final selected = ref.read(selectedConversationProvider);
    if (selected != null && sameConversationTarget(selected, conversation)) {
      ref.read(selectedConversationProvider.notifier).clearSelection();
    }
    await _notification.updateBadgeCount(state.unreadCount);
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
      return conversation.copyWith(displayName: groupName);
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
      return item.copyWith(unreadCount: 0);
    }).toList();
    state = state.copyWith(conversations: next);
    _notification.updateBadgeCount(state.unreadCount);
  }

  void markConversationReadLocal(ConversationSummary conversation) {
    final next = state.conversations.map((item) {
      if (item.unreadCount == 0 ||
          !sameConversationTarget(item, conversation)) {
        return item;
      }
      return item.copyWith(unreadCount: 0);
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
  final consumedLocalThreadIds = <String>{};
  final mergedRefreshed = refreshed.map((conversation) {
    final matchedLocal = _matchingConversationForUpsert(
      local.where((item) => !consumedLocalThreadIds.contains(item.threadId)),
      conversation,
    );
    if (matchedLocal != null) {
      consumedLocalThreadIds.add(matchedLocal.threadId);
    }
    return _mergeConversationReadState(
      refreshed: _mergeConversationTitle(
        refreshed: conversation,
        local: matchedLocal,
      ),
      local: matchedLocal,
    );
  }).toList();
  final refreshedThreadIds = <String>{
    for (final conversation in refreshed) conversation.threadId,
  };
  final localOnly = local
      .where(
        (conversation) =>
            !consumedLocalThreadIds.contains(conversation.threadId) &&
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

ConversationSummary? _matchingConversationForUpsert(
  Iterable<ConversationSummary> conversations,
  ConversationSummary incoming,
) {
  for (final item in conversations) {
    if (item.threadId == incoming.threadId) {
      return item;
    }
  }
  if (incoming.isGroup) {
    return null;
  }
  for (final item in conversations) {
    if (!item.isGroup && sameDirectConversationTarget(item, incoming)) {
      return item;
    }
  }
  return null;
}

ConversationSummary _mergeConversationTitle({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  if (local == null) {
    return refreshed;
  }
  if (!refreshed.isGroup) {
    return _mergeDirectConversationTitle(refreshed: refreshed, local: local);
  }
  if (local.groupId?.trim() != refreshed.groupId?.trim()) {
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
  return refreshed.copyWith(
    displayName: local.displayName,
    avatarSeed: refreshed.avatarSeed ?? local.avatarSeed,
  );
}

ConversationSummary _mergeConversationReadState({
  required ConversationSummary refreshed,
  required ConversationSummary? local,
}) {
  if (local == null ||
      local.unreadCount != 0 ||
      refreshed.unreadCount == 0 ||
      refreshed.lastMessageAt.isAfter(local.lastMessageAt)) {
    return refreshed;
  }
  return refreshed.copyWith(unreadCount: 0);
}

ConversationSummary _mergeDirectConversationTitle({
  required ConversationSummary refreshed,
  required ConversationSummary local,
}) {
  if (local.isGroup || !sameDirectConversationTarget(local, refreshed)) {
    return refreshed;
  }
  final localName = local.displayName.trim();
  final refreshedName = refreshed.displayName.trim();
  if (localName.isEmpty ||
      localName == refreshedName ||
      !_isBetterDirectConversationTitle(localName, refreshedName)) {
    return refreshed;
  }
  return refreshed.copyWith(
    displayName: local.displayName,
    avatarSeed: refreshed.avatarSeed ?? local.avatarSeed,
    peerLifecycleState: local.peerLifecycleState,
  );
}

bool _isBetterDirectConversationTitle(String localName, String refreshedName) {
  if (refreshedName.isEmpty || refreshedName.startsWith('did:')) {
    return true;
  }
  return AgentDisplayName.isUserVisibleName(localName) &&
      !AgentDisplayName.isUserVisibleName(refreshedName);
}

final conversationListProvider =
    StateNotifierProvider<ConversationListController, ConversationListState>(
      (ref) => ConversationListController(ref),
    );
