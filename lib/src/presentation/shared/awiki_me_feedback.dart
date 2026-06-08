import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectionArea, SelectionContainer;

import 'awiki_me_design.dart';
import 'responsive_layout.dart';

const _awikiMeInfoToastDuration = Duration(seconds: 2);
const _awikiMeDangerToastDuration = Duration(seconds: 8);

class AwikiMeToast {
  static void show(
    BuildContext context,
    String message, {
    bool danger = false,
    Duration? duration,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }
    final displayDuration =
        duration ??
        (danger ? _awikiMeDangerToastDuration : _awikiMeInfoToastDuration);
    final entry = OverlayEntry(
      builder: (context) {
        final theme = context.awikiTheme;
        final content = SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: danger
                    ? theme.danger.withValues(alpha: 0.9)
                    : theme.title.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.surface,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        );
        return Positioned(
          left: 20,
          right: 20,
          bottom: 110,
          child: danger
              ? SelectionArea(child: content)
              : IgnorePointer(child: content),
        );
      },
    );
    overlay.insert(entry);
    Future<void>.delayed(displayDuration, () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }
}

class AwikiMeErrorNotice extends StatelessWidget {
  const AwikiMeErrorNotice({
    super.key,
    required this.message,
    this.center = false,
    this.compact = false,
    this.trailing,
  });

  final String message;
  final bool center;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? responsive.spacing(10) : 12),
      decoration: BoxDecoration(
        color: theme.dangerContainer,
        borderRadius: BorderRadius.circular(responsive.radius(8)),
        border: Border.all(color: theme.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: center
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: AwikiMeErrorText(
              message: message,
              textAlign: center ? TextAlign.center : TextAlign.start,
              compact: compact,
            ),
          ),
          if (trailing != null) ...<Widget>[
            SizedBox(width: responsive.spacing(10)),
            SelectionContainer.disabled(child: trailing!),
          ],
        ],
      ),
    );
  }
}

class AwikiMeErrorText extends StatelessWidget {
  const AwikiMeErrorText({
    super.key,
    required this.message,
    this.textAlign,
    this.compact = false,
    this.maxLines,
  });

  final String message;
  final TextAlign? textAlign;
  final bool compact;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final text = Text(
      message,
      maxLines: maxLines,
      textAlign: textAlign,
      style: TextStyle(
        color: theme.danger,
        fontSize: compact ? responsive.metaSm : responsive.bodySm,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
    );
    if (SelectionContainer.maybeOf(context) != null) {
      return text;
    }
    return SelectionArea(child: text);
  }
}

class AwikiMePersistentToast extends StatelessWidget {
  const AwikiMePersistentToast({
    super.key,
    required this.message,
    this.danger = false,
    this.showSpinner = false,
    this.bottom = 110,
  });

  final String message;
  final bool danger;
  final bool showSpinner;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final content = SafeArea(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: danger
                ? theme.danger.withValues(alpha: 0.9)
                : theme.title.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showSpinner) ...<Widget>[
                CupertinoActivityIndicator(color: theme.surface, radius: 8),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.surface,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Positioned(
      left: 20,
      right: 20,
      bottom: bottom,
      child: danger
          ? SelectionArea(child: content)
          : IgnorePointer(child: content),
    );
  }
}

class AwikiMeLoadingMask extends StatelessWidget {
  const AwikiMeLoadingMask({super.key, this.label = '', this.opacity = 0.18});

  final String label;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: CupertinoColors.black.withValues(alpha: opacity),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                color: theme.surface.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(AwikiMeRadii.lg),
                boxShadow: theme.overlayShadow,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const CupertinoActivityIndicator(radius: 12),
                  const SizedBox(height: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
