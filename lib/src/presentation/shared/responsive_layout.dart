import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import 'awiki_me_design.dart';

enum AwikiBreakpoint { phone, large }

class AwikiResponsiveInfo {
  const AwikiResponsiveInfo({required this.width, required this.breakpoint});

  factory AwikiResponsiveInfo.fromWidth(double width) {
    return AwikiResponsiveInfo(
      width: width,
      breakpoint: AwikiBreakpoints.fromWidth(width),
    );
  }

  final double width;
  final AwikiBreakpoint breakpoint;

  bool get isPhone => breakpoint == AwikiBreakpoint.phone;

  bool get isLarge => breakpoint == AwikiBreakpoint.large;

  bool get isPad => isLarge;

  bool get isDesktop => isLarge;

  bool get supportsTwoPane => !isPhone;

  double get uiScale {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 1.0;
      case AwikiBreakpoint.large:
        return 0.72;
    }
  }

  double get spacingScale {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 1.0;
      case AwikiBreakpoint.large:
        return 0.74;
    }
  }

  double get radiusScale {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 1.0;
      case AwikiBreakpoint.large:
        return 0.78;
    }
  }

  double get controlHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 52;
      case AwikiBreakpoint.large:
        return 34;
    }
  }

  double get compactControlHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 44;
      case AwikiBreakpoint.large:
        return 30;
    }
  }

  double get navBarHeight {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 64;
      case AwikiBreakpoint.large:
        return 46;
    }
  }

  double get avatarSizeMd {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 48;
      case AwikiBreakpoint.large:
        return 34;
    }
  }

  double get titleLg {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 20;
      case AwikiBreakpoint.large:
        return 15;
    }
  }

  double get titleXl {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 20;
      case AwikiBreakpoint.large:
        return 16;
    }
  }

  double get bodyMd {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 16;
      case AwikiBreakpoint.large:
        return 12.5;
    }
  }

  double get bodySm {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 14;
      case AwikiBreakpoint.large:
        return 11;
    }
  }

  double get metaSm {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 11;
      case AwikiBreakpoint.large:
        return 9.5;
    }
  }

  double get iconSm {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 18;
      case AwikiBreakpoint.large:
        return 14;
    }
  }

  double get iconMd {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 24;
      case AwikiBreakpoint.large:
        return 18;
    }
  }

  double get iconLg {
    switch (breakpoint) {
      case AwikiBreakpoint.phone:
        return 28;
      case AwikiBreakpoint.large:
        return 20;
    }
  }

  double scaled(double base) => base * uiScale;

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
        return const EdgeInsets.fromLTRB(22, 18, 22, 0);
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
    return AwikiResponsiveInfo.fromWidth(MediaQuery.sizeOf(this).width);
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
