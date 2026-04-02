import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../awiki_me_design.dart';

class TopBarActionButton extends StatelessWidget {
  const TopBarActionButton({
    super.key,
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

class AppCardSection extends StatelessWidget {
  const AppCardSection({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = AwikiMeColors.surface,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AwikiMeDecorations.card(context: context, color: color),
      padding: padding,
      child: child,
    );
  }
}

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AwikiMeInsets.lg),
    this.color,
    this.radius = AwikiMeRadii.md,
    this.margin,
    this.constraints,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double radius;
  final EdgeInsets? margin;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      constraints: constraints,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.awikiTheme.surface,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

class AppPill extends StatelessWidget {
  const AppPill({
    super.key,
    required this.label,
    this.backgroundColor = const Color(0xFFFFF4D6),
    this.foregroundColor = AwikiMeColors.primaryDark,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foregroundColor == AwikiMeColors.primaryDark
              ? theme.primaryDark
              : foregroundColor,
        ),
      ),
    );
  }
}

class AppSectionDivider extends StatelessWidget {
  const AppSectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: context.awikiTheme.border),
        ),
      ),
    );
  }
}

class AppDropMenuItem {
  const AppDropMenuItem({
    required this.label,
    this.onTap,
    this.icon,
    this.destructive = false,
    this.highlighted = false,
  });

  final String label;
  final FutureOr<void> Function()? onTap;
  final IconData? icon;
  final bool destructive;
  final bool highlighted;
}

class AppDropMenu extends StatelessWidget {
  const AppDropMenu({
    super.key,
    this.title,
    required this.items,
  });

  final String? title;
  final List<AppDropMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title != null && title!.trim().isNotEmpty) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
                    child: Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: theme.secondaryText,
                      ),
                    ),
                  ),
                  Container(height: 1, color: theme.border),
                ],
                for (var index = 0; index < items.length; index++) ...<Widget>[
                  _AppDropMenuButton(item: items[index]),
                  if (index != items.length - 1)
                    Container(height: 1, color: theme.border),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppDropMenuButton extends StatelessWidget {
  const _AppDropMenuButton({required this.item});

  final AppDropMenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    Color foregroundColor = theme.title;
    if (item.destructive) {
      foregroundColor = theme.alert;
    } else if (item.highlighted) {
      foregroundColor = theme.primary;
    }

    return GestureDetector(
      onTap: () async {
        Navigator.of(context).pop();
        await item.onTap?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 68,
        child: Center(
          child: item.icon == null
              ? Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: item.highlighted || item.destructive
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: foregroundColor,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(item.icon, size: 24, color: foregroundColor),
                    const SizedBox(width: 12),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: item.highlighted || item.destructive
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: foregroundColor,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.placeholder,
    this.enabled = true,
    this.multiline = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final bool enabled;
  final bool multiline;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return AppSurface(
      color: theme.background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            decoration: null,
            minLines: multiline ? 3 : 1,
            maxLines: multiline ? 5 : 1,
            textAlign: TextAlign.left,
            keyboardType: keyboardType,
            padding: const EdgeInsets.symmetric(vertical: 10),
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(AwikiMeRadii.sm),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.primaryForeground,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: theme.warningContainer,
            borderRadius: BorderRadius.circular(AwikiMeRadii.sm),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.primaryDark,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class AppDangerButton extends StatelessWidget {
  const AppDangerButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: AppSurface(
          padding: const EdgeInsets.symmetric(vertical: 16),
          color: theme.dangerContainer,
          radius: AwikiMeRadii.sm,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.danger,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class AppInlineLinkRow extends StatelessWidget {
  const AppInlineLinkRow({
    super.key,
    required this.label,
    this.icon = CupertinoIcons.link,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AppSurface(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: theme.subtleSurface,
        radius: 12,
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: theme.primaryDark,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppActionRow extends StatelessWidget {
  const AppActionRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      onTap: onTap,
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCardSection(
      color: context.awikiTheme.subtleSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: AwikiMeTextStyles.sectionTitle),
          const SizedBox(height: 8),
          Text(subtitle, style: AwikiMeTextStyles.cardSubtitle),
        ],
      ),
    );
  }
}

class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: destructive ? theme.danger : theme.title,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AwikiMeTextStyles.cardSubtitle),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing ??
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: onTap == null ? theme.border : theme.tertiaryText,
              ),
        ],
      ),
    );
    if (onTap == null) {
      return content;
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }
}
