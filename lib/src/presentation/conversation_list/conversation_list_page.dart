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
      onSettingsTap: () => AppNavigator.pushWithoutAnimation(
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

class _MacConversationList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFFF8FAFD)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    '最近会话',
                    style: TextStyle(
                      color: Color(0xFF101B32),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _MacListIconButton(
                  key: const Key('conversation-quick-actions-button'),
                  semanticLabel: '更多操作',
                  icon: CupertinoIcons.ellipsis,
                  onTap: onShowActions,
                ),
                const SizedBox(width: 10),
                _MacListIconButton(
                  key: const Key('start-conversation-button'),
                  semanticLabel: '发起新消息',
                  icon: CupertinoIcons.plus,
                  onTap: onStartConversation,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CupertinoSearchTextField(
              placeholder: '搜索会话或 Agent',
              style: const TextStyle(fontSize: 13, color: Color(0xFF17213A)),
              placeholderStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8A96AA),
              ),
              prefixIcon: const Icon(
                CupertinoIcons.search,
                color: Color(0xFF34415C),
                size: 18,
              ),
              suffixIcon: const Icon(
                CupertinoIcons.xmark_circle_fill,
                color: Color(0xFFB3BDCD),
                size: 16,
              ),
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFDDE5F0)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CustomScrollView(
              slivers: <Widget>[
                CupertinoSliverRefreshControl(onRefresh: onRefresh),
                if (conversations.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _MacConversationEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset),
                    sliver: SliverList.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final item = conversations[index];
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
                          isGroup: item.isGroup,
                          isSelected: selectedThreadId == item.threadId,
                          onTap: () => onOpen(item),
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
}

class _ConversationRefreshView extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5EAF2)),
          ),
          child: Icon(icon, color: const Color(0xFF34415C), size: 19),
        ),
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
    required this.isGroup,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final int unreadCount;
  final bool isGroup;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE8F0FF) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFCFE0FF)
                  : const Color(0x00FFFFFF),
            ),
          ),
          child: Row(
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  AvatarBadge(seed: title, size: 42),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isGroup
                            ? const Color(0xFFEFE4FF)
                            : const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: CupertinoColors.white),
                      ),
                      child: Text(
                        isGroup ? '群' : 'AI',
                        style: TextStyle(
                          color: isGroup
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFF0B65F8),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
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
                            style: const TextStyle(
                              color: Color(0xFF17213A),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            color: Color(0xFF66728A),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            preview.isEmpty
                                ? context.l10n.conversationsNoMessagePreview
                                : preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF66728A),
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ),
                        if (unreadCount > 0) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
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
  const _MacConversationEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '还没有会话',
          style: TextStyle(color: Color(0xFF7B879D), fontSize: 14),
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
    required this.onTap,
    required this.isSelected,
  });

  final String title;
  final String preview;
  final String timeLabel;
  final int unreadCount;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.tabContentHorizontalPadding,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: responsive.scaledInsets(
          const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        ),
        decoration: BoxDecoration(
          color: isSelected ? theme.subtleSurface : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(responsive.radius(18)),
          border: Border(bottom: BorderSide(color: theme.border)),
        ),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: <Widget>[
              AvatarBadge(seed: title, size: responsive.avatarSizeMd),
              SizedBox(width: responsive.spacing(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w700,
                        color: theme.title,
                      ),
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
                          const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                        ),
                        decoration: BoxDecoration(
                          color: theme.primary,
                          borderRadius: BorderRadius.circular(
                            AwikiMeRadii.pill,
                          ),
                        ),
                        child: Text(
                          unreadCount > 999 ? '999+' : '$unreadCount',
                          style: TextStyle(
                            fontSize: responsive.metaSm,
                            color: theme.primaryForeground,
                            fontWeight: FontWeight.w700,
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
