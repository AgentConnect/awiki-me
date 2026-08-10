part of '../onboarding_page.dart';

class _OnboardingUtilityBar extends StatelessWidget {
  const _OnboardingUtilityBar({
    required this.tenant,
    required this.localeMode,
    required this.onLanguagePressed,
    required this.onPressed,
    this.fillAvailableWidth = false,
  });

  final AppTenantProfile tenant;
  final AppLocaleMode localeMode;
  final VoidCallback onLanguagePressed;
  final VoidCallback onPressed;
  final bool fillAvailableWidth;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final languageButton = _LanguageSwitcherButton(
      localeMode: localeMode,
      onPressed: onLanguagePressed,
    );
    final tenantButton = _TenantSwitcherButton(
      key: const Key('onboarding-tenant-switcher-button'),
      tenant: tenant,
      onPressed: onPressed,
    );
    if (!fillAvailableWidth) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          languageButton,
          SizedBox(width: responsive.spacing(8)),
          tenantButton,
        ],
      );
    }
    return Row(
      children: <Widget>[
        languageButton,
        SizedBox(width: responsive.spacing(8)),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: tenantButton),
        ),
      ],
    );
  }
}

class _LanguageSwitcherButton extends StatelessWidget {
  const _LanguageSwitcherButton({
    required this.localeMode,
    required this.onPressed,
  });

  final AppLocaleMode localeMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final label = compactAppLocaleModeLabel(context, localeMode);
    final fullLabel = appLocaleModeLabel(context, localeMode);
    return AppPressable(
      key: const Key('onboarding-language-switcher-button'),
      onTap: onPressed,
      semanticLabel: '${context.l10n.settingsLanguage}: $fullLabel',
      tooltip: context.l10n.settingsLanguage,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Container(
        constraints: BoxConstraints(minWidth: responsive.displayScaled(58)),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(10),
          vertical: responsive.spacing(7),
        ),
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              CupertinoIcons.textformat,
              size: responsive.displayScaled(15),
              color: theme.secondaryText,
            ),
            SizedBox(width: responsive.spacing(5)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.metaSm,
                fontWeight: FontWeight.w400,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TenantSwitcherButton extends StatelessWidget {
  const _TenantSwitcherButton({
    super.key,
    required this.tenant,
    required this.onPressed,
  });

  final AppTenantProfile tenant;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: context.l10n.tenantSwitcherLabel,
      tooltip: context.l10n.tenantSwitcherLabel,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      child: Container(
        constraints: BoxConstraints(maxWidth: responsive.displayScaled(260)),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(10),
          vertical: responsive.spacing(7),
        ),
        decoration: BoxDecoration(
          color: theme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: theme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              CupertinoIcons.globe,
              size: responsive.displayScaled(14),
              color: theme.secondaryText,
            ),
            SizedBox(width: responsive.spacing(6)),
            Flexible(
              child: Text(
                tenant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.secondaryText,
                  fontSize: responsive.metaSm,
                  fontWeight: FontWeight.w400,
                  height: 1.1,
                ),
              ),
            ),
            SizedBox(width: responsive.spacing(4)),
            Icon(
              CupertinoIcons.chevron_down,
              size: responsive.displayScaled(12),
              color: theme.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }
}
