import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../domain/entities/session_identity.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'onboarding_provider.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final emailController = TextEditingController();
  final handleController = TextEditingController(text: 'awikime');
  final nickController = TextEditingController(text: 'AWiki Me');

  String get _normalizedPhone => phoneController.text.trim();

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    handleController.dispose();
    nickController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final credentials = ref.watch(sessionProvider).localCredentials;
    final runtime = ref.read(appRuntimeProvider.notifier);
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: AwikiAdaptiveScaffold(
        alignment: responsive.isPhone ? Alignment.topCenter : Alignment.center,
        maxWidth: responsive.formMaxWidth,
        includeBottomSafeArea: true,
        padding: EdgeInsets.fromLTRB(
          responsive.isPhone ? 24 : 0,
          responsive.isPhone ? 40 : 32,
          responsive.isPhone ? 24 : 0,
          24,
        ),
        child: ListView(
          children: <Widget>[
            SizedBox(height: responsive.spacing(responsive.isPhone ? 20 : 8)),
            Center(
              child: Image.asset(
                'assets/branding/awiki-me-logo.png',
                width: responsive.scaled(125),
                height: responsive.scaled(125),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(
                  '@_',
                  style: TextStyle(
                    fontSize: responsive.isPhone ? 72 : responsive.scaled(58),
                    fontWeight: FontWeight.w700,
                    color: theme.primary,
                    height: 1,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: responsive.spacing(responsive.isPhone ? 48 : 40),
            ),
            _SegmentedPill(
              value: onboarding.entryMode,
              options: <String, String>{
                'login': context.l10n.onboardingLogin,
                'register': context.l10n.onboardingRegister,
              },
              onChanged: ref.read(onboardingProvider.notifier).setEntryMode,
            ),
            SizedBox(height: responsive.spacing(24)),
            if (onboarding.entryMode == 'login') ...<Widget>[
              _LocalCredentialsCard(
                credentials: credentials,
                onLogin: runtime.loginWithLocalCredential,
              ),
              SizedBox(height: responsive.spacing(16)),
              _LoginToolRow(
                importLabel: context.l10n.onboardingImportCredential,
                refreshLabel: context.l10n.onboardingRefreshCredentials,
                onImport: runtime.importCredentialArchive,
                onRefresh: () =>
                    ref.read(appRuntimeProvider.notifier).initialize(),
              ),
            ] else ...<Widget>[
              if (onboarding.registerStep == 1) ...<Widget>[
                _AuthModeToggle(
                  value: onboarding.authMode,
                  onChanged: ref.read(onboardingProvider.notifier).setAuthMode,
                ),
                SizedBox(
                  height: responsive.spacing(responsive.isPhone ? 32 : 24),
                ),
                if (onboarding.authMode == 'phone') ...<Widget>[
                  AppTextField(
                    controller: phoneController,
                    label: context.l10n.onboardingPhone,
                    placeholder: context.l10n.onboardingPhonePlaceholder,
                    keyboardType: TextInputType.phone,
                    showLabel: !responsive.isPhone,
                    prefix: responsive.isPhone
                        ? const _PhoneFieldPrefix(code: '+86')
                        : null,
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  AppPrimaryButton(
                    label: context.l10n.onboardingSendOtp,
                    onPressed: onboarding.isBusy
                        ? null
                        : () => ref
                            .read(onboardingProvider.notifier)
                            .requestOtp(_normalizedPhone),
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  AppTextField(
                    controller: otpController,
                    label: context.l10n.onboardingOtp,
                    placeholder: context.l10n.onboardingOtpPlaceholder,
                    keyboardType: TextInputType.number,
                    showLabel: !responsive.isPhone,
                  ),
                ] else ...<Widget>[
                  AppTextField(
                    controller: emailController,
                    label: context.l10n.onboardingEmail,
                    placeholder: context.l10n.onboardingEmailPlaceholder,
                    keyboardType: TextInputType.emailAddress,
                    showLabel: !responsive.isPhone,
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  AppPrimaryButton(
                    label: onboarding.isEmailResendCoolingDown
                        ? context.l10n.onboardingResendActivationEmailIn(
                            onboarding.emailResendCountdown,
                          )
                        : context.l10n.onboardingSendActivationEmail,
                    onPressed:
                        onboarding.isBusy || onboarding.isEmailResendCoolingDown
                            ? null
                            : () => ref
                                .read(onboardingProvider.notifier)
                                .requestEmailActivation(
                                    emailController.text.trim()),
                  ),
                  SizedBox(height: responsive.spacing(12)),
                  (onboarding.emailVerified
                      ? AppPrimaryButton(
                          label: context.l10n.commonNext,
                          onPressed: onboarding.isBusy
                              ? null
                              : () => ref
                                  .read(onboardingProvider.notifier)
                                  .setRegisterStep(2),
                        )
                      : AppSecondaryButton(
                          label: onboarding.emailVerified
                              ? context.l10n.onboardingEmailActivated
                              : context.l10n.onboardingCheckActivationStatus,
                          onPressed: onboarding.isBusy
                              ? null
                              : () => ref
                                  .read(onboardingProvider.notifier)
                                  .checkEmailActivation(
                                      emailController.text.trim()),
                        )),
                ],
                SizedBox(height: responsive.spacing(16)),
                if (onboarding.authMode == 'phone')
                  AppPrimaryButton(
                    label: context.l10n.commonNext,
                    onPressed: onboarding.isBusy
                        ? null
                        : () => ref
                            .read(onboardingProvider.notifier)
                            .setRegisterStep(2),
                  ),
              ] else ...<Widget>[
                AppTextField(
                  controller: handleController,
                  label: context.l10n.onboardingHandle,
                  placeholder: context.l10n.onboardingHandlePlaceholder,
                ),
                SizedBox(height: responsive.spacing(12)),
                AppTextField(
                  controller: nickController,
                  label: context.l10n.onboardingNickname,
                  placeholder: context.l10n.onboardingNicknamePlaceholder,
                ),
                SizedBox(height: responsive.spacing(20)),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppSecondaryButton(
                        label: context.l10n.commonPrevious,
                        onPressed: () => ref
                            .read(onboardingProvider.notifier)
                            .setRegisterStep(1),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(12)),
                    Expanded(
                      child: AppPrimaryButton(
                        label: context.l10n.onboardingCompleteRegister,
                        onPressed: onboarding.isBusy
                            ? null
                            : () => _submitRegister(context),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            SizedBox(height: responsive.spacing(56)),
            Center(
              child: Text(
                'Base on awiki.ai',
                style: TextStyle(
                  color: theme.infoAccent,
                  fontSize: responsive.titleLg,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRegister(BuildContext context) async {
    final notifier = ref.read(onboardingProvider.notifier);
    final profileMarkdown = '# ${nickController.text.trim()}\n\n';
    if (ref.read(onboardingProvider).authMode == 'phone') {
      await notifier.registerWithPhone(
        phone: _normalizedPhone,
        otp: otpController.text.trim(),
        handle: handleController.text.trim(),
        nickName: nickController.text.trim(),
        profileMarkdown: profileMarkdown,
      );
      return;
    }
    await notifier.registerWithEmail(
      email: emailController.text.trim(),
      handle: handleController.text.trim(),
      nickName: nickController.text.trim(),
      profileMarkdown: profileMarkdown,
    );
  }
}

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
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return AppSurface(
      color: theme.mutedSurface,
      radius: AwikiMeRadii.pill,
      padding: responsive.scaledInsets(const EdgeInsets.all(4)),
      child: Row(
        children: options.entries
            .map(
              (entry) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(entry.key),
                  child: AppSurface(
                    padding: EdgeInsets.symmetric(
                      vertical: responsive.spacing(12),
                    ),
                    color: value == entry.key
                        ? theme.surface
                        : CupertinoColors.transparent,
                    radius: AwikiMeRadii.pill,
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: responsive.bodyMd,
                        fontWeight: FontWeight.w700,
                        color: value == entry.key
                            ? theme.title
                            : theme.secondaryText,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AuthModeToggle extends StatelessWidget {
  const _AuthModeToggle({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _AuthModeOption(
          key: const Key('auth-mode-phone'),
          selected: value == 'phone',
          assetName: 'assets/icons/icon_mobile.svg',
          label: context.l10n.onboardingPhone,
          activeColor: theme.primary,
          inactiveColor: theme.mutedSurface,
          onTap: () => onChanged('phone'),
        ),
        SizedBox(width: responsive.spacing(14)),
        _AuthModeOption(
          key: const Key('auth-mode-email'),
          selected: value == 'email',
          assetName: 'assets/icons/icon_mail.svg',
          label: context.l10n.onboardingEmail,
          activeColor: theme.primary,
          inactiveColor: theme.mutedSurface,
          onTap: () => onChanged('email'),
        ),
      ],
    );
  }
}

class _AuthModeOption extends StatelessWidget {
  const _AuthModeOption({
    super.key,
    required this.selected,
    required this.assetName,
    required this.label,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final bool selected;
  final String assetName;
  final String label;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final buttonSize = responsive.isPhone ? 72.0 : responsive.scaled(36);
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            color: selected ? activeColor : inactiveColor,
            borderRadius: BorderRadius.circular(buttonSize / 2),
          ),
          child: Center(
            child: AwikiAssetIcon(
              assetName: assetName,
              size: responsive.isPhone ? 30 : responsive.iconMd,
              color: theme.title,
            ),
          ),
        ),
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
            fontWeight: FontWeight.w700,
            color: theme.title,
          ),
        ),
        SizedBox(width: responsive.spacing(10)),
        Container(
          width: 1,
          height: responsive.scaled(26),
          color: theme.border,
        ),
      ],
    );
  }
}

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
  const _CredentialCardTile({
    required this.identity,
    required this.onTap,
  });

  final SessionIdentity identity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    final subtitle = (identity.handle?.trim().isNotEmpty == true)
        ? identity.handle!.trim()
        : identity.credentialName;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
                      fontWeight: FontWeight.w700,
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
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
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
                  borderRadius: BorderRadius.circular(
                    responsive.radius(22),
                  ),
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
                    fontWeight: FontWeight.w700,
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
