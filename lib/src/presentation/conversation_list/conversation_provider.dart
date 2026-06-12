import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../core/group_display_name.dart';
import '../../domain/entities/agent/agent_display_name.dart';
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
    final existing = _matchingConversationForUpsert(
      state.conversations,
      conversation,
    );
    final mergedConversation = _mergeConversationTitle(
      refreshed: conversation,
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
      return conversation.copyWith(
        displayName: groupName,
        avatarUri: groupAvatarUri ?? conversation.avatarUri,
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
    return _mergeConversationTitle(
      refreshed: conversation,
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
    if (!item.isGroup && _sameDirectConversationTarget(item, incoming)) {
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
    avatarUri: refreshed.avatarUri ?? local.avatarUri,
    avatarSeed: refreshed.avatarSeed ?? local.avatarSeed,
    lastMessagePayloadJson: refreshed.lastMessagePayloadJson,
  );
}

ConversationSummary _mergeDirectConversationTitle({
  required ConversationSummary refreshed,
  required ConversationSummary local,
}) {
  if (local.isGroup || !_sameDirectConversationTarget(local, refreshed)) {
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

bool _sameDirectConversationTarget(
  ConversationSummary first,
  ConversationSummary second,
) {
  final firstDid = first.targetDid?.trim();
  final secondDid = second.targetDid?.trim();
  if (firstDid != null &&
      firstDid.isNotEmpty &&
      secondDid != null &&
      secondDid.isNotEmpty &&
      firstDid == secondDid) {
    return true;
  }
  final firstPeer = _normalizedDirectPeer(first.targetPeer);
  final secondPeer = _normalizedDirectPeer(second.targetPeer);
  if (firstPeer != null && secondPeer != null) {
    return firstPeer == secondPeer;
  }
  return false;
}

String? _normalizedDirectPeer(String? value) {
  final peer = value?.trim();
  if (peer == null || peer.isEmpty) {
    return null;
  }
  return peer.startsWith('did:') ? peer : peer.toLowerCase();
}

final conversationListProvider =
    StateNotifierProvider<ConversationListController, ConversationListState>(
      (ref) => ConversationListController(ref),
    );
