import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/services/notification_facade.dart';

class ConversationListState {
  const ConversationListState({
    this.conversations = const <ConversationSummary>[],
    this.isLoading = false,
  });

  final List<ConversationSummary> conversations;
  final bool isLoading;

  int get unreadCount => conversations.fold<int>(
        0,
        (sum, item) => sum + item.unreadCount,
      );

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
    final conversations =
        await ref.read(awikiGatewayProvider).listConversations();
    state = state.copyWith(
      conversations: conversations,
      isLoading: false,
    );
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

  Future<void> clear() async {
    state = const ConversationListState();
    await _notification.updateBadgeCount(0);
  }
}

final conversationListProvider =
    StateNotifierProvider<ConversationListController, ConversationListState>(
  (ref) => ConversationListController(ref),
);
