// [INPUT]: Semantic theme tokens and the shared glass material.
// [OUTPUT]: Glass sheets, pill buttons, verification digits, check rows and
//           progress steps shared by device, recovery and dialog flows.
// [POS]: Presentation-only building blocks for the flat liquid-glass style.

import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

import '../../../app/app_router.dart';
import '../awiki_me_design.dart';
import 'app_widgets.dart';

/// Thick glass panel used by floating sheets and dialogs: a near-opaque
/// frosted fill with a bright top rim, hairline edge and a soft drop shadow.
class AwikiGlassPanel extends StatelessWidget {
  const AwikiGlassPanel({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 20, 18),
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(
              0xFF0B1320,
            ).withValues(alpha: theme.isDark ? 0.45 : 0.18),
            blurRadius: 60,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          // A gradient replaces a BoxDecoration's color, so the fill and
          // the top highlight are painted as separate layers.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.surface.withValues(alpha: theme.isDark ? 0.9 : 0.86),
              borderRadius: borderRadius,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: theme.glassEdgeActive, width: 0.5),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: <Color>[
                    CupertinoColors.white.withValues(
                      alpha: theme.isDark ? 0.06 : 0.5,
                    ),
                    CupertinoColors.white.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Presents [builder] inside a centered floating glass panel, the
/// reference's treatment for approvals and other composed dialogs.
Future<T?> showAwikiGlassDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
  double maxWidth = 440,
}) {
  return AppNavigator.showDialog<T>(
    context,
    (dialogContext) => AwikiGlassDialogFrame(
      maxWidth: maxWidth,
      child: builder(dialogContext),
    ),
    barrierDismissible: dismissible,
  );
}

/// Centers [child] in a thick glass panel that stays clear of the keyboard
/// and scrolls when the content is taller than the screen.
class AwikiGlassDialogFrame extends StatelessWidget {
  const AwikiGlassDialogFrame({
    super.key,
    required this.child,
    this.maxWidth = 440,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      minimum: const EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: AwikiGlassPanel(child: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );
  }
}

/// One choice in an [AwikiGlassAlert]; tapping it closes the alert with
/// [value].
class AwikiAlertAction<T> {
  const AwikiAlertAction({
    required this.label,
    required this.value,
    this.key,
    this.tone = AwikiPillTone.secondary,
  });

  final String label;
  final T value;
  final Key? key;
  final AwikiPillTone tone;
}

/// Shows a centered glass alert and resolves with the chosen action's value,
/// or null when dismissed. [dismissible] false also blocks back navigation.
Future<T?> showAwikiGlassAlert<T>(
  BuildContext context, {
  Key? alertKey,
  String? title,
  String? message,
  Widget? content,
  required List<AwikiAlertAction<T>> actions,
  bool dismissible = true,
}) {
  return AppNavigator.showDialog<T>(
    context,
    (_) => PopScope<T>(
      canPop: dismissible,
      child: AwikiGlassDialogFrame(
        maxWidth: 360,
        child: AwikiGlassAlert<T>(
          key: alertKey,
          title: title,
          message: message,
          content: content,
          actions: actions,
        ),
      ),
    ),
    barrierDismissible: dismissible,
  );
}

/// Alert body: title, message or custom content, then pill actions side by
/// side when there are two or fewer, stacked otherwise.
class AwikiGlassAlert<T> extends StatelessWidget {
  const AwikiGlassAlert({
    super.key,
    this.title,
    this.message,
    this.content,
    required this.actions,
  });

  final String? title;
  final String? message;
  final Widget? content;
  final List<AwikiAlertAction<T>> actions;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    Widget button(AwikiAlertAction<T> action) => AwikiPillButton(
      key: action.key,
      label: action.label,
      tone: action.tone,
      expand: true,
      onPressed: () => Navigator.of(context).pop(action.value),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (title != null)
          Text(
            title!,
            style: TextStyle(color: theme.title, fontSize: 18, height: 1.25),
          ),
        if (message != null) ...<Widget>[
          if (title != null) const SizedBox(height: 10),
          Text(
            message!,
            style: TextStyle(color: theme.body, fontSize: 14, height: 1.45),
          ),
        ],
        if (content != null) ...<Widget>[
          if (title != null || message != null) const SizedBox(height: 14),
          content!,
        ],
        const SizedBox(height: 20),
        if (actions.length <= 2)
          Row(
            children: <Widget>[
              for (var i = 0; i < actions.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: button(actions[i])),
              ],
            ],
          )
        else
          for (var i = 0; i < actions.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 10),
            button(actions[i]),
          ],
      ],
    );
  }
}

enum AwikiPillTone {
  primary,
  secondary,
  danger,
  dangerOutline,
  text,
  dangerText,
}

/// Flat pill button: brand fill for the primary action, glass for secondary,
/// and text-only or outlined variants for quieter or destructive choices.
class AwikiPillButton extends StatelessWidget {
  const AwikiPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = AwikiPillTone.primary,
    this.height = 44,
    this.expand = false,
    this.semanticsIdentifier,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AwikiPillTone tone;
  final double height;
  final bool expand;
  final String? semanticsIdentifier;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final enabled = onPressed != null && !busy;
    final (Color? fill, Color? edge, Color text) = switch (tone) {
      AwikiPillTone.primary => (
        theme.primaryDark,
        null,
        theme.primaryForeground,
      ),
      AwikiPillTone.secondary => (theme.glass, theme.glassEdge, theme.title),
      AwikiPillTone.danger => (theme.dangerFill, null, CupertinoColors.white),
      AwikiPillTone.dangerOutline => (null, theme.danger, theme.danger),
      AwikiPillTone.text => (null, null, theme.title),
      AwikiPillTone.dangerText => (null, null, theme.danger),
    };
    final radius = BorderRadius.circular(height / 2);
    return AppPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      button: true,
      scaleOnPress: true,
      pressedScale: 0.97,
      borderRadius: radius,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled || busy ? 1 : 0.5,
        child: Container(
          height: height,
          constraints: BoxConstraints(minWidth: expand ? double.infinity : 0),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: edge == null
                ? null
                : Border.all(
                    color: edge,
                    width: tone == AwikiPillTone.dangerOutline ? 1 : 0.5,
                  ),
          ),
          child: busy
              ? CupertinoActivityIndicator(radius: 8, color: text)
              : Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: text,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Six verification digits as individual lens tiles with a gap after the
/// third, so both devices can be compared at a glance.
class AwikiSasDigits extends StatelessWidget {
  const AwikiSasDigits({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final digits = code.replaceAll(RegExp(r'\s'), '').split('');
    return Semantics(
      label: code,
      child: ExcludeSemantics(
        child: Row(
          children: <Widget>[
            for (var i = 0; i < digits.length; i++) ...<Widget>[
              if (i > 0) SizedBox(width: i == digits.length ~/ 2 ? 14 : 6),
              Expanded(
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.isDark ? theme.glassLens : theme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.glassEdgeActive,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    digits[i],
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w400,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Square check row for explicit acknowledgements.
class AwikiCheckRow extends StatelessWidget {
  const AwikiCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return AppPressable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      enabled: onChanged != null,
      selected: value,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: value ? theme.primaryDark : null,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: value ? theme.primaryDark : theme.secondaryText,
                ),
              ),
              child: value
                  ? Icon(
                      CupertinoIcons.checkmark,
                      size: 13,
                      color: theme.primaryForeground,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: theme.title, fontSize: 14, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical progress steps: done steps show a filled check, the current one
/// a ring, pending ones a hollow dot, joined by a hairline.
class AwikiFlowSteps extends StatelessWidget {
  const AwikiFlowSteps({super.key, required this.steps, required this.current});

  final List<(String, String?)> steps;

  /// Index of the step in progress; steps before it are done. A value past
  /// the last step marks every step done.
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 20,
                  child: Column(
                    children: <Widget>[
                      _StepDot(
                        done: i < current,
                        active: i == current,
                        theme: theme,
                      ),
                      if (i != steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: theme.glassEdgeActive,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: i == steps.length - 1 ? 0 : 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          steps[i].$1,
                          style: TextStyle(
                            color: i <= current
                                ? theme.title
                                : theme.secondaryText,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                        if (steps[i].$2 != null)
                          Text(
                            steps[i].$2!,
                            style: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.done,
    required this.active,
    required this.theme,
  });

  final bool done;
  final bool active;
  final AwikiMeThemeTokens theme;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(color: theme.success, shape: BoxShape.circle),
        child: const Icon(
          CupertinoIcons.checkmark,
          size: 12,
          color: CupertinoColors.white,
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? theme.title : theme.glassEdgeActive,
          width: active ? 1.5 : 1,
        ),
      ),
      // A static ring: flows can stay on this step indefinitely, so it
      // must not animate.
      child: active
          ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.title,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

/// Label/value rows on a glass card, like the reference's request details.
class AwikiDetailRows extends StatelessWidget {
  const AwikiDetailRows({super.key, required this.rows, this.monoLast = false});

  final List<(String, String)> rows;
  final bool monoLast;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Column(
      children: <Widget>[
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 72,
                  child: Text(
                    rows[i].$1,
                    style: TextStyle(
                      color: theme.secondaryText,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 14,
                      height: 1.5,
                      fontFamilyFallback: monoLast && i == rows.length - 1
                          ? const <String>['Menlo', 'monospace']
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Thick glass decoration for opaque-enough floating surfaces (sheets and
/// dialogs) that do not need a live backdrop blur.
BoxDecoration awikiThickGlassDecoration(
  BuildContext context, {
  required BorderRadius borderRadius,
  Color? fill,
}) {
  final theme = context.awikiTheme;
  return BoxDecoration(
    color: fill ?? theme.surface.withValues(alpha: theme.isDark ? 0.96 : 0.94),
    borderRadius: borderRadius,
    border: Border.all(color: theme.glassEdgeActive, width: 0.5),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: const Color(
          0xFF0B1320,
        ).withValues(alpha: theme.isDark ? 0.45 : 0.18),
        blurRadius: 60,
        offset: const Offset(0, 24),
      ),
    ],
  );
}
