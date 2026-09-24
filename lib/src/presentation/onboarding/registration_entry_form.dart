import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../domain/entities/identity_method.dart';
import '../../l10n/l10n.dart';
import '../shared/awiki_me_design.dart';
import '../shared/responsive_layout.dart';
import '../shared/widgets/app_widgets.dart';
import '../recovery/pending_handle_recovery_entry.dart';
import '../recovery/handle_recovery_page.dart';
import 'onboarding_provider.dart';
import 'registration_entry_provider.dart';

/// Inline invitation and account status details for the fixed auth form.
class RegistrationEntryForm extends ConsumerWidget {
  const RegistrationEntryForm({
    super.key,
    required this.handleController,
    required this.inviteController,
    required this.phoneController,
  });

  final TextEditingController handleController;
  final TextEditingController inviteController;
  final TextEditingController phoneController;

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
        if (state.check?.isExisting == true || state.existingAccountPath) ...[
          Text(l10n.onboardingExistingAccount),
          if (ref.watch(onboardingProvider).didMethod ==
                  IdentityDidMethod.wba &&
              ref
                      .watch(onboardingProvider)
                      .serverInfo
                      ?.supportsPhoneHandleRecovery ==
                  true)
            AppSecondaryButton(
              label: l10n.handleRecoveryTitle,
              semanticsIdentifier: 'e2e-existing-recovery',
              onPressed: () => AppNavigator.push<void>(
                context,
                (_) => HandleRecoveryPage(
                  startNew: true,
                  initialHandle: '${state.handle}.${state.domain}',
                  initialPhone: phoneController.text.trim(),
                  allowPhoneInput: true,
                  autoRequestOtp: false,
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
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
        if (state.busy) const CupertinoActivityIndicator(),
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
              style: const TextStyle(
                color: AwikiMePalette.inkNeutral,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
            if (labelHint != null)
              Flexible(
                child: Text(
                  labelHint!,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: AwikiMePalette.mutedNeutral,
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
            border: Border.all(color: AwikiMePalette.hairline),
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
              style: const TextStyle(
                color: AwikiMePalette.inkNeutral,
                fontSize: 14,
                height: 1.2,
              ),
              placeholderStyle: const TextStyle(
                color: AwikiMePalette.messagePreview,
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
