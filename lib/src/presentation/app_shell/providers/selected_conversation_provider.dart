import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation_summary.dart';

class SelectedConversationController extends StateNotifier<String?> {
  SelectedConversationController() : super(null);

  void selectConversation(ConversationSummary conversation) {
    selectConversationId(conversation.conversationId);
  }

  void selectConversationId(String conversationId) {
    final normalized = conversationId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'must not be empty',
      );
    }
    state = normalized;
  }

  void clearSelection() {
    state = null;
  }
}

final selectedConversationProvider =
    StateNotifierProvider<SelectedConversationController, String?>(
      (ref) => SelectedConversationController(),
    );
