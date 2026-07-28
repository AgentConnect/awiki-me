import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_locale.dart';
import '../../app/e2e_semantics.dart';
import '../../application/models/onboarding_server_info.dart';
import '../../application/tenant/app_tenant.dart';
import '../../l10n/l10n.dart';
import '../../domain/entities/session_identity.dart';
import '../app_shell/providers/app_runtime_provider.dart';
import '../app_shell/providers/session_provider.dart';
import '../shared/app_language_menu.dart';
import '../shared/awiki_me_design.dart';
import '../shared/avatar_badge.dart';
import '../shared/responsive_layout.dart';
import '../shared/tenant_management_dialog.dart';
import '../shared/widgets/app_widgets.dart';
import 'onboarding_provider.dart';

part 'parts/onboarding_mac_part.dart';
part 'parts/onboarding_mobile_controls_part.dart';
part 'parts/onboarding_tenant_part.dart';

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
  ProviderSubscription<AppTenantProfile>? _tenantSubscription;
  Timer? _e2eOtpRetryTimer;
  int _e2eOtpAttempts = 0;

  String get _normalizedPhone => phoneController.text.trim();
  String get _normalizedHandle => handleController.text.trim();

  @override
  void initState() {
    super.initState();
    emailController.addListener(_resetEmailActivationTarget);
    handleController.addListener(_resetEmailActivationTarget);
    _tenantSubscription = ref.listenManual<AppTenantProfile>(
      activeAppTenantProvider,
      (previous, next) {
        if (previous?.id == next.id) {
          return;
        }
        unawaited(
          ref.read(onboardingProvider.notifier).loadServerInfo(force: true),
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(ref.read(onboardingProvider.notifier).loadServerInfo());
    });
  }

  @override
  void dispose() {
    _stopE2eOtpRequestLoop();
    _tenantSubscription?.close();
    emailController.removeListener(_resetEmailActivationTarget);
    handleController.removeListener(_resetEmailActivationTarget);
    phoneController.dispose();
    otpController.dispose();
    emailController.dispose();
    handleController.dispose();
    _mobileScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider);
    final credentials = ref.watch(sessionProvider).localCredentials;
    final activeTenant = ref.watch(activeAppTenantProvider);
    final localeMode = ref.watch(appLocaleModeProvider);
    final runtime = ref.read(appRuntimeProvider.notifier);
    final theme = context.awikiTheme;
    final responsive = context.awikiResponsive;
    if (responsive.usesDesktopLayout) {
      return _MacOnboardingScaffold(
        onboarding: onboarding,
        credentials: credentials,
        phoneController: phoneController,
        otpController: otpController,
        emailController: emailController,
        handleController: handleController,
        onLogin: runtime.loginWithLocalCredential,
        onAuthModeChanged: ref.read(onboardingProvider.notifier).setAuthMode,
        onRequestOtp: _requestOtp,
        onRequestEmailActivation: _requestEmailActivation,
        onCheckEmailActivation: _checkEmailActivation,
        onRegisterStepChanged: ref
            .read(onboardingProvider.notifier)
            .setRegisterStep,
        onSubmitRegister: () => _submitRegister(context),
        activeTenant: activeTenant,
        localeMode: localeMode,
        onLanguagePressed: _showLanguageSheet,
        onTenantPressed: _showTenantManagementDialog,
      );
    }
    return CupertinoPageScaffold(
      backgroundColor: theme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.spacing(18),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final verticalPadding = responsive.spacing(16);
                        final minimumGroupHeight =
                            constraints.maxHeight > verticalPadding * 2
                            ? constraints.maxHeight - verticalPadding * 2
                            : 0.0;
                        return ListView(
                          key: const Key('onboarding-compact-scroll-view'),
                          controller: _mobileScrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.symmetric(
                            vertical: verticalPadding,
                          ),
                          children: <Widget>[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: minimumGroupHeight,
                              ),
                              child: Align(
                                alignment: Alignment.center,
                                child: _CompactOnboardingCard(
                                  onboarding: onboarding,
                                  onAuthModeChanged: ref
                                      .read(onboardingProvider.notifier)
                                      .setAuthMode,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      ..._buildMobileRegisterWidgets(
                                        context: context,
                                        onboarding: onboarding,
                                        responsive: responsive,
                                        theme: theme,
                                      ),
                                      if (credentials.isNotEmpty) ...<Widget>[
                                        SizedBox(
                                          height: responsive.spacing(22),
                                        ),
                                        _OnboardingLocalIdentitySection(
                                          credentials: credentials,
                                          onLogin:
                                              runtime.loginWithLocalCredential,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: EdgeInsets.only(bottom: responsive.spacing(8)),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.spacing(18),
                    ),
                    child: Container(
                      key: const Key('onboarding-compact-footer'),
                      padding: EdgeInsets.only(top: responsive.spacing(8)),
                      decoration: BoxDecoration(
                        color: theme.surface,
                        border: Border(top: BorderSide(color: theme.border)),
                      ),
                      child: _OnboardingUtilityBar(
                        tenant: activeTenant,
                        localeMode: localeMode,
                        fillAvailableWidth: true,
                        onLanguagePressed: _showLanguageSheet,
                        onPressed: _showTenantManagementDialog,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMobileRegisterWidgets({
    required BuildContext context,
    required OnboardingState onboarding,
    required AwikiResponsiveInfo responsive,
    required AwikiMeThemeTokens theme,
  }) {
    if (onboarding.isServerInfoLoading) {
      return <Widget>[
        _OnboardingCapabilityPanel(
          loading: true,
          message: context.l10n.onboardingLoadingServerInfo,
        ),
      ];
    }
    if (onboarding.isServerInfoFailed) {
      return <Widget>[
        _OnboardingCapabilityPanel(
          icon: CupertinoIcons.exclamationmark_triangle,
          message: context.l10n.onboardingServerInfoLoadFailed,
          detail: onboarding.serverInfoError,
          actionLabel: context.l10n.commonRetry,
          onAction: () =>
              ref.read(onboardingProvider.notifier).loadServerInfo(force: true),
        ),
      ];
    }
    if (!onboarding.hasRegistrationMethods) {
      return <Widget>[
        _OnboardingCapabilityPanel(
          icon: CupertinoIcons.lock,
          message: context.l10n.onboardingRegistrationUnavailable,
          actionLabel: context.l10n.commonRetry,
          onAction: () =>
              ref.read(onboardingProvider.notifier).loadServerInfo(force: true),
        ),
      ];
    }
    if (onboarding.usesNoVerificationRegistration) {
      return <Widget>[
        Text(
          context.l10n.onboardingNoVerificationHint,
          style: TextStyle(
            color: theme.secondaryText,
            fontSize: responsive.bodySm,
            height: 1.35,
          ),
        ),
        SizedBox(height: responsive.spacing(16)),
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
        ),
        SizedBox(height: responsive.spacing(14)),
        AppTextField(
          controller: handleController,
          label: context.l10n.onboardingHandle,
          placeholder: context.l10n.onboardingHandlePlaceholder,
          semanticsIdentifier: 'e2e-handle-input',
        ),
        SizedBox(height: responsive.spacing(20)),
        _OnboardingAlignedAction(
          key: const Key('onboarding-no-verification-complete-action'),
          width: responsive.displayScaled(148),
          child: AppPrimaryButton(
            label: context.l10n.onboardingCompleteRegister,
            semanticsIdentifier: 'e2e-complete-login-button',
            onPressed: onboarding.isBusy
                ? null
                : () => _submitRegister(context),
          ),
        ),
      ];
    }

    if (onboarding.registerStep == 1 || onboarding.authMode == 'email') {
      return <Widget>[
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
              onPressed: onboarding.isBusy || onboarding.isOtpResendCoolingDown
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
            controller: handleController,
            label: context.l10n.onboardingHandle,
            placeholder: context.l10n.onboardingHandlePlaceholder,
            showLabel: !responsive.isPhone,
            semanticsIdentifier: 'e2e-handle-input',
          ),
          SizedBox(height: responsive.spacing(14)),
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
                  onboarding.isBusy || onboarding.isEmailResendCoolingDown
                  ? null
                  : _requestEmailActivation,
            ),
          ),
          SizedBox(height: responsive.spacing(14)),
          _OnboardingAlignedAction(
            key: const Key('onboarding-email-action'),
            width: onboarding.emailVerified
                ? responsive.displayScaled(148)
                : responsive.displayScaled(174),
            fillAvailableWidth: responsive.isPhone && !onboarding.emailVerified,
            child: onboarding.emailVerified
                ? AppPrimaryButton(
                    label: context.l10n.onboardingCompleteEmailRegister,
                    semanticsIdentifier: 'e2e-complete-login-button',
                    onPressed: onboarding.isBusy
                        ? null
                        : () => _submitRegister(context),
                  )
                : AppSecondaryButton(
                    label: context.l10n.onboardingCheckActivationStatus,
                    onPressed: onboarding.isBusy ? null : _checkEmailActivation,
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
              onPressed: onboarding.isBusy ? null : () => _setRegisterStep(2),
            ),
          ),
      ];
    }

    return <Widget>[
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
    ];
  }

  Future<void> _showLanguageSheet() {
    return showAppLanguageSheet(context, ref, ref.read(appLocaleModeProvider));
  }

  Future<void> _showTenantManagementDialog() async {
    await showTenantManagementDialog(context);
  }

  Future<void> _submitRegister(BuildContext context) async {
    final notifier = ref.read(onboardingProvider.notifier);
    final handle = handleController.text.trim();
    final profileMarkdown = '# $handle\n\n';
    final onboarding = ref.read(onboardingProvider);
    if (onboarding.usesNoVerificationRegistration) {
      await notifier.registerWithoutContactVerification(
        phone: _normalizedPhone,
        handle: handle,
        nickName: handle,
        profileMarkdown: profileMarkdown,
      );
      return;
    }
    if (onboarding.authMode == 'phone') {
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

  void _requestEmailActivation() {
    unawaited(
      ref
          .read(onboardingProvider.notifier)
          .requestEmailActivation(
            email: emailController.text.trim(),
            handle: _normalizedHandle,
          ),
    );
  }

  void _checkEmailActivation() {
    unawaited(
      ref
          .read(onboardingProvider.notifier)
          .checkEmailActivation(
            email: emailController.text.trim(),
            handle: _normalizedHandle,
          ),
    );
  }

  void _resetEmailActivationTarget() {
    if (!mounted) {
      return;
    }
    if (ref.read(onboardingProvider).authMode != 'email') {
      return;
    }
    ref.read(onboardingProvider.notifier).resetEmailActivation();
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
