import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'awiki_me_design.dart';
import 'display_scale.dart';

enum AwikiBreakpoint { compact, expanded }

class AwikiResponsiveInfo {
  const AwikiResponsiveInfo({
    required this.size,
    required this.breakpoint,
    this.userDisplayScale = AwikiDisplayScale.normal,
  });

  factory AwikiResponsiveInfo.fromSize(
    Size size, {
    double displayScale = AwikiDisplayScale.normal,
  }) {
    return AwikiResponsiveInfo(
      size: size,
      breakpoint: AwikiBreakpoints.fromSize(size),
      userDisplayScale: AwikiDisplayScale.normalize(displayScale),
    );
  }

  /// Width-only compatibility factory. A width-only caller is treated as
  /// having enough height, so only the 720 px boundary applies.
  factory AwikiResponsiveInfo.fromWidth(
    double width, {
    double displayScale = AwikiDisplayScale.normal,
  }) {
    return AwikiResponsiveInfo.fromSize(
      Size(width, AwikiBreakpoints.expandedMinHeight),
      displayScale: AwikiDisplayScale.normalize(displayScale),
    );
  }

  final Size size;
  final AwikiBreakpoint breakpoint;
  final double userDisplayScale;

  double get displayScale => AwikiDisplayScale.effective(userDisplayScale);

  double get width => size.width;

  double get height => size.height;

  bool get isCompact => breakpoint == AwikiBreakpoint.compact;

  bool get isExpanded => breakpoint == AwikiBreakpoint.expanded;

  /// Compatibility name for callers that have not migrated to compact yet.
  bool get isPhone => isCompact;

  /// Compatibility name for callers that have not migrated to expanded yet.
  bool get isLarge => isExpanded;

  bool get isPad => isExpanded;

  bool get isDesktop => isExpanded;

  bool get supportsTwoPane => isExpanded;

  /// Compatibility name for the shared expanded layout.
  ///
  /// Layout semantics no longer depend on the target platform.
  bool get usesDesktopLayout => isExpanded;

  bool get isMacDesktop =>
      isExpanded && defaultTargetPlatform == TargetPlatform.macOS;

  double get uiScale {
    final baseScale = switch (breakpoint) {
      AwikiBreakpoint.compact => 1.0,
      AwikiBreakpoint.expanded => 0.72,
    };
    return baseScale * displayScale;
  }

  double get spacingScale {
    final baseScale = switch (breakpoint) {
      AwikiBreakpoint.compact => 1.0,
      AwikiBreakpoint.expanded => 0.74,
    };
    return baseScale * displayScale;
  }

  double get radiusScale {
    final baseScale = switch (breakpoint) {
      AwikiBreakpoint.compact => 1.0,
      AwikiBreakpoint.expanded => 0.78,
    };
    return baseScale * displayScale;
  }

  double get _fontScale => displayScale;

  double get controlHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 50 * displayScale;
      case AwikiBreakpoint.expanded:
        return 36 * displayScale;
    }
  }

  double get compactControlHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 42 * displayScale;
      case AwikiBreakpoint.expanded:
        return 32 * displayScale;
    }
  }

  double get navBarHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 60 * displayScale;
      case AwikiBreakpoint.expanded:
        return 44 * displayScale;
    }
  }

  double get avatarSizeMd {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 44 * displayScale;
      case AwikiBreakpoint.expanded:
        return 36 * displayScale;
    }
  }

  double get titleLg {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 19 * _fontScale;
      case AwikiBreakpoint.expanded:
        return 16 * _fontScale;
    }
  }

  double get titleXl {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 20 * _fontScale;
      case AwikiBreakpoint.expanded:
        return 17 * _fontScale;
    }
  }

  double get bodyMd {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 16 * _fontScale;
      case AwikiBreakpoint.expanded:
        return 14 * _fontScale;
    }
  }

  double get bodySm {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 14 * _fontScale;
      case AwikiBreakpoint.expanded:
        return 12.5 * _fontScale;
    }
  }

  double get metaSm {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 12 * _fontScale;
      case AwikiBreakpoint.expanded:
        return 11.5 * _fontScale;
    }
  }

  double get iconSm {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 18 * displayScale;
      case AwikiBreakpoint.expanded:
        return 15 * displayScale;
    }
  }

  double get iconMd {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 23 * displayScale;
      case AwikiBreakpoint.expanded:
        return 19 * displayScale;
    }
  }

  double get iconLg {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 26 * displayScale;
      case AwikiBreakpoint.expanded:
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
      case AwikiBreakpoint.compact:
        return double.infinity;
      case AwikiBreakpoint.expanded:
        return 1120;
    }
  }

  double get formMaxWidth {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return double.infinity;
      case AwikiBreakpoint.expanded:
        return 420;
    }
  }

  EdgeInsets get pagePadding {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return const EdgeInsets.symmetric(horizontal: 16);
      case AwikiBreakpoint.expanded:
        return const EdgeInsets.symmetric(horizontal: 32);
    }
  }

  EdgeInsets get tabInnerPadding {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return const EdgeInsets.fromLTRB(22, 0, 22, 0);
      case AwikiBreakpoint.expanded:
        return const EdgeInsets.fromLTRB(18, 18, 18, 0);
    }
  }

  double get tabContentHorizontalPadding {
    switch (breakpoint) {
      case AwikiBreakpoint.compact:
        return 16;
      case AwikiBreakpoint.expanded:
        return 16 * spacingScale;
    }
  }
}

class AwikiBreakpoints {
  const AwikiBreakpoints._();

  static const double expandedMinWidth = 720;
  static const double expandedMinHeight = 600;

  /// Compatibility boundary for existing width-only callers.
  static const double phoneMaxWidth = 719;

  static AwikiBreakpoint fromSize(Size size) {
    if (size.width < expandedMinWidth || size.height < expandedMinHeight) {
      return AwikiBreakpoint.compact;
    }
    return AwikiBreakpoint.expanded;
  }

  /// Compatibility entry point for callers that do not have a height.
  static AwikiBreakpoint fromWidth(double width) {
    return fromSize(Size(width, expandedMinHeight));
  }
}

extension AwikiResponsiveContextX on BuildContext {
  AwikiResponsiveInfo get awikiResponsive {
    return AwikiResponsiveInfo.fromSize(
      MediaQuery.sizeOf(this),
      displayScale: AwikiDisplayScaleScope.of(this),
    );
  }
}

class AwikiSystemNavigationClearance extends StatelessWidget {
  const AwikiSystemNavigationClearance({
    super.key,
    required this.child,
    this.androidAdditionalGap = 4,
  });

  final Widget child;
  final double androidAdditionalGap;

  @override
  Widget build(BuildContext context) {
    final bottom = defaultTargetPlatform == TargetPlatform.android
        ? context.awikiResponsive.spacing(androidAdditionalGap)
        : 0.0;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: child,
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
    this.listPaneWidth = 272,
    this.gap = 0,
    this.minListPaneWidth = 240,
    this.minDetailPaneWidth = 360,
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

  late double _listPaneWidth;

  @override
  void initState() {
    super.initState();
    _listPaneWidth = widget.listPaneWidth;
  }

  @override
  void didUpdateWidget(covariant AwikiPaneLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listPaneWidth != widget.listPaneWidth) {
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
              (widget.enableResize ? 1 : 0),
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
            });
          });
        }
        return Stack(
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(width: resolvedListPaneWidth, child: widget.listPane),
                if (widget.enableResize)
                  Container(width: 1, color: theme.border),
                if (widget.gap > 0) SizedBox(width: widget.gap),
                Expanded(child: widget.detailPane),
              ],
            ),
            if (widget.enableResize)
              Positioned(
                left: resolvedListPaneWidth - (_dividerHitWidth - 1) / 2,
                top: 0,
                bottom: 0,
                width: _dividerHitWidth,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    key: const Key('awiki-pane-divider'),
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _listPaneWidth = (_listPaneWidth + details.delta.dx)
                            .clamp(widget.minListPaneWidth, maxListPaneWidth);
                      });
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
