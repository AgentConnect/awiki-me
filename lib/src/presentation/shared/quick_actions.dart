import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show PopupMenuEntry, RelativeRect, RoundedRectangleBorder, showMenu;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;

import '../../app/app_router.dart';
import '../../l10n/l10n.dart';
import '../app_shell/providers/navigation_provider.dart';
import '../friends/friends_navigation_provider.dart';
import '../group/create_group_dialog.dart';
import 'awiki_me_design.dart';
import 'identity_flow.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

Future<void> showCommonQuickActionsMenu(
  BuildContext context,
  WidgetRef ref, {
  bool includeFollowContact = true,
  bool anchoredToTrigger = false,
}) async {
  final l10n = context.l10n;
  final rootContext = context;
  final items = <AppDropMenuItem>[
    AppDropMenuItem(
      buttonKey: const Key('quick-action-start-conversation'),
      label: l10n.quickActionStartConversation,
      icon: CupertinoIcons.chat_bubble,
      semanticsIdentifier: 'e2e-start-conversation-menu-item',
      onTap: () => showStartConversationDialog(rootContext, ref),
    ),
    AppDropMenuItem(
      buttonKey: const Key('quick-action-create-group'),
      label: l10n.quickActionCreateGroup,
      icon: CupertinoIcons.person_2,
      onTap: () => showCreateGroupDialog(rootContext, ref),
    ),
    AppDropMenuItem(
      buttonKey: const Key('quick-action-join-group'),
      label: l10n.quickActionJoinGroup,
      icon: CupertinoIcons.plus,
      onTap: () {
        ref.read(friendsWorkspaceNavigationProvider.notifier).showGroups();
        ref
            .read(shellDestinationProvider.notifier)
            .selectForLayout(
              ShellDestination.contacts,
              expanded: rootContext.awikiResponsive.usesDesktopLayout,
            );
      },
    ),
    if (includeFollowContact)
      AppDropMenuItem(
        buttonKey: const Key('quick-action-follow-contact'),
        label: l10n.quickActionFollowContact,
        icon: CupertinoIcons.person_add,
        onTap: () => showFollowIdentityDialog(rootContext, ref),
      ),
  ];

  if (anchoredToTrigger && context.awikiResponsive.isExpanded) {
    final shown = await _showAnchoredQuickActionsMenu(
      context,
      items: items,
      semanticLabel: l10n.quickActionsTitle,
    );
    if (shown) {
      return;
    }
    if (!context.mounted) {
      return;
    }
  }

  await AppNavigator.showSheet<void>(
    context,
    (_) => AppDropMenu(title: l10n.quickActionsTitle, items: items),
  );
}

void showFollowContactDialog(BuildContext context, WidgetRef ref) {
  showFollowIdentityDialog(context, ref);
}

Future<bool> _showAnchoredQuickActionsMenu(
  BuildContext context, {
  required List<AppDropMenuItem> items,
  required String semanticLabel,
}) async {
  final anchor = context.findRenderObject();
  final overlay = Overlay.of(
    context,
    rootOverlay: true,
  ).context.findRenderObject();
  if (anchor is! RenderBox || overlay is! RenderBox) {
    return false;
  }

  final responsive = context.awikiResponsive;
  final theme = context.awikiTheme;
  final menuWidth = responsive.displayScaled(200);
  final anchorTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorRect = anchorTopLeft & anchor.size;
  final maxLeft = overlay.size.width - menuWidth - 8;
  final menuLeft = (anchorRect.right - menuWidth)
      .clamp(8.0, maxLeft)
      .toDouble();
  final menuTop = anchorRect.bottom + responsive.displayScaled(6);
  final position = RelativeRect.fromLTRB(
    menuLeft,
    menuTop,
    overlay.size.width - menuLeft - menuWidth,
    overlay.size.height - menuTop,
  );

  final selected = await showMenu<int>(
    context: context,
    useRootNavigator: true,
    position: position,
    semanticLabel: semanticLabel,
    requestFocus: true,
    color: theme.surface,
    surfaceTintColor: CupertinoColors.transparent,
    shadowColor: theme.title.withValues(alpha: 0.22),
    elevation: 16,
    menuPadding: EdgeInsets.all(responsive.displayScaled(5)),
    constraints: BoxConstraints.tightFor(width: menuWidth),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(responsive.displayScaled(12)),
      side: BorderSide(color: theme.border),
    ),
    clipBehavior: Clip.antiAlias,
    items: <PopupMenuEntry<int>>[
      for (var index = 0; index < items.length; index++)
        _QuickActionPopupMenuEntry(
          key: items[index].buttonKey,
          value: index,
          item: items[index],
        ),
    ],
  );
  if (selected == null || !context.mounted) {
    return true;
  }
  await items[selected].onTap?.call();
  return true;
}

class _QuickActionPopupMenuEntry extends PopupMenuEntry<int> {
  const _QuickActionPopupMenuEntry({
    super.key,
    required this.value,
    required this.item,
  });

  final int value;
  final AppDropMenuItem item;

  @override
  double get height => 36;

  @override
  bool represents(int? value) => this.value == value;

  @override
  State<_QuickActionPopupMenuEntry> createState() =>
      _QuickActionPopupMenuEntryState();
}

class _QuickActionPopupMenuEntryState
    extends State<_QuickActionPopupMenuEntry> {
  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final item = widget.item;
    return Semantics(
      role: SemanticsRole.menuItem,
      enabled: item.onTap != null,
      button: true,
      child: AppPressable(
        onTap: item.onTap == null
            ? null
            : () => Navigator.of(context).pop<int>(widget.value),
        semanticLabel: item.label,
        semanticsIdentifier: item.semanticsIdentifier,
        borderRadius: BorderRadius.circular(responsive.displayScaled(8)),
        hoverColor: theme.title.withValues(alpha: 0.05),
        pressedColor: theme.title.withValues(alpha: 0.10),
        child: SizedBox(
          height: responsive.displayScaled(36),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.displayScaled(10),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  item.icon,
                  size: responsive.displayScaled(16),
                  color: theme.secondaryText,
                ),
                SizedBox(width: responsive.displayScaled(10)),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: responsive.displayScaled(13),
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
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
