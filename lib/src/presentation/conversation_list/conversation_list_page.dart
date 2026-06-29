import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show PopupMenuEntry, PopupMenuItem, RelativeRect, showMenu;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../core/date_time_formatter.dart';
import '../../core/performance_logger.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../domain/entities/peer_agent_identity.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../agents/agents_provider.dart';
import '../agents/agent_status_indicator.dart';
import '../agents/agent_visual_status.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/identity_flow.dart';
import '../shared/quick_actions.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../settings/settings_page.dart';
import 'conversation_peer_classifier.dart';
import 'conversation_provider.dart';

typedef ConversationSelectionHandler =
    Future<void> Function(ConversationSummary conversation);

class ConversationListPage extends ConsumerStatefulWidget {
  const ConversationListPage({
    super.key,
    this.onConversationSelected,
    this.selectedThreadId,
    this.embedded = false,
    this.bottomInset = 120,
    this.macStyle = false,
  });

  final ConversationSelectionHandler? onConversationSelected;
  final String? selectedThreadId;
  final bool embedded;
  final double bottomInset;
  final bool macStyle;

  @override
  ConsumerState<ConversationListPage> createState() =>
      _ConversationListPageState();
}

class _ConversationListPageState extends ConsumerState<ConversationListPage> {
  bool get _usesEmbeddedSelection => widget.onConversationSelected != null;

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
    final composerDrafts = ref.watch(chatComposerDraftsProvider);
    final responsive = context.awikiResponsive;
    buildWatch.stop();
    AwikiPerformanceLogger.log(
      'conversation_list_page.build.prepare',
      elapsed: buildWatch.elapsed,
      fields: <String, Object?>{
        'items': state.conversations.length,
        'loading': state.isLoading,
        'mac_style': widget.macStyle && responsive.isMacDesktop,
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

    if (widget.macStyle && responsive.isMacDesktop) {
      return _MacConversationList(
        conversations: state.conversations,
        composerDrafts: composerDrafts,
        selectedThreadId: widget.selectedThreadId,
        bottomInset: widget.bottomInset,
        onRefresh: refreshConversations,
        onOpen: (item) => _openConversation(context, ref, item),
        onDelete: (item) => _deleteConversationFromRecents(context, ref, item),
        onShowActions: () => showCommonQuickActionsMenu(context, ref),
        onStartConversation: () => showStartConversationDialog(context, ref),
      );
    }
    return AwikiMeShellTabPage(
      title: context.l10n.conversationsTitle,
      onSettingsTap: responsive.isMacDesktop
          ? null
          : () => AppNavigator.pushWithoutAnimation(
              context,
              (_) => const SettingsPage(),
            ),
      onQuickActionsTap: () => showCommonQuickActionsMenu(context, ref),
      child: _ConversationRefreshView(
        conversations: state.conversations,
        composerDrafts: composerDrafts,
        selectedThreadId: widget.selectedThreadId,
        embedded: widget.embedded,
        bottomInset: widget.bottomInset,
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
      (dialogContext) => CupertinoAlertDialog(
        title: const Text('删除会话'),
        content: const Text('会话将从最近列表移除，历史消息仍会保留。重新打开或收到新消息后，会话会再次出现在列表中。'),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
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
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    }
  }
}

class _MacConversationList extends ConsumerStatefulWidget {
  const _MacConversationList({
    required this.conversations,
    required this.composerDrafts,
    required this.selectedThreadId,
    required this.bottomInset,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
    required this.onShowActions,
    required this.onStartConversation,
  });

  final List<ConversationSummary> conversations;
  final Map<String, ChatComposerDraft> composerDrafts;
  final String? selectedThreadId;
  final double bottomInset;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onDelete;
  final VoidCallback onShowActions;
  final VoidCallback onStartConversation;

  @override
  ConsumerState<_MacConversationList> createState() =>
      _MacConversationListState();
}

class _MacConversationListState extends ConsumerState<_MacConversationList> {
  String _query = '';

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
      decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              responsive.displayScaled(20),
              responsive.displayScaled(22),
              responsive.displayScaled(20),
              responsive.displayScaled(12),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '最近会话',
                    style: TextStyle(
                      color: const Color(0xFF101B32),
                      fontSize: responsive.displayScaled(16),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                _MacListIconButton(
                  key: const Key('conversation-quick-actions-button'),
                  semanticLabel: '更多操作',
                  icon: CupertinoIcons.ellipsis,
                  onTap: widget.onShowActions,
                ),
                SizedBox(width: responsive.displayScaled(10)),
                _MacListIconButton(
                  key: const Key('start-conversation-button'),
                  semanticLabel: '发起新消息',
                  icon: CupertinoIcons.plus,
                  onTap: widget.onStartConversation,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.displayScaled(20),
            ),
            child: CupertinoSearchTextField(
              placeholder: '搜索会话',
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
              style: TextStyle(
                fontSize: responsive.displayScaled(13),
                color: const Color(0xFF17213A),
              ),
              placeholderStyle: TextStyle(
                fontSize: responsive.displayScaled(13),
                color: const Color(0xFF8A96AA),
              ),
              prefixIcon: Icon(
                CupertinoIcons.search,
                color: const Color(0xFF34415C),
                size: responsive.displayScaled(18),
              ),
              suffixIcon: Icon(
                CupertinoIcons.xmark_circle_fill,
                color: const Color(0xFFB3BDCD),
                size: responsive.displayScaled(16),
              ),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(
                  responsive.displayScaled(9),
                ),
                border: Border.all(color: const Color(0xFFDDE5F0)),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: responsive.displayScaled(10),
                vertical: responsive.displayScaled(9),
              ),
            ),
          ),
          SizedBox(height: responsive.displayScaled(12)),
          Expanded(
            child: CustomScrollView(
              slivers: <Widget>[
                CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
                if (widget.conversations.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MacConversationEmptyState(),
                  )
                else if (visibleConversations.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MacConversationEmptyState(
                      title: '没有找到相关会话',
                      subtitle: hasQuery ? '换个关键词试试' : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      responsive.displayScaled(12),
                      0,
                      responsive.displayScaled(12),
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
                          item,
                          widget.composerDrafts,
                        );
                        return _MacConversationRow(
                          title: DidDisplayFormatter.conversationTitle(
                            item,
                            context.l10n,
                          ),
                          avatarUri: item.avatarUri,
                          preview: preview,
                          timeLabel: DateTimeFormatter.conversationTime(
                            item.lastMessageAt,
                          ),
                          isDeletedAgentConversation:
                              item.isDeletedAgentConversation,
                          classification: classification,
                          agentStatus: agentStatus,
                          isSelected: widget.selectedThreadId == item.threadId,
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
    final query = _normalizedSearchText(_query);
    if (query.isEmpty) {
      return widget.conversations;
    }
    return widget.conversations
        .where((conversation) {
          return _conversationSearchText(context, conversation).contains(query);
        })
        .toList(growable: false);
  }

  String _conversationSearchText(
    BuildContext context,
    ConversationSummary conversation,
  ) {
    return _normalizedSearchText(
      <String>[
        DidDisplayFormatter.conversationTitle(conversation, context.l10n),
        conversation.displayName,
        conversation.lastMessagePreview,
        conversation.targetDid ?? '',
        conversation.groupId ?? '',
        conversation.threadId,
      ].join(' '),
    );
  }

  String _normalizedSearchText(String text) {
    return text.trim().toLowerCase();
  }
}

class _ConversationRefreshView extends ConsumerWidget {
  const _ConversationRefreshView({
    required this.conversations,
    required this.composerDrafts,
    required this.selectedThreadId,
    required this.embedded,
    required this.bottomInset,
    required this.onRefresh,
    required this.onOpen,
    required this.onDelete,
  });

  final List<ConversationSummary> conversations;
  final Map<String, ChatComposerDraft> composerDrafts;
  final String? selectedThreadId;
  final bool embedded;
  final double bottomInset;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationSummary> onOpen;
  final ValueChanged<ConversationSummary> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final responsive = context.awikiResponsive;
    return CustomScrollView(
      slivers: <Widget>[
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        if (conversations.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              embedded: embedded,
              title: context.l10n.conversationsEmptyTitle,
              subtitle: context.l10n.conversationsEmptySubtitle,
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.only(
              top: responsive.spacing(8),
              bottom: bottomInset,
            ),
            sliver: SliverList.builder(
              itemCount: conversations.length,
              itemBuilder: (_, index) {
                final item = conversations[index];
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
                  item,
                  composerDrafts,
                );
                return _ConversationRow(
                  title: DidDisplayFormatter.conversationTitle(
                    item,
                    context.l10n,
                  ),
                  avatarUri: item.avatarUri,
                  preview: preview,
                  timeLabel: DateTimeFormatter.conversationTime(
                    item.lastMessageAt,
                  ),
                  isDeletedAgentConversation: item.isDeletedAgentConversation,
                  classification: classification,
                  agentStatus: agentStatus,
                  isSelected: selectedThreadId == item.threadId,
                  onTap: () => onOpen(item),
                  onLongPress: () => onDelete(item),
                );
              },
            ),
          ),
      ],
    );
  }
}

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
    return AppIconButton(
      onPressed: onTap,
      semanticLabel: semanticLabel,
      tooltip: semanticLabel,
      size: responsive.displayScaled(32),
      backgroundColor: CupertinoColors.white,
      borderColor: const Color(0xFFE5EAF2),
      borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
      child: Icon(
        icon,
        color: const Color(0xFF34415C),
        size: responsive.displayScaled(19),
      ),
    );
  }
}

class _MacConversationRow extends StatelessWidget {
  const _MacConversationRow({
    required this.title,
    required this.avatarUri,
    required this.preview,
    required this.timeLabel,
    required this.isDeletedAgentConversation,
    required this.classification,
    required this.agentStatus,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  final String title;
  final String? avatarUri;
  final _ConversationPreviewPresentation preview;
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
    final badgeLabel = classification.compactBadgeLabel;
    return _ConversationContextMenuRegion(
      onDelete: onDelete,
      child: Padding(
        padding: EdgeInsets.only(bottom: responsive.displayScaled(6)),
        child: AppPressableTile(
          onTap: onTap,
          selected: isSelected,
          semanticLabel: title,
          borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
          backgroundColor: CupertinoColors.white,
          selectedBackgroundColor: const Color(0xFFE8F0FF),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFCFE0FF)
                : const Color(0x00FFFFFF),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: EdgeInsets.all(responsive.displayScaled(10)),
            child: Row(
              children: <Widget>[
                Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    AvatarBadge(
                      seed: title,
                      size: responsive.displayScaled(42),
                      avatarUri: avatarUri,
                    ),
                    if (badgeLabel != null)
                      Positioned(
                        right: responsive.displayScaled(-2),
                        bottom: responsive.displayScaled(-2),
                        child: _ConversationPeerBadge(
                          label: badgeLabel,
                          isGroup: classification.isGroup,
                          muted: isDeletedAgentConversation,
                          compact: true,
                          borderColor: CupertinoColors.white,
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
                            child: _ConversationTitleStatusLine(
                              title: title,
                              isDeletedAgentConversation:
                                  isDeletedAgentConversation,
                              compact: true,
                              titleStyle: TextStyle(
                                color: const Color(0xFF17213A),
                                fontSize: responsive.displayScaled(13.5),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: responsive.displayScaled(5)),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _ConversationPreviewLine(
                              presentation: preview,
                              compact: true,
                              emptyText:
                                  context.l10n.conversationsNoMessagePreview,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (agentStatus != null) ...<Widget>[
                  SizedBox(width: responsive.displayScaled(7)),
                  AgentStatusDot(
                    status: agentStatus!,
                    size: responsive.displayScaled(8),
                  ),
                ],
                SizedBox(width: responsive.displayScaled(8)),
                Text(
                  timeLabel,
                  style: TextStyle(
                    color: const Color(0xFF66728A),
                    fontSize: responsive.displayScaled(10.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MacConversationEmptyState extends StatelessWidget {
  const _MacConversationEmptyState({this.title = '还没有会话', this.subtitle});

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
                color: const Color(0xFF7B879D),
                fontSize: responsive.displayScaled(14),
              ),
            ),
            if (subtitle != null) ...<Widget>[
              SizedBox(height: responsive.displayScaled(6)),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF9AA5B8),
                  fontSize: responsive.displayScaled(12),
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
    required this.title,
    required this.avatarUri,
    required this.preview,
    required this.timeLabel,
    required this.isDeletedAgentConversation,
    required this.classification,
    required this.agentStatus,
    required this.onTap,
    required this.onLongPress,
    required this.isSelected,
  });

  final String title;
  final String? avatarUri;
  final _ConversationPreviewPresentation preview;
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
    final badgeLabel = classification.compactBadgeLabel;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.tabContentHorizontalPadding,
      ),
      child: AppPressableTile(
        onTap: onTap,
        onLongPress: onLongPress,
        selected: isSelected,
        semanticLabel: title,
        borderRadius: BorderRadius.circular(responsive.radius(18)),
        backgroundColor: CupertinoColors.transparent,
        selectedBackgroundColor: theme.subtleSurface,
        border: Border(bottom: BorderSide(color: theme.border)),
        padding: responsive.scaledInsets(
          const EdgeInsets.fromLTRB(10, 14, 14, 14),
        ),
        child: Row(
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                AvatarBadge(
                  seed: title,
                  size: responsive.avatarSizeMd,
                  avatarUri: avatarUri,
                ),
                if (badgeLabel != null)
                  Positioned(
                    right: responsive.displayScaled(-2),
                    bottom: responsive.displayScaled(-2),
                    child: _ConversationPeerBadge(
                      label: badgeLabel,
                      isGroup: classification.isGroup,
                      compact: true,
                      borderColor: CupertinoColors.white,
                    ),
                  ),
              ],
            ),
            SizedBox(width: responsive.spacing(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _ConversationTitleStatusLine(
                          title: title,
                          isDeletedAgentConversation:
                              isDeletedAgentConversation,
                          compact: false,
                          titleStyle: TextStyle(
                            fontSize: responsive.bodyMd,
                            fontWeight: FontWeight.w400,
                            color: theme.title,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: responsive.spacing(4)),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _ConversationPreviewLine(
                          presentation: preview,
                          compact: false,
                          emptyText: context.l10n.conversationsNoMessagePreview,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.spacing(8)),
            Padding(
              key: const Key('conversation-row-right-meta'),
              padding: EdgeInsets.only(right: responsive.scaled(2)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: responsive.scaled(58),
                  maxWidth: responsive.scaled(90),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      timeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      textAlign: TextAlign.right,
                      style: AwikiMeTextStyles.meta.copyWith(
                        fontSize: responsive.metaSm,
                        letterSpacing: 0,
                      ),
                    ),
                    if (agentStatus != null) ...<Widget>[
                      SizedBox(height: responsive.spacing(7)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          if (agentStatus != null)
                            AgentStatusDot(
                              status: agentStatus!,
                              size: responsive.scaled(8),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'delete', child: Text('删除会话')),
      ],
    );
    if (selected == 'delete') {
      widget.onDelete();
    }
  }
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
  ConversationSummary conversation,
  Map<String, ChatComposerDraft> drafts,
) {
  final draft = _draftForConversation(conversation, drafts);
  final tags = <_ConversationPreviewTag>[];
  if (conversation.unreadCount > 0) {
    tags.add(
      _ConversationPreviewTag(
        text: '未读 ${_conversationCountLabel(conversation.unreadCount)}',
        tone: _ConversationPreviewTagTone.unread,
      ),
    );
  }
  if (conversation.hasUnreadMention) {
    tags.add(
      const _ConversationPreviewTag(
        text: '@我',
        tone: _ConversationPreviewTagTone.mention,
      ),
    );
  }
  if (draft.isEmpty) {
    return _ConversationPreviewPresentation(
      text: conversation.lastMessagePreview,
      tags: tags,
    );
  }
  final text = draft.text.trim();
  if (text.isNotEmpty) {
    return _ConversationPreviewPresentation(
      text: text,
      tags: <_ConversationPreviewTag>[
        ...tags,
        const _ConversationPreviewTag(
          text: '草稿',
          tone: _ConversationPreviewTagTone.draft,
        ),
      ],
    );
  }
  final attachment = draft.pendingAttachment;
  if (attachment != null) {
    return _ConversationPreviewPresentation(
      text: '附件：${attachment.displayName}',
      tags: <_ConversationPreviewTag>[
        ...tags,
        const _ConversationPreviewTag(
          text: '草稿',
          tone: _ConversationPreviewTagTone.draft,
        ),
      ],
    );
  }
  return _ConversationPreviewPresentation(
    text: conversation.lastMessagePreview,
    tags: tags,
  );
}

ChatComposerDraft _draftForConversation(
  ConversationSummary conversation,
  Map<String, ChatComposerDraft> drafts,
) {
  for (final key in conversation.visibilityKeys) {
    final draft = drafts[key.trim()];
    if (draft != null) {
      return draft;
    }
  }
  final threadDraft = drafts[conversation.threadId.trim()];
  return threadDraft ?? const ChatComposerDraft();
}

String _conversationCountLabel(int count) => count > 999 ? '999+' : '$count';

class _ConversationPreviewPresentation {
  const _ConversationPreviewPresentation({
    required this.text,
    this.tags = const <_ConversationPreviewTag>[],
  });

  final String text;
  final List<_ConversationPreviewTag> tags;
}

enum _ConversationPreviewTagTone { unread, mention, draft }

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
              color: compact ? const Color(0xFF66728A) : theme.secondaryText,
              fontSize: compact
                  ? responsive.displayScaled(11.5)
                  : responsive.bodySm,
              height: compact ? 1.25 : 1.2,
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
      key: Key('conversation-preview-tag:${tag.text}'),
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
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

({Color background, Color border, Color foreground})
_conversationPreviewTagPalette(_ConversationPreviewTagTone tone) {
  return switch (tone) {
    _ConversationPreviewTagTone.unread => (
      background: const Color(0xFFEAF2FF),
      border: const Color(0xFFCFE0FF),
      foreground: const Color(0xFF0B65F8),
    ),
    _ConversationPreviewTagTone.mention => (
      background: const Color(0xFFFFECEB),
      border: const Color(0xFFFFD6D3),
      foreground: const Color(0xFFC22A22),
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
          _DeletedAgentConversationBadge(compact: compact),
        ],
      ],
    );
  }
}

class _ConversationPeerBadge extends StatelessWidget {
  const _ConversationPeerBadge({
    required this.label,
    required this.isGroup,
    this.muted = false,
    this.compact = false,
    this.borderColor,
  });

  final String label;
  final bool isGroup;
  final bool muted;
  final bool compact;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final background = muted
        ? const Color(0xFFF1F3F7)
        : isGroup
        ? const Color(0xFFEFE4FF)
        : const Color(0xFFEAF2FF);
    final foreground = muted
        ? const Color(0xFF66728A)
        : isGroup
        ? const Color(0xFF7C3AED)
        : const Color(0xFF0B65F8);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.displayScaled(compact ? 5 : 7),
        vertical: responsive.displayScaled(compact ? 2 : 3),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(
          responsive.displayScaled(compact ? 5 : 999),
        ),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: foreground,
          fontSize: responsive.displayScaled(compact ? 9 : 10.5),
          fontWeight: FontWeight.w600,
          height: 1,
        ),
      ),
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
        color: const Color(0xFFF1F3F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE1E7F0)),
      ),
      child: Text(
        '智能体已删除',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xFF66728A),
          fontSize: responsive.displayScaled(compact ? 10 : 10.5),
          fontWeight: FontWeight.w600,
          height: 1,
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
