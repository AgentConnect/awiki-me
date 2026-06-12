import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/group_display_name.dart';
import '../../../domain/entities/conversation_summary.dart';
import '../../../domain/entities/group_summary.dart';

class SelectedConversationController
    extends StateNotifier<ConversationSummary?> {
  SelectedConversationController() : super(null);

  void selectConversation(ConversationSummary conversation) {
    state = conversation;
  }

  void applyGroupNames(List<GroupSummary> groups) {
    final current = state;
    if (current == null || !current.isGroup) {
      return;
    }
    final groupId = current.groupId?.trim() ?? '';
    for (final group in groups) {
      if (group.groupId != groupId ||
          GroupDisplayName.isIdLike(group.displayName, groupId) ||
          (group.displayName == current.displayName &&
              group.avatarUri == current.avatarUri)) {
        continue;
      }
      state = current.copyWith(
        displayName: group.displayName,
        avatarUri: group.avatarUri ?? current.avatarUri,
      );
      return;
    }
  }

  void clearSelection() {
    state = null;
  }
}

final selectedConversationProvider =
    StateNotifierProvider<SelectedConversationController, ConversationSummary?>(
      (ref) => SelectedConversationController(),
    );
