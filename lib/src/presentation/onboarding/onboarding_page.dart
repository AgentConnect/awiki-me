import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../domain/entities/session_identity.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/awiki_me_design.dart';
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
    return CupertinoPageScaffold(
      backgroundColor: theme.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          children: <Widget>[
            const SizedBox(height: 20),
            Center(
              child: Image.asset(
                'assets/branding/awiki-me-logo.png',
                width: 125,
                height: 125,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(
                  '@_',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w700,
                    color: theme.primary,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            _SegmentedPill(
              value: onboarding.entryMode,
              options: <String, String>{
                'login': context.l10n.onboardingLogin,
                'register': context.l10n.onboardingRegister,
              },
              onChanged: ref.read(onboardingProvider.notifier).setEntryMode,
            ),
            const SizedBox(height: 24),
            if (onboarding.entryMode == 'login') ...<Widget>[
              _LocalCredentialsCard(
                credentials: credentials,
                onLogin: runtime.loginWithLocalCredential,
              ),
              const SizedBox(height: 12),
              _SecondaryActionButton(
                label: context.l10n.onboardingImportCredential,
                onPressed: runtime.importCredentialArchive,
                icon: Icons.file_upload_outlined,
              ),
              const SizedBox(height: 12),
              _SecondaryActionButton(
                label: context.l10n.onboardingRefreshCredentials,
                onPressed: () =>
                    ref.read(appRuntimeProvider.notifier).initialize(),
                icon: Icons.fingerprint,
              ),
            ] else ...<Widget>[
              _RegisterProgress(step: onboarding.registerStep),
              const SizedBox(height: 20),
              if (onboarding.registerStep == 1) ...<Widget>[
                _AuthModeToggle(
                  value: onboarding.authMode,
                  onChanged: ref.read(onboardingProvider.notifier).setAuthMode,
                ),
                const SizedBox(height: 24),
                if (onboarding.authMode == 'phone') ...<Widget>[
                  AppTextField(
                    controller: phoneController,
                    label: context.l10n.onboardingPhone,
                    placeholder: context.l10n.onboardingPhonePlaceholder,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  AppPrimaryButton(
                    label: context.l10n.onboardingSendOtp,
                    onPressed: onboarding.isBusy
                        ? null
                        : () => ref
                            .read(onboardingProvider.notifier)
                            .requestOtp(_normalizedPhone),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: otpController,
                    label: context.l10n.onboardingOtp,
                    placeholder: context.l10n.onboardingOtpPlaceholder,
                    keyboardType: TextInputType.number,
                  ),
                ] else ...<Widget>[
                  AppTextField(
                    controller: emailController,
                    label: context.l10n.onboardingEmail,
                    placeholder: context.l10n.onboardingEmailPlaceholder,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  AppPrimaryButton(
                    label: context.l10n.onboardingSendActivationEmail,
                    onPressed: onboarding.isBusy
                        ? null
                        : () => ref
                            .read(onboardingProvider.notifier)
                            .requestEmailActivation(
                                emailController.text.trim()),
                  ),
                  const SizedBox(height: 12),
                  AppSecondaryButton(
                    label: onboarding.emailVerified
                        ? context.l10n.onboardingEmailActivated
                        : context.l10n.onboardingCheckActivationStatus,
                    onPressed: onboarding.isBusy
                        ? null
                        : () => ref
                            .read(onboardingProvider.notifier)
                            .checkEmailActivation(emailController.text.trim()),
                  ),
                ],
                const SizedBox(height: 20),
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
                const SizedBox(height: 12),
                AppTextField(
                  controller: nickController,
                  label: context.l10n.onboardingNickname,
                  placeholder: context.l10n.onboardingNicknamePlaceholder,
                ),
                const SizedBox(height: 20),
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
                    const SizedBox(width: 12),
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
            const SizedBox(height: 56),
            Center(
              child: Text(
                'Secure messaging client',
                style: TextStyle(
                  color: theme.infoAccent,
                  fontSize: 16,
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
    return AppSurface(
      color: theme.mutedSurface,
      radius: AwikiMeRadii.pill,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: options.entries
            .map(
              (entry) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(entry.key),
                  child: AppSurface(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    color: value == entry.key
                        ? theme.surface
                        : CupertinoColors.transparent,
                    radius: AwikiMeRadii.pill,
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
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

class _RegisterProgress extends StatelessWidget {
  const _RegisterProgress({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(child: _ProgressNode(index: 1, step: step, label: '1')),
        const SizedBox(width: 12),
        Expanded(child: _ProgressNode(index: 2, step: step, label: '2')),
      ],
    );
  }
}

class _ProgressNode extends StatelessWidget {
  const _ProgressNode({
    required this.index,
    required this.step,
    required this.label,
  });

  final int index;
  final int step;
  final String label;

  @override
  Widget build(BuildContext context) {
    final active = step >= index;
    return AppSurface(
      padding: EdgeInsets.zero,
      color: active ? context.awikiTheme.primary : context.awikiTheme.border,
      radius: AwikiMeRadii.pill,
      constraints: const BoxConstraints.tightFor(height: 6),
      child: const SizedBox.shrink(),
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
    return _SegmentedPill(
      value: value,
      options: <String, String>{
        'phone': context.l10n.onboardingPhone,
        'email': context.l10n.onboardingEmail,
      },
      onChanged: onChanged,
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
    return AppCardSection(
      color: context.awikiTheme.subtleSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            context.l10n.onboardingLogin,
            style: AwikiMeTextStyles.sectionTitle,
          ),
          const SizedBox(height: 12),
          if (credentials.isEmpty)
            Text(
              context.l10n.onboardingMissingLocalCredential,
              style: AwikiMeTextStyles.cardSubtitle,
            )
          else
            ...credentials.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppSurface(
                  padding: EdgeInsets.zero,
                  radius: 12,
                  child: AppListTile(
                    title: item.displayName,
                    subtitle: item.credentialName,
                    leading: Icon(
                      Icons.fingerprint,
                      color: context.awikiTheme.primary,
                    ),
                    onTap: () => onLogin(item.credentialName),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.awikiTheme;
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: AppSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          color: theme.warningContainer,
          radius: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, color: theme.primaryDark),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: theme.primaryDark,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
