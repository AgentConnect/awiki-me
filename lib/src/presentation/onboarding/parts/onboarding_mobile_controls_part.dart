part of '../onboarding_page.dart';

String _authModeLabel(BuildContext context, OnboardingIdentityMethodId id) {
  return switch (id) {
    OnboardingIdentityMethodId.phone => context.l10n.onboardingPhone,
    OnboardingIdentityMethodId.email => context.l10n.onboardingEmail,
    OnboardingIdentityMethodId.handleOnly => context.l10n.onboardingHandle,
  };
}

class _OnboardingCapabilityPanel extends StatelessWidget {
  const _OnboardingCapabilityPanel({
    required this.message,
    this.loading = false,
    this.icon,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final bool loading;
  final IconData? icon;
  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final responsive = context.awikiResponsive;
    final theme = context.awikiTheme;
    final detailText = detail?.trim();
    return Container(
      key: const Key('onboarding-capability-panel'),
      padding: EdgeInsets.all(responsive.spacing(16)),
      decoration: BoxDecoration(
        color: context.awikiTheme.surface,
        borderRadius: BorderRadius.circular(responsive.radius(12)),
        border: Border.all(color: theme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: responsive.iconLg,
                height: responsive.iconLg,
                child: Center(
                  child: loading
                      ? const CupertinoActivityIndicator(radius: 9)
                      : Icon(
                          icon ?? CupertinoIcons.info_circle,
                          color: context.awikiTheme.primary,
                          size: responsive.iconMd,
                        ),
                ),
              ),
              SizedBox(width: responsive.spacing(10)),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: theme.title,
                    fontSize: responsive.bodySm,
                    height: 1.35,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          if (detailText != null && detailText.isNotEmpty) ...<Widget>[
            SizedBox(height: responsive.spacing(10)),
            Text(
              detailText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.secondaryText,
                fontSize: responsive.metaSm,
                height: 1.35,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...<Widget>[
            SizedBox(height: responsive.spacing(14)),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: responsive.displayScaled(118),
                ),
                child: AppSecondaryButton(
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ),
            ),
          ],
        ],
      ),
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
