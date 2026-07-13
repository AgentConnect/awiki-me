part of '../onboarding_page.dart';

class _MacOnboardingScaffold extends StatelessWidget {
  const _MacOnboardingScaffold({
    required this.onboarding,
    required this.credentials,
    required this.phoneController,
    required this.otpController,
    required this.emailController,
    required this.handleController,
    required this.onLogin,
    required this.onImport,
    required this.onRefresh,
    required this.onModeChanged,
    required this.onAuthModeChanged,
    required this.onRequestOtp,
    required this.onRequestEmailActivation,
    required this.onCheckEmailActivation,
    required this.onRegisterStepChanged,
    required this.onSubmitRegister,
    required this.activeTenant,
    required this.localeMode,
    required this.onLanguagePressed,
    required this.onTenantPressed,
  });

  final OnboardingState onboarding;
  final List<SessionIdentity> credentials;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final TextEditingController emailController;
  final TextEditingController handleController;
  final Future<void> Function(String credentialName) onLogin;
  final VoidCallback? onImport;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onAuthModeChanged;
  final VoidCallback onRequestOtp;
  final VoidCallback onRequestEmailActivation;
  final VoidCallback onCheckEmailActivation;
  final ValueChanged<int> onRegisterStepChanged;
  final VoidCallback onSubmitRegister;
  final AppTenantProfile activeTenant;
  final AppLocaleMode localeMode;
  final VoidCallback onLanguagePressed;
  final VoidCallback onTenantPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFF8FBFF), Color(0xFFFFFFFF)],
          ),
        ),
        child: Stack(
          children: <Widget>[
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _MacOnboardingBackgroundPainter()),
              ),
            ),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useCompactLayout = constraints.maxWidth < 1080;
                  final footerReserve = useCompactLayout ? 104.0 : 122.0;
                  final cardMaxHeight = constraints.maxHeight - footerReserve;
                  final authCard = _MacAuthCard(
                    maxHeight: cardMaxHeight < 420 ? 420 : cardMaxHeight,
                    onboarding: onboarding,
                    credentials: credentials,
                    phoneController: phoneController,
                    otpController: otpController,
                    emailController: emailController,
                    handleController: handleController,
                    onLogin: onLogin,
                    onImport: onImport,
                    onRefresh: onRefresh,
                    onModeChanged: onModeChanged,
                    onAuthModeChanged: onAuthModeChanged,
                    onRequestOtp: onRequestOtp,
                    onRequestEmailActivation: onRequestEmailActivation,
                    onCheckEmailActivation: onCheckEmailActivation,
                    onRegisterStepChanged: onRegisterStepChanged,
                    onSubmitRegister: onSubmitRegister,
                  );
                  return SafeArea(
                    minimum: const EdgeInsets.only(bottom: 88),
                    child: Padding(
                      padding: useCompactLayout
                          ? const EdgeInsets.fromLTRB(28, 24, 28, 12)
                          : const EdgeInsets.fromLTRB(72, 34, 82, 18),
                      child: useCompactLayout
                          ? Center(child: authCard)
                          : Row(
                              children: <Widget>[
                                const Expanded(
                                  flex: 8,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _MacOnboardingHero(),
                                  ),
                                ),
                                const SizedBox(width: 64),
                                Expanded(
                                  flex: 10,
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: authCard,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 28,
              right: 28,
              bottom: 18,
              child: SafeArea(
                top: false,
                minimum: EdgeInsets.zero,
                child: _MacOnboardingFooter(
                  tenant: activeTenant,
                  localeMode: localeMode,
                  onLanguagePressed: onLanguagePressed,
                  onTenantPressed: onTenantPressed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacOnboardingBackgroundPainter extends CustomPainter {
  const _MacOnboardingBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x0D0B65F8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final origin = Offset(size.width * 0.62, size.height * 0.44);
    canvas.drawOval(
      Rect.fromCenter(
        center: origin,
        width: size.width * 1.08,
        height: size.height * 1.32,
      ),
      paint,
    );
    paint.color = const Color(0x080B65F8);
    canvas.drawOval(
      Rect.fromCenter(
        center: origin,
        width: size.width * 1.32,
        height: size.height * 1.56,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MacOnboardingHero extends StatelessWidget {
  const _MacOnboardingHero();

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0B65F8);
    const ink = Color(0xFF101B32);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFE6EDF8)),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x140B65F8),
                      blurRadius: 22,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/branding/awiki-me-logo.png',
                    width: 43,
                    height: 43,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text(
                      'AW',
                      style: TextStyle(
                        color: blue,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              const Text(
                'AWiki',
                key: Key('onboarding-mac-hero-title'),
                style: TextStyle(
                  color: ink,
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 38),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: context.l10n.onboardingMacHeroPrefix),
                TextSpan(
                  text: context.l10n.onboardingMacHeroHighlight,
                  style: const TextStyle(color: blue),
                ),
                TextSpan(text: context.l10n.onboardingMacHeroSuffix),
              ],
            ),
            style: const TextStyle(
              color: ink,
              fontSize: 31,
              height: 1.22,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.25,
            ),
          ),
          const SizedBox(height: 13),
          Text(
            context.l10n.onboardingMacSubtitle,
            style: const TextStyle(
              color: Color(0xFF64708A),
              fontSize: 15,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 34),
          _MacFeatureItem(
            icon: CupertinoIcons.shield,
            title: context.l10n.onboardingMacFeatureSecureTitle,
            subtitle: context.l10n.onboardingMacFeatureSecureSubtitle,
          ),
          const SizedBox(height: 22),
          _MacFeatureItem(
            icon: CupertinoIcons.person_2,
            title: context.l10n.onboardingMacFeatureCollaborateTitle,
            subtitle: context.l10n.onboardingMacFeatureCollaborateSubtitle,
          ),
          const SizedBox(height: 22),
          _MacFeatureItem(
            icon: CupertinoIcons.lock,
            title: context.l10n.onboardingMacFeatureControlTitle,
            subtitle: context.l10n.onboardingMacFeatureControlSubtitle,
          ),
          const SizedBox(height: 40),
          const _MacDotGrid(),
        ],
      ),
    );
  }
}

class _MacFeatureItem extends StatelessWidget {
  const _MacFeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF5FF),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(icon, color: const Color(0xFF0B65F8), size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF17213A),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF7B879D),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MacDotGrid extends StatelessWidget {
  const _MacDotGrid();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 116,
      height: 54,
      child: Wrap(
        spacing: 13,
        runSpacing: 10,
        children: List<Widget>.generate(
          30,
          (_) => Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFBFD1EA),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ),
    );
  }
}

class _MacAuthCard extends StatelessWidget {
  const _MacAuthCard({
    required this.maxHeight,
    required this.onboarding,
    required this.credentials,
    required this.phoneController,
    required this.otpController,
    required this.emailController,
    required this.handleController,
    required this.onLogin,
    required this.onImport,
    required this.onRefresh,
    required this.onModeChanged,
    required this.onAuthModeChanged,
    required this.onRequestOtp,
    required this.onRequestEmailActivation,
    required this.onCheckEmailActivation,
    required this.onRegisterStepChanged,
    required this.onSubmitRegister,
  });

  final double maxHeight;
  final OnboardingState onboarding;
  final List<SessionIdentity> credentials;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final TextEditingController emailController;
  final TextEditingController handleController;
  final Future<void> Function(String credentialName) onLogin;
  final VoidCallback? onImport;
  final VoidCallback? onRefresh;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onAuthModeChanged;
  final VoidCallback onRequestOtp;
  final VoidCallback onRequestEmailActivation;
  final VoidCallback onCheckEmailActivation;
  final ValueChanged<int> onRegisterStepChanged;
  final VoidCallback onSubmitRegister;

  @override
  Widget build(BuildContext context) {
    final usingCredential = onboarding.entryMode == 'login';
    return Container(
      key: const Key('onboarding-mac-auth-card'),
      constraints: BoxConstraints(maxWidth: 540, maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE5F0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120B1F3A),
            blurRadius: 38,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 28, 34, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                usingCredential
                    ? context.l10n.onboardingLogin
                    : context.l10n.onboardingRegister,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF101B32),
                  fontSize: 25,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                usingCredential
                    ? context.l10n.onboardingCredentialsField
                    : context.l10n.onboardingLoginRegisterHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF66728A),
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              _MacAuthMethodSelector(
                onboarding: onboarding,
                onModeChanged: onModeChanged,
                onAuthModeChanged: onAuthModeChanged,
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: usingCredential
                    ? _MacLoginForm(
                        key: const ValueKey<String>('mac-login-form'),
                        credentials: credentials,
                        onLogin: onLogin,
                        onImport: onImport,
                        onRefresh: onRefresh,
                      )
                    : _MacRegisterForm(
                        key: ValueKey<String>(
                          'mac-register-${onboarding.authMode}-${onboarding.registerStep}',
                        ),
                        onboarding: onboarding,
                        phoneController: phoneController,
                        otpController: otpController,
                        emailController: emailController,
                        handleController: handleController,
                        onRequestOtp: onRequestOtp,
                        onRequestEmailActivation: onRequestEmailActivation,
                        onCheckEmailActivation: onCheckEmailActivation,
                        onRegisterStepChanged: onRegisterStepChanged,
                        onSubmitRegister: onSubmitRegister,
                      ),
              ),
              if (!usingCredential && credentials.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                _MacLocalIdentityShortcut(
                  credentials: credentials,
                  onLogin: onLogin,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MacAuthMethodSelector extends StatelessWidget {
  const _MacAuthMethodSelector({
    required this.onboarding,
    required this.onModeChanged,
    required this.onAuthModeChanged,
  });

  final OnboardingState onboarding;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onAuthModeChanged;

  @override
  Widget build(BuildContext context) {
    final methods = onboarding.registrationMethods;
    final usingCredential = onboarding.entryMode == 'login';
    return Container(
      key: const Key('onboarding-mac-auth-method-tabs'),
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE5F0)),
      ),
      child: Row(
        children: <Widget>[
          for (final method in methods)
            Expanded(
              child: _MacAuthMethodButton(
                key: Key('auth-mode-${method.id.wireName}'),
                label: _authModeLabel(context, method.id),
                icon: _macAuthModeIcon(method.id),
                selected:
                    !usingCredential &&
                    onboarding.authMode == method.id.wireName,
                onTap: () {
                  onModeChanged('register');
                  onAuthModeChanged(method.id.wireName);
                },
              ),
            ),
          Expanded(
            child: _MacAuthMethodButton(
              key: const Key('onboarding-mac-credential-mode'),
              label: context.l10n.onboardingCredentialsField,
              icon: CupertinoIcons.shield,
              selected: usingCredential,
              onTap: () => onModeChanged('login'),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _macAuthModeIcon(OnboardingIdentityMethodId id) {
  return switch (id) {
    OnboardingIdentityMethodId.phone => CupertinoIcons.phone,
    OnboardingIdentityMethodId.email => CupertinoIcons.mail,
    OnboardingIdentityMethodId.handleOnly => CupertinoIcons.at,
  };
}

class _MacAuthMethodButton extends StatelessWidget {
  const _MacAuthMethodButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      scaleOnPress: true,
      pressedScale: 0.985,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? CupertinoColors.white : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? const Color(0xFF7EAAFF)
                : CupertinoColors.transparent,
          ),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x140B65F8),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: selected
                  ? const Color(0xFF0B65F8)
                  : const Color(0xFF66728A),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF0B65F8)
                        : const Color(0xFF39445D),
                    fontSize: 14,
                    height: 1,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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

class _MacLoginForm extends StatelessWidget {
  const _MacLoginForm({
    super.key,
    required this.credentials,
    required this.onLogin,
    required this.onImport,
    required this.onRefresh,
  });

  final List<SessionIdentity> credentials;
  final Future<void> Function(String credentialName) onLogin;
  final VoidCallback? onImport;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MacCredentialPicker(credentials: credentials, onLogin: onLogin),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: _MacSecondaryAction(
                label: context.l10n.onboardingImportCredential,
                icon: CupertinoIcons.square_arrow_down,
                onPressed: onImport,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MacSecondaryAction(
                label: context.l10n.onboardingRefreshCredentials,
                icon: CupertinoIcons.arrow_clockwise,
                onPressed: onRefresh,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MacLocalIdentityShortcut extends StatelessWidget {
  const _MacLocalIdentityShortcut({
    required this.credentials,
    required this.onLogin,
  });

  final List<SessionIdentity> credentials;
  final Future<void> Function(String credentialName) onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('onboarding-mac-local-credential-section'),
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: _MacDivider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                context.l10n.onboardingLogin,
                style: const TextStyle(
                  color: Color(0xFF7B879D),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Expanded(child: _MacDivider()),
          ],
        ),
        const SizedBox(height: 18),
        for (final identity in credentials)
          Padding(
            padding: EdgeInsets.only(
              bottom: identity == credentials.last ? 0 : 10,
            ),
            child: _MacCredentialTile(
              identity: identity,
              onTap: () => onLogin(identity.credentialName),
            ),
          ),
      ],
    );
  }
}

class _MacDivider extends StatelessWidget {
  const _MacDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFE1E7F0));
  }
}

class _MacCredentialPicker extends StatelessWidget {
  const _MacCredentialPicker({
    required this.credentials,
    required this.onLogin,
  });

  final List<SessionIdentity> credentials;
  final Future<void> Function(String credentialName) onLogin;

  @override
  Widget build(BuildContext context) {
    if (credentials.isEmpty) {
      return Container(
        height: 106,
        decoration: _macFieldDecoration(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  CupertinoIcons.person_crop_circle_badge_exclam,
                  color: Color(0xFF7B879D),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    context.l10n.onboardingNoLocalCredentialSaved,
                    style: const TextStyle(
                      color: Color(0xFF7B879D),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      children: credentials
          .map(
            (identity) => Padding(
              padding: EdgeInsets.only(
                bottom: identity == credentials.last ? 0 : 10,
              ),
              child: _MacCredentialTile(
                identity: identity,
                onTap: () => onLogin(identity.credentialName),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MacCredentialTile extends StatelessWidget {
  const _MacCredentialTile({required this.identity, required this.onTap});

  final SessionIdentity identity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = (identity.handle?.trim().isNotEmpty == true)
        ? identity.handle!.trim()
        : identity.credentialName;
    return AppPressableTile(
      onTap: onTap,
      semanticLabel: identity.displayName,
      borderRadius: BorderRadius.circular(11),
      backgroundColor: CupertinoColors.white,
      child: Container(
        constraints: const BoxConstraints(minHeight: 68),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: _macFieldDecoration(),
        child: Row(
          children: <Widget>[
            AvatarBadge(seed: identity.displayName, size: 38),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    identity.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF17213A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF7B879D),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              context.l10n.onboardingLogin,
              style: const TextStyle(
                color: Color(0xFF0B65F8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 7),
            const Icon(
              CupertinoIcons.chevron_right,
              color: Color(0xFF8EA0B8),
              size: 15,
            ),
          ],
        ),
      ),
    );
  }
}

class _MacRegisterForm extends StatelessWidget {
  const _MacRegisterForm({
    super.key,
    required this.onboarding,
    required this.phoneController,
    required this.otpController,
    required this.emailController,
    required this.handleController,
    required this.onRequestOtp,
    required this.onRequestEmailActivation,
    required this.onCheckEmailActivation,
    required this.onRegisterStepChanged,
    required this.onSubmitRegister,
  });

  final OnboardingState onboarding;
  final TextEditingController phoneController;
  final TextEditingController otpController;
  final TextEditingController emailController;
  final TextEditingController handleController;
  final VoidCallback onRequestOtp;
  final VoidCallback onRequestEmailActivation;
  final VoidCallback onCheckEmailActivation;
  final ValueChanged<int> onRegisterStepChanged;
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
            label: context.l10n.onboardingPhone,
            placeholder: context.l10n.onboardingPhonePlaceholder,
            keyboardType: TextInputType.phone,
            prefix: const _MacPhonePrefix(),
          ),
          const SizedBox(height: 16),
          _MacOutlinedField(
            controller: handleController,
            label: context.l10n.onboardingHandle,
            placeholder: context.l10n.onboardingHandlePlaceholder,
            icon: CupertinoIcons.at,
          ),
          const SizedBox(height: 22),
          _MacPrimaryAction(
            label: context.l10n.onboardingCompleteRegister,
            onPressed: onboarding.isBusy ? null : onSubmitRegister,
          ),
        ],
      );
    }

    if (onboarding.registerStep == 2 && onboarding.authMode == 'phone') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MacOutlinedField(
            controller: handleController,
            label: context.l10n.onboardingHandle,
            placeholder: context.l10n.onboardingHandlePlaceholder,
            icon: CupertinoIcons.at,
          ),
          const SizedBox(height: 22),
          Row(
            children: <Widget>[
              Expanded(
                child: _MacSecondaryAction(
                  label: context.l10n.commonPrevious,
                  onPressed: () => onRegisterStepChanged(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MacPrimaryAction(
                  label: context.l10n.onboardingCompleteRegister,
                  onPressed: onboarding.isBusy ? null : onSubmitRegister,
                ),
              ),
            ],
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
            label: context.l10n.onboardingPhone,
            placeholder: context.l10n.onboardingPhonePlaceholder,
            keyboardType: TextInputType.phone,
            prefix: const _MacPhonePrefix(),
          ),
          const SizedBox(height: 16),
          _MacOutlinedField(
            controller: otpController,
            label: context.l10n.onboardingOtp,
            placeholder: context.l10n.onboardingOtpPlaceholder,
            keyboardType: TextInputType.number,
            icon: CupertinoIcons.number,
            suffix: _MacInlineAction(
              label: onboarding.isOtpResendCoolingDown
                  ? context.l10n.onboardingResendOtpIn(
                      onboarding.otpResendCountdown,
                    )
                  : context.l10n.onboardingSendOtp,
              onPressed: onboarding.isBusy || onboarding.isOtpResendCoolingDown
                  ? null
                  : onRequestOtp,
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            key: const Key('onboarding-mac-phone-next-action'),
            width: double.infinity,
            child: _MacPrimaryAction(
              label: context.l10n.commonNext,
              onPressed: onboarding.isBusy
                  ? null
                  : () => onRegisterStepChanged(2),
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
          label: context.l10n.onboardingHandle,
          placeholder: context.l10n.onboardingHandlePlaceholder,
          icon: CupertinoIcons.at,
        ),
        const SizedBox(height: 16),
        _MacOutlinedField(
          controller: emailController,
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
      style: const TextStyle(
        color: Color(0xFF66728A),
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _MacOutlinedField extends StatelessWidget {
  const _MacOutlinedField({
    required this.controller,
    required this.label,
    required this.placeholder,
    this.icon,
    this.keyboardType,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final IconData? icon;
  final TextInputType? keyboardType;
  final Widget? prefix;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MacFieldLabel(label),
        const SizedBox(height: 9),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: _macFieldDecoration(),
          child: Row(
            children: <Widget>[
              if (prefix != null) ...<Widget>[
                prefix!,
                const SizedBox(width: 12),
                Container(width: 1, height: 25, color: const Color(0xFFE1E7F0)),
                const SizedBox(width: 12),
              ] else if (icon != null) ...<Widget>[
                Icon(icon, size: 18, color: const Color(0xFF66728A)),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  placeholder: placeholder,
                  decoration: null,
                  padding: EdgeInsets.zero,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 14,
                    height: 1.2,
                  ),
                  placeholderStyle: const TextStyle(
                    color: Color(0xFF8795AA),
                    fontSize: 14,
                    height: 1.2,
                  ),
                ),
              ),
              if (suffix != null) ...<Widget>[
                const SizedBox(width: 10),
                Container(width: 1, height: 25, color: const Color(0xFFE1E7F0)),
                const SizedBox(width: 10),
                suffix!,
              ],
            ],
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
    return const Text(
      '+86',
      style: TextStyle(
        color: Color(0xFF39445D),
        fontSize: 14,
        fontWeight: FontWeight.w500,
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
      style: const TextStyle(
        color: Color(0xFF27334A),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _MacInlineAction extends StatelessWidget {
  const _MacInlineAction({required this.label, this.onPressed});

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
            style: const TextStyle(
              color: Color(0xFF0B65F8),
              fontSize: 13,
              fontWeight: FontWeight.w600,
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
      borderRadius: BorderRadius.circular(9),
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
        height: 48,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[Color(0xFF0B65F8), Color(0xFF0752F0)],
          ),
          borderRadius: BorderRadius.circular(9),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x220B65F8),
              blurRadius: 16,
              offset: Offset(0, 7),
            ),
          ],
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
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
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
  const _MacSecondaryAction({required this.label, this.icon, this.onPressed});

  final String label;
  final IconData? icon;
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
      borderRadius: BorderRadius.circular(9),
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
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: CupertinoColors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFD5DFEC)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, color: const Color(0xFF39445D), size: 17),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Color(0xFF27334A),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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

BoxDecoration _macFieldDecoration() {
  return BoxDecoration(
    color: CupertinoColors.white,
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: const Color(0xFFD5DFEC)),
  );
}

class _MacOnboardingFooter extends StatelessWidget {
  const _MacOnboardingFooter({
    required this.tenant,
    required this.localeMode,
    required this.onLanguagePressed,
    required this.onTenantPressed,
  });

  final AppTenantProfile tenant;
  final AppLocaleMode localeMode;
  final VoidCallback onLanguagePressed;
  final VoidCallback onTenantPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Row(
        children: <Widget>[
          _MacFooterButton(
            key: const Key('onboarding-language-switcher-button'),
            icon: CupertinoIcons.globe,
            label: appLocaleModeLabel(context, localeMode),
            tooltip: context.l10n.settingsLanguage,
            onTap: onLanguagePressed,
          ),
          const Spacer(),
          _MacFooterButton(
            icon: CupertinoIcons.globe,
            label: tenant.name,
            tooltip: context.l10n.tenantSwitcherLabel,
            onTap: onTenantPressed,
          ),
        ],
      ),
    );
  }
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
              Icon(icon, color: const Color(0xFF66728A), size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF536078),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              const Icon(
                CupertinoIcons.chevron_down,
                color: Color(0xFF8A98AD),
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
