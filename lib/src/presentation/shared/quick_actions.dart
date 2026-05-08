import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../../l10n/l10n.dart';
import '../friends/friends_provider.dart';
import '../group/create_group_page.dart';
import '../group/group_list_page.dart';
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
        if (includeAddFriend)
          AppDropMenuItem(
            label: l10n.quickActionAddFriend,
            onTap: () {
              showAddFriendDialog(rootContext, ref);
            },
          ),
      ],
    ),
  );
}

void showAddFriendDialog(BuildContext context, WidgetRef ref) {
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
            try {
              final status = await ref
                  .read(friendsProvider.notifier)
                  .checkRelationship(value);
              if (status != null && status.relationship != 'none') {
                return;
              }
              await ref.read(friendsProvider.notifier).follow(value);
            } catch (error) {
              ref
                  .read(uiFeedbackProvider.notifier)
                  .showError(AppMessage.fromError(error));
            }
          },
          child: Text(context.l10n.commonSend),
        ),
      ],
    ),
  );
}
