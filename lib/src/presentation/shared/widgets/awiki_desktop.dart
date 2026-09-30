// [INPUT]: Semantic theme tokens and the shared pressable.
// [OUTPUT]: The reference's quiet desktop controls: soft fills, a square
//           soft icon button, a soft search pill and a small bordered button.
// [POS]: Presentation-only building blocks for the macOS/desktop layout.

import 'package:flutter/cupertino.dart';

import '../awiki_me_design.dart';
import '../responsive_layout.dart';
import 'app_widgets.dart';

/// Reference `--fg-soft-2`: the resting fill of desktop search pills, square
/// buttons and selected rows.
Color awikiDesktopSoftFill(BuildContext context) {
  final theme = context.awikiTheme;
  return theme.title.withValues(alpha: theme.isDark ? 0.10 : 0.065);
}

/// Reference `--fg-soft`: the lighter hover fill of desktop rows and cards.
Color awikiDesktopHoverFill(BuildContext context) {
  final theme = context.awikiTheme;
  return theme.title.withValues(alpha: theme.isDark ? 0.06 : 0.05);
}

/// Reference `.icon-btn.sq`: a 30-unit square with a soft fill.
class AwikiSoftIconButton extends StatelessWidget {
  const AwikiSoftIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onTap,
    this.semanticsIdentifier,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final radius = BorderRadius.circular(responsive.displayScaled(6));
    return AppPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: semanticLabel,
      button: true,
      borderRadius: radius,
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: responsive.displayScaled(30),
        height: responsive.displayScaled(30),
        decoration: BoxDecoration(
          color: state.hovered || state.pressed
              ? theme.title.withValues(alpha: theme.isDark ? 0.16 : 0.14)
              : awikiDesktopSoftFill(context),
          borderRadius: radius,
        ),
        child: child,
      ),
      child: Icon(
        icon,
        color: theme.title,
        size: responsive.displayScaled(16),
      ),
    );
  }
}

/// Reference desktop `.search input`: a 30-unit borderless soft pill.
class AwikiSoftSearchField extends StatelessWidget {
  const AwikiSoftSearchField({
    super.key,
    required this.placeholder,
    required this.onChanged,
    this.controller,
    this.focusNode,
  });

  final String placeholder;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return SizedBox(
      height: responsive.displayScaled(30),
      child: CupertinoSearchTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        onChanged: onChanged,
        style: TextStyle(fontSize: 13, color: theme.title),
        placeholderStyle: TextStyle(fontSize: 13, color: theme.secondaryText),
        prefixIcon: Icon(
          CupertinoIcons.search,
          color: theme.secondaryText,
          size: responsive.displayScaled(15),
        ),
        prefixInsets: EdgeInsetsDirectional.only(
          start: responsive.displayScaled(9),
        ),
        suffixIcon: Icon(
          CupertinoIcons.xmark_circle_fill,
          color: theme.tertiaryText,
          size: responsive.displayScaled(14),
        ),
        decoration: BoxDecoration(
          color: awikiDesktopSoftFill(context),
          borderRadius: BorderRadius.circular(responsive.displayScaled(6)),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.displayScaled(6),
          vertical: responsive.displayScaled(6),
        ),
      ),
    );
  }
}

/// Reference `.btn.btn-secondary.btn-sm`: a 28-unit white button with a
/// hairline border; [danger] tints only the text.
class AwikiSmallButton extends StatelessWidget {
  const AwikiSmallButton({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final radius = BorderRadius.circular(6);
    final enabled = onTap != null && !busy;
    return AppPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel: label,
      button: true,
      borderRadius: radius,
      builder: (context, state, child) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: state.hovered || state.pressed
              ? theme.background
              : theme.surface,
          borderRadius: radius,
          border: Border.all(
            color: state.hovered || state.pressed
                ? Color.lerp(theme.border, theme.title, 0.4)!
                : theme.border,
          ),
        ),
        child: child,
      ),
      child: busy
          ? const CupertinoActivityIndicator(radius: 7)
          : Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: danger ? theme.danger : theme.title,
                fontSize: 13,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
    );
  }
}

/// Reference `.dlg-actions`: a right-aligned quiet cancel and a primary
/// action. Phones use pills; desktop uses 32-unit buttons with 6-unit corners.
class AwikiDialogActionRow extends StatelessWidget {
  const AwikiDialogActionRow({
    super.key,
    required this.cancelLabel,
    required this.onCancel,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryKey,
    this.primarySemanticsIdentifier,
    this.primaryBusy = false,
    this.destructive = false,
  });

  final String cancelLabel;
  final VoidCallback? onCancel;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final Key? primaryKey;
  final String? primarySemanticsIdentifier;
  final bool primaryBusy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final phone = context.awikiResponsive.isPhone;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        _AwikiDialogButton(
          label: cancelLabel,
          onTap: onCancel,
          primary: false,
          phone: phone,
        ),
        SizedBox(width: phone ? 10 : 8),
        _AwikiDialogButton(
          key: primaryKey,
          label: primaryLabel,
          onTap: onPrimary,
          primary: true,
          destructive: destructive,
          busy: primaryBusy,
          phone: phone,
          semanticsIdentifier: primarySemanticsIdentifier,
        ),
      ],
    );
  }
}

class _AwikiDialogButton extends StatelessWidget {
  const _AwikiDialogButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.primary,
    required this.phone,
    this.destructive = false,
    this.busy = false,
    this.semanticsIdentifier,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool phone;
  final bool destructive;
  final bool busy;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final enabled = onTap != null && !busy;
    final height = phone ? 40.0 : 32.0;
    final radius = BorderRadius.circular(phone ? height / 2 : 6);
    final fill = primary
        ? (destructive ? theme.dangerFill : theme.primaryDark)
        : null;
    final textColor = primary
        ? (destructive ? CupertinoColors.white : theme.primaryForeground)
        : theme.title;
    return AppPressable(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      button: true,
      borderRadius: radius,
      builder: (context, state, child) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled || busy ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: height,
          padding: EdgeInsets.symmetric(horizontal: phone ? 18 : 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill ??
                (state.hovered || state.pressed
                    ? awikiDesktopSoftFill(context)
                    : awikiDesktopSoftFill(context).withValues(alpha: 0)),
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
      child: busy
          ? CupertinoActivityIndicator(
              radius: 7,
              color: primary ? textColor : null,
            )
          : Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: phone ? 15 : 14,
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
    );
  }
}
