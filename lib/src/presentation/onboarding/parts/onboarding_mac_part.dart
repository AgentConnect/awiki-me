// [INPUT]: Onboarding page state and callbacks from the parent presentation surface.
// [OUTPUT]: Desktop login, registration, and local-identity login controls.
// [POS]: Part of onboarding_page.dart; existing Handle actions are chosen by the parent.

part of '../onboarding_page.dart';

class _MacOnboardingScaffold extends StatelessWidget {
  const _MacOnboardingScaffold({
    required this.onboarding,
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
  final VoidCallback onLanguagePressed;
  final VoidCallback onTenantPressed;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return CupertinoPageScaffold(
      backgroundColor: theme.surface,
      child: SafeArea(
        child: AwikiSystemNavigationClearance(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth <= 700;
              final tenantButton = _MacFooterButton(
                key: const Key('onboarding-tenant-switcher-button'),
                icon: CupertinoIcons.globe,
                label: activeTenant.name,
                tooltip: context.l10n.tenantSwitcherLabel,
                onTap: onTenantPressed,
              );
              final languageButton = _MacFooterButton(
                key: const Key('onboarding-language-switcher-button'),
                icon: CupertinoIcons.globe,
                label: appLocaleModeLabel(context, localeMode),
                tooltip: context.l10n.settingsLanguage,
                onTap: onLanguagePressed,
              );
              final form = Expanded(
                child: ColoredBox(
                  color: theme.surface,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 20 : 40,
                      compact ? 24 : 44,
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
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                      decoration: BoxDecoration(
                        color: theme.background,
                        border: Border(bottom: BorderSide(color: theme.border)),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Expanded(flex: 3, child: _MacCompactBrand()),
                          const SizedBox(width: 12),
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
                    width: 296,
                    decoration: BoxDecoration(
                      color: theme.background,
                      border: Border(right: BorderSide(color: theme.border)),
                    ),
                    padding: const EdgeInsets.fromLTRB(32, 64, 28, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Expanded(
                          child: SingleChildScrollView(
                            child: _MacOnboardingHero(),
                          ),
                        ),
                        tenantButton,
                        languageButton,
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
  }
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
    final theme = context.awikiTheme;
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
            CupertinoSlidingSegmentedControl<bool>(
              key: const Key('onboarding-entry-tabs'),
              groupValue: showIdentities,
              backgroundColor: theme.subtleSurface,
              thumbColor: theme.surface,
              disabledChildren: onboarding.isBusy
                  ? const <bool>{false, true}
                  : const <bool>{},
              onValueChanged: (value) {
                if (value != null && !onboarding.isBusy) {
                  ref
                      .read(onboardingProvider.notifier)
                      .setEntryMode(value ? 'login' : 'register');
                }
              },
              children: <bool, Widget>{
                false: Padding(
                  key: const Key('onboarding-register-entry'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    context.l10n.onboardingRegister,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                true: Padding(
                  key: const Key('onboarding-identity-entry'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    context.l10n.onboardingLogin,
                    style: TextStyle(
                      color: theme.title,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              },
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
              if (onboarding.hasRegistrationMethods) ...<Widget>[
                _MacAuthMethodSelector(
                  onboarding: onboarding,
                  onAuthModeChanged: onAuthModeChanged,
                ),
                const SizedBox(height: 16),
              ],
              _MacRegisterForm(
                key: ValueKey<String>('mac-register-${onboarding.authMode}'),
                onboarding: onboarding,
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
          width: 34,
          height: 34,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'AWiki Me',
            style: TextStyle(
              color: context.awikiTheme.title,
              fontSize: 15,
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
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      decoration: _macFieldDecoration(context),
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
                  padding: const EdgeInsets.fromLTRB(15, 11, 12, 11),
                  child: Row(
                    children: <Widget>[
                      AvatarBadge(seed: displayName, size: 38),
                      const SizedBox(width: 13),
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
                                  fontSize: 15,
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
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: 11),
              color: theme.navigationBorder,
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
                          size: 17,
                          color: enabled ? theme.danger : theme.tertiaryText,
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
          PendingHandleRecoveryEntry(
            handleController: handleController,
            phoneController: phoneController,
          ),
          const SizedBox(height: 22),
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
          PendingHandleRecoveryEntry(
            handleController: handleController,
            phoneController: phoneController,
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
          const SizedBox(height: 22),
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
        PendingHandleRecoveryEntry(
          handleController: handleController,
          phoneController: phoneController,
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
        const SizedBox(height: 22),
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
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _focused ? theme.surface : theme.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _focused ? theme.primary : theme.border,
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (widget.prefix != null) ...<Widget>[
                    widget.prefix!,
                    const SizedBox(width: 8),
                    Container(width: 1, height: 16, color: theme.border),
                    const SizedBox(width: 8),
                  ] else if (widget.icon != null) ...<Widget>[
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
                          fontSize: 14,
                          height: 1.2,
                        ),
                        placeholderStyle: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 14,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  if (widget.suffix != null) ...<Widget>[
                    const SizedBox(width: 6),
                    Container(width: 1, height: 16, color: theme.border),
                    const SizedBox(width: 6),
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
    return Text(
      '+86',
      style: TextStyle(
        color: context.awikiTheme.title,
        fontSize: 14,
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
    return Text(
      label,
      style: TextStyle(
        color: context.awikiTheme.title,
        fontSize: 13,
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
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: context.awikiTheme.primary,
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
        opacity: !state.enabled
            ? 0.52
            : state.pressed
            ? 0.84
            : 1,
        duration: const Duration(milliseconds: 120),
        child: child,
      ),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: context.awikiTheme.primaryDark,
          borderRadius: BorderRadius.circular(6),
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
                    color: context.awikiTheme.primaryForeground,
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
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
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
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

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
              const SizedBox(width: 7),
              Icon(
                CupertinoIcons.chevron_down,
                color: context.awikiTheme.tertiaryText,
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
