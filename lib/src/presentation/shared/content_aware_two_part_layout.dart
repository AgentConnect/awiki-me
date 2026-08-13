import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';

enum AwikiTwoPartAlignment { start, end }

/// Keeps two content groups inline while both fit, then stacks them as whole
/// groups. The primary group receives all space left by the secondary group.
class AwikiContentAwareTwoPartLayout extends MultiChildRenderObjectWidget {
  AwikiContentAwareTwoPartLayout({
    super.key,
    required Widget primary,
    required Widget secondary,
    required this.gap,
    required this.overflowGap,
    this.minimumPrimaryWidth = 0,
    this.overflowSecondaryAlignment = AwikiTwoPartAlignment.start,
  }) : super(children: <Widget>[primary, secondary]);

  final double gap;
  final double overflowGap;
  final double minimumPrimaryWidth;
  final AwikiTwoPartAlignment overflowSecondaryAlignment;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderAwikiContentAwareTwoPartLayout(
      gap: gap,
      overflowGap: overflowGap,
      minimumPrimaryWidth: minimumPrimaryWidth,
      overflowSecondaryAlignment: overflowSecondaryAlignment,
      textDirection: Directionality.of(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderAwikiContentAwareTwoPartLayout)
      ..gap = gap
      ..overflowGap = overflowGap
      ..minimumPrimaryWidth = minimumPrimaryWidth
      ..overflowSecondaryAlignment = overflowSecondaryAlignment
      ..textDirection = Directionality.of(context);
  }
}

class _AwikiTwoPartParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAwikiContentAwareTwoPartLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AwikiTwoPartParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AwikiTwoPartParentData> {
  _RenderAwikiContentAwareTwoPartLayout({
    required double gap,
    required double overflowGap,
    required double minimumPrimaryWidth,
    required AwikiTwoPartAlignment overflowSecondaryAlignment,
    required TextDirection textDirection,
  }) : _gap = gap,
       _overflowGap = overflowGap,
       _minimumPrimaryWidth = minimumPrimaryWidth,
       _overflowSecondaryAlignment = overflowSecondaryAlignment,
       _textDirection = textDirection;

  double get gap => _gap;
  double _gap;
  set gap(double value) {
    if (_gap == value) return;
    _gap = value;
    markNeedsLayout();
  }

  double get overflowGap => _overflowGap;
  double _overflowGap;
  set overflowGap(double value) {
    if (_overflowGap == value) return;
    _overflowGap = value;
    markNeedsLayout();
  }

  double get minimumPrimaryWidth => _minimumPrimaryWidth;
  double _minimumPrimaryWidth;
  set minimumPrimaryWidth(double value) {
    if (_minimumPrimaryWidth == value) return;
    _minimumPrimaryWidth = value;
    markNeedsLayout();
  }

  AwikiTwoPartAlignment get overflowSecondaryAlignment =>
      _overflowSecondaryAlignment;
  AwikiTwoPartAlignment _overflowSecondaryAlignment;
  set overflowSecondaryAlignment(AwikiTwoPartAlignment value) {
    if (_overflowSecondaryAlignment == value) return;
    _overflowSecondaryAlignment = value;
    markNeedsLayout();
  }

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _primary => firstChild!;
  RenderBox get _secondary => childAfter(_primary)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AwikiTwoPartParentData) {
      child.parentData = _AwikiTwoPartParentData();
    }
  }

  double _minimumInlinePrimaryWidth(double height, double naturalWidth) {
    final requestedMinimum = minimumPrimaryWidth > 0
        ? minimumPrimaryWidth
        : _primary.getMinIntrinsicWidth(height);
    return math.min(naturalWidth, requestedMinimum);
  }

  bool _fitsInline(
    double maxWidth,
    double primaryWidth,
    double secondaryWidth,
  ) {
    return !maxWidth.isFinite ||
        secondaryWidth + gap + primaryWidth <= maxWidth;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final naturalPrimary = _primary.getMaxIntrinsicWidth(height);
    return _minimumInlinePrimaryWidth(height, naturalPrimary) +
        gap +
        _secondary.getMaxIntrinsicWidth(height);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    return _primary.getMaxIntrinsicWidth(height) +
        gap +
        _secondary.getMaxIntrinsicWidth(height);
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    return _dryLayout(BoxConstraints(maxWidth: width)).height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    return _dryLayout(BoxConstraints(maxWidth: width)).height;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _dryLayout(constraints);

  Size _dryLayout(BoxConstraints constraints) {
    final maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : double.infinity;
    final naturalSecondary = _secondary.getDryLayout(const BoxConstraints());
    final naturalPrimary = _primary.getDryLayout(const BoxConstraints());
    final primaryMinimum = _minimumInlinePrimaryWidth(
      double.infinity,
      naturalPrimary.width,
    );

    late final Size contentSize;
    if (_fitsInline(maxWidth, primaryMinimum, naturalSecondary.width)) {
      final resolvedWidth = maxWidth.isFinite
          ? maxWidth
          : naturalPrimary.width + gap + naturalSecondary.width;
      final primarySize = _primary.getDryLayout(
        BoxConstraints(
          maxWidth: math.max(0.0, resolvedWidth - gap - naturalSecondary.width),
        ),
      );
      contentSize = Size(
        resolvedWidth,
        math.max(primarySize.height, naturalSecondary.height),
      );
    } else {
      final primarySize = _primary.getDryLayout(
        BoxConstraints(maxWidth: maxWidth),
      );
      final secondarySize = _secondary.getDryLayout(
        BoxConstraints(maxWidth: maxWidth),
      );
      contentSize = Size(
        maxWidth,
        primarySize.height + overflowGap + secondarySize.height,
      );
    }
    return constraints.constrain(contentSize);
  }

  @override
  void performLayout() {
    assert(childCount == 2);
    final maxWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : double.infinity;
    final naturalSecondary = _secondary.getDryLayout(const BoxConstraints());
    final naturalPrimary = _primary.getDryLayout(const BoxConstraints());
    final primaryMinimum = _minimumInlinePrimaryWidth(
      double.infinity,
      naturalPrimary.width,
    );

    if (_fitsInline(maxWidth, primaryMinimum, naturalSecondary.width)) {
      _layoutInline(maxWidth, naturalPrimary, naturalSecondary);
    } else {
      _layoutStacked(maxWidth);
    }
  }

  void _layoutInline(
    double maxWidth,
    Size naturalPrimary,
    Size naturalSecondary,
  ) {
    final resolvedWidth = maxWidth.isFinite
        ? maxWidth
        : naturalPrimary.width + gap + naturalSecondary.width;
    _secondary.layout(const BoxConstraints(), parentUsesSize: true);
    _primary.layout(
      BoxConstraints(
        maxWidth: math.max(0.0, resolvedWidth - gap - _secondary.size.width),
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(
      Size(
        resolvedWidth,
        math.max(_primary.size.height, _secondary.size.height),
      ),
    );

    final primaryData = _primary.parentData! as _AwikiTwoPartParentData;
    final secondaryData = _secondary.parentData! as _AwikiTwoPartParentData;
    final primaryY = (size.height - _primary.size.height) / 2;
    final secondaryY = (size.height - _secondary.size.height) / 2;
    if (textDirection == TextDirection.ltr) {
      primaryData.offset = Offset(0, primaryY);
      secondaryData.offset = Offset(
        size.width - _secondary.size.width,
        secondaryY,
      );
    } else {
      primaryData.offset = Offset(size.width - _primary.size.width, primaryY);
      secondaryData.offset = Offset(0, secondaryY);
    }
  }

  void _layoutStacked(double maxWidth) {
    final resolvedWidth = maxWidth.isFinite ? maxWidth : 0.0;
    _primary.layout(
      BoxConstraints(maxWidth: resolvedWidth),
      parentUsesSize: true,
    );
    _secondary.layout(
      BoxConstraints(maxWidth: resolvedWidth),
      parentUsesSize: true,
    );
    final naturalWidth = math.max(_primary.size.width, _secondary.size.width);
    final contentWidth = maxWidth.isFinite ? maxWidth : naturalWidth;
    size = constraints.constrain(
      Size(
        contentWidth,
        _primary.size.height + overflowGap + _secondary.size.height,
      ),
    );

    final primaryData = _primary.parentData! as _AwikiTwoPartParentData;
    final secondaryData = _secondary.parentData! as _AwikiTwoPartParentData;
    primaryData.offset = Offset(_startOffset(_primary.size.width), 0);
    secondaryData.offset = Offset(
      _alignedOffset(_secondary.size.width, overflowSecondaryAlignment),
      _primary.size.height + overflowGap,
    );
  }

  double _startOffset(double childWidth) {
    return textDirection == TextDirection.ltr ? 0 : size.width - childWidth;
  }

  double _alignedOffset(double childWidth, AwikiTwoPartAlignment alignment) {
    final alignLeft = alignment == AwikiTwoPartAlignment.start
        ? textDirection == TextDirection.ltr
        : textDirection == TextDirection.rtl;
    return alignLeft ? 0 : size.width - childWidth;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
