import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_router.dart';
import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_member_summary.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/user_profile.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../agents/agent_inbox_panel.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../chat/chat_page.dart';
import '../group/group_list_page.dart';
import '../group/group_provider.dart';
import '../profile/peer_profile_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/awiki_me_feedback.dart';
import '../shared/avatar_badge.dart';
import '../shared/copyable_did_line.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/responsive_layout.dart';
import '../shared/sidebar_workspace.dart';
import '../shared/widgets/app_widgets.dart';
import 'conversation_list_page.dart';
import 'conversation_peer_classifier.dart';

part 'parts/conversation_workspace_mac_layout_part.dart';
part 'parts/conversation_workspace_identity_part.dart';
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

    final selectedConversation = ref.watch(selectedConversationProvider);
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
        selectedThreadId: selectedConversation?.threadId,
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
              key: ValueKey('chat-view:${selectedConversation.threadId}'),
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
