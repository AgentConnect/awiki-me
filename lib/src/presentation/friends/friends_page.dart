import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../group/create_group_page.dart';
import '../group/group_list_page.dart';
import '../profile/profile_provider.dart';
import '../settings/settings_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/widgets/app_widgets.dart';
import 'friends_provider.dart';

class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key});

  String _calcThreadId(String myDid, String peerDid) {
    final list = <String>[myDid, peerDid]..sort();
    return 'dm:${list[0]}:${list[1]}';
  }

  Future<void> _sendMessage(
    BuildContext context,
    WidgetRef ref,
    String peerDid,
    String peerName,
  ) async {
    final myDid = ref.read(profileProvider).profile?.did;
    if (myDid == null) {
      return;
    }
    final threadId = _calcThreadId(myDid, peerDid);
    final conversations = ref.read(conversationListProvider).conversations;
    var targetConv = conversations
        .where((item) => item.threadId == threadId)
        .cast<ConversationSummary?>()
        .firstWhere((_) => true, orElse: () => null);
    targetConv ??= ConversationSummary(
      threadId: threadId,
      displayName: peerName,
      lastMessagePreview: '',
      lastMessageAt: DateTime.now(),
      unreadCount: 0,
      isGroup: false,
      targetDid: peerDid,
    );
    await ref.read(chatThreadsProvider.notifier).openConversation(targetConv);
    if (!context.mounted) {
      return;
    }
    await AppNavigator.push(
      context,
      (_) => ChatPage(conversation: targetConv!),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(friendsProvider);
    final theme = context.awikiTheme;
    final items = <_FriendListItem>[const _FriendListItem.group()];
    for (final item in state.following) {
      items.add(
        _FriendListItem.contact(
          title: DidDisplayFormatter.compactDisplayName(
            displayName: item.displayName,
            fallbackDid: item.did,
          ),
          did: item.did,
        ),
      );
    }
    if (items.length == 1) {
      for (final item in state.followers) {
        items.add(
          _FriendListItem.contact(
            title: DidDisplayFormatter.compactDisplayName(
              displayName: item.displayName,
              fallbackDid: item.did,
            ),
            did: item.did,
          ),
        );
      }
    }

    return Stack(
      children: <Widget>[
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 120),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox.shrink(),
          itemBuilder: (context, index) {
            if (index == 0) {
              return AwikiMeTopBar(
                title: context.l10n.friendsTitle,
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
                  onTap: () => _showQuickActions(context),
                  child: Icon(
                    Icons.add,
                    size: 26,
                    color: theme.title,
                  ),
                ),
              );
            }
            final item = items[index - 1];
            if (item.isGroup) {
              return _FriendRow.group(
                onTap: () => AppNavigator.push(
                  context,
                  (_) => const GroupListPage(),
                ),
              );
            }
            return _FriendRow.contact(
              seed: item.title!,
              title: item.title!,
              onTap: () => _sendMessage(context, ref, item.did!, item.title!),
            );
          },
        ),
        const Positioned(
          right: 10,
          top: 220,
          bottom: 130,
          child: _IndexRail(),
        ),
      ],
    );
  }

  Future<void> _showQuickActions(BuildContext context) async {
    await AppNavigator.showSheet<void>(
      context,
      (sheetContext) => AppDropMenu(
        title: context.l10n.quickActionsTitle.toUpperCase(),
        items: <AppDropMenuItem>[
          AppDropMenuItem(
            label: context.l10n.quickActionCreateGroup,
            onTap: () {
              AppNavigator.push(context, (_) => const CreateGroupPage());
            },
          ),
          AppDropMenuItem(
            label: context.l10n.quickActionJoinGroup,
            onTap: () {
              AppNavigator.push(context, (_) => const GroupListPage());
            },
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow.contact({
    required this.seed,
    required this.title,
    required this.onTap,
  }) : isGroup = false;

  const _FriendRow.group({required this.onTap})
      : isGroup = true,
        seed = 'group',
        title = 'group';

  final bool isGroup;
  final String seed;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.border),
        ),
      ),
      child: AppListTile(
        title: title,
        leading: isGroup
            ? AppSurface(
                padding: EdgeInsets.zero,
                color: theme.colorScheme.secondaryContainer,
                radius: AwikiMeRadii.pill,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                child: Icon(
                  Icons.group,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 20,
                ),
              )
            : AvatarBadge(seed: seed, size: 32),
        onTap: onTap,
      ),
    );
  }
}

class _IndexRail extends StatelessWidget {
  const _IndexRail();

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    const letters = <String>[
      'A',
      'B',
      'C',
      'E',
      'F',
      'G',
      'H',
      'I',
      'J',
      'M',
      'S',
      '#'
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: letters
          .map(
            (letter) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                letter,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: letter == 'E' ? FontWeight.w700 : FontWeight.w500,
                  color: letter == 'E' ? theme.primaryDark : theme.tertiaryText,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FriendListItem {
  const _FriendListItem.contact({
    required this.title,
    required this.did,
  }) : isGroup = false;

  const _FriendListItem.group()
      : isGroup = true,
        title = null,
        did = null;

  final bool isGroup;
  final String? title;
  final String? did;
}
