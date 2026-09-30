import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show PopupMenuEntry, PopupMenuItem, RelativeRect, showMenu;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:awiki_me/l10n/app_localizations.dart';

import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../core/date_time_formatter.dart';
import '../../core/group_display_name.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/group_system_event.dart';
import '../../domain/entities/group_summary.dart';
import '../../domain/entities/peer_agent_identity.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../agents/agents_provider.dart';
import '../agents/personal_agent_feature_visibility.dart';
import '../agents/agent_status_indicator.dart';
import '../agents/agent_visual_status.dart';
import '../agents/acp_session_provider.dart';
import '../group/group_provider.dart';
import '../devices/device_join_request_notice.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/app_dialog.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/formatters/localized_ui_formatters.dart';
import '../shared/formatters/markdown_preview_formatter.dart';
import '../shared/quick_actions.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../shared/widgets/awiki_glass.dart';
import '../profile/peer_display_profile_provider.dart';
import 'conversation_list_ordering.dart';
import 'conversation_peer_classifier.dart';
import 'conversation_provider.dart';

typedef ConversationSelectionHandler =
    Future<void> Function(ConversationSummary conversation);

class ConversationListPage extends ConsumerStatefulWidget {
  const ConversationListPage({
    super.key,
    this.onConversationSelected,
    this.selectedConversationId,
    this.embedded = false,
    this.bottomInset = 120,
    this.macStyle = false,
  });

  final ConversationSelectionHandler? onConversationSelected;
  final String? selectedConversationId;
  final bool embedded;
  final double bottomInset;
  final bool macStyle;

  @override
  ConsumerState<ConversationListPage> createState() =>
      _ConversationListPageState();
}

class _ConversationListPageState extends ConsumerState<ConversationListPage> {
  bool get _usesEmbeddedSelection => widget.onConversationSelected != null;

  /// Phone search stays folded behind the header icon until opened.
  final ValueNotifier<bool> _searchOpen = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _searchOpen.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(agentsProvider.notifier).ensureLoaded());
    });
  }

  @override
  Widget build(BuildContext context) {
    final buildWatch = Stopwatch()..start();
    final state = ref.watch(conversationListProvider);
    final conversations = personalAgentVisibleConversations(
      conversations: state.conversations,
      agents: ref.watch(agentsProvider.select((state) => state.agents)),
      personalAgentVisible: ref.watch(personalAgentFeatureVisibleProvider),
    );
    final composerDrafts = ref.watch(chatComposerDraftsProvider);
    final responsive = context.awikiResponsive;
    buildWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_list_page.build.prepare',
      elapsed: buildWatch.elapsed,
      fields: <String, Object?>{
        'items': conversations.length,
        'loading': state.isLoading,
        'mac_style': widget.macStyle && responsive.usesDesktopLayout,
      },
      minMs: 1,
      level: AwikiPerformanceLogLevel.verbose,
    );
    Future<void> refreshConversations() async {
      try {
        await ref.read(conversationListProvider.notifier).refresh();
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.fromError(error));
      }
    }

    if (widget.macStyle && responsive.usesDesktopLayout) {
      return _MacConversationList(
        conversations: conversations,
        loadState: state.loadState,
        composerDrafts: composerDrafts,
        selectedConversationId: _selectedConversationKey(
          widget.selectedConversationId,
        ),
        bottomInset: widget.bottomInset,
        onRefresh: refreshConversations,
        onOpen: (item) => _openConversation(context, ref, item),
        onDelete: (item) => _deleteConversationFromRecents(context, ref, item),
        onShowActions: (anchorContext) {
          unawaited(
            showCommonQuickActionsMenu(
              anchorContext,
              ref,
              anchoredToTrigger: true,
            ),
          );
        },
      );
    }
    return AwikiMeShellTabPage(
      title: context.l10n.conversationsTitle,
      quickActionIcon: CupertinoIcons.add_circled,
      secondaryAction: _ConversationSearchToggle(searchOpen: _searchOpen),
      onQuickActionsTap: (anchorContext) => showCommonQuickActionsMenu(
        anchorContext,
        ref,
        anchoredToTrigger: true,
      ),
      child: _ConversationRefreshView(
        conversations: conversations,
        loadState: state.loadState,
        composerDrafts: composerDrafts,
        selectedConversationId: _selectedConversationKey(
          widget.selectedConversationId,
        ),
        embedded: widget.embedded,
        bottomInset: widget.bottomInset,
        searchOpen: _searchOpen,
        onRefresh: refreshConversations,
        onOpen: (item) => _openConversation(context, ref, item),
        onDelete: (item) => _deleteConversationFromRecents(context, ref, item),
      ),
    );
  }

  Future<void> _openConversation(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary item,
  ) async {
    ref
        .read(conversationListProvider.notifier)
        .restoreConversationBestEffort(item);
    unawaited(ref.read(chatThreadsProvider.notifier).openConversation(item));
    if (!context.mounted) {
      return;
    }
    if (_usesEmbeddedSelection) {
      await widget.onConversationSelected?.call(item);
      return;
    }
    await AppNavigator.push(context, (_) => ChatPage(conversation: item));
  }

  Future<void> _deleteConversationFromRecents(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary item,
  ) async {
    final confirmed = await AppNavigator.showDialog<bool>(
      context,
      (dialogContext) => _ConversationDeleteDialog(
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await ref.read(conversationListProvider.notifier).deleteFromRecents(item);
      ref
          .read(uiFeedbackProvider.notifier)
          .showInfo(AppMessage.conversationRemovedFromRecents());
    } catch (error) {
      if (isSessionEpochChangedError(error)) {
        return;
      }
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }
}

class _MacConversationList extends ConsumerStatefulWidget {
  const _MacConversationList({
    required this.conversations,
    required this.loadState,
    required this.composerDrafts,
    required this.selectedConversationId,
    required this.bottomInset,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
    required this.onShowActions,
  });

  final List<ConversationSummary> conversations;
  final ConversationListLoadState loadState;
  final Map<String, ChatComposerDraft> composerDrafts;
  final String? selectedConversationId;
  final double bottomInset;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onDelete;
  final ValueChanged<BuildContext> onShowActions;

  @override
  ConsumerState<_MacConversationList> createState() =>
      _MacConversationListState();
}

class _MacConversationListState extends ConsumerState<_MacConversationList> {
  String _query = '';
  _ConversationFilter _filter = _ConversationFilter.all;

  @override
  void didUpdateWidget(covariant _MacConversationList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_query.isNotEmpty &&
        widget.conversations.isEmpty &&
        oldWidget.conversations.isNotEmpty) {
      _query = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final buildWatch = Stopwatch()..start();
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final visibleConversations = _filterConversations(context);
    final hasQuery = _query.trim().isNotEmpty;
    buildWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_list_page.mac_build.prepare',
      elapsed: buildWatch.elapsed,
      fields: <String, Object?>{
        'items': widget.conversations.length,
        'visible': visibleConversations.length,
        'query': hasQuery,
      },
      minMs: 1,
      level: AwikiPerformanceLogLevel.verbose,
    );
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Reference `.col-head`: a borderless soft search pill and a
          // square soft "+" sharing one 30-unit row.
          Padding(
            padding: EdgeInsets.fromLTRB(
              responsive.displayScaled(14),
              responsive.displayScaled(12),
              responsive.displayScaled(12),
              responsive.displayScaled(4),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: responsive.displayScaled(30),
                    child: CupertinoSearchTextField(
                      key: const Key('conversation-search-field'),
                      placeholder: context.l10n.conversationsSearchPlaceholder,
                      onChanged: (value) {
                        setState(() {
                          _query = value;
                        });
                      },
                      style: TextStyle(fontSize: 13, color: theme.title),
                      placeholderStyle: TextStyle(
                        fontSize: 13,
                        color: theme.secondaryText,
                      ),
                      prefixIcon: Icon(
                        CupertinoIcons.search,
                        color: theme.secondaryText,
                        size: responsive.displayScaled(15),
                      ),
                      prefixInsets: EdgeInsetsDirectional.only(
                        start: responsive.displayScaled(9),
                      ),
                      suffixIcon: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: theme.tertiaryText,
                        size: responsive.displayScaled(14),
                      ),
                      decoration: BoxDecoration(
                        color: theme.title.withValues(
                          alpha: theme.isDark ? 0.10 : 0.065,
                        ),
                        borderRadius: BorderRadius.circular(
                          responsive.displayScaled(6),
                        ),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: responsive.displayScaled(6),
                        vertical: responsive.displayScaled(6),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: responsive.displayScaled(8)),
                Builder(
                  builder: (anchorContext) => _MacListIconButton(
                    key: const Key('conversation-quick-actions-button'),
                    semanticLabel: context.l10n.commonMoreActions,
                    icon: CupertinoIcons.plus,
                    onTap: () => widget.onShowActions(anchorContext),
                  ),
                ),
              ],
            ),
          ),
          if (ref.watch(pendingJoinRequestProvider) case final request?)
            Padding(
              key: const Key('conversation-list-join-notice'),
              padding: EdgeInsets.fromLTRB(
                responsive.displayScaled(12),
                responsive.displayScaled(8),
                responsive.displayScaled(12),
                0,
              ),
              child: DeviceJoinRequestNoticeCard(
                request: request,
                onReview: () => reviewDeviceJoinRequest(context, ref, request),
              ),
            ),
          _ConversationFilterBar(
            value: _filter,
            onChanged: (value) => setState(() => _filter = value),
          ),
          Expanded(
            child: CustomScrollView(
              slivers: <Widget>[
                CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
                if (widget.conversations.isEmpty &&
                    widget.loadState == ConversationListLoadState.error)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _ConversationLoadErrorState(
                      onRetry: widget.onRefresh,
                    ),
                  )
                else if (widget.conversations.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MacConversationEmptyState(
                      title: context.l10n.conversationsEmptyTitle,
                      subtitle: context.l10n.conversationsEmptySubtitle,
                    ),
                  )
                else if (visibleConversations.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MacConversationEmptyState(
                      title: context.l10n.conversationsNoResultsTitle,
                      subtitle: hasQuery
                          ? context.l10n.conversationsNoResultsSubtitle
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      responsive.displayScaled(6),
                      responsive.displayScaled(2),
                      responsive.displayScaled(6),
                      responsive.displayScaled(widget.bottomInset),
                    ),
                    sliver: SliverList.builder(
                      itemCount: visibleConversations.length,
                      itemBuilder: (context, index) {
                        final item = visibleConversations[index];
                        final classification = _conversationPeerClassification(
                          ref,
                          item,
                        );
                        final agentStatus = _conversationAgentStatus(
                          ref,
                          item,
                          classification,
                        );
                        final preview = _conversationPreviewPresentation(
                          ref,
                          context.l10n,
                          item,
                          widget.composerDrafts,
                        );
                        return _MacConversationRow(
                          key: Key('conversation-row:${item.conversationId}'),
                          conversationId: item.conversationId,
                          title: _conversationPresentationTitle(
                            ref,
                            item,
                            context.l10n,
                          ),
                          avatarUri: _conversationPresentationAvatarUri(
                            ref,
                            item,
                          ),
                          preview: preview,
                          unreadCount: item.unreadCount,
                          timeLabel: item.lastMessagePreview.trim().isEmpty
                              ? ''
                              : DateTimeFormatter.conversationTime(
                                  item.lastMessageAt,
                                ),
                          isDeletedAgentConversation:
                              item.isDeletedAgentConversation,
                          classification: classification,
                          agentStatus: agentStatus,
                          isSelected: _isSelectedConversation(
                            item,
                            selectedConversationId:
                                widget.selectedConversationId,
                          ),
                          onTap: () => widget.onOpen(item),
                          onDelete: () => widget.onDelete(item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<ConversationSummary> _filterConversations(BuildContext context) {
    final query = _normalizedConversationSearchText(_query);
    final conversations = query.isEmpty
        ? widget.conversations
        : widget.conversations.where((conversation) {
            return _conversationSearchText(
              ref,
              context,
              conversation,
            ).contains(query);
          });
    return sortConversationsForPresentation(
      conversations.where(
        (conversation) => switch (_filter) {
          _ConversationFilter.all => true,
          _ConversationFilter.unread => conversation.unreadCount > 0,
          _ConversationFilter.agent => _conversationPeerClassification(
            ref,
            conversation,
          ).isAgent,
          _ConversationFilter.group => conversation.isGroup,
        },
      ),
      draftFor: (conversation) =>
          _draftSortStateForConversation(conversation, widget.composerDrafts),
    );
  }
}

enum _ConversationFilter { all, unread, agent, group }

class _ConversationFilterBar extends StatelessWidget {
  const _ConversationFilterBar({required this.value, required this.onChanged});

  final _ConversationFilter value;
  final ValueChanged<_ConversationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    if (context.awikiResponsive.isPhone) {
      return _PhoneConversationFilterTrack(value: value, onChanged: onChanged);
    }
    // The filter strip scrolls only when it overflows; it never shows a bar.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Row(
          children: <Widget>[
            for (final filter in _ConversationFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: AppPressable(
                  key: Key('conversation-filter-${filter.name}'),
                  semanticLabel: _conversationFilterLabel(context, filter),
                  selected: filter == value,
                  onTap: () => onChanged(filter),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 26,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: filter == value
                          ? theme.title.withValues(
                              alpha: theme.isDark ? 0.10 : 0.065,
                            )
                          : CupertinoColors.transparent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      _conversationFilterLabel(context, filter),
                      style: TextStyle(
                        fontSize: 13,
                        color: filter == value
                            ? theme.title
                            : theme.secondaryText,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Phone filters: one fitted glass track whose chosen segment is a flat
/// lens, as in the reference.
class _PhoneConversationFilterTrack extends StatelessWidget {
  const _PhoneConversationFilterTrack({
    required this.value,
    required this.onChanged,
  });

  final _ConversationFilter value;
  final ValueChanged<_ConversationFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        // Mirrors the desktop strip: overflow scrolls without a bar.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: AwikiGlassSurface(
              key: const Key('conversation-filter-track'),
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.all(3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final filter in _ConversationFilter.values) ...<Widget>[
                    if (filter != _ConversationFilter.values.first)
                      const SizedBox(width: 2),
                    AppPressable(
                      key: Key('conversation-filter-${filter.name}'),
                      semanticLabel: _conversationFilterLabel(context, filter),
                      selected: filter == value,
                      onTap: () => onChanged(filter),
                      borderRadius: BorderRadius.circular(15),
                      child: AnimatedContainer(
                        key: Key('conversation-filter-chip-${filter.name}'),
                        duration: const Duration(milliseconds: 150),
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: filter == value
                              ? theme.glassLens
                              : theme.glassLens.withValues(alpha: 0),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: filter == value
                                ? theme.glassEdgeActive
                                : theme.glassEdgeActive.withValues(alpha: 0),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          _conversationFilterLabel(context, filter),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            color: filter == value
                                ? theme.title
                                : theme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _conversationFilterLabel(
  BuildContext context,
  _ConversationFilter filter,
) => switch (filter) {
  _ConversationFilter.all => context.l10n.friendsTabAll,
  _ConversationFilter.unread => context.l10n.conversationsFilterUnread,
  _ConversationFilter.agent => context.l10n.shellNavAgents,
  _ConversationFilter.group => context.l10n.friendsTabGroups,
};

String? _selectedConversationKey(String? value) {
  final key = value?.trim();
  return key == null || key.isEmpty ? null : key;
}

bool _isSelectedConversation(
  ConversationSummary item, {
  required String? selectedConversationId,
}) {
  final itemConversationId = item.conversationId.trim();
  return selectedConversationId != null &&
      itemConversationId.isNotEmpty &&
      itemConversationId == selectedConversationId;
}

ConversationDraftSortState? _draftSortStateForConversation(
  ConversationSummary conversation,
  Map<String, ChatComposerDraft> drafts,
) {
  final draft = _draftForConversation(conversation, drafts);
  if (draft.isEmpty) {
    return null;
  }
  return ConversationDraftSortState(updatedAt: draft.updatedAt);
}

class _ConversationRefreshView extends ConsumerStatefulWidget {
  const _ConversationRefreshView({
    required this.conversations,
    required this.loadState,
    required this.composerDrafts,
    required this.selectedConversationId,
    required this.embedded,
    required this.bottomInset,
    required this.searchOpen,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
  });

  final List<ConversationSummary> conversations;
  final ConversationListLoadState loadState;
  final Map<String, ChatComposerDraft> composerDrafts;
  final String? selectedConversationId;
  final bool embedded;
  final double bottomInset;

  /// Whether the phone search row is shown; toggled from the header.
  final ValueNotifier<bool> searchOpen;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onDelete;

  @override
  ConsumerState<_ConversationRefreshView> createState() =>
      _ConversationRefreshViewState();
}

class _ConversationRefreshViewState
    extends ConsumerState<_ConversationRefreshView> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  _ConversationFilter _filter = _ConversationFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    widget.searchOpen.addListener(_onSearchOpenChanged);
    _searchFocus.addListener(_onSearchFocusChanged);
  }

  void _onSearchOpenChanged() {
    if (!mounted) {
      return;
    }
    if (widget.searchOpen.value) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.searchOpen.value) {
          _searchFocus.requestFocus();
        }
      });
      return;
    }
    // Folding the field away also drops the query, as in the reference.
    _searchFocus.unfocus();
    setState(() {
      _query = '';
      _searchController.clear();
    });
  }

  void _onSearchFocusChanged() {
    if (!_searchFocus.hasFocus &&
        _searchController.text.trim().isEmpty &&
        widget.searchOpen.value) {
      widget.searchOpen.value = false;
    }
  }

  @override
  void didUpdateWidget(covariant _ConversationRefreshView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_query.isNotEmpty &&
        widget.conversations.isEmpty &&
        oldWidget.conversations.isNotEmpty) {
      _query = '';
      _searchController.clear();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only phones fold the search behind the header icon.
    if (!context.awikiResponsive.isPhone && widget.searchOpen.value) {
      widget.searchOpen.value = false;
    }
  }

  @override
  void dispose() {
    widget.searchOpen.removeListener(_onSearchOpenChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buildWatch = Stopwatch()..start();
    final visibleConversations = _filterConversations(context);
    final hasQuery = _query.trim().isNotEmpty;
    buildWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_list_page.compact_build.prepare',
      elapsed: buildWatch.elapsed,
      fields: <String, Object?>{
        'items': widget.conversations.length,
        'visible': visibleConversations.length,
        'query': hasQuery,
        'embedded': widget.embedded,
      },
      minMs: 1,
      level: AwikiPerformanceLogLevel.verbose,
    );
    return _ConversationSearchableRefreshView(
      filterControls: _ConversationFilterBar(
        value: _filter,
        onChanged: (value) => setState(() => _filter = value),
      ),
      conversations: widget.conversations,
      loadState: widget.loadState,
      visibleConversations: visibleConversations,
      composerDrafts: widget.composerDrafts,
      selectedConversationId: widget.selectedConversationId,
      embedded: widget.embedded,
      bottomInset: widget.bottomInset,
      hasQuery: hasQuery,
      searchController: _searchController,
      searchFocus: _searchFocus,
      showSearch: !context.awikiResponsive.isPhone || widget.searchOpen.value,
      onSearchEscape: () => widget.searchOpen.value = false,
      onQueryChanged: (value) {
        setState(() {
          _query = value;
        });
      },
      onRefresh: widget.onRefresh,
      onOpen: widget.onOpen,
      onDelete: widget.onDelete,
    );
  }

  List<ConversationSummary> _filterConversations(BuildContext context) {
    final query = _normalizedConversationSearchText(_query);
    final conversations = query.isEmpty
        ? widget.conversations
        : widget.conversations.where((conversation) {
            return _conversationSearchText(
              ref,
              context,
              conversation,
            ).contains(query);
          });
    return sortConversationsForPresentation(
      conversations.where(
        (conversation) => switch (_filter) {
          _ConversationFilter.all => true,
          _ConversationFilter.unread => conversation.unreadCount > 0,
          _ConversationFilter.agent => _conversationPeerClassification(
            ref,
            conversation,
          ).isAgent,
          _ConversationFilter.group => conversation.isGroup,
        },
      ),
      draftFor: (conversation) =>
          _draftSortStateForConversation(conversation, widget.composerDrafts),
    );
  }
}

class _ConversationSearchableRefreshView extends ConsumerWidget {
  const _ConversationSearchableRefreshView({
    required this.filterControls,
    required this.conversations,
    required this.loadState,
    required this.visibleConversations,
    required this.composerDrafts,
    required this.selectedConversationId,
    required this.embedded,
    required this.bottomInset,
    required this.hasQuery,
    required this.searchController,
    required this.searchFocus,
    required this.showSearch,
    required this.onSearchEscape,
    required this.onQueryChanged,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
  });

  final Widget filterControls;
  final List<ConversationSummary> conversations;
  final ConversationListLoadState loadState;
  final List<ConversationSummary> visibleConversations;
  final Map<String, ChatComposerDraft> composerDrafts;
  final String? selectedConversationId;
  final bool embedded;
  final double bottomInset;
  final bool hasQuery;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final bool showSearch;
  final VoidCallback onSearchEscape;
  final ValueChanged<String> onQueryChanged;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    return CustomScrollView(
      slivers: <Widget>[
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        if (showSearch)
          SliverToBoxAdapter(
            child: _CompactConversationSearchField(
              controller: searchController,
              focusNode: searchFocus,
              onChanged: onQueryChanged,
              onEscape: onSearchEscape,
            ),
          ),
        if (responsive.isPhone && ref.watch(pendingJoinRequestProvider) != null)
          SliverToBoxAdapter(
            child: Padding(
              key: const Key('conversation-list-join-notice'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: DeviceJoinRequestNoticeCard(
                request: ref.watch(pendingJoinRequestProvider)!,
                onReview: () => reviewDeviceJoinRequest(
                  context,
                  ref,
                  ref.read(pendingJoinRequestProvider)!,
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(child: filterControls),
        if (conversations.isEmpty &&
            loadState == ConversationListLoadState.error)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ConversationLoadErrorState(onRetry: onRefresh),
          )
        else if (conversations.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              embedded: embedded,
              title: context.l10n.conversationsEmptyTitle,
              subtitle: context.l10n.conversationsEmptySubtitle,
            ),
          )
        else if (visibleConversations.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              embedded: embedded,
              title: context.l10n.conversationsNoResultsTitle,
              subtitle: hasQuery
                  ? context.l10n.conversationsNoResultsSubtitle
                  : '',
            ),
          )
        else
          SliverPadding(
            padding: responsive.isPhone
                ? EdgeInsets.fromLTRB(
                    6,
                    0,
                    6,
                    bottomInset + AwikiFloatingTabBarInset.of(context),
                  )
                : EdgeInsets.only(bottom: bottomInset),
            sliver: SliverList.builder(
              itemCount: visibleConversations.length,
              itemBuilder: (_, index) {
                final item = visibleConversations[index];
                final classification = _conversationPeerClassification(
                  ref,
                  item,
                );
                final agentStatus = _conversationAgentStatus(
                  ref,
                  item,
                  classification,
                );
                final preview = _conversationPreviewPresentation(
                  ref,
                  context.l10n,
                  item,
                  composerDrafts,
                );
                final row = _ConversationRow(
                  conversationId: item.conversationId,
                  title: _conversationPresentationTitle(
                    ref,
                    item,
                    context.l10n,
                  ),
                  avatarUri: _conversationPresentationAvatarUri(ref, item),
                  preview: preview,
                  unreadCount: item.unreadCount,
                  timeLabel: item.lastMessagePreview.trim().isEmpty
                      ? ''
                      : DateTimeFormatter.conversationTime(item.lastMessageAt),
                  isDeletedAgentConversation: item.isDeletedAgentConversation,
                  classification: classification,
                  agentStatus: agentStatus,
                  isSelected: _isSelectedConversation(
                    item,
                    selectedConversationId: selectedConversationId,
                  ),
                  onTap: () => onOpen(item),
                  onLongPress: () => onDelete(item),
                );
                if (!responsive.isCompact) {
                  return KeyedSubtree(
                    key: Key('conversation-row:${item.conversationId}'),
                    child: row,
                  );
                }
                return _SwipeToDeleteConversationRow(
                  key: Key('conversation-row:${item.conversationId}'),
                  conversationId: item.conversationId,
                  title: _conversationPresentationTitle(
                    ref,
                    item,
                    context.l10n,
                  ),
                  onDelete: () => onDelete(item),
                  child: row,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ConversationDeleteDialog extends StatelessWidget {
  const _ConversationDeleteDialog({
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return AppConfirmationDialog(
      title: context.l10n.conversationsDeleteTitle,
      message: context.l10n.conversationsDeleteContent,
      confirmLabel: context.l10n.commonDelete,
      destructive: true,
      onCancel: onCancel,
      onConfirm: onConfirm,
    );
  }
}

class _SwipeToDeleteConversationRow extends StatefulWidget {
  const _SwipeToDeleteConversationRow({
    super.key,
    required this.conversationId,
    required this.title,
    required this.onDelete,
    required this.child,
  });

  final String conversationId;
  final String title;
  final VoidCallback onDelete;
  final Widget child;

  @override
  State<_SwipeToDeleteConversationRow> createState() =>
      _SwipeToDeleteConversationRowState();
}

class _SwipeToDeleteConversationRowState
    extends State<_SwipeToDeleteConversationRow> {
  double _dragOffset = 0;
  bool _hasInteracted = false;
  bool _actionVisible = false;

  void _handleDragUpdate(DragUpdateDetails details, double actionExtent) {
    setState(() {
      _hasInteracted = true;
      _actionVisible = true;
      _dragOffset = (_dragOffset + details.delta.dx).clamp(-actionExtent, 0.0);
    });
  }

  void _handleDragEnd(DragEndDetails details, double actionExtent) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen = velocity < -220 || _dragOffset < -actionExtent * 0.45;
    setState(() {
      _actionVisible = shouldOpen;
      _dragOffset = shouldOpen ? -actionExtent : 0;
    });
  }

  void _handleDelete() {
    setState(() {
      _actionVisible = false;
      _dragOffset = 0;
    });
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final actionExtent = responsive.displayScaled(84);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final foreground = !_hasInteracted
        ? widget.child
        : AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_dragOffset, 0, 0),
            child: widget.child,
          );
    return ClipRect(
      child: Stack(
        children: <Widget>[
          if (_actionVisible)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: actionExtent,
                  child: CupertinoButton(
                    key: Key(
                      'conversation-row-delete:${widget.conversationId}',
                    ),
                    padding: EdgeInsets.zero,
                    color: theme.danger,
                    borderRadius: BorderRadius.zero,
                    onPressed: _handleDelete,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          CupertinoIcons.delete,
                          color: context.awikiTheme.surface,
                          size: responsive.displayScaled(20),
                        ),
                        SizedBox(height: responsive.spacing(4)),
                        Text(
                          context.l10n.conversationsSwipeDelete,
                          style: TextStyle(
                            color: context.awikiTheme.surface,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) =>
                _handleDragUpdate(details, actionExtent),
            onHorizontalDragEnd: (details) =>
                _handleDragEnd(details, actionExtent),
            child: foreground,
          ),
        ],
      ),
    );
  }
}

class _CompactConversationSearchField extends StatelessWidget {
  const _CompactConversationSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onEscape,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onEscape;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    if (responsive.isPhone) {
      return Padding(
        key: const Key('compact-conversation-search-surface'),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: SizedBox(
          height: 44,
          child: AwikiGlassSurface(
            borderRadius: BorderRadius.circular(22),
            child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.escape): onEscape,
              },
              child: CupertinoSearchTextField(
                key: const Key('conversation-search-field'),
                controller: controller,
                focusNode: focusNode,
                placeholder: context.l10n.conversationsSearchPlaceholder,
                onChanged: onChanged,
                style: TextStyle(fontSize: 16, color: theme.title),
                placeholderStyle: TextStyle(
                  fontSize: 16,
                  color: theme.secondaryText,
                ),
                prefixIcon: Icon(
                  CupertinoIcons.search,
                  color: theme.secondaryText,
                  size: 17,
                ),
                suffixIcon: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: theme.tertiaryText,
                  size: 17,
                ),
                prefixInsets: const EdgeInsetsDirectional.only(start: 14),
                decoration: const BoxDecoration(),
                padding: const EdgeInsetsDirectional.fromSTEB(8, 10, 12, 10),
              ),
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      key: const Key('compact-conversation-search-surface'),
      decoration: BoxDecoration(color: theme.surface),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          responsive.spacing(16),
          responsive.spacing(8),
          responsive.spacing(16),
          responsive.spacing(12),
        ),
        child: SizedBox(
          height: responsive.displayScaled(52),
          child: CupertinoSearchTextField(
            key: const Key('conversation-search-field'),
            controller: controller,
            focusNode: focusNode,
            placeholder: context.l10n.conversationsSearchPlaceholder,
            onChanged: onChanged,
            style: TextStyle(fontSize: 15, color: theme.title),
            placeholderStyle: TextStyle(
              fontSize: 15,
              color: theme.tertiaryText,
            ),
            prefixIcon: Icon(
              CupertinoIcons.search,
              color: theme.secondaryText,
              size: responsive.iconSm,
            ),
            suffixIcon: Icon(
              CupertinoIcons.xmark_circle_fill,
              color: theme.tertiaryText,
              size: responsive.iconSm,
            ),
            decoration: BoxDecoration(
              color: theme.subtleSurface,
              borderRadius: BorderRadius.circular(responsive.radius(16)),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: responsive.spacing(14),
              vertical: responsive.spacing(12),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bare search glyph beside the phone header's plus button; it folds the
/// search row open and closed.
class _ConversationSearchToggle extends StatelessWidget {
  const _ConversationSearchToggle({required this.searchOpen});

  final ValueNotifier<bool> searchOpen;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: searchOpen,
      builder: (context, open, _) => AppPressable(
        key: const Key('conversation-search-toggle'),
        onTap: () => searchOpen.value = !open,
        semanticLabel: context.l10n.conversationsSearchPlaceholder,
        semanticsIdentifier: 'e2e-conversation-search-toggle',
        tooltip: context.l10n.conversationsSearchPlaceholder,
        button: true,
        selected: open,
        scaleOnPress: true,
        pressedScale: 0.9,
        borderRadius: BorderRadius.circular(18),
        builder: (context, state, child) => SizedBox(
          width: 36,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: open || state.pressed || state.hovered
                    ? theme.title.withValues(alpha: 0.08)
                    : theme.title.withValues(alpha: 0),
              ),
              child: child,
            ),
          ),
        ),
        child: Icon(CupertinoIcons.search, size: 20, color: theme.title),
      ),
    );
  }
}

/// Reference `.icon-btn.sq`: a 30-unit square with a soft fill.
class _MacListIconButton extends StatelessWidget {
  const _MacListIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final soft = theme.title.withValues(alpha: theme.isDark ? 0.10 : 0.065);
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      button: true,
      borderRadius: BorderRadius.circular(responsive.displayScaled(6)),
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: responsive.displayScaled(30),
        height: responsive.displayScaled(30),
        decoration: BoxDecoration(
          color: state.hovered || state.pressed
              ? theme.title.withValues(alpha: theme.isDark ? 0.16 : 0.14)
              : soft,
          borderRadius: BorderRadius.circular(responsive.displayScaled(6)),
        ),
        child: child,
      ),
      child: Icon(icon, color: theme.title, size: responsive.displayScaled(16)),
    );
  }
}

class _MacConversationRow extends StatelessWidget {
  const _MacConversationRow({
    super.key,
    required this.conversationId,
    required this.title,
    required this.avatarUri,
    required this.preview,
    required this.unreadCount,
    required this.timeLabel,
    required this.isDeletedAgentConversation,
    required this.classification,
    required this.agentStatus,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  final String conversationId;
  final String title;
  final String? avatarUri;
  final _ConversationPreviewPresentation preview;
  final int unreadCount;
  final String timeLabel;
  final bool isDeletedAgentConversation;
  final ConversationPeerClassification classification;
  final AgentVisualStatus? agentStatus;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final badgeLabel = localizeConversationCompactBadge(
      context.l10n,
      classification,
    );
    return _ConversationContextMenuRegion(
      onDelete: onDelete,
      child: Padding(
        padding: EdgeInsets.only(bottom: responsive.displayScaled(2)),
        child: AppPressableTile(
          onTap: onTap,
          selected: isSelected,
          semanticLabel: title,
          borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
          backgroundColor: CupertinoColors.transparent,
          selectedBackgroundColor: theme.subtleSurface,
          hoverColor: isSelected
              ? CupertinoColors.transparent
              : theme.subtleSurface.withValues(alpha: 0.65),
          pressedColor: theme.subtleSurface,
          selectedBoxShadow: const <BoxShadow>[],
          hoverBoxShadow: const <BoxShadow>[],
          duration: AwikiMeMotion.instant,
          interactionExitDuration: Duration.zero,
          animateSelection: false,
          border: Border.all(color: CupertinoColors.transparent),
          padding: EdgeInsets.symmetric(
            horizontal: responsive.displayScaled(10),
            vertical: responsive.displayScaled(11),
          ),
          child: Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AvatarBadge(
                    seed: title,
                    size: responsive.displayScaled(40),
                    avatarUri: avatarUri,
                    square: classification.isAgent,
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: responsive.displayScaled(-5),
                      top: responsive.displayScaled(-5),
                      child: _ConversationUnreadBadge(count: unreadCount),
                    ),
                  if (agentStatus != null)
                    Positioned(
                      right: responsive.displayScaled(-1),
                      bottom: responsive.displayScaled(-1),
                      child: AgentStatusDot(
                        status: agentStatus!,
                        size: responsive.displayScaled(8),
                      ),
                    ),
                ],
              ),
              SizedBox(width: responsive.displayScaled(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              Flexible(
                                child: KeyedSubtree(
                                  key: Key(
                                    'conversation-row-title:$conversationId',
                                  ),
                                  child: _ConversationTitleStatusLine(
                                    title: title,
                                    isDeletedAgentConversation:
                                        isDeletedAgentConversation,
                                    compact: true,
                                    titleStyle: TextStyle(
                                      color: theme.title,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                              if (badgeLabel != null) ...<Widget>[
                                const SizedBox(width: 6),
                                _ConversationPeerBadge(
                                  label: badgeLabel,
                                  isGroup: classification.isGroup,
                                  muted: isDeletedAgentConversation,
                                  compact: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        KeyedSubtree(
                          key: const Key('conversation-row-right-meta'),
                          child: Text(
                            timeLabel,
                            maxLines: 1,
                            style: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 11,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: responsive.displayScaled(3)),
                    KeyedSubtree(
                      key: Key('conversation-row-preview:$conversationId'),
                      child: _ConversationPreviewLine(
                        presentation: preview,
                        compact: true,
                        emptyText: context.l10n.conversationsNoMessagePreview,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacConversationEmptyState extends StatelessWidget {
  const _MacConversationEmptyState({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(responsive.displayScaled(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.awikiTheme.secondaryText,
                fontSize: 14,
              ),
            ),
            if (subtitle != null) ...<Widget>[
              SizedBox(height: responsive.displayScaled(6)),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.awikiTheme.tertiaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversationId,
    required this.title,
    required this.avatarUri,
    required this.preview,
    required this.unreadCount,
    required this.timeLabel,
    required this.isDeletedAgentConversation,
    required this.classification,
    required this.agentStatus,
    required this.onTap,
    required this.onLongPress,
    required this.isSelected,
  });

  final String conversationId;
  final String title;
  final String? avatarUri;
  final _ConversationPreviewPresentation preview;
  final int unreadCount;
  final String timeLabel;
  final bool isDeletedAgentConversation;
  final ConversationPeerClassification classification;
  final AgentVisualStatus? agentStatus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final badgeLabel = localizeConversationCompactBadge(
      context.l10n,
      classification,
    );
    final phone = responsive.isPhone;
    return Stack(
      children: <Widget>[
        AppPressableTile(
          onTap: onTap,
          onLongPress: onLongPress,
          selected: isSelected,
          semanticLabel: title,
          borderRadius: phone ? BorderRadius.circular(16) : BorderRadius.zero,
          backgroundColor: phone ? const Color(0x00000000) : theme.surface,
          selectedBackgroundColor: phone
              ? theme.glassLens
              : theme.subtleSurface,
          hoverColor: phone ? theme.glassLens : theme.subtleSurface,
          pressedColor: phone ? theme.glassLens : theme.mutedSurface,
          duration: AwikiMeMotion.instant,
          interactionExitDuration: Duration.zero,
          animateSelection: false,
          padding: phone
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 12)
              : EdgeInsets.symmetric(
                  horizontal: responsive.spacing(16),
                  vertical: responsive.spacing(12),
                ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: responsive.displayScaled(phone ? 44 : 50),
            ),
            child: Row(
              children: <Widget>[
                Stack(
                  key: Key('conversation-row-avatar:$conversationId'),
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    AvatarBadge(
                      seed: title,
                      size: phone ? 40 : responsive.displayScaled(48),
                      avatarUri: avatarUri,
                      square: classification.isAgent,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: responsive.displayScaled(-4),
                        top: responsive.displayScaled(-4),
                        child: _ConversationUnreadBadge(count: unreadCount),
                      ),
                    if (agentStatus != null)
                      Positioned(
                        right: responsive.displayScaled(-1),
                        bottom: responsive.displayScaled(-1),
                        child: AgentStatusDot(
                          status: agentStatus!,
                          size: responsive.displayScaled(9),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: responsive.spacing(12)),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // The kind tag follows the name, as in the reference.
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: KeyedSubtree(
                              key: Key(
                                'conversation-row-title:$conversationId',
                              ),
                              child: _ConversationTitleStatusLine(
                                title: title,
                                isDeletedAgentConversation:
                                    isDeletedAgentConversation,
                                compact: false,
                                titleStyle: TextStyle(
                                  fontSize: phone ? 16 : 15.5,
                                  fontWeight: FontWeight.w400,
                                  color: theme.title,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ),
                          if (badgeLabel != null) ...<Widget>[
                            SizedBox(width: responsive.spacing(5)),
                            _ConversationPeerBadge(
                              label: badgeLabel,
                              isGroup: classification.isGroup,
                              muted: isDeletedAgentConversation,
                              compact: true,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: responsive.spacing(2)),
                      KeyedSubtree(
                        key: Key('conversation-row-preview:$conversationId'),
                        child: _ConversationPreviewLine(
                          presentation: preview,
                          compact: false,
                          emptyText: context.l10n.conversationsNoMessagePreview,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: responsive.spacing(10)),
                SizedBox(
                  width: responsive.displayScaled(38),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      KeyedSubtree(
                        key: const Key('conversation-row-right-meta'),
                        child: Text(
                          timeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: theme.tertiaryText,
                            fontSize: 11.5,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: responsive.spacing(5)),
                      SizedBox(height: responsive.displayScaled(18)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!phone)
          Positioned(
            left: 80,
            right: 0,
            bottom: 0,
            child: SizedBox(
              key: Key('conversation-row-separator:$conversationId'),
              height: 1,
              child: ColoredBox(color: theme.border),
            ),
          ),
      ],
    );
  }
}

class _ConversationContextMenuRegion extends StatefulWidget {
  const _ConversationContextMenuRegion({
    required this.child,
    required this.onDelete,
  });

  final Widget child;
  final VoidCallback onDelete;

  @override
  State<_ConversationContextMenuRegion> createState() =>
      _ConversationContextMenuRegionState();
}

class _ConversationContextMenuRegionState
    extends State<_ConversationContextMenuRegion> {
  Offset? _secondaryTapPosition;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) {
        _secondaryTapPosition = details.globalPosition;
      },
      onSecondaryTap: _showMenu,
      child: widget.child,
    );
  }

  Future<void> _showMenu() async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = _secondaryTapPosition;
    if (overlay == null || position == null) {
      widget.onDelete();
      return;
    }
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'delete',
          child: Text(context.l10n.conversationsDeleteTitle),
        ),
      ],
    );
    if (selected == 'delete') {
      widget.onDelete();
    }
  }
}

String _conversationSearchText(
  WidgetRef ref,
  BuildContext context,
  ConversationSummary conversation,
) {
  return _normalizedConversationSearchText(
    <String>[
      _conversationPresentationTitle(ref, conversation, context.l10n),
      conversation.displayName,
      conversation.lastMessagePreview,
      conversation.targetDid ?? '',
      conversation.groupId ?? '',
      conversation.threadId,
    ].join(' '),
  );
}

String _conversationPresentationTitle(
  WidgetRef ref,
  ConversationSummary conversation,
  AppLocalizations l10n,
) {
  if (conversation.isGroup) {
    final group = _presentationGroup(ref, conversation);
    final groupName = group?.displayName.trim() ?? '';
    if (!GroupDisplayName.isIdLike(groupName, group?.groupId)) {
      return groupName;
    }
  }
  if (!conversation.isGroup) {
    final targetDid = conversation.targetDid?.trim() ?? '';
    final runtimeAgent = targetDid.isEmpty
        ? null
        : localRuntimeAgentForConversationTarget(
            targetDid,
            ref.watch(agentsProvider).agents,
          );
    if (runtimeAgent != null) {
      return localizeAgentTitle(l10n, runtimeAgent);
    }
    return ref.watch(
      peerDisplayNameProvider(
        PeerDisplayNameRequest(
          peerPersonaId: conversation.peerPersonaId,
          did: conversation.targetDid,
          fullHandle: conversation.targetPeer,
          senderNameSnapshot: conversation.displayName,
          unknownLabel: l10n.chatUnknownUser,
        ),
      ),
    );
  }
  return DidDisplayFormatter.conversationTitle(conversation, l10n);
}

String? _conversationPresentationAvatarUri(
  WidgetRef ref,
  ConversationSummary conversation,
) {
  if (!conversation.isGroup) {
    return peerAvatarUri(
          ref.watch(peerDisplayProfileProvider),
          conversation.targetDid,
          peerPersonaId: conversation.peerPersonaId,
        ) ??
        conversation.avatarUri;
  }
  return _presentationGroup(ref, conversation)?.avatarUri ??
      conversation.avatarUri;
}

GroupSummary? _presentationGroup(
  WidgetRef ref,
  ConversationSummary conversation,
) {
  final conversationId = conversation.conversationId.trim();
  for (final group in ref.watch(groupProvider).groups) {
    if (group.conversationId.trim() == conversationId) {
      return group;
    }
  }
  return null;
}

String _normalizedConversationSearchText(String text) {
  return text.trim().toLowerCase();
}

AgentVisualStatus? _conversationAgentStatus(
  WidgetRef ref,
  ConversationSummary conversation,
  ConversationPeerClassification classification,
) {
  if (!classification.isAgent || conversation.isDeletedAgentConversation) {
    return null;
  }
  final pendingInThread = ref.watch(
    pendingAgentDidsForThreadProvider(conversation.threadId),
  );
  final runtimeAgent = classification.localRuntimeAgent;
  if (runtimeAgent == null) {
    if (pendingInThread.isNotEmpty) {
      return const AgentVisualStatus(AgentVisualStatusKind.processing);
    }
    return null;
  }
  final hasPendingTurn =
      ref.watch(pendingAgentDidsProvider).contains(runtimeAgent.agentDid) ||
      pendingInThread.contains(runtimeAgent.agentDid);
  return AgentVisualStatus.fromAgent(
    runtimeAgent,
    authoritativeBusy: ref
        .watch(acpSessionsProvider)
        .busyForAgent(runtimeAgent.agentDid),
    hasPendingTurn: hasPendingTurn,
  );
}

ConversationPeerClassification _conversationPeerClassification(
  WidgetRef ref,
  ConversationSummary conversation,
) {
  return ref
      .watch(
        conversationPeerClassificationProvider(
          ConversationPeerTarget.fromConversation(conversation),
        ),
      )
      .maybeWhen(
        data: (value) => value,
        orElse: () =>
            _fallbackConversationPeerClassification(ref, conversation),
      );
}

ConversationPeerClassification _fallbackConversationPeerClassification(
  WidgetRef ref,
  ConversationSummary conversation,
) {
  if (conversation.isGroup) {
    return const ConversationPeerClassification.group();
  }
  if (conversation.isDeletedAgentConversation) {
    return const ConversationPeerClassification.agent(
      agentKind: PeerAgentKind.runtime,
    );
  }
  final targetDid = conversation.targetDid?.trim();
  if (targetDid == null || targetDid.isEmpty) {
    return const ConversationPeerClassification.unknown();
  }
  final localRuntime = localRuntimeAgentForConversationTarget(
    targetDid,
    ref.watch(agentsProvider).agents,
  );
  if (localRuntime != null) {
    return ConversationPeerClassification.agent(
      agentKind: PeerAgentKind.runtime,
      localRuntimeAgent: localRuntime,
    );
  }
  if (conversationTargetDidLooksLikeAgent(targetDid)) {
    return const ConversationPeerClassification.agent(
      agentKind: PeerAgentKind.runtime,
    );
  }
  return const ConversationPeerClassification.unknown();
}

_ConversationPreviewPresentation _conversationPreviewPresentation(
  WidgetRef ref,
  AppLocalizations l10n,
  ConversationSummary conversation,
  Map<String, ChatComposerDraft> drafts,
) {
  final systemEvent =
      conversation.lastMessageSnapshot?.groupSystemEvent ??
      GroupSystemEvent.tryParse(conversation.lastMessagePayloadJson);
  final actorName = systemEvent == null
      ? null
      : ref.watch(
          publicIdentityDisplayNameProvider(
            PublicIdentityDisplayNameRequest(
              did: systemEvent.actorDid,
              unknownLabel: l10n.commonUnknown,
            ),
          ),
        );
  final subjectName = systemEvent == null
      ? null
      : ref.watch(
          publicIdentityDisplayNameProvider(
            PublicIdentityDisplayNameRequest(
              did: systemEvent.subjectDid,
              unknownLabel: l10n.commonUnknown,
            ),
          ),
        );
  final draft = _draftForConversation(conversation, drafts);
  final tags = <_ConversationPreviewTag>[];
  if (conversation.hasUnreadMention) {
    tags.add(
      _ConversationPreviewTag(
        text: l10n.conversationsMentionMeTag,
        tone: _ConversationPreviewTagTone.mention,
      ),
    );
  }
  if (draft.isEmpty) {
    return _ConversationPreviewPresentation(
      text: localizeConversationPreview(
        l10n,
        conversation,
        groupEventActorName: actorName,
        groupEventSubjectName: subjectName,
      ),
      tags: tags,
    );
  }
  final text = draft.text.trim();
  if (text.isNotEmpty) {
    return _ConversationPreviewPresentation(
      text: markdownPlainTextPreview(text),
      tags: <_ConversationPreviewTag>[
        ...tags,
        _ConversationPreviewTag(
          text: l10n.conversationsDraftTag,
          tone: _ConversationPreviewTagTone.draft,
        ),
      ],
    );
  }
  final attachment = draft.pendingAttachment;
  if (attachment != null) {
    return _ConversationPreviewPresentation(
      text: l10n.conversationsAttachmentPreview(
        localizeAttachmentDraftName(l10n, attachment),
      ),
      tags: <_ConversationPreviewTag>[
        ...tags,
        _ConversationPreviewTag(
          text: l10n.conversationsDraftTag,
          tone: _ConversationPreviewTagTone.draft,
        ),
      ],
    );
  }
  return _ConversationPreviewPresentation(
    text: localizeConversationPreview(
      l10n,
      conversation,
      groupEventActorName: actorName,
      groupEventSubjectName: subjectName,
    ),
    tags: tags,
  );
}

ChatComposerDraft _draftForConversation(
  ConversationSummary conversation,
  Map<String, ChatComposerDraft> drafts,
) {
  return drafts[conversation.conversationId] ?? const ChatComposerDraft();
}

class _ConversationPreviewPresentation {
  const _ConversationPreviewPresentation({
    required this.text,
    this.tags = const <_ConversationPreviewTag>[],
  });

  final String text;
  final List<_ConversationPreviewTag> tags;
}

enum _ConversationPreviewTagTone { mention, draft }

class _ConversationPreviewTag {
  const _ConversationPreviewTag({required this.text, required this.tone});

  final String text;
  final _ConversationPreviewTagTone tone;
}

class _ConversationPreviewLine extends StatelessWidget {
  const _ConversationPreviewLine({
    required this.presentation,
    required this.compact,
    required this.emptyText,
  });

  final _ConversationPreviewPresentation presentation;
  final bool compact;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final text = presentation.text.trim();
    return Row(
      children: <Widget>[
        for (final tag in presentation.tags) ...<Widget>[
          _ConversationPreviewTagBadge(tag: tag, compact: compact),
          SizedBox(
            width: compact
                ? responsive.displayScaled(4)
                : responsive.displayScaled(5),
          ),
        ],
        Expanded(
          child: Text(
            text.isEmpty ? emptyText : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.tertiaryText,
              fontSize: compact
                  ? responsive.displayScaled(12.5)
                  : responsive.displayScaled(13.5),
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationPreviewTagBadge extends StatelessWidget {
  const _ConversationPreviewTagBadge({
    required this.tag,
    required this.compact,
  });

  final _ConversationPreviewTag tag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final palette = _conversationPreviewTagPalette(tag.tone);
    return Container(
      key: Key('conversation-preview-tag-${tag.tone.name}'),
      padding: EdgeInsets.symmetric(
        horizontal: compact
            ? responsive.displayScaled(4.5)
            : responsive.displayScaled(5.5),
        vertical: compact
            ? responsive.displayScaled(1.5)
            : responsive.displayScaled(2.5),
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(responsive.displayScaled(4.5)),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        tag.text,
        maxLines: 1,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: palette.foreground,
          fontSize: compact
              ? responsive.displayScaled(10)
              : responsive.displayScaled(10.5),
          height: 1,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

class _ConversationUnreadBadge extends StatelessWidget {
  const _ConversationUnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final label = count > 99 ? '99+' : '$count';
    final diameter = responsive.displayScaled(
      count > 99
          ? 26
          : count > 9
          ? 22
          : 18,
    );
    return Container(
      key: const Key('conversation-row-unread-badge'),
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.awikiTheme.unread,
        shape: BoxShape.circle,
        border: Border.all(
          color: context.awikiTheme.surface,
          width: responsive.displayScaled(1.5),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: context.awikiTheme.surface,
          fontSize: count > 99 ? 9 : 10.5,
          fontWeight: FontWeight.w400,
          height: 1,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

({Color background, Color border, Color foreground})
_conversationPreviewTagPalette(_ConversationPreviewTagTone tone) {
  return switch (tone) {
    _ConversationPreviewTagTone.mention => (
      background: const Color(0xFFFFECEB),
      border: const Color(0xFFFFD6D3),
      foreground: AwikiMePalette.dangerRed,
    ),
    _ConversationPreviewTagTone.draft => (
      background: const Color(0xFFFFF4E5),
      border: const Color(0xFFFFDFB0),
      foreground: const Color(0xFFB25E00),
    ),
  };
}

class _ConversationTitleStatusLine extends StatelessWidget {
  const _ConversationTitleStatusLine({
    required this.title,
    required this.titleStyle,
    required this.isDeletedAgentConversation,
    required this.compact,
  });

  final String title;
  final TextStyle titleStyle;
  final bool isDeletedAgentConversation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        if (isDeletedAgentConversation) ...<Widget>[
          SizedBox(width: responsive.displayScaled(compact ? 6 : 7)),
          Flexible(child: _DeletedAgentConversationBadge(compact: compact)),
        ],
      ],
    );
  }
}

/// Kind tag beside a conversation name ("AI", "群"): the reference's quiet
/// hairline outline with muted text, never a colored fill.
class _ConversationPeerBadge extends StatelessWidget {
  const _ConversationPeerBadge({
    required this.label,
    required this.isGroup,
    this.muted = false,
    this.compact = false,
  });

  final String label;
  final bool isGroup;
  final bool muted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AwikiNameTag(
      key: const Key('conversation-peer-badge'),
      label: label,
      muted: muted,
    );
  }
}

class _DeletedAgentConversationBadge extends StatelessWidget {
  const _DeletedAgentConversationBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Container(
      key: const Key('deleted-agent-conversation-badge'),
      padding: EdgeInsets.symmetric(
        horizontal: responsive.displayScaled(compact ? 6 : 7),
        vertical: responsive.displayScaled(compact ? 2 : 3),
      ),
      decoration: BoxDecoration(
        color: context.awikiTheme.subtleSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.awikiTheme.border),
      ),
      child: Text(
        context.l10n.conversationsDeletedAgentBadge,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.awikiTheme.secondaryText,
          fontSize: compact ? 10 : 10.5,
          fontWeight: FontWeight.w400,
          height: 1,
        ),
      ),
    );
  }
}

class _ConversationLoadErrorState extends StatelessWidget {
  const _ConversationLoadErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(responsive.displayScaled(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              context.l10n.operationFailedRetry,
              key: const Key('conversation-list-load-error'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.awikiTheme.secondaryText,
                fontSize: 13,
              ),
            ),
            SizedBox(height: responsive.displayScaled(10)),
            CupertinoButton(
              key: const Key('conversation-list-load-retry'),
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.embedded,
  });

  final String title;
  final String subtitle;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    if (!embedded) {
      final theme = context.awikiTheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          responsive.spacing(24),
          responsive.spacing(24),
          responsive.spacing(24),
          responsive.spacing(72),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              key: const Key('compact-conversation-inline-empty-state'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AwikiMeTextStyles.sectionTitle.copyWith(
                    color: theme.secondaryText,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...<Widget>[
                  SizedBox(height: responsive.spacing(8)),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: AwikiMeTextStyles.cardSubtitle.copyWith(
                      color: theme.secondaryText,
                      fontSize: responsive.bodySm,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: responsive.scaledInsets(
        EdgeInsets.fromLTRB(
          responsive.tabInnerPadding.left,
          32,
          responsive.tabInnerPadding.right,
          embedded ? 24 : 12,
        ),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: EmptyStateCard(title: title, subtitle: subtitle),
      ),
    );
  }
}
