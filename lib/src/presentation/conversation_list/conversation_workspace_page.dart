import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conversation_summary.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../chat/chat_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/compact_nested_navigator_back_scope.dart';
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

class ConversationWorkspacePage extends ConsumerStatefulWidget {
  const ConversationWorkspacePage({super.key, this.listFooter});

  final Widget? listFooter;

  @override
  ConsumerState<ConversationWorkspacePage> createState() =>
      _ConversationWorkspacePageState();
}

class _ConversationWorkspacePageState
    extends ConsumerState<ConversationWorkspacePage> {
  final GlobalKey<NavigatorState> _compactNavigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final selectedConversation = _selectedConversation(
      ref.watch(selectedConversationProvider),
      ref.watch(conversationListProvider).conversations,
    );
    if (!responsive.supportsTwoPane) {
      final active =
          !AwikiShellNavigationScope.isPresent(context) ||
          ref.watch(shellDestinationProvider) == ShellDestination.messages;
      return CompactNestedNavigatorBackScope(
        key: const Key('conversation-compact-back-scope'),
        active: active,
        hasNestedRoute: selectedConversation != null,
        navigatorKey: _compactNavigatorKey,
        onMissingNestedRoute: () {
          ref.read(selectedConversationProvider.notifier).clearSelection();
        },
        child: Navigator(
          key: _compactNavigatorKey,
          pages: <Page<void>>[
            CupertinoPage<void>(
              key: const ValueKey<String>('conversation-directory'),
              child: ConversationListPage(
                selectedConversationId: selectedConversation?.conversationId,
                onConversationSelected: (conversation) async {
                  ref
                      .read(selectedConversationProvider.notifier)
                      .selectConversation(conversation);
                },
              ),
            ),
            if (selectedConversation != null)
              CupertinoPage<void>(
                key: ValueKey<String>(
                  'conversation-chat:${selectedConversation.conversationId}',
                ),
                child: ChatPage(conversation: selectedConversation),
              ),
          ],
          onDidRemovePage: (page) {
            if (page.key != const ValueKey<String>('conversation-directory')) {
              ref.read(selectedConversationProvider.notifier).clearSelection();
            }
          },
        ),
      );
    }

    if (responsive.usesDesktopLayout) {
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
      footer: widget.listFooter,
      sidebar: ConversationListPage(
        embedded: true,
        selectedConversationId: selectedConversation?.conversationId,
        bottomInset: widget.listFooter == null ? 24 : 16,
        onConversationSelected: (conversation) async {
          ref
              .read(selectedConversationProvider.notifier)
              .selectConversation(conversation);
        },
      ),
      detailPane: selectedConversation == null
          ? const AwikiWorkspaceEmptyDetail()
          : ChatView(
              key: ValueKey('chat-view:${selectedConversation.conversationId}'),
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

ConversationSummary? _selectedConversation(
  String? selectedConversationId,
  List<ConversationSummary> conversations,
) {
  final selected = selectedConversationId?.trim();
  if (selected == null || selected.isEmpty) {
    return null;
  }
  for (final conversation in conversations) {
    if (conversation.conversationId == selected) {
      return conversation;
    }
  }
  return null;
}
