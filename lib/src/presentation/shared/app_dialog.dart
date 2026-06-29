import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';
import 'responsive_layout.dart';

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

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final mediaSize = MediaQuery.sizeOf(context);
    final maxDialogWidth = responsive.isPhone
        ? mediaSize.width - horizontalPadding * 2
        : maxWidth;
    final maxDialogHeight = mediaSize.height * maxHeightFraction;
    return SafeArea(
      minimum: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
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
                  borderRadius ?? BorderRadius.circular(responsive.radius(16)),
              boxShadow: theme.overlayShadow,
            ),
            child: ClipRRect(
              borderRadius:
                  borderRadius ?? BorderRadius.circular(responsive.radius(16)),
              clipBehavior: clipBehavior,
              child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
