import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../l10n/l10n.dart';
import '../group/create_group_page.dart';
import '../group/group_list_page.dart';
import 'identity_flow.dart';
import 'widgets/app_widgets.dart';

Future<void> showCommonQuickActionsMenu(
  BuildContext context,
  WidgetRef ref, {
  bool includeAddFriend = true,
}) async {
  final l10n = context.l10n;
  final rootContext = context;
  await AppNavigator.showSheet<void>(
    context,
    (_) => AppDropMenu(
      title: l10n.quickActionsTitle.toUpperCase(),
      items: <AppDropMenuItem>[
        AppDropMenuItem(
          label: '发起新消息',
          icon: CupertinoIcons.square_pencil,
          onTap: () {
            showStartConversationDialog(rootContext, ref);
          },
        ),
        AppDropMenuItem(
          label: l10n.quickActionCreateGroup,
          icon: CupertinoIcons.person_3_fill,
          onTap: () {
            AppNavigator.push(rootContext, (_) => const CreateGroupPage());
          },
        ),
        AppDropMenuItem(
          label: l10n.quickActionJoinGroup,
          icon: CupertinoIcons.link,
          onTap: () {
            AppNavigator.push(rootContext, (_) => const GroupListPage());
          },
        ),
        if (includeAddFriend)
          AppDropMenuItem(
            label: l10n.quickActionAddFriend,
            icon: CupertinoIcons.person_badge_plus,
            onTap: () {
              showAddIdentityDialog(rootContext, ref);
            },
          ),
      ],
    ),
  );
}

void showAddFriendDialog(BuildContext context, WidgetRef ref) {
  showAddIdentityDialog(context, ref);
}
