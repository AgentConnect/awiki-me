import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import 'awiki_me_design.dart';
import 'awiki_me_semantic_icon.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

enum AwikiMeTopBarTitleLayout { centered, adaptive }

class AwikiMeTopBar extends StatelessWidget {
  const AwikiMeTopBar({
    super.key,
    required this.title,
    required this.leading,
    this.trailing,
    this.leadingWidth = 44,
    this.trailingWidth = 44,
    this.padding = const EdgeInsets.only(bottom: 18),
    this.titleColor,
    this.titleFontSize,
    this.titleFontWeight,
    this.titleLayout = AwikiMeTopBarTitleLayout.centered,
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
  final AwikiMeTopBarTitleLayout titleLayout;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final titleInset = leadingWidth > trailingWidth
        ? leadingWidth
        : trailingWidth;
    final resolvedTitleStyle = AwikiMeTextStyles.navTitle.copyWith(
      color: titleColor,
      fontSize: titleFontSize ?? responsive.titleXl,
      fontWeight: titleFontWeight,
    );
    return Padding(
      padding: padding,
      child: SizedBox(
        height: responsive.isPhone ? 52 : 44,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useCenteredTitle =
                titleLayout == AwikiMeTopBarTitleLayout.centered ||
                _canCenterTitle(
                  context,
                  maxWidth: constraints.maxWidth,
                  style: resolvedTitleStyle,
                );
            final titlePadding =
                titleLayout == AwikiMeTopBarTitleLayout.centered
                ? EdgeInsets.symmetric(horizontal: titleInset + 8)
                : useCenteredTitle
                ? EdgeInsets.zero
                : EdgeInsets.only(left: leadingWidth, right: trailingWidth);
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned.fill(
                  child: Padding(
                    padding: titlePadding,
                    child: Align(
                      alignment: useCenteredTitle
                          ? Alignment.center
                          : Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: useCenteredTitle
                            ? TextAlign.center
                            : TextAlign.left,
                        style: resolvedTitleStyle,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: leadingWidth,
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: leading,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: trailingWidth,
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _canCenterTitle(
    BuildContext context, {
    required double maxWidth,
    required TextStyle style,
  }) {
    if (titleLayout != AwikiMeTopBarTitleLayout.adaptive ||
        !maxWidth.isFinite) {
      return true;
    }
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout();
    final centeredLeft = (maxWidth - painter.width) / 2;
    final centeredRight = centeredLeft + painter.width;
    return centeredLeft >= leadingWidth &&
        centeredRight <= maxWidth - trailingWidth;
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
  final ValueChanged<BuildContext>? onQuickActionsTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    const titleColor = AwikiMePalette.inkNeutral;
    const actionColor = AwikiMePalette.mutedNeutral;
    return AwikiMeTopBar(
      title: title,
      padding: EdgeInsets.zero,
      titleColor: titleColor,
      titleFontSize: responsive.isPhone
          ? responsive.displayScaled(16)
          : responsive.displayScaled(14),
      titleFontWeight: FontWeight.w600,
      leading: onSettingsTap == null
          ? const SizedBox.shrink()
          : TopBarActionButton(
              onTap: onSettingsTap,
              semanticsIdentifier: 'e2e-settings-button',
              semanticsLabel: context.l10n.settingsTitle,
              child: AwikiMeSemanticIcon(
                role: AwikiMeIconRole.settings,
                size: responsive.iconLg,
                color: actionColor,
              ),
            ),
      trailing: onQuickActionsTap == null
          ? const SizedBox.shrink()
          : Builder(
              builder: (anchorContext) => TopBarActionButton(
                key: const Key('shell-quick-actions-button'),
                onTap: () => onQuickActionsTap!(anchorContext),
                semanticsIdentifier: 'e2e-quick-actions-button',
                semanticsLabel: context.l10n.commonMoreActions,
                child: AwikiMeSemanticIcon(
                  role: AwikiMeIconRole.add,
                  size: responsive.iconLg,
                  color: actionColor,
                ),
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
  final ValueChanged<BuildContext>? onQuickActionsTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final innerPadding = responsive.isPhone
        ? const EdgeInsets.symmetric(horizontal: 8)
        : responsive.tabInnerPadding;
    return ColoredBox(
      key: const Key('shell-tab-page-surface'),
      color: theme.surface,
      child: Column(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
              border: Border(bottom: BorderSide(color: theme.border)),
            ),
            child: Padding(
              padding: responsive.scaledInsets(innerPadding),
              child: AwikiMeShellTopBar(
                title: title,
                onSettingsTap: onSettingsTap,
                onQuickActionsTap: onQuickActionsTap,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
