import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

class AwikiMeTopBar extends StatelessWidget {
  const AwikiMeTopBar({
    super.key,
    required this.title,
    required this.leading,
    this.trailing,
    this.leadingWidth = 30,
    this.trailingWidth = 30,
    this.padding = const EdgeInsets.only(bottom: 18),
  });

  final String title;
  final Widget leading;
  final Widget? trailing;
  final double leadingWidth;
  final double trailingWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: leadingWidth,
            height: responsive.iconLg,
            child: Center(child: leading),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AwikiMeTextStyles.navTitle.copyWith(
                fontSize: responsive.titleXl,
              ),
            ),
          ),
          SizedBox(
            width: trailingWidth,
            height: responsive.iconLg,
            child: Center(child: trailing ?? const SizedBox.shrink()),
          ),
        ],
      ),
    );
  }
}

class AwikiMeShellTopBar extends StatelessWidget {
  const AwikiMeShellTopBar({
    super.key,
    required this.title,
    this.onSettingsTap,
    this.onQuickActionsTap,
  });

  final String title;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onQuickActionsTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AwikiMeTopBar(
      title: title,
      padding: EdgeInsets.zero,
      leading: onSettingsTap == null
          ? const SizedBox.shrink()
          : TopBarActionButton(
              onTap: onSettingsTap,
              child: AwikiAssetIcon(
                assetName: 'assets/icons/icon_settings.svg',
                size: responsive.iconLg,
                color: theme.title,
              ),
            ),
      trailing: onQuickActionsTap == null
          ? const SizedBox.shrink()
          : TopBarActionButton(
              onTap: onQuickActionsTap,
              child: AwikiAssetIcon(
                assetName: 'assets/icons/icon_add.svg',
                size: responsive.iconLg,
                color: theme.title,
              ),
            ),
    );
  }
}

class AwikiMeShellTabPage extends StatelessWidget {
  const AwikiMeShellTabPage({
    super.key,
    required this.title,
    required this.child,
    this.onSettingsTap,
    this.onQuickActionsTap,
  });

  final String title;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onQuickActionsTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final innerPadding = responsive.tabInnerPadding;
    return Column(
      children: <Widget>[
        Padding(
          padding: responsive.scaledInsets(innerPadding.copyWith(bottom: 8)),
          child: AwikiMeShellTopBar(
            title: title,
            onSettingsTap: onSettingsTap,
            onQuickActionsTap: onQuickActionsTap,
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
