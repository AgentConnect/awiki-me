import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_transport_failure.dart';
import '../shared/awiki_me_feedback.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../recovery/pending_handle_recovery_entry.dart';
import 'onboarding_provider.dart';
import 'registration_entry_provider.dart';

/// Inline invitation and validation details for the fixed auth form.
class RegistrationEntryForm extends ConsumerWidget {
  const RegistrationEntryForm({
    super.key,
    required this.handleController,
    required this.inviteController,
    required this.phoneController,
    this.showLoading = true,
  });

  final TextEditingController handleController;
  final TextEditingController inviteController;
  final TextEditingController phoneController;
  final bool showLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registrationEntryProvider);
    final onboarding = ref.watch(onboardingProvider);
    final showInviteHandleHint =
        onboarding.authMode != 'phone' ||
        onboarding.usesNoVerificationRegistration;
    final l10n = context.l10n;
    final error = switch (state.error) {
      null => null,
      'invite_required' => l10n.onboardingInviteRequired,
      'invite_invalid' =>
        state.step == RegistrationEntryStep.invite
            ? l10n.onboardingInviteInvalidBeforeContact
            : l10n.onboardingInviteInvalid,
      'invite_length_six' => l10n.onboardingInviteLengthSix,
      'invite_length_max_64' => l10n.onboardingInviteLengthMax64,
      'registration_closed' => l10n.onboardingRegistrationClosed,
      tlsHandshakeFailureCode => l10n.secureConnectionFailed,
      trustBundleFailureCode => l10n.trustResourcesInvalid,
      'check_timeout' => l10n.requestTimeoutRetry,
      'check_network' => l10n.networkUnavailableRetry,
      'check_unsupported' => l10n.onboardingAccountCheckUnsupported,
      'check_failed' => l10n.onboardingAccountCheckFailed,
      _ => l10n.onboardingAccountUnavailable,
    };
    return Column(
      key: const Key('registration-entry-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.step == RegistrationEntryStep.invite &&
            state.check?.inviteRequired == true) ...[
          if (showInviteHandleHint) ...[
            Text(l10n.onboardingInviteHandleHint),
            const SizedBox(height: 8),
          ],
          context.awikiResponsive.usesDesktopLayout
              ? _RegistrationMacInviteField(
                  controller: inviteController,
                  label: l10n.onboardingInviteCode,
                  placeholder: l10n.onboardingInviteCode,
                  labelHint: showInviteHandleHint
                      ? null
                      : l10n.onboardingShortHandleInviteHint,
                )
              : AppTextField(
                  controller: inviteController,
                  label: l10n.onboardingInviteCode,
                  labelTrailing: showInviteHandleHint
                      ? null
                      : Text(
                          l10n.onboardingShortHandleInviteHint,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: context.awikiTheme.secondaryText,
                            fontSize: context.awikiResponsive.metaSm,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                  placeholder: l10n.onboardingInviteCode,
                  semanticsIdentifier: 'e2e-invite-input',
                ),
          const SizedBox(height: 4),
        ],
        if (state.check?.decision == 'unavailable')
          Text(l10n.onboardingAccountUnavailable),
        PendingHandleRecoveryEntry(
          handleController: handleController,
          phoneController: phoneController,
        ),
        if (const <String>{
          'identity.local_registry_conflict',
          'handle_recovery.local_state_conflict',
        }.contains(onboarding.phoneRegistrationFailureCode))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.registrationLocalStateNeedsAttention,
              key: const Key('registration-local-state-guidance'),
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ),
        if (error != null && state.errorDetail != null)
          AppSecondaryButton(
            label: l10n.commonDetails,
            onPressed: () => showAwikiMeErrorDetailDialog(
              context,
              message: error,
              detail: state.errorDetail!,
            ),
          ),
        if (state.busy && showLoading) const CupertinoActivityIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error,
              key: const Key('registration-entry-error'),
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ),
      ],
    );
  }
}

class _RegistrationMacInviteField extends StatelessWidget {
  const _RegistrationMacInviteField({
    required this.controller,
    required this.label,
    required this.placeholder,
    this.labelHint,
  });

  final TextEditingController controller;
  final String label;
  final String placeholder;
  final String? labelHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.awikiTheme.title,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (labelHint != null)
              Flexible(
                child: Text(
                  labelHint!,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: context.awikiTheme.secondaryText,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 9),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.awikiTheme.border),
          ),
          alignment: Alignment.center,
          child: Semantics(
            identifier: 'e2e-invite-input',
            textField: true,
            child: CupertinoTextField(
              controller: controller,
              placeholder: placeholder,
              decoration: null,
              padding: EdgeInsets.zero,
              style: TextStyle(
                color: context.awikiTheme.title,
                fontSize: 14,
                height: 1.2,
              ),
              placeholderStyle: TextStyle(
                color: context.awikiTheme.tertiaryText,
                fontSize: 14,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
