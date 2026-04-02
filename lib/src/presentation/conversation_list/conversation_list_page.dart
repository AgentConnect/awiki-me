import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../core/date_time_formatter.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../friends/friends_provider.dart';
import '../group/create_group_page.dart';
import '../group/group_list_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/widgets/app_widgets.dart';
import '../settings/settings_page.dart';
import 'conversation_provider.dart';

class ConversationListPage extends ConsumerWidget {
  const ConversationListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationListProvider);
    final theme = context.awikiTheme;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          child: AwikiMeTopBar(
            title: context.l10n.conversationsTitle,
            padding: EdgeInsets.zero,
            leading: TopBarActionButton(
              onTap: () => AppNavigator.push(
                context,
                (_) => const SettingsPage(),
              ),
              child: Icon(
                Icons.settings_outlined,
                size: 24,
                color: theme.title,
              ),
            ),
            trailing: TopBarActionButton(
              onTap: () => _showQuickActions(context, ref),
              child: Icon(
                Icons.add,
                size: 26,
                color: theme.title,
              ),
            ),
          ),
        ),
        Expanded(
          child: state.conversations.isEmpty
              ? _EmptyState(
                  title: context.l10n.conversationsEmptyTitle,
                  subtitle: context.l10n.conversationsEmptySubtitle)
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
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
                      onTap: () async {
                        await ref
                            .read(chatThreadsProvider.notifier)
                            .openConversation(item);
                        if (!context.mounted) {
                          return;
                        }
                        await AppNavigator.push(
                          context,
                          (_) => ChatPage(conversation: item),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showQuickActions(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final rootContext = context;
    await AppNavigator.showSheet<void>(
      context,
      (sheetContext) => AppDropMenu(
        title: l10n.quickActionsTitle.toUpperCase(),
        items: <AppDropMenuItem>[
          AppDropMenuItem(
            label: l10n.quickActionCreateGroup,
            onTap: () {
              AppNavigator.push(rootContext, (_) => const CreateGroupPage());
            },
          ),
          AppDropMenuItem(
            label: l10n.quickActionJoinGroup,
            onTap: () {
              AppNavigator.push(rootContext, (_) => const GroupListPage());
            },
          ),
          AppDropMenuItem(
            label: l10n.quickActionAddFriend,
            highlighted: true,
            onTap: () {
              _showAddFriendDialog(rootContext, ref);
            },
          ),
        ],
      ),
    );
  }

  void _showAddFriendDialog(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();
    AppNavigator.showDialog<void>(
      context,
      (ctx) => CupertinoAlertDialog(
        title: Text(context.l10n.addFriendTitle),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppTextField(
            controller: textController,
            label: context.l10n.addFriendTitle,
            placeholder: context.l10n.addFriendPlaceholder,
          ),
        ),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonCancel),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () async {
              final value = textController.text.trim();
              if (value.isEmpty) {
                return;
              }
              Navigator.of(ctx).pop();
              final status = await ref
                  .read(friendsProvider.notifier)
                  .checkRelationship(value);
              if (status != null && status.relationship != 'none') {
                return;
              }
              await ref.read(friendsProvider.notifier).follow(value);
            },
            child: Text(context.l10n.commonSend),
          ),
        ],
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
  });

  final String title;
  final String preview;
  final String timeLabel;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.border),
          ),
        ),
        child: AppListTile(
          title: title,
          subtitle: preview.isEmpty
              ? context.l10n.conversationsNoMessagePreview
              : preview,
          leading: AvatarBadge(seed: title, size: 48),
          onTap: onTap,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                timeLabel,
                style: AwikiMeTextStyles.meta.copyWith(letterSpacing: 0),
              ),
              if (unreadCount > 0) ...<Widget>[
                const SizedBox(height: 8),
                AppSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  color: theme.primary,
                  radius: AwikiMeRadii.pill,
                  child: Text(
                    unreadCount > 999 ? '999+' : '$unreadCount',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.primaryForeground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
      children: <Widget>[
        EmptyStateCard(title: title, subtitle: subtitle),
      ],
    );
  }
}
