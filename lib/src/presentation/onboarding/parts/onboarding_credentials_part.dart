part of '../onboarding_page.dart';

class _LocalCredentialsCard extends StatelessWidget {
  const _LocalCredentialsCard({
    required this.credentials,
    required this.onLogin,
  });

  final List<SessionIdentity> credentials;
  final Future<void> Function(String credentialName) onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppCardSection(
      color: theme.subtleSurface,
      padding: responsive.scaledInsets(
        const EdgeInsets.fromLTRB(14, 14, 14, 14),
      ),
      child: credentials.isEmpty
          ? SizedBox(
              height: responsive.scaled(120),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: responsive.scaled(44),
                      height: responsive.scaled(44),
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(
                          responsive.radius(22),
                        ),
                      ),
                      child: Center(
                        child: AwikiAssetIcon(
                          assetName: 'assets/icons/icon_keyoff.svg',
                          color: theme.tertiaryText,
                          size: responsive.iconMd,
                        ),
                      ),
                    ),
                    SizedBox(height: responsive.spacing(12)),
                    Text(
                      context.l10n.onboardingMissingLocalCredential,
                      textAlign: TextAlign.center,
                      style: AwikiMeTextStyles.cardSubtitle.copyWith(
                        fontSize: responsive.bodySm,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: credentials
                  .map(
                    (item) => Padding(
                      padding: EdgeInsets.only(
                        bottom: item == credentials.last
                            ? 0
                            : responsive.spacing(10),
                      ),
                      child: _CredentialCardTile(
                        identity: item,
                        onTap: () => onLogin(item.credentialName),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _CredentialCardTile extends StatelessWidget {
  const _CredentialCardTile({required this.identity, required this.onTap});

  final SessionIdentity identity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final subtitle = (identity.handle?.trim().isNotEmpty == true)
        ? identity.handle!.trim()
        : identity.credentialName;
    return AppPressableTile(
      onTap: onTap,
      semanticLabel: identity.displayName,
      borderRadius: BorderRadius.circular(responsive.radius(20)),
      backgroundColor: theme.subtleSurface,
      child: AppSurface(
        padding: responsive.scaledInsets(
          const EdgeInsets.fromLTRB(14, 16, 14, 16),
        ),
        color: theme.subtleSurface,
        radius: responsive.radius(20),
        child: Row(
          children: <Widget>[
            AvatarBadge(
              seed: identity.displayName,
              size: responsive.isPhone ? 56 : responsive.avatarSizeMd,
            ),
            SizedBox(width: responsive.spacing(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    identity.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: responsive.titleLg,
                      fontWeight: FontWeight.w600,
                      color: theme.title,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(4)),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: responsive.bodyMd,
                      color: theme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.spacing(12)),
            AwikiAssetIcon(
              assetName: 'assets/icons/icon_right.svg',
              size: responsive.iconSm,
              color: theme.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginToolRow extends StatelessWidget {
  const _LoginToolRow({
    required this.importLabel,
    required this.refreshLabel,
    required this.onImport,
    required this.onRefresh,
  });

  final String importLabel;
  final String refreshLabel;
  final VoidCallback? onImport;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppCardSection(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          _LoginToolButton(
            label: importLabel,
            assetName: 'assets/icons/icon_key.svg',
            onPressed: onImport,
          ),
          const AppSectionDivider(),
          _LoginToolButton(
            label: refreshLabel,
            assetName: 'assets/icons/icon_reload.svg',
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}

class _LoginToolButton extends StatelessWidget {
  const _LoginToolButton({
    required this.label,
    required this.assetName,
    this.onPressed,
  });

  final String label;
  final String assetName;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppPressableTile(
      onTap: onPressed,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(responsive.radius(16)),
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: Padding(
          padding: responsive.scaledInsets(
            const EdgeInsets.fromLTRB(16, 18, 16, 18),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: responsive.scaled(44),
                height: responsive.scaled(44),
                decoration: BoxDecoration(
                  color: theme.subtleSurface,
                  borderRadius: BorderRadius.circular(responsive.radius(22)),
                ),
                child: Center(
                  child: AwikiAssetIcon(
                    assetName: assetName,
                    size: responsive.iconMd,
                    color: theme.title,
                  ),
                ),
              ),
              SizedBox(width: responsive.spacing(16)),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: responsive.titleLg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: responsive.spacing(12)),
              AwikiAssetIcon(
                assetName: 'assets/icons/icon_right.svg',
                size: responsive.iconSm,
                color: theme.tertiaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
