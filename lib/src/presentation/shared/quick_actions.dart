import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show
        PopupMenuEntry,
        RelativeRect,
        RoundedRectangleBorder,
        showGeneralDialog,
        showMenu;
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

  if (anchoredToTrigger) {
    final shown = context.awikiResponsive.isExpanded
        ? await _showAnchoredQuickActionsMenu(
            context,
            items: items,
            semanticLabel: l10n.quickActionsTitle,
          )
        : await _showCompactAnchoredQuickActionsMenu(
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

Future<bool> _showCompactAnchoredQuickActionsMenu(
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

  final anchorTopLeft = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final anchorRect = anchorTopLeft & anchor.size;
  final theme = context.awikiTheme;
  final selected = await showGeneralDialog<int>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: semanticLabel,
    barrierColor: theme.title.withValues(alpha: 0.06),
    transitionDuration: AwikiMeMotion.standard,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _CompactAnchoredQuickActionsMenu(
        anchorRect: anchorRect,
        items: items,
        semanticLabel: semanticLabel,
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: AwikiMeMotion.emphasized,
        ),
        child: child,
      );
    },
  );
  if (selected == null || !context.mounted) {
    return true;
  }
  await items[selected].onTap?.call();
  return true;
}

class _CompactAnchoredQuickActionsMenu extends StatelessWidget {
  const _CompactAnchoredQuickActionsMenu({
    required this.anchorRect,
    required this.items,
    required this.semanticLabel,
  });

  final Rect anchorRect;
  final List<AppDropMenuItem> items;
  final String semanticLabel;

  static const double _horizontalMargin = 8;
  static const double _targetMenuWidth = 196;
  static const double _rowHeight = 52;
  static const double _pointerWidth = 20;
  static const double _pointerHeight = 10;
  static const double _menuGap = 10;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final theme = context.awikiTheme;
    final menuWidth = math
        .min(
          _targetMenuWidth,
          math.max(0, screenSize.width - (_horizontalMargin * 2)),
        )
        .toDouble();
    final menuHeight = _rowHeight * items.length;
    final menuLeft = math.max(
      _horizontalMargin,
      screenSize.width - menuWidth - _horizontalMargin,
    );
    final maxMenuTop = math.max(
      safePadding.top + _horizontalMargin,
      screenSize.height - safePadding.bottom - menuHeight - _horizontalMargin,
    );
    final menuTop = (anchorRect.bottom + _menuGap)
        .clamp(safePadding.top + _horizontalMargin, maxMenuTop)
        .toDouble();
    final pointerCenter = (anchorRect.center.dx - menuLeft)
        .clamp(18.0, menuWidth - 18)
        .toDouble();

    return Semantics(
      role: SemanticsRole.menu,
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: Stack(
        key: const Key('compact-quick-actions-overlay'),
        children: <Widget>[
          Positioned(
            left: menuLeft + pointerCenter - (_pointerWidth / 2),
            top: menuTop - _pointerHeight + 1,
            child: IgnorePointer(
              child: CustomPaint(
                key: const Key('compact-quick-actions-pointer'),
                size: const Size(_pointerWidth, _pointerHeight),
                painter: _QuickActionsPointerPainter(
                  fillColor: theme.surface,
                  borderColor: theme.border,
                ),
              ),
            ),
          ),
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: menuWidth,
            height: menuHeight,
            child: DecoratedBox(
              key: const Key('compact-quick-actions-menu'),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: BorderRadius.circular(AwikiMeRadii.sm),
                border: Border.all(color: theme.border),
                boxShadow: AwikiMeShadows.overlay,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AwikiMeRadii.sm - 1),
                child: Column(
                  children: <Widget>[
                    for (var index = 0; index < items.length; index++)
                      _CompactQuickActionRow(
                        item: items[index],
                        value: index,
                        showDivider: index < items.length - 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactQuickActionRow extends StatelessWidget {
  const _CompactQuickActionRow({
    required this.item,
    required this.value,
    required this.showDivider,
  });

  final AppDropMenuItem item;
  final int value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Semantics(
      role: SemanticsRole.menuItem,
      enabled: item.onTap != null,
      button: true,
      child: SizedBox(
        height: _CompactAnchoredQuickActionsMenu._rowHeight,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: AppPressable(
                key: item.buttonKey,
                onTap: item.onTap == null
                    ? null
                    : () => Navigator.of(
                        context,
                        rootNavigator: true,
                      ).pop<int>(value),
                semanticLabel: item.label,
                semanticsIdentifier: item.semanticsIdentifier,
                borderRadius: BorderRadius.circular(AwikiMeRadii.xs),
                hoverColor: theme.title.withValues(alpha: 0.05),
                pressedColor: AwikiMePalette.actionBlueSoft.withValues(
                  alpha: 0.72,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: <Widget>[
                      ExcludeSemantics(
                        child: Icon(
                          item.icon,
                          size: 20,
                          color: AwikiMePalette.actionBlue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AwikiMePalette.inkNeutral,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (showDivider)
              const Positioned(
                left: 48,
                right: 16,
                bottom: 0,
                height: 1,
                child: ColoredBox(color: AwikiMePalette.hairline),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsPointerPainter extends CustomPainter {
  const _QuickActionsPointerPainter({
    required this.fillColor,
    required this.borderColor,
  });

  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _QuickActionsPointerPainter oldDelegate) {
    return fillColor != oldDelegate.fillColor ||
        borderColor != oldDelegate.borderColor;
  }
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
