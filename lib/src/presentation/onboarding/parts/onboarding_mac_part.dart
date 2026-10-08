// [INPUT]: Onboarding page state and callbacks from the parent presentation surface.
// [OUTPUT]: Desktop login, registration, and local-identity login controls.
// [POS]: Part of onboarding_page.dart; existing Handle actions are chosen by the parent.

part of '../onboarding_page.dart';

class _MacOnboardingScaffold extends StatelessWidget {
  const _MacOnboardingScaffold({
    required this.onboarding,
    required this.registrationEntry,
    required this.registrationReady,
    required this.otpCooldown,
    required this.credentials,
    required this.phoneController,
    required this.otpController,
    required this.emailController,
    required this.handleController,
    required this.onLogin,
    required this.onDeleteCredential,
    required this.onAuthModeChanged,
    required this.onRequestOtp,
    required this.onRequestEmailActivation,
    required this.onCheckEmailActivation,
    required this.onSubmitRegister,
    required this.activeTenant,
    required this.localeMode,
    required this.onLanguagePressed,
    required this.onTenantPressed,
  });

  final OnboardingState onboarding;
  final Widget registrationEntry;
  final bool registrationReady;
  final SmsOtpCooldownState otpCooldown;
  final List<SessionIdentity> credentials;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final TextEditingController emailController;
  final TextEditingController handleController;
  final Future<void> Function(String credentialName) onLogin;
  final ValueChanged<SessionIdentity> onDeleteCredential;
  final ValueChanged<String> onAuthModeChanged;
  final VoidCallback onRequestOtp;
  final VoidCallback onRequestEmailActivation;
  final VoidCallback onCheckEmailActivation;
  final VoidCallback onSubmitRegister;
  final AppTenantProfile activeTenant;
  final AppLocaleMode localeMode;
  final ValueChanged<BuildContext> onLanguagePressed;
  final VoidCallback onTenantPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    final scaffold = CupertinoPageScaffold(
      backgroundColor: phone ? const Color(0x00000000) : theme.surface,
      child: SafeArea(
        child: AwikiSystemNavigationClearance(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth <= 700;
              final tenantButton = Builder(
                builder: (anchorContext) => _PhoneTenantPill(
                  key: const Key('onboarding-tenant-switcher-button'),
                  name: activeTenant.name,
                  dense: true,
                  onTap: () => showTenantSwitcherMenu(anchorContext),
                ),
              );
              Widget languageButtonFor({required bool showChevron}) => Builder(
                builder: (anchorContext) => _MacFooterButton(
                  key: const Key('onboarding-language-switcher-button'),
                  icon: CupertinoIcons.globe,
                  label: appLocaleModeLabel(context, localeMode),
                  tooltip: context.l10n.settingsLanguage,
                  showChevron: showChevron,
                  onTap: () => onLanguagePressed(anchorContext),
                ),
              );
              final languageButton = languageButtonFor(showChevron: true);
              final form = Expanded(
                child: ColoredBox(
                  color: phone ? const Color(0x00000000) : theme.surface,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 40,
                      phone ? 16 : (compact ? 24 : 44),
                      compact ? 20 : 40,
                      24,
                    ),
                    child: LayoutBuilder(
                      builder: (context, formConstraints) => Align(
                        alignment: Alignment.topCenter,
                        child: _MacAuthCard(
                          key: ValueKey(
                            '${activeTenant.backendBaseUrl}|${activeTenant.didHost}',
                          ),
                          maxHeight: formConstraints.maxHeight,
                          onboarding: onboarding,
                          registrationEntry: registrationEntry,
                          registrationReady: registrationReady,
                          otpCooldown: otpCooldown,
                          credentials: credentials,
                          phoneController: phoneController,
                          otpController: otpController,
                          emailController: emailController,
                          handleController: handleController,
                          onLogin: onLogin,
                          onDeleteCredential: onDeleteCredential,
                          onAuthModeChanged: onAuthModeChanged,
                          onRequestOtp: onRequestOtp,
                          onRequestEmailActivation: onRequestEmailActivation,
                          onCheckEmailActivation: onCheckEmailActivation,
                          onSubmitRegister: onSubmitRegister,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              if (compact) {
                return Column(
                  key: const Key('onboarding-desktop-compact-layout'),
                  children: <Widget>[
                    Container(
                      padding: phone
                          ? const EdgeInsets.fromLTRB(20, 14, 16, 6)
                          : const EdgeInsets.fromLTRB(20, 16, 12, 12),
                      decoration: phone
                          ? null
                          : BoxDecoration(
                              color: theme.surface,
                              border: Border(
                                bottom: BorderSide(color: theme.border),
                              ),
                            ),
                      child: Row(
                        children: <Widget>[
                          const Expanded(flex: 3, child: _MacCompactBrand()),
                          const SizedBox(width: 12),
                          if (phone)
                            Builder(
                              builder: (anchorContext) => _PhoneTenantPill(
                                key: const Key(
                                  'onboarding-tenant-switcher-button',
                                ),
                                name: activeTenant.name,
                                onTap: () =>
                                    showTenantSwitcherMenu(anchorContext),
                              ),
                            )
                          else
                            Expanded(flex: 2, child: tenantButton),
                        ],
                      ),
                    ),
                    form,
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: KeyedSubtree(
                        key: const Key('onboarding-compact-footer'),
                        child: languageButton,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                key: const Key('onboarding-expanded-layout'),
                children: <Widget>[
                  Container(
                    key: const Key('onboarding-brand-pane'),
                    width: 352,
                    // Monochrome brand pane: plain paper split from the form
                    // by a hairline, with no glow.
                    decoration: BoxDecoration(
                      color: theme.surface,
                      border: Border(right: BorderSide(color: theme.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 64, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Expanded(
                          child: SingleChildScrollView(
                            child: _MacOnboardingHero(),
                          ),
                        ),
                        // Language on the left, tenant on the right, in one
                        // footer row.
                        Row(
                          key: const Key('onboarding-brand-footer'),
                          children: <Widget>[
                            // Space is tight beside the tenant, so the globe
                            // alone marks the language control here.
                            languageButtonFor(showChevron: false),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: tenantButton,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  form,
                ],
              );
            },
          ),
        ),
      ),
    );
    if (!phone) {
      return scaffold;
    }
    return ColoredBox(
      key: const Key('onboarding-paper-surface'),
      color: theme.surface,
      child: scaffold,
    );
  }
}

/// Tenant switcher pill shared by the phone header and the desktop login
/// footer: "租户 | name" with an up/down chevron on the monochrome paper material.
class _PhoneTenantPill extends StatelessWidget {
  const _PhoneTenantPill({
    super.key,
    required this.name,
    required this.onTap,
    this.dense = false,
  });

  final String name;
  final VoidCallback onTap;

  /// Tighter insets for the desktop login footer, where the pill shares a
  /// row with the language control.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return AppPressable(
      onTap: onTap,
      semanticLabel: context.l10n.tenantSwitcherLabel,
      tooltip: context.l10n.tenantSwitcherLabel,
      scaleOnPress: true,
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(22),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: dense ? 36 : 44, maxWidth: 240),
        child: DecoratedBox(
          decoration: _loginPaperDecoration(context, radius: 22),
          child: Padding(
            padding: dense
                ? const EdgeInsets.fromLTRB(12, 4, 10, 4)
                : const EdgeInsets.fromLTRB(16, 5, 12, 5),
            // In a tight slot the "租户 |" caption gives way to the name.
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (constraints.maxWidth >= 150) ...<Widget>[
                    Text(
                      context.l10n.tenantManagementTitle,
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 12,
                      margin: EdgeInsets.symmetric(horizontal: dense ? 6 : 8),
                      color: theme.border,
                    ),
                  ],
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.title,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  SizedBox(width: dense ? 6 : 8),
                  Icon(
                    CupertinoIcons.chevron_up_chevron_down,
                    size: 14,
                    color: theme.secondaryText,
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

/// The login page's monochrome material: paper fill with a hairline edge.
/// [edge] swaps the hairline for ink (focus, outlined actions); there are no
/// grey fills.
BoxDecoration _loginPaperDecoration(
  BuildContext context, {
  double radius = 16,
  Color? edge,
  double edgeWidth = 1,
}) {
  final theme = context.awikiTheme;
  return BoxDecoration(
    color: theme.surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: edge ?? theme.border, width: edgeWidth),
  );
}

class _MacOnboardingHero extends StatelessWidget {
  const _MacOnboardingHero();

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _MacCompactBrand(),
        const SizedBox(height: 44),
        Text(
          '${context.l10n.onboardingMacHeroPrefix.trim()}\n'
          '${context.l10n.onboardingMacHeroHighlight}'
          '${context.l10n.onboardingMacHeroSuffix}',
          key: const Key('onboarding-mac-hero-title'),
          style: TextStyle(
            color: theme.title,
            fontSize: 30,
            height: 1.25,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.onboardingMacSubtitle,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: 13,
            height: 1.7,
          ),
        ),
      ],
    );
  }
}

class _MacAuthCard extends ConsumerWidget {
  const _MacAuthCard({
    super.key,
    required this.maxHeight,
    required this.onboarding,
    required this.registrationEntry,
    required this.registrationReady,
    required this.otpCooldown,
    required this.credentials,
    required this.phoneController,
    required this.otpController,
    required this.emailController,
    required this.handleController,
    required this.onLogin,
    required this.onDeleteCredential,
    required this.onAuthModeChanged,
    required this.onRequestOtp,
    required this.onRequestEmailActivation,
    required this.onCheckEmailActivation,
    required this.onSubmitRegister,
  });

  final double maxHeight;
  final OnboardingState onboarding;
  final Widget registrationEntry;
  final bool registrationReady;
  final SmsOtpCooldownState otpCooldown;
  final List<SessionIdentity> credentials;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final TextEditingController emailController;
  final TextEditingController handleController;
  final Future<void> Function(String credentialName) onLogin;
  final ValueChanged<SessionIdentity> onDeleteCredential;
  final ValueChanged<String> onAuthModeChanged;
  final VoidCallback onRequestOtp;
  final VoidCallback onRequestEmailActivation;
  final VoidCallback onCheckEmailActivation;
  final VoidCallback onSubmitRegister;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showIdentities = onboarding.entryMode == 'login';
    return Container(
      key: const Key('onboarding-mac-auth-card'),
      constraints: BoxConstraints(maxWidth: 336, maxHeight: maxHeight),
      child: SingleChildScrollView(
        key: const Key('onboarding-form-scroll-view'),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _LoginEntryTabs(
              showIdentities: showIdentities,
              enabled: !onboarding.isBusy,
              registerLabel: context.l10n.onboardingRegister,
              identityLabel: context.l10n.onboardingLogin,
              onChanged: (value) => ref
                  .read(onboardingProvider.notifier)
                  .setEntryMode(value ? 'login' : 'register'),
            ),
            const SizedBox(height: 16),
            if (showIdentities)
              if (credentials.isEmpty)
                _OnboardingCapabilityPanel(
                  icon: CupertinoIcons.person_crop_circle,
                  message: context.l10n.noLocalCredentialsFound,
                )
              else
                _OnboardingLocalIdentitySection(
                  credentials: credentials,
                  onLogin: onLogin,
                  onDeleteCredential: onDeleteCredential,
                  actionsEnabled: !onboarding.isBusy,
                  deletingIdentitySelector:
                      onboarding.deletingLocalIdentitySelector,
                )
            else ...<Widget>[
              IdentityMethodPicker(handleController: handleController),
              if (registrationReady &&
                  onboarding.hasRegistrationMethods) ...<Widget>[
                _MacAuthMethodSelector(
                  onboarding: onboarding,
                  onAuthModeChanged: onAuthModeChanged,
                ),
                const SizedBox(height: 16),
              ],
              _MacRegisterForm(
                key: ValueKey<String>('mac-register-${onboarding.authMode}'),
                onboarding: onboarding,
                registrationEntry: registrationEntry,
                otpCooldown: otpCooldown,
                phoneController: phoneController,
                otpController: otpController,
                emailController: emailController,
                handleController: handleController,
                onRequestOtp: onRequestOtp,
                onRequestEmailActivation: onRequestEmailActivation,
                onCheckEmailActivation: onCheckEmailActivation,
                onSubmitRegister: onSubmitRegister,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Entry switch: a paper track whose chosen segment is solid ink.
class _LoginEntryTabs extends StatelessWidget {
  const _LoginEntryTabs({
    required this.showIdentities,
    required this.enabled,
    required this.registerLabel,
    required this.identityLabel,
    required this.onChanged,
  });

  final bool showIdentities;
  final bool enabled;
  final String registerLabel;
  final String identityLabel;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    final segmentRadius = phone ? 18.0 : 5.0;
    Widget segment(bool value, String label, Key key) {
      final selected = value == showIdentities;
      return Expanded(
        child: AppPressable(
          key: key,
          onTap: enabled && !selected ? () => onChanged(value) : null,
          enabled: enabled,
          selected: selected,
          semanticLabel: label,
          scaleOnPress: true,
          pressedScale: 0.96,
          borderRadius: BorderRadius.circular(segmentRadius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: phone ? 36 : 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? theme.title : theme.title.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(segmentRadius),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? theme.primaryForeground : theme.title,
                fontSize: phone ? 14 : 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: const Key('onboarding-entry-tabs'),
      padding: EdgeInsets.all(phone ? 4 : 3),
      decoration: _loginPaperDecoration(context, radius: phone ? 22 : 8),
      child: Row(
        children: <Widget>[
          segment(false, registerLabel, const Key('onboarding-register-entry')),
          SizedBox(width: phone ? 4 : 3),
          segment(true, identityLabel, const Key('onboarding-identity-entry')),
        ],
      ),
    );
  }
}

class _MacCompactBrand extends StatelessWidget {
  const _MacCompactBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('onboarding-desktop-compact-brand'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SvgPicture.asset(
          'assets/branding/awiki-me-mark.svg',
          key: const Key('onboarding-brand-logo'),
          width: context.awikiResponsive.isPhone ? 30 : 34,
          height: context.awikiResponsive.isPhone ? 30 : 34,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'AWiki Me',
            style: TextStyle(
              color: context.awikiTheme.title,
              fontSize: context.awikiResponsive.isPhone ? 16 : 15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _MacAuthMethodSelector extends StatelessWidget {
  const _MacAuthMethodSelector({
    required this.onboarding,
    required this.onAuthModeChanged,
  });

  final OnboardingState onboarding;
  final ValueChanged<String> onAuthModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return Container(
      key: const Key('onboarding-mac-auth-method-tabs'),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.border)),
      ),
      child: Row(
        children: <Widget>[
          for (final method in onboarding.registrationMethods)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: AppPressable(
                key: Key('auth-mode-${method.id.wireName}'),
                semanticLabel: _authModeLabel(context, method.id),
                selected: onboarding.authMode == method.id.wireName,
                onTap: onboarding.isBusy
                    ? null
                    : () => onAuthModeChanged(method.id.wireName),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: onboarding.authMode == method.id.wireName
                            ? theme.title
                            : CupertinoColors.transparent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Text(
                    _authModeLabel(context, method.id),
                    style: TextStyle(
                      fontSize: 13,
                      color: onboarding.authMode == method.id.wireName
                          ? theme.title
                          : theme.secondaryText,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OnboardingLocalIdentitySection extends StatelessWidget {
  const _OnboardingLocalIdentitySection({
    required this.credentials,
    required this.onLogin,
    required this.onDeleteCredential,
    required this.actionsEnabled,
    this.deletingIdentitySelector,
  });

  final List<SessionIdentity> credentials;
  final Future<void> Function(String credentialName) onLogin;
  final ValueChanged<SessionIdentity> onDeleteCredential;
  final bool actionsEnabled;
  final String? deletingIdentitySelector;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('onboarding-local-credential-section'),
      children: <Widget>[
        for (final identity in credentials)
          Padding(
            padding: EdgeInsets.only(
              bottom: identity == credentials.last ? 0 : 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _OnboardingCredentialTile(
                  key: Key(
                    'onboarding-local-credential:${identity.credentialName}',
                  ),
                  identity: identity,
                  actionsEnabled: actionsEnabled,
                  isDeleting:
                      deletingIdentitySelector ==
                      identity.localIdentitySelector,
                  onLogin: () => onLogin(identity.credentialName),
                  onDelete: () => onDeleteCredential(identity),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OnboardingCredentialTile extends StatelessWidget {
  const _OnboardingCredentialTile({
    super.key,
    required this.identity,
    required this.actionsEnabled,
    required this.isDeleting,
    required this.onLogin,
    required this.onDelete,
  });

  final SessionIdentity identity;
  final bool actionsEnabled;
  final bool isDeleting;
  final VoidCallback onLogin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final subtitle = (identity.handle?.trim().isNotEmpty == true)
        ? identity.handle!.trim()
        : identity.did;
    final displayName = identity.visibleDisplayName;
    final enabled = actionsEnabled && !isDeleting;
    final phone = context.awikiResponsive.isPhone;
    return Container(
      constraints: BoxConstraints(minHeight: phone ? 68 : 60),
      decoration: phone
          ? _macFieldDecoration(context)
          : BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.border),
            ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: AppPressable(
                key: Key(
                  'onboarding-local-credential-select:${identity.credentialName}',
                ),
                onTap: enabled ? onLogin : null,
                semanticLabel: '${context.l10n.onboardingLogin}: $displayName',
                semanticsIdentifier:
                    'onboarding-local-credential-select:${identity.credentialName}',
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(10),
                ),
                child: Padding(
                  padding: phone
                      ? const EdgeInsets.fromLTRB(15, 11, 12, 11)
                      : const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: <Widget>[
                      AvatarBadge(seed: displayName, size: phone ? 38 : 36),
                      SizedBox(width: phone ? 13 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            _DesktopCredentialTooltip(
                              message: displayName,
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.awikiTheme.title,
                                  fontSize: phone ? 15 : 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _DesktopCredentialTooltip(
                              message: subtitle,
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.awikiTheme.secondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AppPressable(
              key: Key(
                'onboarding-local-credential-delete:${identity.credentialName}',
              ),
              onTap: enabled ? onDelete : null,
              semanticLabel:
                  '${context.l10n.localCredentialDeleteAction}: $displayName',
              tooltip: context.l10n.localCredentialDeleteAction,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(10),
              ),
              hoverColor: theme.danger.withValues(alpha: 0.06),
              pressedColor: theme.danger.withValues(alpha: 0.10),
              focusColor: theme.danger.withValues(alpha: 0.28),
              child: SizedBox(
                width: 50,
                child: Center(
                  child: isDeleting
                      ? const CupertinoActivityIndicator(radius: 7)
                      : Icon(
                          CupertinoIcons.delete,
                          size: phone ? 17 : 15,
                          // Desktop keeps the delete action quiet; the hover
                          // tint signals it is destructive.
                          color: !enabled
                              ? theme.tertiaryText
                              : phone
                              ? theme.danger
                              : theme.secondaryText,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopCredentialTooltip extends StatelessWidget {
  const _DesktopCredentialTooltip({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
    final normalizedMessage = message.trim();
    if (!isDesktopPlatform || normalizedMessage.isEmpty) {
      return child;
    }
    return Tooltip(
      message: normalizedMessage,
      waitDuration: const Duration(milliseconds: 350),
      ignorePointer: true,
      excludeFromSemantics: true,
      child: child,
    );
  }
}

class _MacRegisterForm extends StatelessWidget {
  const _MacRegisterForm({
    super.key,
    required this.onboarding,
    required this.registrationEntry,
    required this.otpCooldown,
    required this.phoneController,
    required this.otpController,
    required this.emailController,
    required this.handleController,
    required this.onRequestOtp,
    required this.onRequestEmailActivation,
    required this.onCheckEmailActivation,
    required this.onSubmitRegister,
  });

  final OnboardingState onboarding;
  final Widget registrationEntry;
  final SmsOtpCooldownState otpCooldown;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final TextEditingController emailController;
  final TextEditingController handleController;
  final VoidCallback onRequestOtp;
  final VoidCallback onRequestEmailActivation;
  final VoidCallback onCheckEmailActivation;
  final VoidCallback onSubmitRegister;

  @override
  Widget build(BuildContext context) {
    if (onboarding.isServerInfoLoading) {
      return _OnboardingCapabilityPanel(
        loading: true,
        message: context.l10n.onboardingLoadingServerInfo,
      );
    }
    if (onboarding.isServerInfoFailed) {
      return Consumer(
        builder: (context, ref, _) => _OnboardingCapabilityPanel(
          icon: CupertinoIcons.exclamationmark_triangle,
          message: context.l10n.onboardingServerInfoLoadFailed,
          detail: onboarding.serverInfoError,
          actionLabel: context.l10n.commonRetry,
          onAction: () =>
              ref.read(onboardingProvider.notifier).loadServerInfo(force: true),
        ),
      );
    }
    if (!onboarding.hasRegistrationMethods) {
      return Consumer(
        builder: (context, ref, _) => _OnboardingCapabilityPanel(
          icon: CupertinoIcons.lock,
          message: context.l10n.onboardingRegistrationUnavailable,
          actionLabel: context.l10n.commonRetry,
          onAction: () =>
              ref.read(onboardingProvider.notifier).loadServerInfo(force: true),
        ),
      );
    }
    if (onboarding.usesNoVerificationRegistration) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MacAuthHint(text: context.l10n.onboardingNoVerificationHint),
          const SizedBox(height: 18),
          _MacOutlinedField(
            controller: phoneController,
            semanticsIdentifier: 'e2e-phone-input',
            label: context.l10n.onboardingPhone,
            placeholder: context.l10n.onboardingPhonePlaceholder,
            keyboardType: TextInputType.phone,
            prefix: const _MacPhonePrefix(),
          ),
          const SizedBox(height: 16),
          _MacOutlinedField(
            controller: handleController,
            semanticsIdentifier: 'e2e-handle-input',
            label: context.l10n.onboardingHandle,
            placeholder: context.l10n.onboardingHandlePlaceholder,
            icon: CupertinoIcons.at,
          ),
          const SizedBox(height: 16),
          registrationEntry,
          SizedBox(height: context.awikiResponsive.isPhone ? 22 : 8),
          _MacPrimaryAction(
            label: context.l10n.onboardingCompleteRegister,
            onPressed: onboarding.isBusy ? null : onSubmitRegister,
          ),
        ],
      );
    }

    if (onboarding.authMode == 'phone') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MacOutlinedField(
            controller: phoneController,
            semanticsIdentifier: 'e2e-phone-input',
            label: context.l10n.onboardingPhone,
            placeholder: context.l10n.onboardingPhonePlaceholder,
            keyboardType: TextInputType.phone,
            prefix: const _MacPhonePrefix(),
          ),
          const SizedBox(height: 16),
          _MacOutlinedField(
            controller: handleController,
            semanticsIdentifier: 'e2e-handle-input',
            label: context.l10n.onboardingHandle,
            placeholder: context.l10n.onboardingHandlePlaceholder,
            icon: CupertinoIcons.at,
          ),
          const SizedBox(height: 16),
          _MacOutlinedField(
            controller: otpController,
            semanticsIdentifier: 'e2e-otp-input',
            label: context.l10n.onboardingOtp,
            placeholder: context.l10n.onboardingOtpPlaceholder,
            keyboardType: TextInputType.number,
            icon: CupertinoIcons.number,
            suffix: _MacInlineAction(
              semanticsIdentifier: 'e2e-send-otp-button',
              label: otpCooldown.isCoolingDown
                  ? context.l10n.onboardingResendOtpIn(
                      otpCooldown.remainingSeconds,
                    )
                  : context.l10n.onboardingSendOtp,
              onPressed: onboarding.isBusy || !otpCooldown.canSend
                  ? null
                  : onRequestOtp,
            ),
          ),
          if (otpCooldown.isCoolingDown) const E2eMarker('e2e-otp-sent'),
          _OtpCompleteMarker(controller: otpController),
          const SizedBox(height: 16),
          registrationEntry,
          SizedBox(height: context.awikiResponsive.isPhone ? 22 : 8),
          SizedBox(
            key: const Key('onboarding-mac-phone-submit-action'),
            width: double.infinity,
            child: _MacPrimaryAction(
              label: context.l10n.onboardingPhoneLoginOrRegisterAction,
              onPressed: onboarding.isBusy || !onboarding.canSubmitPhoneOtp
                  ? null
                  : onSubmitRegister,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MacOutlinedField(
          controller: handleController,
          semanticsIdentifier: 'e2e-handle-input',
          label: context.l10n.onboardingHandle,
          placeholder: context.l10n.onboardingHandlePlaceholder,
          icon: CupertinoIcons.at,
        ),
        const SizedBox(height: 16),
        _MacOutlinedField(
          controller: emailController,
          semanticsIdentifier: 'e2e-email-input',
          label: context.l10n.onboardingEmail,
          placeholder: context.l10n.onboardingEmailPlaceholder,
          icon: CupertinoIcons.mail,
          keyboardType: TextInputType.emailAddress,
          suffix: _MacInlineAction(
            label: onboarding.isEmailResendCoolingDown
                ? context.l10n.onboardingResendActivationEmailIn(
                    onboarding.emailResendCountdown,
                  )
                : context.l10n.onboardingSendActivationEmail,
            onPressed: onboarding.isBusy || onboarding.isEmailResendCoolingDown
                ? null
                : onRequestEmailActivation,
          ),
        ),
        const SizedBox(height: 16),
        registrationEntry,
        SizedBox(height: context.awikiResponsive.isPhone ? 22 : 8),
        SizedBox(
          key: const Key('onboarding-mac-email-action'),
          width: double.infinity,
          child: onboarding.emailVerified
              ? _MacPrimaryAction(
                  label: context.l10n.onboardingCompleteEmailRegister,
                  onPressed: onboarding.isBusy ? null : onSubmitRegister,
                )
              : _MacSecondaryAction(
                  label: context.l10n.onboardingCheckActivationStatus,
                  onPressed: onboarding.isBusy ? null : onCheckEmailActivation,
                ),
        ),
      ],
    );
  }
}

class _MacAuthHint extends StatelessWidget {
  const _MacAuthHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.awikiTheme.secondaryText,
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _MacOutlinedField extends StatefulWidget {
  const _MacOutlinedField({
    required this.controller,
    required this.label,
    required this.placeholder,
    this.semanticsIdentifier,
    this.icon,
    this.keyboardType,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final String? semanticsIdentifier;
  final IconData? icon;
  final TextInputType? keyboardType;
  final Widget? prefix;
  final Widget? suffix;

  @override
  State<_MacOutlinedField> createState() => _MacOutlinedFieldState();
}

class _MacOutlinedFieldState extends State<_MacOutlinedField> {
  bool _focused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final phone = context.awikiResponsive.isPhone;
    final fontSize = phone ? 16.0 : 14.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MacFieldLabel(widget.label),
        const SizedBox(height: 6),
        Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _focusNode.requestFocus,
            child: Container(
              constraints: BoxConstraints(minHeight: phone ? 50 : 38),
              padding: phone
                  ? const EdgeInsets.fromLTRB(14, 7, 7, 7)
                  : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              // Focus draws an ink edge; the fill stays paper.
              decoration: _loginPaperDecoration(
                context,
                radius: phone ? 16 : 6,
                edge: _focused ? theme.title : null,
                edgeWidth: _focused && phone ? 1.5 : 1,
              ),
              child: Row(
                children: <Widget>[
                  if (widget.prefix != null) ...<Widget>[
                    widget.prefix!,
                    const SizedBox(width: 8),
                    Container(
                      width: phone ? 0.5 : 1,
                      height: 16,
                      color: theme.border,
                    ),
                    const SizedBox(width: 8),
                  ] else if (!phone &&
                      widget.icon == CupertinoIcons.at) ...<Widget>[
                    // Reference desktop fields: a small quiet "@" for the
                    // handle and no glyph for code or email.
                    Text(
                      '@',
                      style: TextStyle(
                        color: theme.secondaryText,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ] else if (phone && widget.icon != null) ...<Widget>[
                    Icon(widget.icon, size: 18, color: theme.secondaryText),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Semantics(
                      identifier: widget.semanticsIdentifier,
                      child: CupertinoTextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        keyboardType: widget.keyboardType,
                        placeholder: widget.placeholder,
                        decoration: null,
                        padding: EdgeInsets.zero,
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(
                          color: theme.title,
                          fontSize: fontSize,
                          height: 1.2,
                        ),
                        placeholderStyle: TextStyle(
                          color: theme.secondaryText,
                          fontSize: fontSize,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  if (widget.suffix != null) ...<Widget>[
                    const SizedBox(width: 8),
                    widget.suffix!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MacPhonePrefix extends StatelessWidget {
  const _MacPhonePrefix();

  @override
  Widget build(BuildContext context) {
    final phone = context.awikiResponsive.isPhone;
    return Text(
      '+86',
      style: TextStyle(
        color: phone
            ? context.awikiTheme.title
            : context.awikiTheme.secondaryText,
        fontSize: phone ? 14 : 13,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _MacFieldLabel extends StatelessWidget {
  const _MacFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final phone = context.awikiResponsive.isPhone;
    return Text(
      label,
      style: TextStyle(
        color: phone
            ? context.awikiTheme.title
            : context.awikiTheme.secondaryText,
        fontSize: phone ? 13 : 12,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _MacInlineAction extends StatelessWidget {
  const _MacInlineAction({
    required this.label,
    this.semanticsIdentifier,
    this.onPressed,
  });

  final String label;
  final String? semanticsIdentifier;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      tooltip: label,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(7),
      builder: (context, state, child) => AnimatedOpacity(
        opacity: !state.enabled
            ? 0.48
            : state.pressed
            ? 0.72
            : 1,
        duration: const Duration(milliseconds: 120),
        child: child,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: context.awikiResponsive.isPhone
            ? Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: onPressed == null
                    ? null
                    : _loginPaperDecoration(
                        context,
                        radius: 18,
                        edge: context.awikiTheme.title,
                      ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      color: context.awikiTheme.title,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1,
                    ),
                  ),
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: context.awikiTheme.title,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1,
                  ),
                ),
              ),
      ),
    );
  }
}

class _MacPrimaryAction extends StatelessWidget {
  const _MacPrimaryAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      tooltip: label,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: 0.985,
      borderRadius: BorderRadius.circular(6),
      builder: (context, state, child) => AnimatedOpacity(
        opacity: state.pressed ? 0.84 : 1,
        duration: const Duration(milliseconds: 120),
        child: child,
      ),
      child: Container(
        height: context.awikiResponsive.isPhone ? 50 : 40,
        // Monochrome: the button stays solid ink even when disabled, so it
        // never reads as grey; only the label fades.
        decoration: BoxDecoration(
          color: context.awikiTheme.title,
          borderRadius: BorderRadius.circular(
            context.awikiResponsive.isPhone ? 25 : 6,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: context.awikiTheme.primaryForeground.withValues(
                      alpha: onPressed == null ? 0.5 : 1,
                    ),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacSecondaryAction extends StatelessWidget {
  const _MacSecondaryAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      tooltip: label,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: 0.985,
      borderRadius: BorderRadius.circular(6),
      builder: (context, state, child) => AnimatedOpacity(
        opacity: !state.enabled
            ? 0.52
            : state.pressed
            ? 0.80
            : 1,
        duration: const Duration(milliseconds: 120),
        child: child,
      ),
      child: Container(
        height: context.awikiResponsive.isPhone ? 50 : 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: context.awikiResponsive.isPhone
            ? _loginPaperDecoration(
                context,
                radius: 25,
                edge: context.awikiTheme.title,
              )
            : BoxDecoration(
                color: context.awikiTheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.awikiTheme.border),
              ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: context.awikiTheme.title,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _macFieldDecoration(BuildContext context) {
  if (context.awikiResponsive.isPhone) {
    return _loginPaperDecoration(context, radius: 18);
  }
  return BoxDecoration(
    color: context.awikiTheme.surface,
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: context.awikiTheme.border),
  );
}

class _MacFooterButton extends StatelessWidget {
  const _MacFooterButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: tooltip,
      tooltip: tooltip,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: context.awikiTheme.secondaryText, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.awikiTheme.secondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (showChevron) ...<Widget>[
                const SizedBox(width: 7),
                Icon(
                  CupertinoIcons.chevron_down,
                  color: context.awikiTheme.tertiaryText,
                  size: 12,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
