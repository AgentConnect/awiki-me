import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../l10n/l10n.dart';
import 'adaptive_overlays.dart';
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
    final effectiveHeightFraction = responsive.isCompact
        ? math.max(maxHeightFraction, 0.94)
        : maxHeightFraction;
    final maxDialogHeight =
        availableHeight.clamp(0.0, mediaSize.height).toDouble() *
        effectiveHeightFraction;
    final effectiveBorderRadius =
        borderRadius ??
        BorderRadius.circular(responsive.radius(responsive.isCompact ? 14 : 8));
    if (responsive.isCompact) {
      return CompactBottomSheet(
        maxWidth: maxWidth,
        maxHeightFraction: effectiveHeightFraction,
        horizontalMargin: horizontalPadding,
        avoidKeyboard: avoidViewInsets,
        surfaceColor: surfaceColor,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      );
    }
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
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: maxDialogHeight,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceColor ?? theme.surface,
                borderRadius: effectiveBorderRadius,
                boxShadow: theme.overlayShadow,
              ),
              child: ClipRRect(
                borderRadius: effectiveBorderRadius,
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
    this.closeLabel,
    this.closeButtonKey,
    this.isCloseEnabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onClose;
  final String? closeLabel;
  final Key? closeButtonKey;
  final bool isCloseEnabled;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final effectiveCloseLabel = closeLabel ?? context.l10n.commonClose;
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
          key: closeButtonKey,
          onPressed: isCloseEnabled ? onClose : null,
          semanticLabel: effectiveCloseLabel,
          tooltip: effectiveCloseLabel,
          size: responsive.displayScaled(responsive.isCompact ? 44 : 32),
          backgroundColor: theme.subtleSurface,
          borderColor: theme.border,
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

class AppConfirmationDialog extends StatelessWidget {
  const AppConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
    this.cancelLabel,
    this.onCancel,
    this.destructive = false,
    this.confirmButtonKey,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final bool destructive;
  final Key? confirmButtonKey;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final cancel = onCancel ?? () => Navigator.of(context).pop();
    return AppDialogScaffold(
      maxWidth: 460,
      maxHeightFraction: 0.8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          responsive.spacing(20),
          responsive.spacing(16),
          responsive.spacing(20),
          responsive.spacing(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppDialogHeader(title: title, onClose: cancel),
            SizedBox(height: responsive.spacing(16)),
            Text(
              message,
              style: TextStyle(
                color: context.awikiTheme.body,
                fontSize: responsive.bodySm,
                height: 1.45,
              ),
            ),
            SizedBox(height: responsive.spacing(20)),
            Row(
              children: <Widget>[
                Expanded(
                  child: AppSecondaryButton(
                    label: cancelLabel ?? context.l10n.commonCancel,
                    onPressed: cancel,
                  ),
                ),
                SizedBox(width: responsive.spacing(10)),
                Expanded(
                  child: destructive
                      ? AppDangerButton(
                          key: confirmButtonKey,
                          label: confirmLabel,
                          onPressed: onConfirm,
                        )
                      : AppPrimaryButton(
                          key: confirmButtonKey,
                          label: confirmLabel,
                          onPressed: onConfirm,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
