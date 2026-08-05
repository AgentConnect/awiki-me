part of '../onboarding_page.dart';

class _CompactOnboardingCard extends StatelessWidget {
  const _CompactOnboardingCard({
    required this.onboarding,
    required this.onAuthModeChanged,
    required this.child,
  });

  final OnboardingState onboarding;
  final ValueChanged<String> onAuthModeChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Container(
      key: const Key('onboarding-compact-auth-card'),
      padding: EdgeInsets.fromLTRB(
        responsive.spacing(4),
        responsive.spacing(12),
        responsive.spacing(4),
        responsive.spacing(22),
      ),
      color: theme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _CompactOnboardingBrand(),
          SizedBox(height: responsive.spacing(18)),
          Text(
            context.l10n.onboardingRegister,
            style: TextStyle(
              color: theme.title,
              fontSize: responsive.bodyMd,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: responsive.spacing(14)),
          if (onboarding.hasRegistrationMethods) ...<Widget>[
            _AuthModeToggle(
              value: onboarding.authMode,
              methods: onboarding.registrationMethods,
              onChanged: onAuthModeChanged,
            ),
            SizedBox(height: responsive.spacing(22)),
          ],
          child,
        ],
      ),
    );
  }
}

class _CompactOnboardingBrand extends StatelessWidget {
  const _CompactOnboardingBrand();

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return Row(
      key: const Key('onboarding-compact-brand'),
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        Image.asset(
          'assets/branding/awiki-me-logo.png',
          key: const Key('onboarding-compact-logo'),
          width: responsive.scaled(36),
          height: responsive.scaled(36),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => SizedBox.square(
            dimension: responsive.scaled(36),
            child: Center(
              child: Text(
                'AW',
                style: TextStyle(
                  color: AwikiMePalette.actionBlue,
                  fontSize: responsive.titleLg,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: responsive.spacing(12)),
        Text(
          'AWiki',
          style: TextStyle(
            color: theme.title,
            fontSize: responsive.titleXl,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AuthModeToggle extends StatelessWidget {
  const _AuthModeToggle({
    required this.value,
    required this.methods,
    required this.onChanged,
  });

  final String value;
  final List<OnboardingIdentityMethod> methods;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: responsive.isPhone
              ? responsive.displayScaled(286)
              : responsive.displayScaled(310),
        ),
        child: SizedBox(
          width: double.infinity,
          child: Container(
            key: const Key('onboarding-auth-mode-tabs'),
            padding: responsive.scaledInsets(const EdgeInsets.all(4)),
            decoration: BoxDecoration(
              color: AwikiMePalette.actionBlueBorder.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(responsive.radius(12)),
            ),
            child: Row(
              children: <Widget>[
                for (
                  var index = 0;
                  index < methods.length;
                  index++
                ) ...<Widget>[
                  Expanded(
                    child: _AuthModeOption(
                      key: Key('auth-mode-${methods[index].id.wireName}'),
                      selected: value == methods[index].id.wireName,
                      assetName: _authModeAssetName(methods[index].id),
                      label: _authModeLabel(context, methods[index].id),
                      onTap: () => onChanged(methods[index].id.wireName),
                    ),
                  ),
                  if (index != methods.length - 1)
                    SizedBox(width: responsive.spacing(4)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _authModeLabel(BuildContext context, OnboardingIdentityMethodId id) {
  return switch (id) {
    OnboardingIdentityMethodId.phone => context.l10n.onboardingPhone,
    OnboardingIdentityMethodId.email => context.l10n.onboardingEmail,
    OnboardingIdentityMethodId.handleOnly => context.l10n.onboardingHandle,
  };
}

String _authModeAssetName(OnboardingIdentityMethodId id) {
  return switch (id) {
    OnboardingIdentityMethodId.phone => 'assets/icons/icon_mobile.svg',
    OnboardingIdentityMethodId.email => 'assets/icons/icon_mail.svg',
    OnboardingIdentityMethodId.handleOnly => 'assets/icons/icon_mobile.svg',
  };
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

class _OnboardingAlignedAction extends StatelessWidget {
  const _OnboardingAlignedAction({
    super.key,
    required this.child,
    required this.width,
    this.fillAvailableWidth = false,
  });

  final Widget child;
  final double width;
  final bool fillAvailableWidth;

  @override
  Widget build(BuildContext context) {
    if (fillAvailableWidth) {
      return SizedBox(width: double.infinity, child: child);
    }
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class _OnboardingCapabilityPanel extends StatelessWidget {
  const _OnboardingCapabilityPanel({
    required this.message,
    this.loading = false,
    this.icon,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final bool loading;
  final IconData? icon;
  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final detailText = detail?.trim();
    return Container(
      key: const Key('onboarding-capability-panel'),
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(responsive.radius(12)),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: responsive.iconLg,
                height: responsive.iconLg,
                child: Center(
                  child: loading
                      ? const CupertinoActivityIndicator(radius: 9)
                      : Icon(
                          icon ?? CupertinoIcons.info_circle,
                          color: AwikiMePalette.actionBlue,
                          size: responsive.iconMd,
                        ),
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: responsive.bodySm,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (detailText != null && detailText.isNotEmpty) ...<Widget>[
            SizedBox(height: responsive.spacing(10)),
            Text(
              detailText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.metaSm,
                height: 1.35,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...<Widget>[
            SizedBox(height: responsive.spacing(14)),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: responsive.displayScaled(118),
                ),
                child: AppSecondaryButton(
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ),
            ),
          ],
        ],
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
