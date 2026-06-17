part of '../onboarding_page.dart';

class _SegmentedPill extends StatelessWidget {
  const _SegmentedPill({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Align(
      alignment: Alignment.center,
      child: Container(
        key: const Key('onboarding-entry-tabs'),
        constraints: BoxConstraints(
          maxWidth: responsive.isPhone ? 286 : responsive.displayScaled(310),
        ),
        padding: responsive.scaledInsets(const EdgeInsets.all(4)),
        decoration: BoxDecoration(
          color: AwikiMePalette.actionBlueBorder.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(responsive.radius(12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map(
                (entry) => Flexible(
                  fit: FlexFit.loose,
                  child: _CompactSegmentOption(
                    label: entry.value,
                    selected: value == entry.key,
                    minWidth: responsive.isPhone
                        ? responsive.displayScaled(124)
                        : responsive.displayScaled(128),
                    verticalPadding: responsive.spacing(11),
                    fontSize: responsive.bodyMd,
                    selectedColor: AwikiMePalette.actionBlue,
                    unselectedColor: AwikiMePalette.actionMuted,
                    onTap: () => onChanged(entry.key),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _AuthModeToggle extends StatelessWidget {
  const _AuthModeToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('onboarding-auth-mode-tabs'),
        padding: responsive.scaledInsets(const EdgeInsets.all(4)),
        decoration: BoxDecoration(
          color: AwikiMePalette.actionBlueBorder.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(responsive.radius(12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _AuthModeOption(
              key: const Key('auth-mode-phone'),
              selected: value == 'phone',
              assetName: 'assets/icons/icon_mobile.svg',
              label: context.l10n.onboardingPhone,
              onTap: () => onChanged('phone'),
            ),
            SizedBox(width: responsive.spacing(4)),
            _AuthModeOption(
              key: const Key('auth-mode-email'),
              selected: value == 'email',
              assetName: 'assets/icons/icon_mail.svg',
              label: context.l10n.onboardingEmail,
              onTap: () => onChanged('email'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthModeOption extends StatelessWidget {
  const _AuthModeOption({
    super.key,
    required this.selected,
    required this.assetName,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String assetName;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final buttonHeight = responsive.isPhone
        ? responsive.compactControlHeight
        : responsive.scaled(40);
    final foreground = selected
        ? AwikiMePalette.actionBlue
        : AwikiMePalette.actionMuted;
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      child: Container(
        height: buttonHeight,
        constraints: BoxConstraints(
          minWidth: responsive.isPhone
              ? responsive.displayScaled(96)
              : responsive.displayScaled(96),
        ),
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(12)),
        decoration: BoxDecoration(
          color: selected ? CupertinoColors.white : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          border: Border.all(
            color: selected
                ? AwikiMePalette.actionBlueBorder
                : CupertinoColors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AwikiAssetIcon(
              assetName: assetName,
              size: responsive.iconMd,
              color: foreground,
            ),
            SizedBox(width: responsive.spacing(8)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: AwikiMeTextStyles.buttonLabel.copyWith(
                  color: foreground,
                  fontSize: responsive.bodySm,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSegmentOption extends StatelessWidget {
  const _CompactSegmentOption({
    required this.label,
    required this.selected,
    required this.minWidth,
    required this.verticalPadding,
    required this.fontSize,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double minWidth;
  final double verticalPadding;
  final double fontSize;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minWidth: minWidth),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(14),
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: selected ? CupertinoColors.white : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x100B65F8),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontSize: fontSize,
              height: 1,
              forceStrutHeight: true,
            ),
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? selectedColor : unselectedColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingAlignedAction extends StatelessWidget {
  const _OnboardingAlignedAction({
    super.key,
    required this.child,
    required this.width,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class _PhoneFieldPrefix extends StatelessWidget {
  const _PhoneFieldPrefix({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          code,
          style: TextStyle(
            fontSize: responsive.bodyMd,
            fontWeight: FontWeight.w600,
            color: theme.title,
          ),
        ),
        SizedBox(width: responsive.spacing(10)),
        Container(width: 1, height: responsive.scaled(26), color: theme.border),
      ],
    );
  }
}

class _OtpCompleteMarker extends StatelessWidget {
  const _OtpCompleteMarker({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (value.text.replaceAll(RegExp(r'\s+'), '').length != 6) {
          return const SizedBox.shrink();
        }
        return const E2eMarker('e2e-otp-complete');
      },
    );
  }
}

class _VerificationInlineButton extends StatelessWidget {
  const _VerificationInlineButton({
    required this.label,
    this.onPressed,
    this.semanticsIdentifier,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      builder: (context, state, child) {
        return AnimatedOpacity(
          opacity: state.enabled
              ? state.pressed
                    ? 0.78
                    : state.hovered || state.focused
                    ? 0.90
                    : 1
              : 0.55,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Container(
        constraints: BoxConstraints(
          minWidth: responsive.scaled(92),
          maxWidth: responsive.scaled(132),
          minHeight: responsive.compactControlHeight,
        ),
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(12)),
        decoration: BoxDecoration(
          color: AwikiMePalette.actionBlueSoft,
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: AwikiMePalette.actionBlueBorder),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontSize: responsive.bodySm,
              height: 1,
              forceStrutHeight: true,
            ),
            style: AwikiMeTextStyles.buttonLabel.copyWith(
              color: AwikiMePalette.actionBlue,
              fontSize: responsive.bodySm,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
