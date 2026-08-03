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

Future<ConversationSummary> prepareGroupChat(
  WidgetRef ref,
  GroupSummary group,
) async {
  final conversation = await ref
      .read(conversationListProvider.notifier)
      .commitConversationId(group.conversationId);
  await ref.read(chatThreadsProvider.notifier).openConversation(conversation);
  return conversation;
}

Future<void> openGroupChat(
  BuildContext context,
  WidgetRef ref,
  GroupSummary group,
) async {
  final conversation = await prepareGroupChat(ref, group);
  if (!context.mounted) {
    return;
  }

  if (!AwikiShellNavigationScope.isPresent(context)) {
    await AppNavigator.push(
      context,
      (_) => ChatPage(conversation: conversation),
    );
    return;
  }

  ref
      .read(selectedConversationProvider.notifier)
      .selectConversation(conversation);
  ref
      .read(shellDestinationProvider.notifier)
      .selectForLayout(
        ShellDestination.messages,
        expanded: context.awikiResponsive.usesDesktopLayout,
      );
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.popUntil((route) => route.isFirst);
  }
}
