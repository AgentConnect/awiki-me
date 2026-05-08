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
  });

  final ConversationSelectionHandler? onConversationSelected;
  final String? selectedThreadId;
  final bool embedded;
  final double bottomInset;

  bool get _usesEmbeddedSelection => onConversationSelected != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationListProvider);
    final responsive = context.awikiResponsive;
    return AwikiMeShellTabPage(
      title: context.l10n.conversationsTitle,
      onSettingsTap: () => AppNavigator.pushWithoutAnimation(
        context,
        (_) => const SettingsPage(),
      ),
      onQuickActionsTap: () => showCommonQuickActionsMenu(context, ref),
      child: state.conversations.isEmpty
          ? _EmptyState(
              embedded: embedded,
              title: context.l10n.conversationsEmptyTitle,
              subtitle: context.l10n.conversationsEmptySubtitle,
            )
          : ListView.builder(
              padding: EdgeInsets.only(
                top: responsive.spacing(8),
                bottom: bottomInset,
              ),
              itemCount: state.conversations.length,
              itemBuilder: (_, index) {
                final item = state.conversations[index];
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
                  onTap: () => _openConversation(context, ref, item),
                );
              },
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
    return ListView(
      padding: responsive.scaledInsets(
        EdgeInsets.fromLTRB(
          responsive.tabInnerPadding.left,
          32,
          responsive.tabInnerPadding.right,
          embedded ? 24 : 12,
        ),
      ),
      children: <Widget>[EmptyStateCard(title: title, subtitle: subtitle)],
    );
  }
}
