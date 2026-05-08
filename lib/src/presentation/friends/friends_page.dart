import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/conversation_summary.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../app_shell/providers/selected_conversation_provider.dart';
import '../chat/chat_page.dart';
import '../chat/chat_provider.dart';
import '../conversation_list/conversation_provider.dart';
import '../group/group_list_page.dart';
import '../profile/profile_provider.dart';
import '../settings/settings_page.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/awiki_me_top_bar.dart';
import '../shared/formatters/display_formatters.dart';
import '../shared/quick_actions.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'friends_provider.dart';

class FriendsPage extends ConsumerWidget {
  const FriendsPage({super.key, this.embedded = false, this.bottomInset = 120});

  final bool embedded;
  final double bottomInset;

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
    if (context.awikiResponsive.supportsTwoPane) {
      ref
          .read(selectedConversationProvider.notifier)
          .selectConversation(targetConv);
      ref.read(shellTabProvider.notifier).setTab(0);
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
    final responsive = context.awikiResponsive;
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

    final rows = items
        .map(
          (item) => item.isGroup
              ? _FriendRow.group(
                  onTap: () =>
                      AppNavigator.push(context, (_) => const GroupListPage()),
                )
              : _FriendRow.contact(
                  seed: item.title!,
                  title: item.title!,
                  onTap: () =>
                      _sendMessage(context, ref, item.did!, item.title!),
                ),
        )
        .toList();

    if (!responsive.supportsTwoPane) {
      final mobileContent = AwikiMeShellTabPage(
        title: context.l10n.friendsTitle,
        onSettingsTap: () => AppNavigator.pushWithoutAnimation(
          context,
          (_) => const SettingsPage(),
        ),
        onQuickActionsTap: () => showCommonQuickActionsMenu(context, ref),
        child: ListView.separated(
          padding: EdgeInsets.only(bottom: embedded ? bottomInset : 120),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox.shrink(),
          itemBuilder: (context, index) => rows[index],
        ),
      );
      if (embedded) {
        return mobileContent;
      }
      return mobileContent;
    }

    final content = AwikiMeShellTabPage(
      title: context.l10n.friendsTitle,
      onSettingsTap: () => AppNavigator.pushWithoutAnimation(
        context,
        (_) => const SettingsPage(),
      ),
      onQuickActionsTap: () => showCommonQuickActionsMenu(context, ref),
      child: Padding(
        padding: EdgeInsets.only(bottom: embedded ? bottomInset : 120),
        child: DecoratedBox(
          decoration: BoxDecoration(color: theme.background),
          child: Stack(
            children: <Widget>[
              ListView.separated(
                padding: EdgeInsets.only(right: responsive.spacing(24)),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox.shrink(),
                itemBuilder: (context, index) => rows[index],
              ),
              Positioned(
                top: 0,
                right: responsive.spacing(8),
                bottom: 0,
                child: const _IndexRail(),
              ),
            ],
          ),
        ),
      ),
    );

    if (embedded) {
      return content;
    }

    return AwikiAdaptiveScaffold(
      maxWidth: responsive.supportsTwoPane ? double.infinity : 920,
      child: content,
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
    final responsive = context.awikiResponsive;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.tabContentHorizontalPadding,
        ),
        child: AppListTile(
          horizontalPadding: 0,
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
                    CupertinoIcons.person_3_fill,
                    color: theme.colorScheme.onSecondaryContainer,
                    size: 20,
                  ),
                )
              : AvatarBadge(seed: seed, size: 32),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _IndexRail extends StatelessWidget {
  const _IndexRail();

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
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
      '#',
    ];
    final fontSize = responsive.isPhone ? 11.0 : 8.0;
    final itemSpacing = responsive.isPhone ? 3.0 : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: letters
                  .map(
                    (letter) => Padding(
                      padding: EdgeInsets.symmetric(vertical: itemSpacing),
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: letter == 'E'
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: letter == 'E'
                              ? theme.primaryDark
                              : theme.tertiaryText,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _FriendListItem {
  const _FriendListItem.contact({required this.title, required this.did})
    : isGroup = false;

  const _FriendListItem.group() : isGroup = true, title = null, did = null;

  final bool isGroup;
  final String? title;
  final String? did;
}
