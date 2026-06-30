import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';
import 'responsive_layout.dart';
import 'widgets/app_widgets.dart';

class AppDialogScaffold extends StatelessWidget {
  const AppDialogScaffold({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.maxHeightFraction = 0.86,
    this.horizontalPadding = 16,
    this.verticalPadding = 20,
    this.borderRadius,
    this.padding,
    this.surfaceColor,
    this.clipBehavior = Clip.antiAlias,
    this.avoidViewInsets = false,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeightFraction;
  final double horizontalPadding;
  final double verticalPadding;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final Color? surfaceColor;
  final Clip clipBehavior;
  final bool avoidViewInsets;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final viewInsets = avoidViewInsets
        ? MediaQuery.viewInsetsOf(context)
        : EdgeInsets.zero;
    final maxDialogWidth = responsive.isPhone
        ? mediaSize.width - horizontalPadding * 2
        : maxWidth;
    final availableHeight =
        mediaSize.height -
        verticalPadding * 2 -
        viewInsets.top -
        viewInsets.bottom;
    final maxDialogHeight =
        availableHeight.clamp(0.0, mediaSize.height).toDouble() *
        maxHeightFraction;
    return SafeArea(
      minimum: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: viewInsets.top,
          bottom: viewInsets.bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceColor ?? theme.surface,
                borderRadius:
                    borderRadius ??
                    BorderRadius.circular(responsive.radius(16)),
                boxShadow: theme.overlayShadow,
              ),
              child: ClipRRect(
                borderRadius:
                    borderRadius ??
                    BorderRadius.circular(responsive.radius(16)),
                clipBehavior: clipBehavior,
                child: Padding(
                  padding: padding ?? EdgeInsets.zero,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onClose,
    this.closeLabel = '关闭',
    this.isCloseEnabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onClose;
  final String closeLabel;
  final bool isCloseEnabled;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final subtitleText = subtitle?.trim();
    return Row(
      crossAxisAlignment: subtitleText == null || subtitleText.isEmpty
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          SizedBox(width: responsive.spacing(10)),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.title,
                  fontSize: responsive.titleLg,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
              if (subtitleText != null && subtitleText.isNotEmpty) ...<Widget>[
                SizedBox(height: responsive.spacing(6)),
                Text(
                  subtitleText,
                  style: TextStyle(
                    color: theme.secondaryText,
                    fontSize: responsive.bodySm,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(width: responsive.spacing(10)),
        AppIconButton(
          onPressed: isCloseEnabled ? onClose : null,
          semanticLabel: closeLabel,
          tooltip: closeLabel,
          size: responsive.displayScaled(32),
          backgroundColor: const Color(0xFFF5F7FB),
          borderColor: const Color(0xFFE4E9F2),
          borderRadius: BorderRadius.circular(responsive.radius(10)),
          child: Icon(
            CupertinoIcons.xmark,
            color: theme.secondaryText,
            size: responsive.iconSm,
          ),
        ),
      ],
    );
  }
}
