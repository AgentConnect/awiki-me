import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/e2e_semantics.dart';
import '../../l10n/l10n.dart';
import '../../domain/entities/session_identity.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import 'onboarding_provider.dart';

part 'parts/onboarding_mac_part.dart';
part 'parts/onboarding_mobile_controls_part.dart';
part 'parts/onboarding_credentials_part.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const int _e2eOtpMaxAttempts = 15;
  static const Duration _e2eOtpRetryInterval = Duration(seconds: 5);

  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final emailController = TextEditingController();
  final handleController = TextEditingController();
  final _mobileScrollController = ScrollController();
  ProviderSubscription<AppRuntimeState>? _runtimeSubscription;
  Timer? _e2eOtpRetryTimer;
  int _e2eOtpAttempts = 0;
  bool _initialEntryModeResolved = false;

  String get _normalizedPhone => phoneController.text.trim();

  @override
  void initState() {
    super.initState();
    _runtimeSubscription = ref.listenManual<AppRuntimeState>(
      appRuntimeProvider,
      (_, next) {
        if (next.isInitialized && !next.isBusy) {
          _resolveInitialEntryMode();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final runtime = ref.read(appRuntimeProvider);
      final credentials = ref.read(sessionProvider).localCredentials;
      if (!runtime.isBusy &&
          (runtime.isInitialized || credentials.isNotEmpty)) {
        _resolveInitialEntryMode();
      }
    });
  }

  @override
  void dispose() {
    _stopE2eOtpRequestLoop();
    _runtimeSubscription?.close();
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    handleController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  void _resolveInitialEntryMode() {
    if (_initialEntryModeResolved || !mounted) {
      return;
    }
    final runtime = ref.read(appRuntimeProvider);
    final credentials = ref.read(sessionProvider).localCredentials;
    if (runtime.isBusy) {
      return;
    }
    if (!runtime.isInitialized && credentials.isEmpty) {
      return;
    }
    _initialEntryModeResolved = true;
    ref
        .read(onboardingProvider.notifier)
        .setEntryModeFromLocalCredentials(credentials);
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final credentials = ref.watch(sessionProvider).localCredentials;
    final runtime = ref.read(appRuntimeProvider.notifier);
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    if (responsive.isMacDesktop) {
      return _MacOnboardingScaffold(
        onboarding: onboarding,
        credentials: credentials,
        phoneController: phoneController,
        otpController: otpController,
        emailController: emailController,
        handleController: handleController,
        onLogin: runtime.loginWithLocalCredential,
        onImport: runtime.importCredentialArchive,
        onRefresh: runtime.refreshLocalCredentials,
        onModeChanged: ref.read(onboardingProvider.notifier).setEntryMode,
        onAuthModeChanged: ref.read(onboardingProvider.notifier).setAuthMode,
        onRequestOtp: _requestOtp,
        onRequestEmailActivation: () => ref
            .read(onboardingProvider.notifier)
            .requestEmailActivation(emailController.text.trim()),
        onCheckEmailActivation: () => ref
            .read(onboardingProvider.notifier)
            .checkEmailActivation(emailController.text.trim()),
        onRegisterStepChanged: ref
            .read(onboardingProvider.notifier)
            .setRegisterStep,
        onSubmitRegister: () => _submitRegister(context),
      );
    }
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
          controller: _mobileScrollController,
          children: <Widget>[
            SizedBox(height: responsive.spacing(responsive.isPhone ? 20 : 8)),
            Center(
              child: Container(
                width: responsive.scaled(126),
                height: responsive.scaled(126),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(
                    responsive.radius(responsive.isPhone ? 28 : 24),
                  ),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x160B65F8),
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/branding/awiki-me-logo.png',
                  width: responsive.scaled(92),
                  height: responsive.scaled(92),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    '@_',
                    style: TextStyle(
                      fontSize: responsive.isPhone ? 72 : responsive.scaled(58),
                      fontWeight: FontWeight.w600,
                      color: AwikiMePalette.actionBlue,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: responsive.spacing(responsive.isPhone ? 34 : 30)),
            _SegmentedPill(
              value: onboarding.entryMode,
              options: <String, String>{
                'register': context.l10n.onboardingRegister,
                'login': context.l10n.onboardingLogin,
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
                onRefresh: runtime.refreshLocalCredentials,
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
                Text(
                  context.l10n.onboardingLoginRegisterHint,
                  style: TextStyle(
                    color: theme.secondaryText,
                    fontSize: responsive.bodySm,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: responsive.spacing(16)),
                if (onboarding.authMode == 'phone') ...<Widget>[
                  AppTextField(
                    controller: phoneController,
                    label: context.l10n.onboardingPhone,
                    placeholder: context.l10n.onboardingPhonePlaceholder,
                    keyboardType: TextInputType.phone,
                    showLabel: !responsive.isPhone,
                    semanticsIdentifier: 'e2e-phone-input',
                    prefix: responsive.isPhone
                        ? const _PhoneFieldPrefix(code: '+86')
                        : null,
                    suffix: _VerificationInlineButton(
                      semanticsIdentifier: 'e2e-send-otp-button',
                      label: onboarding.isOtpResendCoolingDown
                          ? context.l10n.onboardingResendOtpIn(
                              onboarding.otpResendCountdown,
                            )
                          : context.l10n.onboardingSendOtp,
                      onPressed:
                          onboarding.isBusy || onboarding.isOtpResendCoolingDown
                          ? null
                          : _requestOtp,
                    ),
                  ),
                  SizedBox(height: responsive.spacing(14)),
                  AppTextField(
                    controller: otpController,
                    label: context.l10n.onboardingOtp,
                    placeholder: context.l10n.onboardingOtpPlaceholder,
                    keyboardType: TextInputType.number,
                    showLabel: !responsive.isPhone,
                    semanticsIdentifier: 'e2e-otp-input',
                  ),
                  if (onboarding.isOtpResendCoolingDown)
                    const E2eMarker('e2e-otp-sent'),
                  _OtpCompleteMarker(controller: otpController),
                ] else ...<Widget>[
                  AppTextField(
                    controller: emailController,
                    label: context.l10n.onboardingEmail,
                    placeholder: context.l10n.onboardingEmailPlaceholder,
                    keyboardType: TextInputType.emailAddress,
                    showLabel: !responsive.isPhone,
                    suffix: _VerificationInlineButton(
                      label: onboarding.isEmailResendCoolingDown
                          ? context.l10n.onboardingResendActivationEmailIn(
                              onboarding.emailResendCountdown,
                            )
                          : context.l10n.onboardingSendActivationEmail,
                      onPressed:
                          onboarding.isBusy ||
                              onboarding.isEmailResendCoolingDown
                          ? null
                          : () => ref
                                .read(onboardingProvider.notifier)
                                .requestEmailActivation(
                                  emailController.text.trim(),
                                ),
                    ),
                  ),
                  SizedBox(height: responsive.spacing(14)),
                  _OnboardingAlignedAction(
                    key: const Key('onboarding-email-action'),
                    width: onboarding.emailVerified
                        ? responsive.displayScaled(122)
                        : responsive.displayScaled(174),
                    child: onboarding.emailVerified
                        ? AppPrimaryButton(
                            label: context.l10n.commonNext,
                            onPressed: onboarding.isBusy
                                ? null
                                : () => ref
                                      .read(onboardingProvider.notifier)
                                      .setRegisterStep(2),
                          )
                        : AppSecondaryButton(
                            label: context.l10n.onboardingCheckActivationStatus,
                            onPressed: onboarding.isBusy
                                ? null
                                : () => ref
                                      .read(onboardingProvider.notifier)
                                      .checkEmailActivation(
                                        emailController.text.trim(),
                                      ),
                          ),
                  ),
                ],
                SizedBox(height: responsive.spacing(16)),
                if (onboarding.authMode == 'phone')
                  _OnboardingAlignedAction(
                    key: const Key('onboarding-phone-next-action'),
                    width: responsive.displayScaled(122),
                    child: AppPrimaryButton(
                      label: context.l10n.commonNext,
                      semanticsIdentifier: 'e2e-login-next-button',
                      onPressed: onboarding.isBusy
                          ? null
                          : () => _setRegisterStep(2),
                    ),
                  ),
              ] else ...<Widget>[
                AppTextField(
                  controller: handleController,
                  label: context.l10n.onboardingHandle,
                  placeholder: context.l10n.onboardingHandlePlaceholder,
                  semanticsIdentifier: 'e2e-handle-input',
                ),
                SizedBox(height: responsive.spacing(20)),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppSecondaryButton(
                        label: context.l10n.commonPrevious,
                        onPressed: () => _setRegisterStep(1),
                      ),
                    ),
                    SizedBox(width: responsive.spacing(12)),
                    Expanded(
                      child: AppPrimaryButton(
                        label: onboarding.authMode == 'phone'
                            ? context.l10n.onboardingCompleteRegister
                            : context.l10n.onboardingCompleteEmailRegister,
                        semanticsIdentifier: 'e2e-complete-login-button',
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
                'Based on awiki.info',
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
    final handle = handleController.text.trim();
    final profileMarkdown = '# $handle\n\n';
    if (ref.read(onboardingProvider).authMode == 'phone') {
      await notifier.loginOrRegisterWithPhone(
        phone: _normalizedPhone,
        otp: otpController.text.trim(),
        handle: handle,
        nickName: handle,
        profileMarkdown: profileMarkdown,
      );
      return;
    }
    await notifier.registerWithEmail(
      email: emailController.text.trim(),
      handle: handle,
      nickName: handle,
      profileMarkdown: profileMarkdown,
    );
  }

  void _requestOtp() {
    if (!awikiE2eEnabled) {
      unawaited(
        ref.read(onboardingProvider.notifier).requestOtp(_normalizedPhone),
      );
      return;
    }
    _startE2eOtpRequestLoop();
  }

  void _startE2eOtpRequestLoop() {
    _stopE2eOtpRequestLoop();
    _e2eOtpAttempts = 0;
    _tryRequestOtpForE2e();
    _e2eOtpRetryTimer = Timer.periodic(
      _e2eOtpRetryInterval,
      (_) => _tryRequestOtpForE2e(),
    );
  }

  void _tryRequestOtpForE2e() {
    if (!mounted) {
      _stopE2eOtpRequestLoop();
      return;
    }
    final onboarding = ref.read(onboardingProvider);
    if (onboarding.isOtpResendCoolingDown ||
        onboarding.registerStep != 1 ||
        onboarding.authMode != 'phone') {
      _stopE2eOtpRequestLoop();
      return;
    }
    if (onboarding.isBusy) {
      return;
    }
    if (_e2eOtpAttempts >= _e2eOtpMaxAttempts) {
      _stopE2eOtpRequestLoop();
      return;
    }
    _e2eOtpAttempts += 1;
    unawaited(
      ref.read(onboardingProvider.notifier).requestOtp(_normalizedPhone),
    );
  }

  void _stopE2eOtpRequestLoop() {
    _e2eOtpRetryTimer?.cancel();
    _e2eOtpRetryTimer = null;
  }

  void _setRegisterStep(int step) {
    ref.read(onboardingProvider.notifier).setRegisterStep(step);
    if (step != 2) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mobileScrollController.hasClients) {
        return;
      }
      unawaited(
        _mobileScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
    });
  }
}
