import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/tenant/app_tenant.dart';
import '../../l10n/l10n.dart';
import '../shared/widgets/app_widgets.dart';
import '../recovery/pending_handle_recovery_entry.dart';
import 'registration_entry_provider.dart';

/// Shared account/invitation steps for mobile and desktop layouts.
class RegistrationEntryForm extends ConsumerWidget {
  const RegistrationEntryForm({
    super.key,
    required this.handleController,
    required this.inviteController,
    required this.phoneController,
    required this.onBack,
  });

  final TextEditingController handleController;
  final TextEditingController inviteController;
  final TextEditingController phoneController;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registrationEntryProvider);
    final controller = ref.read(registrationEntryProvider.notifier);
    final domain = ref.watch(activeAppTenantProvider).didHost;
    final l10n = context.l10n;
    final error = switch (state.error) {
      null => null,
      'invite_required' => l10n.onboardingInviteRequired,
      'invite_invalid' => l10n.onboardingInviteInvalid,
      'registration_closed' => l10n.onboardingRegistrationClosed,
      'check_failed' => l10n.onboardingAccountCheckFailed,
      _ => l10n.onboardingAccountUnavailable,
    };
    return Column(
      key: const Key('registration-entry-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.step == RegistrationEntryStep.account) ...[
          Text(l10n.onboardingAccountFirst),
          const SizedBox(height: 12),
          AppTextField(
            controller: handleController,
            label: l10n.onboardingHandle,
            placeholder: l10n.onboardingHandlePlaceholder,
            semanticsIdentifier: 'e2e-handle-input',
          ),
          const SizedBox(height: 12),
          AppPrimaryButton(
            label: l10n.onboardingAccountNext,
            semanticsIdentifier: 'e2e-account-next',
            onPressed: state.busy
                ? null
                : () => controller.checkAccount(handleController.text, domain),
          ),
          AppSecondaryButton(
            label: l10n.onboardingExistingAccountAction,
            semanticsIdentifier: 'e2e-existing-account',
            onPressed: state.busy
                ? null
                : () => controller.continueExisting(
                    handleController.text,
                    domain,
                  ),
          ),
        ] else if (state.step == RegistrationEntryStep.invite) ...[
          Text(state.check!.fullHandle),
          const SizedBox(height: 12),
          Text(l10n.onboardingInviteRequired),
          const SizedBox(height: 12),
          AppTextField(
            controller: inviteController,
            label: l10n.onboardingInviteCode,
            placeholder: l10n.onboardingInviteCode,
            semanticsIdentifier: 'e2e-invite-input',
          ),
          const SizedBox(height: 12),
          AppPrimaryButton(
            label: l10n.onboardingAccountNext,
            semanticsIdentifier: 'e2e-invite-next',
            onPressed: () =>
                controller.continueWithInvite(inviteController.text),
          ),
        ] else if (state.check?.isExisting == true ||
            state.existingAccountPath) ...[
          Text(l10n.onboardingExistingAccount),
          const SizedBox(height: 12),
        ],
        PendingHandleRecoveryEntry(
          handleController: handleController,
          phoneController: phoneController,
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
        if (state.step != RegistrationEntryStep.account)
          CupertinoButton(
            onPressed: onBack,
            child: Text(l10n.onboardingChangeAccount),
          ),
      ],
    );
  }
}
