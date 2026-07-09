import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../l10n/l10n.dart';
import '../group/create_group_dialog.dart';
import '../group/group_list_page.dart';
import 'identity_flow.dart';
import 'widgets/app_widgets.dart';

Future<void> showCommonQuickActionsMenu(
  BuildContext context,
  WidgetRef ref, {
  bool includeFollowContact = true,
}) async {
  final l10n = context.l10n;
  final rootContext = context;
  await AppNavigator.showSheet<void>(
    context,
    (_) => AppDropMenu(
      title: l10n.quickActionsTitle.toUpperCase(),
      items: <AppDropMenuItem>[
        AppDropMenuItem(
          label: l10n.quickActionStartConversation,
          icon: CupertinoIcons.square_pencil,
          semanticsIdentifier: 'e2e-start-conversation-menu-item',
          onTap: () => showStartConversationDialog(rootContext, ref),
        ),
        AppDropMenuItem(
          label: l10n.quickActionCreateGroup,
          icon: CupertinoIcons.person_3_fill,
          onTap: () => showCreateGroupDialog(rootContext, ref),
        ),
        AppDropMenuItem(
          label: l10n.quickActionJoinGroup,
          icon: CupertinoIcons.link,
          onTap: () =>
              AppNavigator.push(rootContext, (_) => const GroupListPage()),
        ),
        if (includeFollowContact)
          AppDropMenuItem(
            label: l10n.quickActionFollowContact,
            icon: CupertinoIcons.person_badge_plus,
            onTap: () => showFollowIdentityDialog(rootContext, ref),
          ),
      ],
    ),
  );
}

void showFollowContactDialog(BuildContext context, WidgetRef ref) {
  showFollowIdentityDialog(context, ref);
}
