import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'awiki_me_design.dart';
import 'display_scale.dart';

enum AwikiBreakpoint { phone, large }

class AwikiResponsiveInfo {
  const AwikiResponsiveInfo({
    required this.width,
    required this.breakpoint,
    this.displayScale = AwikiDisplayScale.normal,
  });

  factory AwikiResponsiveInfo.fromWidth(
    double width, {
    double displayScale = AwikiDisplayScale.normal,
  }) {
    return AwikiResponsiveInfo(
      width: width,
      breakpoint: AwikiBreakpoints.fromWidth(width),
      displayScale: AwikiDisplayScale.normalize(displayScale),
    );
  }

  final double width;
  final AwikiBreakpoint breakpoint;
  final double displayScale;

  bool get isPhone => breakpoint == AwikiBreakpoint.phone;

  bool get isLarge => breakpoint == AwikiBreakpoint.large;

  bool get isPad => isLarge;

  bool get isDesktop => isLarge;

  bool get supportsTwoPane => !isPhone;

  bool get isMacDesktop =>
      supportsTwoPane && defaultTargetPlatform == TargetPlatform.macOS;

  double get uiScale {
    final baseScale = switch (breakpoint) {
      AwikiBreakpoint.phone => 1.0,
      AwikiBreakpoint.large => 0.72,
    };
    return baseScale * displayScale;
  }

  double get spacingScale {
    final baseScale = switch (breakpoint) {
      AwikiBreakpoint.phone => 1.0,
      AwikiBreakpoint.large => 0.74,
    };
    return baseScale * displayScale;
  }

  double get radiusScale {
    final baseScale = switch (breakpoint) {
      AwikiBreakpoint.phone => 1.0,
      AwikiBreakpoint.large => 0.78,
    };
    return baseScale * displayScale;
  }

  double get _fontScale => displayScale;

  double get controlHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 50 * displayScale;
      case AwikiBreakpoint.large:
        return 36 * displayScale;
    }
  }

  double get compactControlHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 42 * displayScale;
      case AwikiBreakpoint.large:
        return 32 * displayScale;
    }
  }

  double get navBarHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 60 * displayScale;
      case AwikiBreakpoint.large:
        return 44 * displayScale;
    }
  }

  double get avatarSizeMd {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 44 * displayScale;
      case AwikiBreakpoint.large:
        return 36 * displayScale;
    }
  }

  double get titleLg {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 19 * _fontScale;
      case AwikiBreakpoint.large:
        return 16 * _fontScale;
    }
  }

  double get titleXl {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 20 * _fontScale;
      case AwikiBreakpoint.large:
        return 17 * _fontScale;
    }
  }

  double get bodyMd {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 16 * _fontScale;
      case AwikiBreakpoint.large:
        return 14 * _fontScale;
    }
  }

  double get bodySm {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 14 * _fontScale;
      case AwikiBreakpoint.large:
        return 12.5 * _fontScale;
    }
  }

  double get metaSm {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 12 * _fontScale;
      case AwikiBreakpoint.large:
        return 11.5 * _fontScale;
    }
  }

  double get iconSm {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 18 * displayScale;
      case AwikiBreakpoint.large:
        return 15 * displayScale;
    }
  }

  double get iconMd {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 23 * displayScale;
      case AwikiBreakpoint.large:
        return 19 * displayScale;
    }
  }

  double get iconLg {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 26 * displayScale;
      case AwikiBreakpoint.large:
        return 21 * displayScale;
    }
  }

  double scaled(double base) => base * uiScale;

  double displayScaled(double base) => base * displayScale;

  double spacing(double base) => base * spacingScale;

  double radius(double base) => base * radiusScale;

  EdgeInsets scaledInsets(EdgeInsets base) {
    return EdgeInsets.fromLTRB(
      base.left * spacingScale,
      base.top * spacingScale,
      base.right * spacingScale,
      base.bottom * spacingScale,
    );
  }

  double get contentMaxWidth {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return double.infinity;
      case AwikiBreakpoint.large:
        return 1120;
    }
  }

  double get formMaxWidth {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return double.infinity;
      case AwikiBreakpoint.large:
        return 420;
    }
  }

  EdgeInsets get pagePadding {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return const EdgeInsets.symmetric(horizontal: 16);
      case AwikiBreakpoint.large:
        return const EdgeInsets.symmetric(horizontal: 32);
    }
  }

  EdgeInsets get tabInnerPadding {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return const EdgeInsets.fromLTRB(22, 0, 22, 0);
      case AwikiBreakpoint.large:
        return const EdgeInsets.fromLTRB(18, 18, 18, 0);
    }
  }

  double get tabContentHorizontalPadding {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 16;
      case AwikiBreakpoint.large:
        return 16 * spacingScale;
    }
  }
}

class AwikiBreakpoints {
  const AwikiBreakpoints._();

  static const double phoneMaxWidth = 719;
  static AwikiBreakpoint fromWidth(double width) {
    if (width < 720) {
      return AwikiBreakpoint.phone;
    }
    return AwikiBreakpoint.large;
  }
}

extension AwikiResponsiveContextX on BuildContext {
  AwikiResponsiveInfo get awikiResponsive {
    return AwikiResponsiveInfo.fromWidth(
      MediaQuery.sizeOf(this).width,
      displayScale: AwikiDisplayScaleScope.of(this),
    );
  }
}

class AwikiAdaptiveScaffold extends StatelessWidget {
  const AwikiAdaptiveScaffold({
    super.key,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.maxWidth,
    this.padding,
    this.includeBottomSafeArea = false,
  });

  final Widget child;
  final Alignment alignment;
  final double? maxWidth;
  final EdgeInsets? padding;
  final bool includeBottomSafeArea;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final resolvedPadding = (padding ?? responsive.pagePadding).copyWith(
      bottom: includeBottomSafeArea
          ? (padding?.bottom ?? responsive.pagePadding.bottom)
          : 0,
    );
    return SafeArea(
      bottom: includeBottomSafeArea,
      child: Padding(
        padding: resolvedPadding,
        child: Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth ?? responsive.contentMaxWidth,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class AwikiPaneLayout extends StatefulWidget {
  const AwikiPaneLayout({
    super.key,
    required this.listPane,
    required this.detailPane,
    this.listPaneWidth = 340,
    this.gap = 0,
    this.minListPaneWidth = 280,
    this.minDetailPaneWidth = 320,
    this.enableResize = true,
  });

  final Widget listPane;
  final Widget detailPane;
  final double listPaneWidth;
  final double gap;
  final double minListPaneWidth;
  final double minDetailPaneWidth;
  final bool enableResize;

  @override
  State<AwikiPaneLayout> createState() => _AwikiPaneLayoutState();
}

class _AwikiPaneLayoutState extends State<AwikiPaneLayout> {
  static const double _dividerHitWidth = 12;
  static double? _sharedListPaneWidth;

  late double _listPaneWidth;

  @override
  void initState() {
    super.initState();
    _listPaneWidth = _sharedListPaneWidth ?? widget.listPaneWidth;
  }

  @override
  void didUpdateWidget(covariant AwikiPaneLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sharedListPaneWidth == null &&
        oldWidget.listPaneWidth != widget.listPaneWidth) {
      _listPaneWidth = widget.listPaneWidth;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxListPaneWidth = math.max(
          widget.minListPaneWidth,
          constraints.maxWidth -
              widget.minDetailPaneWidth -
              widget.gap -
              (widget.enableResize ? _dividerHitWidth : 0),
        );
        final resolvedListPaneWidth = _listPaneWidth.clamp(
          widget.minListPaneWidth,
          maxListPaneWidth,
        );
        if (resolvedListPaneWidth != _listPaneWidth) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _listPaneWidth = resolvedListPaneWidth;
              _sharedListPaneWidth = resolvedListPaneWidth;
            });
          });
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: resolvedListPaneWidth, child: widget.listPane),
            if (widget.enableResize)
              MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  key: const Key('awiki-pane-divider'),
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _listPaneWidth = (_listPaneWidth + details.delta.dx)
                          .clamp(widget.minListPaneWidth, maxListPaneWidth);
                      _sharedListPaneWidth = _listPaneWidth;
                    });
                  },
                  child: SizedBox(
                    width: _dividerHitWidth,
                    child: Center(
                      child: Container(width: 1, color: theme.border),
                    ),
                  ),
                ),
              ),
            if (widget.gap > 0) SizedBox(width: widget.gap),
            Expanded(child: widget.detailPane),
          ],
        );
      },
    );
  }
}
