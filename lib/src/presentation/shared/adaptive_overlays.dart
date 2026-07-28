import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';

class CompactActionSheet extends StatelessWidget {
  const CompactActionSheet({
    super.key,
    required this.child,
    this.maxWidth = 520,
    this.horizontalMargin = 12,
  });

  final Widget child;
  final double maxWidth;
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    const radius = BorderRadius.all(Radius.circular(14));
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(horizontalMargin, 8, horizontalMargin, 8),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: radius,
              boxShadow: theme.overlayShadow,
            ),
            child: ClipRRect(borderRadius: radius, child: child),
          ),
        ),
      ),
    );
  }
}

class CompactBottomSheet extends StatelessWidget {
  const CompactBottomSheet({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.maxHeightFraction = 0.94,
    this.horizontalMargin = 12,
    this.avoidKeyboard = true,
    this.showGrabHandle = true,
    this.surfaceColor,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeightFraction;
  final double horizontalMargin;
  final bool avoidKeyboard;
  final bool showGrabHandle;
  final Color? surfaceColor;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = context.awikiTheme;
    final keyboardInset = avoidKeyboard ? media.viewInsets.bottom : 0.0;
    final safeHeight = math.max(
      0,
      media.size.height - media.padding.top - keyboardInset - 12,
    );
    const radius = BorderRadius.vertical(top: Radius.circular(16));
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        bottom: keyboardInset == 0,
        minimum: EdgeInsets.symmetric(horizontal: horizontalMargin),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: safeHeight * maxHeightFraction,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceColor ?? theme.surface,
                borderRadius: radius,
                boxShadow: theme.overlayShadow,
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (showGrabHandle)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Container(
                          key: const Key('compact-bottom-sheet-grab-handle'),
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: theme.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    Flexible(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
