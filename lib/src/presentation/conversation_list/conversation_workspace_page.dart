import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conversation_summary.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../chat/chat_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/localized_ui_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import '../shared/widgets/app_widgets.dart';
import 'conversation_list_page.dart';
import 'conversation_peer_classifier.dart';
import 'conversation_provider.dart';

part 'parts/conversation_workspace_mac_layout_part.dart';
part 'parts/conversation_workspace_panel_widgets_part.dart';
part 'parts/conversation_workspace_agent_detail_part.dart';

class ConversationWorkspacePage extends ConsumerWidget {
  const ConversationWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    if (!responsive.supportsTwoPane) {
      return const ConversationListPage();
    }

    final selectedConversation = _effectiveSelectedConversation(
      ref.watch(selectedConversationProvider),
      ref.watch(conversationListProvider).conversations,
    );
    if (responsive.isMacDesktop) {
      return _MacConversationWorkspace(
        selectedConversation: selectedConversation,
        onConversationSelected: (conversation) async {
          ref
              .read(selectedConversationProvider.notifier)
              .selectConversation(conversation);
        },
        onClearSelection: () {
          ref.read(selectedConversationProvider.notifier).clearSelection();
        },
      );
    }
    return AwikiSidebarWorkspace(
      footer: listFooter,
      sidebar: ConversationListPage(
        embedded: true,
        selectedConversationId: selectedConversation?.effectiveConversationId,
        bottomInset: listFooter == null ? 24 : 16,
        onConversationSelected: (conversation) async {
          ref
              .read(selectedConversationProvider.notifier)
              .selectConversation(conversation);
        },
      ),
      detailPane: selectedConversation == null
          ? const AwikiWorkspaceEmptyDetail()
          : ChatView(
              key: ValueKey(
                'chat-view:${selectedConversation.effectiveConversationId}',
              ),
              conversation: selectedConversation,
              embedded: true,
              onBack: () {
                ref
                    .read(selectedConversationProvider.notifier)
                    .clearSelection();
              },
            ),
    );
  }
}

ConversationSummary? _effectiveSelectedConversation(
  ConversationSummary? selected,
  List<ConversationSummary> conversations,
) {
  if (selected == null) {
    return null;
  }
  final selectedConversationId = selected.effectiveConversationId.trim();
  if (selectedConversationId.isEmpty) {
    return selected;
  }
  for (final conversation in conversations) {
    if (conversation.effectiveConversationId.trim() == selectedConversationId) {
      return conversation;
    }
  }
  final selectedThreadId = selected.threadId.trim();
  if (selectedThreadId.isNotEmpty) {
    for (final conversation in conversations) {
      if (conversation.threadId.trim() == selectedThreadId) {
        return conversation;
      }
    }
  }
  for (final conversation in conversations) {
    if (conversation.threadId.trim() == selectedConversationId) {
      return conversation;
    }
  }
  return selected;
}
