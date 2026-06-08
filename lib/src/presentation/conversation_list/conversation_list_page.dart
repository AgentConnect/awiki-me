import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../core/date_time_formatter.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
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

class ConversationListPage extends ConsumerWidget {
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

  bool get _usesEmbeddedSelection => onConversationSelected != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationListProvider);
    final responsive = context.awikiResponsive;
    if (macStyle && responsive.isMacDesktop) {
      return _MacConversationList(
        conversations: state.conversations,
        selectedThreadId: selectedThreadId,
        bottomInset: bottomInset,
        onRefresh: () => ref.read(conversationListProvider.notifier).refresh(),
        onOpen: (item) => _openConversation(context, ref, item),
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
        selectedThreadId: selectedThreadId,
        embedded: embedded,
        bottomInset: bottomInset,
        onRefresh: () => ref.read(conversationListProvider.notifier).refresh(),
        onOpen: (item) => _openConversation(context, ref, item),
      ),
    );
  }

  Future<void> _openConversation(
    BuildContext context,
    WidgetRef ref,
    ConversationSummary item,
  ) async {
    await ref.read(chatThreadsProvider.notifier).openConversation(item);
    if (!context.mounted) {
      return;
    }
    if (_usesEmbeddedSelection) {
      await onConversationSelected?.call(item);
      return;
    }
    await AppNavigator.push(context, (_) => ChatPage(conversation: item));
  }
}

class _MacConversationList extends ConsumerStatefulWidget {
  const _MacConversationList({
    required this.conversations,
    required this.selectedThreadId,
    required this.bottomInset,
    required this.onRefresh,
    required this.onOpen,
    required this.onShowActions,
    required this.onStartConversation,
  });

  final List<ConversationSummary> conversations;
  final String? selectedThreadId;
  final double bottomInset;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationSummary> onOpen;
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
    final responsive = context.awikiResponsive;
    final visibleConversations = _filterConversations(context);
    final hasQuery = _query.trim().isNotEmpty;
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
                        final classification = ref
                            .watch(
                              conversationPeerClassificationProvider(
                                ConversationPeerTarget.fromConversation(item),
                              ),
                            )
                            .maybeWhen(
                              data: (value) => value,
                              orElse: () => item.isGroup
                                  ? const ConversationPeerClassification.group()
                                  : const ConversationPeerClassification.unknown(),
                            );
                        return _MacConversationRow(
                          title: DidDisplayFormatter.conversationTitle(
                            item,
                            context.l10n,
                          ),
                          preview: item.lastMessagePreview,
                          timeLabel: DateTimeFormatter.conversationTime(
                            item.lastMessageAt,
                          ),
                          unreadCount: item.unreadCount,
                          classification: classification,
                          isSelected: widget.selectedThreadId == item.threadId,
                          onTap: () => widget.onOpen(item),
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
    required this.selectedThreadId,
    required this.embedded,
    required this.bottomInset,
    required this.onRefresh,
    required this.onOpen,
  });

  final List<ConversationSummary> conversations;
  final String? selectedThreadId;
  final bool embedded;
  final double bottomInset;
  final Future<void> Function() onRefresh;
  final ValueChanged<ConversationSummary> onOpen;

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
                final classification = ref
                    .watch(
                      conversationPeerClassificationProvider(
                        ConversationPeerTarget.fromConversation(item),
                      ),
                    )
                    .maybeWhen(
                      data: (value) => value,
                      orElse: () => item.isGroup
                          ? const ConversationPeerClassification.group()
                          : const ConversationPeerClassification.unknown(),
                    );
                return _ConversationRow(
                  title: DidDisplayFormatter.conversationTitle(
                    item,
                    context.l10n,
                  ),
                  preview: item.lastMessagePreview,
                  timeLabel: DateTimeFormatter.conversationTime(
                    item.lastMessageAt,
                  ),
                  unreadCount: item.unreadCount,
                  classification: classification,
                  isSelected: selectedThreadId == item.threadId,
                  onTap: () => onOpen(item),
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
    required this.preview,
    required this.timeLabel,
    required this.unreadCount,
    required this.classification,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final int unreadCount;
  final ConversationPeerClassification classification;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final badgeLabel = classification.compactBadgeLabel;
    return Padding(
      padding: EdgeInsets.only(bottom: responsive.displayScaled(6)),
      child: AppPressableTile(
        onTap: onTap,
        selected: isSelected,
        semanticLabel: title,
        borderRadius: BorderRadius.circular(responsive.displayScaled(10)),
        backgroundColor: CupertinoColors.white,
        selectedBackgroundColor: const Color(0xFFE8F0FF),
        border: Border.all(
          color: isSelected ? const Color(0xFFCFE0FF) : const Color(0x00FFFFFF),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.all(responsive.displayScaled(10)),
          child: Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AvatarBadge(seed: title, size: responsive.displayScaled(42)),
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
              SizedBox(width: responsive.displayScaled(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF17213A),
                              fontSize: responsive.displayScaled(13.5),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
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
                    SizedBox(height: responsive.displayScaled(5)),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            preview.isEmpty
                                ? context.l10n.conversationsNoMessagePreview
                                : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF66728A),
                              fontSize: responsive.displayScaled(11.5),
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (unreadCount > 0) ...<Widget>[
                          SizedBox(width: responsive.displayScaled(8)),
                          Container(
                            width: responsive.displayScaled(8),
                            height: responsive.displayScaled(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B65F8),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ],
                      ],
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
    required this.preview,
    required this.timeLabel,
    required this.unreadCount,
    required this.classification,
    required this.onTap,
    required this.isSelected,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final int unreadCount;
  final ConversationPeerClassification classification;
  final VoidCallback onTap;
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
        selected: isSelected,
        semanticLabel: title,
        borderRadius: BorderRadius.circular(responsive.radius(18)),
        backgroundColor: CupertinoColors.transparent,
        selectedBackgroundColor: theme.subtleSurface,
        border: Border(bottom: BorderSide(color: theme.border)),
        padding: responsive.scaledInsets(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        ),
        child: Row(
          children: <Widget>[
            AvatarBadge(seed: title, size: responsive.avatarSizeMd),
            SizedBox(width: responsive.spacing(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: responsive.bodyMd,
                            fontWeight: FontWeight.w400,
                            color: theme.title,
                          ),
                        ),
                      ),
                      if (badgeLabel != null) ...<Widget>[
                        SizedBox(width: responsive.spacing(8)),
                        _ConversationPeerBadge(
                          label: badgeLabel,
                          isGroup: classification.isGroup,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: responsive.spacing(4)),
                  Text(
                    preview.isEmpty
                        ? context.l10n.conversationsNoMessagePreview
                        : preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: responsive.bodySm,
                      height: 1.2,
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.spacing(10)),
            SizedBox(
              width: responsive.scaled(58),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    timeLabel,
                    style: AwikiMeTextStyles.meta.copyWith(
                      fontSize: responsive.metaSm,
                      letterSpacing: 0,
                    ),
                  ),
                  if (unreadCount > 0) ...<Widget>[
                    SizedBox(height: responsive.spacing(8)),
                    Container(
                      padding: responsive.scaledInsets(
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      ),
                      decoration: BoxDecoration(
                        color: theme.primary,
                        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
                      ),
                      child: Text(
                        unreadCount > 999 ? '999+' : '$unreadCount',
                        style: TextStyle(
                          fontSize: responsive.metaSm,
                          color: theme.primaryForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationPeerBadge extends StatelessWidget {
  const _ConversationPeerBadge({
    required this.label,
    required this.isGroup,
    this.compact = false,
    this.borderColor,
  });

  final String label;
  final bool isGroup;
  final bool compact;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final background = isGroup
        ? const Color(0xFFEFE4FF)
        : const Color(0xFFEAF2FF);
    final foreground = isGroup
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
