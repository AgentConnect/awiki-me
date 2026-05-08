import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../awiki_me_design.dart';
import '../responsive_layout.dart';

class TopBarActionButton extends StatelessWidget {
  const TopBarActionButton({super.key, required this.child, this.onTap});

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

class AwikiAssetIcon extends StatelessWidget {
  const AwikiAssetIcon({
    super.key,
    required this.assetName,
    this.size = 24,
    this.color,
  });

  final String assetName;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetName,
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
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
    final responsive = context.awikiResponsive;
    return Container(
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AwikiMeRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: responsive.metaSm,
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
    final responsive = context.awikiResponsive;
    return Padding(
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 16),
      ),
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
  const AppDropMenu({super.key, this.title, required this.items});

  final String? title;
  final List<AppDropMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: responsive.scaledInsets(const EdgeInsets.all(16)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(responsive.radius(24)),
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
                    padding: responsive.scaledInsets(
                      const EdgeInsets.fromLTRB(24, 18, 24, 14),
                    ),
                    child: Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: responsive.metaSm,
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
    final responsive = context.awikiResponsive;
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
        height: responsive.isPhone ? 68 : responsive.scaled(56),
        child: Center(
          child: item.icon == null
              ? Text(
                  item.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: responsive.titleLg,
                    fontWeight: item.highlighted || item.destructive
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: foregroundColor,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      item.icon,
                      size: responsive.iconMd,
                      color: foregroundColor,
                    ),
                    SizedBox(width: responsive.spacing(12)),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: responsive.titleLg,
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
    this.showLabel = true,
    this.prefix,
    this.backgroundColor,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final bool enabled;
  final bool multiline;
  final TextInputType? keyboardType;
  final bool showLabel;
  final Widget? prefix;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final textField = CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      decoration: null,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 5 : 1,
      textAlign: TextAlign.left,
      keyboardType: keyboardType,
      padding: multiline
          ? EdgeInsets.symmetric(vertical: responsive.spacing(10))
          : EdgeInsets.zero,
      enabled: enabled,
      style: TextStyle(fontSize: responsive.bodyMd, color: theme.title),
      placeholderStyle: TextStyle(
        fontSize: responsive.bodyMd,
        color: theme.secondaryText,
      ),
    );
    return AppSurface(
      color: backgroundColor ?? theme.subtleSurface,
      padding: responsive.scaledInsets(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (showLabel) ...<Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w600,
                color: theme.secondaryText,
              ),
            ),
            SizedBox(height: responsive.spacing(6)),
          ],
          if (multiline)
            textField
          else
            SizedBox(
              height: responsive.compactControlHeight,
              child: Row(
                children: <Widget>[
                  if (prefix != null) ...<Widget>[
                    prefix!,
                    SizedBox(width: responsive.spacing(10)),
                  ],
                  Expanded(child: Center(child: textField)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          constraints: BoxConstraints(minHeight: responsive.controlHeight),
          padding: EdgeInsets.symmetric(vertical: responsive.spacing(10)),
          decoration: BoxDecoration(
            color: theme.primary,
            borderRadius: BorderRadius.circular(
              responsive.radius(AwikiMeRadii.sm),
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              strutStyle: StrutStyle(
                fontSize: responsive.bodyMd,
                height: 1,
                forceStrutHeight: true,
              ),
              style: TextStyle(
                color: theme.primaryForeground,
                fontSize: responsive.bodyMd,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Container(
          constraints: BoxConstraints(minHeight: responsive.controlHeight),
          padding: EdgeInsets.symmetric(vertical: responsive.spacing(10)),
          decoration: BoxDecoration(
            color: theme.warningContainer,
            borderRadius: BorderRadius.circular(
              responsive.radius(AwikiMeRadii.sm),
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              strutStyle: StrutStyle(
                fontSize: responsive.bodyMd,
                height: 1,
                forceStrutHeight: true,
              ),
              style: TextStyle(
                color: theme.primaryDark,
                fontSize: responsive.bodyMd,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppDangerButton extends StatelessWidget {
  const AppDangerButton({super.key, required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: AppSurface(
          padding: EdgeInsets.symmetric(vertical: responsive.spacing(10)),
          color: theme.dangerContainer,
          radius: AwikiMeRadii.sm,
          constraints: BoxConstraints(minHeight: responsive.controlHeight),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              strutStyle: StrutStyle(
                fontSize: responsive.bodyMd,
                height: 1,
                forceStrutHeight: true,
              ),
              style: TextStyle(
                color: theme.danger,
                fontSize: responsive.bodyMd,
                height: 1,
                fontWeight: FontWeight.w700,
              ),
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
    this.iconAsset,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final String? iconAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AppSurface(
        padding: responsive.scaledInsets(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        color: theme.subtleSurface,
        radius: 12,
        child: Row(
          children: <Widget>[
            if (iconAsset != null)
              AwikiAssetIcon(
                assetName: iconAsset!,
                color: theme.primaryDark,
                size: responsive.iconSm,
              )
            else
              Icon(icon, color: theme.primaryDark, size: responsive.iconSm),
            SizedBox(width: responsive.spacing(8)),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: responsive.bodySm,
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
          SizedBox(height: context.awikiResponsive.spacing(8)),
          Text(
            subtitle,
            style: AwikiMeTextStyles.cardSubtitle.copyWith(
              fontSize: context.awikiResponsive.bodySm,
            ),
          ),
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
    this.horizontalPadding,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final double? horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final content = Padding(
      padding: responsive.scaledInsets(
        EdgeInsets.symmetric(horizontal: horizontalPadding ?? 16, vertical: 16),
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            SizedBox(width: responsive.spacing(16)),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: responsive.bodyMd,
                    fontWeight: FontWeight.w700,
                    color: destructive ? theme.danger : theme.title,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  SizedBox(height: responsive.spacing(2)),
                  Text(
                    subtitle!,
                    style: AwikiMeTextStyles.cardSubtitle.copyWith(
                      fontSize: responsive.bodySm,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: responsive.spacing(12)),
          trailing ??
              AwikiAssetIcon(
                assetName: 'assets/icons/icon_right.svg',
                size: responsive.iconSm,
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
