import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../shared/responsive_layout.dart';

Future<void> openGroupChat(
  BuildContext context,
  WidgetRef ref,
  GroupSummary group, {
  bool closeCurrentRouteOnDesktop = false,
  bool replaceCurrentRouteOnPhone = false,
}) async {
  final conversation = ConversationSummary(
    threadId: 'group:${group.groupId}',
    displayName: group.name,
    lastMessagePreview: '',
    lastMessageAt: group.lastMessageAt ?? DateTime.now(),
    unreadCount: 0,
    isGroup: true,
    groupId: group.groupId,
    avatarSeed: group.groupId,
  );

  await ref
      .read(conversationListProvider.notifier)
      .restoreConversation(conversation);
  ref.read(conversationListProvider.notifier).upsertConversation(conversation);
  await ref.read(chatThreadsProvider.notifier).openConversation(conversation);
  if (!context.mounted) {
    return;
  }

  if (context.awikiResponsive.supportsTwoPane) {
    ref
        .read(selectedConversationProvider.notifier)
        .selectConversation(conversation);
    ref.read(shellTabProvider.notifier).setTab(0);
    final navigator = Navigator.of(context);
    if (closeCurrentRouteOnDesktop && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    } else if (closeCurrentRouteOnDesktop) {
      await AppNavigator.pushReplacement<void, void>(
        context,
        (_) => ChatPage(conversation: conversation),
      );
    }
    return;
  }

  if (replaceCurrentRouteOnPhone) {
    await AppNavigator.pushReplacement<void, void>(
      context,
      (_) => ChatPage(conversation: conversation),
    );
    return;
  }
  await AppNavigator.push(context, (_) => ChatPage(conversation: conversation));
}
