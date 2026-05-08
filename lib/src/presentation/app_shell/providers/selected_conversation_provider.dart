import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/conversation_summary.dart';

class SelectedConversationController
    extends StateNotifier<ConversationSummary?> {
  SelectedConversationController() : super(null);

  void selectConversation(ConversationSummary conversation) {
    state = conversation;
  }

  void clearSelection() {
    state = null;
  }
}

final selectedConversationProvider =
    StateNotifierProvider<SelectedConversationController, ConversationSummary?>(
  (ref) => SelectedConversationController(),
);
