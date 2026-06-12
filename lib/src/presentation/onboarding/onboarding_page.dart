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
              child: Image.asset(
                'assets/branding/awiki-me-logo.png',
                width: responsive.scaled(125),
                height: responsive.scaled(125),
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
            SizedBox(height: responsive.spacing(responsive.isPhone ? 48 : 40)),
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

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFF7FAFF), Color(0xFFFFFFFF)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useCompactMacLayout = constraints.maxWidth < 1040;
            final authCard = _MacAuthCard(
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
              child: Padding(
                padding: useCompactMacLayout
                    ? const EdgeInsets.fromLTRB(28, 32, 28, 36)
                    : const EdgeInsets.fromLTRB(54, 42, 72, 54),
                child: useCompactMacLayout
                    ? Center(child: authCard)
                    : Row(
                        children: <Widget>[
                          const Expanded(flex: 11, child: _MacOnboardingHero()),
                          const SizedBox(width: 76),
                          Expanded(
                            flex: 9,
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
    );
  }
}

class _MacOnboardingHero extends StatelessWidget {
  const _MacOnboardingHero();

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF0B65F8);
    const ink = Color(0xFF101B32);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x160B65F8),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Center(
                child: Image.asset(
                  'assets/branding/awiki-me-logo.png',
                  width: 46,
                  height: 46,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text(
                    'AW',
                    style: TextStyle(
                      color: blue,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            const Text(
              'AWiki',
              style: TextStyle(
                color: ink,
                fontSize: 38,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 36),
        const Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: '连接你的 '),
              TextSpan(
                text: 'Agent',
                style: TextStyle(color: blue),
              ),
              TextSpan(text: ' 世界'),
            ],
          ),
          style: TextStyle(
            color: ink,
            fontSize: 34,
            height: 1.18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '安全连接人、Agent 与组织，协作更智能，决策更高效。',
          style: TextStyle(
            color: Color(0xFF64708A),
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 34),
        const Expanded(child: _MacAgentOrbit()),
        const SizedBox(height: 24),
        const SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MacFeatureItem(
                  icon: CupertinoIcons.shield,
                  title: '安全可靠',
                  subtitle: '企业级安全防护体系',
                ),
                SizedBox(width: 34),
                _MacFeatureItem(
                  icon: CupertinoIcons.person_2,
                  title: '高效协作',
                  subtitle: '人机协同，信息无缝流转',
                ),
                SizedBox(width: 34),
                _MacFeatureItem(
                  icon: CupertinoIcons.lock,
                  title: '权限可控',
                  subtitle: '精细化权限，数据更安心',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MacAgentOrbit extends StatelessWidget {
  const _MacAgentOrbit();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(child: CustomPaint(painter: _MacOrbitPainter())),
        Align(
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: -0.5,
            child: Container(
              width: 166,
              height: 94,
              decoration: BoxDecoration(
                color: CupertinoColors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x240B65F8),
                    blurRadius: 36,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'AW',
                  style: TextStyle(
                    color: Color(0xFF0B65F8),
                    fontSize: 38,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Positioned(
          top: 18,
          left: 170,
          child: _MacAgentChip(name: '融资 Agent', seed: 'financing'),
        ),
        const Positioned(
          top: 150,
          left: 10,
          child: _MacAgentChip(name: '法务 Agent', seed: 'legal'),
        ),
        const Positioned(
          right: 30,
          top: 160,
          child: _MacAgentChip(name: '投资机构', seed: 'investor', verified: true),
        ),
        const Positioned(
          left: 250,
          bottom: 24,
          child: _MacAgentChip(name: 'BP Agent', seed: 'bp'),
        ),
        const Positioned(
          left: 130,
          bottom: 78,
          child: _MacFloatingIcon(icon: CupertinoIcons.sparkles),
        ),
        const Positioned(
          right: 138,
          top: 70,
          child: _MacFloatingIcon(icon: CupertinoIcons.person),
        ),
        const Positioned(
          left: 122,
          top: 78,
          child: _MacFloatingIcon(icon: CupertinoIcons.shield),
        ),
      ],
    );
  }
}

class _MacOrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.48, size.height * 0.5);
    final orbitPaint = Paint()
      ..color = const Color(0x1A0B65F8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final radius in <double>[112, 168, 224]) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: radius * 1.7, height: radius),
        orbitPaint,
      );
    }
    final dotPaint = Paint()..color = const Color(0x330B65F8);
    for (final offset in <Offset>[
      Offset(size.width * 0.2, size.height * 0.44),
      Offset(size.width * 0.72, size.height * 0.32),
      Offset(size.width * 0.35, size.height * 0.82),
      Offset(size.width * 0.62, size.height * 0.62),
    ]) {
      canvas.drawCircle(offset, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MacAgentChip extends StatelessWidget {
  const _MacAgentChip({
    required this.name,
    required this.seed,
    this.verified = false,
  });

  final String name;
  final String seed;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 164,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6ECF5)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140B1F3A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          AvatarBadge(seed: seed, size: 42),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: verified
                            ? const Color(0xFF17BF63)
                            : const Color(0xFF20C86B),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      verified ? '已认证' : '在线',
                      style: const TextStyle(
                        color: Color(0xFF64708A),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacFloatingIcon extends StatelessWidget {
  const _MacFloatingIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(27),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120B65F8),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Icon(icon, color: const Color(0xFF0B65F8), size: 24),
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
      children: <Widget>[
        Icon(icon, color: const Color(0xFF0B65F8), size: 30),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF17213A),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF7B879D), fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

class _MacAuthCard extends StatelessWidget {
  const _MacAuthCard({
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
    return Container(
      constraints: const BoxConstraints(maxWidth: 490),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDDE5F0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x120B1F3A),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(38, 32, 38, 34),
                child: Column(
                  children: <Widget>[
                    _MacAuthTabs(
                      value: onboarding.entryMode,
                      onChanged: onModeChanged,
                    ),
                    const SizedBox(height: 28),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: onboarding.entryMode == 'login'
                          ? _MacLoginForm(
                              key: const ValueKey<String>('mac-login-form'),
                              credentials: credentials,
                              onLogin: onLogin,
                              onImport: onImport,
                              onRefresh: onRefresh,
                            )
                          : _MacRegisterForm(
                              key: const ValueKey<String>('mac-register-form'),
                              onboarding: onboarding,
                              phoneController: phoneController,
                              otpController: otpController,
                              emailController: emailController,
                              handleController: handleController,
                              onAuthModeChanged: onAuthModeChanged,
                              onRequestOtp: onRequestOtp,
                              onRequestEmailActivation:
                                  onRequestEmailActivation,
                              onCheckEmailActivation: onCheckEmailActivation,
                              onRegisterStepChanged: onRegisterStepChanged,
                              onSubmitRegister: onSubmitRegister,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacAuthTabs extends StatelessWidget {
  const _MacAuthTabs({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const Key('onboarding-mac-entry-tabs'),
        constraints: const BoxConstraints(maxWidth: 306),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F5FE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE7F7)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _MacAuthTab(
                label: context.l10n.onboardingRegister,
                selected: value == 'register',
                onTap: () => onChanged('register'),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _MacAuthTab(
                label: context.l10n.onboardingLogin,
                selected: value == 'login',
                onTap: () => onChanged('login'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacAuthTab extends StatelessWidget {
  const _MacAuthTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? CupertinoColors.white : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x120B65F8),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF0B65F8)
                  : const Color(0xFF66728A),
              fontSize: 16,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1,
            ),
          ),
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
        const _MacFieldLabel('身份凭证'),
        const SizedBox(height: 10),
        _MacCredentialPicker(credentials: credentials, onLogin: onLogin),
        const SizedBox(height: 18),
        _MacPrimaryAction(
          label: context.l10n.onboardingImportCredential,
          icon: CupertinoIcons.square_arrow_down,
          onPressed: onImport,
        ),
        const SizedBox(height: 14),
        _MacSecondaryAction(
          label: context.l10n.onboardingRefreshCredentials,
          icon: CupertinoIcons.arrow_clockwise,
          onPressed: onRefresh,
        ),
      ],
    );
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
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  CupertinoIcons.person_crop_circle_badge_exclam,
                  color: Color(0xFF7B879D),
                  size: 20,
                ),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '本机暂无已保存身份凭证',
                    style: TextStyle(
                      color: Color(0xFF98A3B8),
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
      borderRadius: BorderRadius.circular(9),
      backgroundColor: CupertinoColors.white,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _macFieldDecoration(),
        child: Row(
          children: <Widget>[
            AvatarBadge(seed: identity.displayName, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    identity.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF17213A),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
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
            const Icon(
              CupertinoIcons.chevron_right,
              color: Color(0xFF9AA6BA),
              size: 16,
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
    required this.onAuthModeChanged,
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
  final ValueChanged<String> onAuthModeChanged;
  final VoidCallback onRequestOtp;
  final VoidCallback onRequestEmailActivation;
  final VoidCallback onCheckEmailActivation;
  final ValueChanged<int> onRegisterStepChanged;
  final VoidCallback onSubmitRegister;

  @override
  Widget build(BuildContext context) {
    if (onboarding.registerStep == 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _MacOutlinedField(
            controller: handleController,
            label: context.l10n.onboardingHandle,
            placeholder: context.l10n.onboardingHandlePlaceholder,
            icon: CupertinoIcons.at,
          ),
          const SizedBox(height: 24),
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
                  label: onboarding.authMode == 'phone'
                      ? context.l10n.onboardingCompleteRegister
                      : context.l10n.onboardingCompleteEmailRegister,
                  onPressed: onboarding.isBusy ? null : onSubmitRegister,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _MacAuthModeRow(
          value: onboarding.authMode,
          onChanged: onAuthModeChanged,
        ),
        const SizedBox(height: 14),
        _MacAuthHint(text: context.l10n.onboardingLoginRegisterHint),
        const SizedBox(height: 20),
        if (onboarding.authMode == 'phone') ...<Widget>[
          _MacOutlinedField(
            controller: phoneController,
            label: context.l10n.onboardingPhone,
            placeholder: context.l10n.onboardingPhonePlaceholder,
            icon: CupertinoIcons.phone,
            keyboardType: TextInputType.phone,
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
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: _MacOutlinedField(
                  controller: otpController,
                  label: context.l10n.onboardingOtp,
                  placeholder: context.l10n.onboardingOtpPlaceholder,
                  icon: CupertinoIcons.number,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                key: const Key('onboarding-mac-phone-next-action'),
                width: 118,
                child: _MacPrimaryAction(
                  label: context.l10n.commonNext,
                  onPressed: onboarding.isBusy
                      ? null
                      : () => onRegisterStepChanged(2),
                ),
              ),
            ],
          ),
        ] else ...<Widget>[
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
              onPressed:
                  onboarding.isBusy || onboarding.isEmailResendCoolingDown
                  ? null
                  : onRequestEmailActivation,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              key: const Key('onboarding-mac-email-action'),
              width: onboarding.emailVerified ? 118 : 168,
              child: onboarding.emailVerified
                  ? _MacPrimaryAction(
                      label: context.l10n.commonNext,
                      onPressed: onboarding.isBusy
                          ? null
                          : () => onRegisterStepChanged(2),
                    )
                  : _MacSecondaryAction(
                      label: context.l10n.onboardingCheckActivationStatus,
                      onPressed: onboarding.isBusy
                          ? null
                          : onCheckEmailActivation,
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MacAuthModeRow extends StatelessWidget {
  const _MacAuthModeRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('onboarding-mac-auth-mode-tabs'),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDDE5F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _MacAuthModeButton(
              key: const Key('auth-mode-phone'),
              label: context.l10n.onboardingPhone,
              icon: CupertinoIcons.phone,
              selected: value == 'phone',
              onTap: () => onChanged('phone'),
            ),
            const SizedBox(width: 4),
            _MacAuthModeButton(
              key: const Key('auth-mode-email'),
              label: context.l10n.onboardingEmail,
              icon: CupertinoIcons.mail,
              selected: value == 'email',
              onTap: () => onChanged('email'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacAuthModeButton extends StatelessWidget {
  const _MacAuthModeButton({
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
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 86),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? CupertinoColors.white : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? const Color(0xFFC9DAFF)
                : CupertinoColors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: selected
                  ? const Color(0xFF0B65F8)
                  : const Color(0xFF66728A),
            ),
            const SizedBox(width: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF0B65F8)
                      : const Color(0xFF66728A),
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

class _MacAuthHint extends StatelessWidget {
  const _MacAuthHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF7B879D),
        fontSize: 12,
        height: 1.35,
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
    required this.icon,
    this.keyboardType,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final IconData icon;
  final TextInputType? keyboardType;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _MacFieldLabel(label),
        const SizedBox(height: 10),
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: _macFieldDecoration(),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: const Color(0xFF66728A)),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoTextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  placeholder: placeholder,
                  decoration: null,
                  padding: EdgeInsets.zero,
                  style: const TextStyle(
                    color: Color(0xFF17213A),
                    fontSize: 14,
                  ),
                  placeholderStyle: const TextStyle(
                    color: Color(0xFFB3BDCD),
                    fontSize: 14,
                  ),
                ),
              ),
              if (suffix != null) ...<Widget>[
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

class _MacFieldLabel extends StatelessWidget {
  const _MacFieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF39445D),
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
      borderRadius: BorderRadius.circular(8),
      builder: (context, state, child) {
        final opacity = !state.enabled
            ? 0.55
            : state.pressed
            ? 0.78
            : state.hovered || state.focused
            ? 0.90
            : 1.0;
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Opacity(
        opacity: 1,
        child: Container(
          height: 34,
          constraints: const BoxConstraints(minWidth: 88, maxWidth: 132),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFC9DAFF)),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              strutStyle: const StrutStyle(
                fontSize: 13,
                height: 1,
                forceStrutHeight: true,
              ),
              style: const TextStyle(
                color: Color(0xFF0B65F8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MacPrimaryAction extends StatelessWidget {
  const _MacPrimaryAction({required this.label, this.icon, this.onPressed});

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
      builder: (context, state, child) {
        final opacity = !state.enabled
            ? 0.55
            : state.pressed
            ? 0.84
            : state.hovered || state.focused
            ? 0.94
            : 1.0;
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Opacity(
        opacity: 1,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF0B65F8), Color(0xFF0752F0)],
            ),
            borderRadius: BorderRadius.circular(9),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x240B65F8),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, color: CupertinoColors.white, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
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
      builder: (context, state, child) {
        final opacity = !state.enabled
            ? 0.55
            : state.pressed
            ? 0.82
            : state.hovered || state.focused
            ? 0.92
            : 1.0;
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Opacity(
        opacity: 1,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFDDE5F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, color: const Color(0xFF17213A), size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF17213A),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration _macFieldDecoration() {
  return BoxDecoration(
    color: CupertinoColors.white,
    borderRadius: BorderRadius.circular(9),
    border: Border.all(color: const Color(0xFFDDE5F0)),
  );
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
    final responsive = context.awikiResponsive;
    return Align(
      alignment: Alignment.center,
      child: Container(
        key: const Key('onboarding-entry-tabs'),
        constraints: BoxConstraints(
          maxWidth: responsive.isPhone ? 286 : responsive.displayScaled(310),
        ),
        padding: responsive.scaledInsets(const EdgeInsets.all(4)),
        decoration: BoxDecoration(
          color: AwikiMePalette.actionBlueBorder.withValues(alpha: 0.48),
          borderRadius: BorderRadius.circular(responsive.radius(12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: options.entries
              .map(
                (entry) => Flexible(
                  fit: FlexFit.loose,
                  child: _CompactSegmentOption(
                    label: entry.value,
                    selected: value == entry.key,
                    minWidth: responsive.isPhone
                        ? responsive.displayScaled(124)
                        : responsive.displayScaled(128),
                    verticalPadding: responsive.spacing(11),
                    fontSize: responsive.bodyMd,
                    selectedColor: AwikiMePalette.actionBlue,
                    unselectedColor: AwikiMePalette.actionMuted,
                    onTap: () => onChanged(entry.key),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _AuthModeToggle extends StatelessWidget {
  const _AuthModeToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('onboarding-auth-mode-tabs'),
        padding: responsive.scaledInsets(const EdgeInsets.all(4)),
        decoration: BoxDecoration(
          color: AwikiMePalette.actionBlueBorder.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(responsive.radius(12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _AuthModeOption(
              key: const Key('auth-mode-phone'),
              selected: value == 'phone',
              assetName: 'assets/icons/icon_mobile.svg',
              label: context.l10n.onboardingPhone,
              onTap: () => onChanged('phone'),
            ),
            SizedBox(width: responsive.spacing(4)),
            _AuthModeOption(
              key: const Key('auth-mode-email'),
              selected: value == 'email',
              assetName: 'assets/icons/icon_mail.svg',
              label: context.l10n.onboardingEmail,
              onTap: () => onChanged('email'),
            ),
          ],
        ),
      ),
    );
  }
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
        constraints: BoxConstraints(
          minWidth: responsive.isPhone
              ? responsive.displayScaled(96)
              : responsive.displayScaled(96),
        ),
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

class _CompactSegmentOption extends StatelessWidget {
  const _CompactSegmentOption({
    required this.label,
    required this.selected,
    required this.minWidth,
    required this.verticalPadding,
    required this.fontSize,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double minWidth;
  final double verticalPadding;
  final double fontSize;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      selected: selected,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(9)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minWidth: minWidth),
        padding: EdgeInsets.symmetric(
          horizontal: responsive.spacing(14),
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: selected ? CupertinoColors.white : CupertinoColors.transparent,
          borderRadius: BorderRadius.circular(responsive.radius(9)),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x100B65F8),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontSize: fontSize,
              height: 1,
              forceStrutHeight: true,
            ),
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? selectedColor : unselectedColor,
            ),
          ),
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
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SizedBox(width: double.infinity, child: child),
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

class _VerificationInlineButton extends StatelessWidget {
  const _VerificationInlineButton({
    required this.label,
    this.onPressed,
    this.semanticsIdentifier,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    return AppPressable(
      onTap: onPressed,
      semanticLabel: label,
      semanticsIdentifier: semanticsIdentifier,
      enabled: onPressed != null,
      scaleOnPress: true,
      pressedScale: 0.98,
      borderRadius: BorderRadius.circular(responsive.radius(8)),
      builder: (context, state, child) {
        return AnimatedOpacity(
          opacity: state.enabled
              ? state.pressed
                    ? 0.78
                    : state.hovered || state.focused
                    ? 0.90
                    : 1
              : 0.55,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: child,
        );
      },
      child: Container(
        constraints: BoxConstraints(
          minWidth: responsive.scaled(92),
          maxWidth: responsive.scaled(132),
          minHeight: responsive.compactControlHeight,
        ),
        padding: EdgeInsets.symmetric(horizontal: responsive.spacing(12)),
        decoration: BoxDecoration(
          color: AwikiMePalette.actionBlueSoft,
          borderRadius: BorderRadius.circular(responsive.radius(8)),
          border: Border.all(color: AwikiMePalette.actionBlueBorder),
        ),
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(
              fontSize: responsive.bodySm,
              height: 1,
              forceStrutHeight: true,
            ),
            style: AwikiMeTextStyles.buttonLabel.copyWith(
              color: AwikiMePalette.actionBlue,
              fontSize: responsive.bodySm,
              height: 1,
            ),
          ),
        ),
      ),
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
