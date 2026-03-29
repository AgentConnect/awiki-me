import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import '../app_shell/app_controller.dart';
import '../shared/awiki_me_design.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  String _entryMode = 'login';
  String _authMode = 'phone';
  int _registerStep = 1;
  bool _emailVerified = false;

  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final emailController = TextEditingController();
  final handleController = TextEditingController(text: 'awikime');
  final nickController = TextEditingController(text: 'AWiki Me');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.refreshLocalCredentials();
    });
  }

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
    final controller = widget.controller;
    return CupertinoPageScaffold(
      backgroundColor: AwikiMeColors.background,
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
                errorBuilder: (_, __, ___) => const Text(
                  '@_',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w700,
                    color: AwikiMeColors.primary,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            _SegmentedPill(
              value: _entryMode,
              options: const <String, String>{
                'login': '登录',
                'register': '注册',
              },
              onChanged: (value) {
                setState(() {
                  _entryMode = value;
                  if (value == 'login') {
                    _registerStep = 1;
                  }
                });
              },
            ),
            const SizedBox(height: 24),
            if (_entryMode == 'login') ...<Widget>[
              _LocalCredentialsCard(controller: controller),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: '导入身份凭证',
                onPressed: controller.isBusy
                    ? null
                    : () => controller.importCredentialArchive(),
                icon: Icons.file_upload_outlined,
              ),
              const SizedBox(height: 12),
              _SecondaryButton(
                label: '重新识别本地凭证',
                onPressed: controller.isBusy
                    ? null
                    : () => controller.refreshLocalCredentials(),
                icon: Icons.fingerprint,
              ),
            ] else ...<Widget>[
              _RegisterProgress(step: _registerStep),
              const SizedBox(height: 20),
              if (_registerStep == 1) ...<Widget>[
                _AuthModeToggle(
                  value: _authMode,
                  onChanged: (value) {
                    setState(() {
                      _authMode = value;
                      _emailVerified = false;
                    });
                  },
                ),
                const SizedBox(height: 24),
                if (_authMode == 'phone') ...<Widget>[
                  _PhoneField(controller: phoneController),
                  const SizedBox(height: 12),
                  _PrimaryButton(
                    label: '发送验证码',
                    onPressed: controller.isBusy
                        ? null
                        : () => controller.requestOtp(_normalizedPhone),
                  ),
                  const SizedBox(height: 12),
                  _InputCard(
                    label: '验证码',
                    child: CupertinoTextField(
                      controller: otpController,
                      placeholder: '输入验证码',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.left,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: null,
                    ),
                  ),
                ] else ...<Widget>[
                  _InputCard(
                    label: '邮箱',
                    child: CupertinoTextField(
                      controller: emailController,
                      placeholder: '输入邮箱地址',
                      keyboardType: TextInputType.emailAddress,
                      textAlign: TextAlign.left,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _PrimaryButton(
                    label: '发送激活邮件',
                    onPressed: controller.isBusy
                        ? null
                        : () => controller.requestEmailActivation(
                            emailController.text.trim()),
                  ),
                  const SizedBox(height: 12),
                  _SecondaryButton(
                    label: _emailVerified ? '邮箱已激活' : '我已激活，检查状态',
                    onPressed: controller.isBusy
                        ? null
                        : () async {
                            final verified =
                                await controller.checkEmailActivation(
                                    emailController.text.trim());
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _emailVerified = verified;
                            });
                          },
                  ),
                ],
                const SizedBox(height: 20),
                _PrimaryButton(
                  label: '下一步',
                  onPressed:
                      controller.isBusy ? null : () => _goToRegisterStep2(),
                ),
              ] else ...<Widget>[
                _InputCard(
                  label: '账号用户名',
                  child: CupertinoTextField(
                    controller: handleController,
                    placeholder: '用户名 handle',
                    textAlign: TextAlign.left,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: null,
                  ),
                ),
                const SizedBox(height: 12),
                _InputCard(
                  label: '昵称',
                  child: CupertinoTextField(
                    controller: nickController,
                    placeholder: '输入昵称',
                    textAlign: TextAlign.left,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: null,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _SecondaryButton(
                        label: '上一步',
                        onPressed: () => setState(() => _registerStep = 1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PrimaryButton(
                        label: '完成注册',
                        onPressed: controller.isBusy
                            ? null
                            : () => _submitRegister(context),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            if (controller.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                controller.errorMessage!,
                style: const TextStyle(
                  color: AwikiMeColors.danger,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 56),
            const Center(
              child: Text(
                'Secure messaging client',
                style: TextStyle(
                  color: Color(0xFF2563EB),
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

  String get _normalizedPhone {
    final raw = phoneController.text.trim();
    if (raw.startsWith('+')) {
      return raw;
    }
    return '+86$raw';
  }

  void _goToRegisterStep2() {
    if (_authMode == 'phone') {
      if (_normalizedPhone.replaceAll(RegExp(r'\D'), '').length < 6) {
        _showDialog(title: '手机号不完整', content: '请输入正确的手机号。');
        return;
      }
      if (otpController.text.trim().isEmpty) {
        _showDialog(title: '缺少验证码', content: '请输入收到的验证码后再继续。');
        return;
      }
    } else {
      if (emailController.text.trim().isEmpty) {
        _showDialog(title: '缺少邮箱', content: '请输入邮箱地址。');
        return;
      }
      if (!_emailVerified) {
        _showDialog(title: '尚未激活', content: '请先完成邮箱激活并检查状态。');
        return;
      }
    }
    setState(() => _registerStep = 2);
  }

  void _submitRegister(BuildContext context) {
    final handle = handleController.text.trim().toLowerCase();
    final handlePattern = RegExp(r'^[a-z0-9-]{2,32}$');
    if (!handlePattern.hasMatch(handle)) {
      _showDialog(
        title: 'handle 不合法',
        content: '仅支持小写字母、数字、中划线，长度 2-32。',
      );
      return;
    }
    if (nickController.text.trim().isEmpty) {
      _showDialog(title: '缺少昵称', content: '请输入昵称。');
      return;
    }

    if (_authMode == 'phone') {
      widget.controller.loginWithOtp(
        phone: _normalizedPhone,
        otp: otpController.text.trim(),
        handle: handle,
        nickName: nickController.text.trim(),
        profileMarkdown: '# Hello $handle',
      );
      return;
    }

    widget.controller.loginWithEmail(
      email: emailController.text.trim(),
      handle: handle,
      nickName: nickController.text.trim(),
      profileMarkdown: '# Hello $handle',
    );
  }

  void _showDialog({
    required String title,
    required String content,
  }) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
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
    const radius = 22.0;
    final keys = options.keys.toList(growable: false);
    final selectedIndex = keys.indexOf(value).clamp(0, keys.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbWidth = (width - 8) / keys.length;
        return Container(
          height: 62,
          decoration: BoxDecoration(
            color: AwikiMeColors.mutedSurface,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          child: Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: 4 + thumbWidth * selectedIndex,
                top: 4,
                width: thumbWidth,
                height: 54,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AwikiMeColors.surface,
                      borderRadius: BorderRadius.circular(radius),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: keys.map((key) {
                  final active = key == value;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(key),
                      child: Center(
                        child: Text(
                          options[key]!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: active
                                ? AwikiMeColors.title
                                : AwikiMeColors.primaryDark,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
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
        Expanded(
            child: _ProgressNode(index: 1, active: step == 1, label: '验证方式')),
        Container(
            height: 2,
            width: 24,
            color: step == 2 ? AwikiMeColors.primary : AwikiMeColors.border),
        Expanded(
            child: _ProgressNode(index: 2, active: step == 2, label: '账号资料')),
      ],
    );
  }
}

class _ProgressNode extends StatelessWidget {
  const _ProgressNode({
    required this.index,
    required this.active,
    required this.label,
  });

  final int index;
  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: active ? AwikiMeColors.primary : AwikiMeColors.mutedSurface,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active ? AwikiMeColors.surface : AwikiMeColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? AwikiMeColors.title : AwikiMeColors.secondaryText,
            ),
          ),
        ),
      ],
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _AuthModeButton(
          active: value == 'phone',
          icon: Icons.smartphone,
          label: '手机号',
          onTap: () => onChanged('phone'),
        ),
        const SizedBox(width: 24),
        _AuthModeButton(
          active: value == 'email',
          icon: Icons.mail_outline,
          label: '邮箱',
          onTap: () => onChanged('email'),
        ),
      ],
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color:
                  active ? const Color(0xFFFFF4D6) : AwikiMeColors.mutedSurface,
              borderRadius: BorderRadius.circular(999),
              border:
                  active ? Border.all(color: const Color(0x33FFAA00)) : null,
            ),
            child: Icon(
              icon,
              size: 24,
              color:
                  active ? AwikiMeColors.primaryDark : AwikiMeColors.secondaryText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? AwikiMeColors.title : AwikiMeColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalCredentialsCard extends StatelessWidget {
  const _LocalCredentialsCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.localCredentials.isEmpty) {
      return Container(
        decoration: AwikiMeDecorations.card(color: AwikiMeColors.subtleSurface),
        padding: const EdgeInsets.all(16),
        child: const Text(
          '暂未识别到本地凭证，请先重新识别。',
          style: AwikiMeTextStyles.cardSubtitle,
        ),
      );
    }

    return Column(
      children: controller.localCredentials.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: controller.isBusy
                ? null
                : () =>
                    controller.loginWithLocalCredential(item.credentialName),
            child: Container(
              decoration:
                  AwikiMeDecorations.card(color: AwikiMeColors.subtleSurface),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Color(0xFFDDE8F7),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (item.displayName.isEmpty
                              ? item.handle ?? 'A'
                              : item.displayName)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AwikiMeColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.displayName,
                          style:
                              AwikiMeTextStyles.cardTitle.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.handle?.isNotEmpty == true
                              ? '@${item.handle}'
                              : item.credentialName,
                          style: AwikiMeTextStyles.cardSubtitle,
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFFD2B48C),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface, radius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Text(
              '+86',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AwikiMeColors.title,
              ),
            ),
          ),
          Container(width: 1, height: 24, color: AwikiMeColors.border),
          const SizedBox(width: 12),
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: '输入手机号',
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.left,
              placeholderStyle: const TextStyle(
                color: Color(0xFFD2D5DE),
                fontSize: 16,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AwikiMeDecorations.card(color: AwikiMeColors.surface, radius: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AwikiMeColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontSize: 16,
                color: AwikiMeColors.title,
              ),
              textAlign: TextAlign.left,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: enabled ? AwikiMeColors.primary : AwikiMeColors.mutedSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: enabled ? AwikiMeColors.surface : AwikiMeColors.primaryDark,
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration:
            AwikiMeDecorations.card(color: const Color(0xFFE3E2E7), radius: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: AwikiMeColors.primaryDark),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AwikiMeColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
