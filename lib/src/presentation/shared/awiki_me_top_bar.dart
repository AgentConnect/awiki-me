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
    this.titleColor,
    this.titleFontSize,
    this.titleFontWeight,
  });

  final String title;
  final Widget leading;
  final Widget? trailing;
  final double leadingWidth;
  final double trailingWidth;
  final EdgeInsets padding;
  final Color? titleColor;
  final double? titleFontSize;
  final FontWeight? titleFontWeight;

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
                color: titleColor,
                fontSize: titleFontSize ?? responsive.titleXl,
                fontWeight: titleFontWeight,
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
    final responsive = context.awikiResponsive;
    const titleColor = Color(0xFF2B3340);
    const actionColor = Color(0xFF5F6875);
    return AwikiMeTopBar(
      title: title,
      padding: EdgeInsets.zero,
      titleColor: titleColor,
      titleFontSize: responsive.titleXl - responsive.displayScaled(1),
      titleFontWeight: FontWeight.w500,
      leading: onSettingsTap == null
          ? const SizedBox.shrink()
          : TopBarActionButton(
              onTap: onSettingsTap,
              semanticsIdentifier: 'e2e-settings-button',
              semanticsLabel: '设置',
              child: AwikiAssetIcon(
                assetName: 'assets/icons/icon_settings.svg',
                size: responsive.iconLg,
                color: actionColor,
              ),
            ),
      trailing: onQuickActionsTap == null
          ? const SizedBox.shrink()
          : TopBarActionButton(
              onTap: onQuickActionsTap,
              semanticsIdentifier: 'e2e-quick-actions-button',
              semanticsLabel: '更多操作',
              child: AwikiAssetIcon(
                assetName: 'assets/icons/icon_add.svg',
                size: responsive.iconLg,
                color: actionColor,
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
