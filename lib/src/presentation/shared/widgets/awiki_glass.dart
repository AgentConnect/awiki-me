// [INPUT]: Semantic theme tokens and responsive metrics.
// [OUTPUT]: Phone liquid-glass surfaces, glow canvas and shared bar controls.
// [POS]: Presentation-only material shared by compact navigation, headers and cards.

import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

import '../awiki_me_design.dart';
import '../responsive_layout.dart';
import 'app_widgets.dart';

/// Blur radius of the reference's flat glass (`blur(22px) saturate(…)`).
const double awikiGlassBlurSigma = 11;

/// Reference `--list-bg`: white in light, graphite canvas in dark.
Color awikiCompactListBackground(BuildContext context) {
  final theme = context.awikiTheme;
  return theme.isDark ? theme.background : theme.surface;
}

/// Page canvas carrying the reference's two soft brand glows so glass above
/// it has light to bend. Content still owns its own scrolling.
class AwikiGlassBackdrop extends StatelessWidget {
  const AwikiGlassBackdrop({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return DecoratedBox(
      key: const Key('awiki-glass-backdrop'),
      decoration: BoxDecoration(color: color ?? theme.background),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.84, -1),
            radius: 0.9,
            colors: <Color>[
              theme.glowPrimary,
              theme.glowPrimary.withValues(alpha: 0),
            ],
            stops: const <double>[0, 0.72],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1, -0.68),
              radius: 0.75,
              colors: <Color>[
                theme.glowSecondary,
                theme.glowSecondary.withValues(alpha: 0),
              ],
              stops: const <double>[0, 0.72],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One shared flat material: an even frosted fill and a hairline edge, with
/// no depth cues. Selected variants tint with the lens color.
class AwikiGlassSurface extends StatelessWidget {
  const AwikiGlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.selected = false,
    this.blur = true,
    this.padding,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool selected;
  final bool blur;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? theme.glassLens : theme.glass,
        borderRadius: borderRadius,
        border: Border.all(
          color: selected ? theme.glassEdgeActive : theme.glassEdge,
          width: 0.5,
        ),
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (!blur) {
      return decorated;
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: awikiGlassBlurSigma,
          sigmaY: awikiGlassBlurSigma,
        ),
        child: decorated,
      ),
    );
  }
}

/// Header back control: only the chevron, in the title color, inside a
/// 44-unit touch target.
class AwikiBackButton extends StatelessWidget {
  const AwikiBackButton({
    super.key,
    required this.onTap,
    required this.semanticsLabel,
    this.semanticsIdentifier,
  });

  final VoidCallback? onTap;
  final String semanticsLabel;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return TopBarActionButton(
      onTap: onTap,
      semanticsLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      borderRadius: BorderRadius.circular(22),
      child: Icon(
        CupertinoIcons.chevron_left,
        size: responsive.isPhone ? 22 : responsive.iconMd,
        color: context.awikiTheme.title,
      ),
    );
  }
}

/// Bar "+" action: a thin circle whose diameter follows the header title so
/// the control reads as part of the title bar rather than a filled button.
class AwikiCircledPlusButton extends StatelessWidget {
  const AwikiCircledPlusButton({
    super.key,
    required this.onTap,
    required this.semanticsLabel,
    this.semanticsIdentifier,
    this.titleFontSize,
  });

  final VoidCallback? onTap;
  final String semanticsLabel;
  final String? semanticsIdentifier;
  final double? titleFontSize;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final fontSize =
        titleFontSize ??
        (responsive.isPhone ? 16 : responsive.displayScaled(14));
    final diameter = MediaQuery.textScalerOf(context).scale(fontSize * 1.125);
    final color = context.awikiTheme.title;
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticsLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: semanticsLabel,
      button: true,
      enabled: onTap != null,
      scaleOnPress: true,
      pressedScale: 0.9,
      borderRadius: BorderRadius.circular(22),
      builder: (context, state, child) {
        final active = state.pressed || state.hovered;
        return SizedBox.square(
          dimension: TopBarActionButton.minimumSize,
          child: Center(
            child: AnimatedContainer(
              key: const Key('awiki-circled-plus'),
              duration: const Duration(milliseconds: 150),
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? color.withValues(alpha: 0.10)
                    : color.withValues(alpha: 0),
                border: Border.all(color: color, width: 1),
              ),
              child: child,
            ),
          ),
        );
      },
      child: Center(
        child: CustomPaint(
          size: Size.square(diameter * 0.56),
          painter: _PlusPainter(
            color: color,
            strokeWidth: (diameter * 0.56) / 20 * 2.4,
          ),
        ),
      ),
    );
  }
}

class _PlusPainter extends CustomPainter {
  const _PlusPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final inset = size.width * 0.2;
    final mid = size.width / 2;
    canvas
      ..drawLine(Offset(mid, inset), Offset(mid, size.height - inset), paint)
      ..drawLine(Offset(inset, mid), Offset(size.width - inset, mid), paint);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// Height the floating compact tab bar covers at the bottom of root pages.
/// Scrollable root lists add it to their bottom padding so their last rows
/// can scroll clear of the bar while content still flows underneath it.
class AwikiFloatingTabBarInset extends InheritedWidget {
  const AwikiFloatingTabBarInset({
    super.key,
    required this.inset,
    required super.child,
  });

  final double inset;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AwikiFloatingTabBarInset>()
          ?.inset ??
      0;

  @override
  bool updateShouldNotify(AwikiFloatingTabBarInset oldWidget) =>
      oldWidget.inset != inset;
}
