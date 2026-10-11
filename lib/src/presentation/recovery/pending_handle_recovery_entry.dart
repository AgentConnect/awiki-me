import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_router.dart';
import '../../application/tenant/app_tenant.dart';
import '../../domain/entities/handle_recovery.dart';
import '../../l10n/l10n.dart';
import '../../domain/entities/identity_method.dart';
import '../onboarding/onboarding_provider.dart';
import '../shared/awiki_me_design.dart';
import '../shared/widgets/app_widgets.dart';
import 'handle_recovery_page.dart';
import 'handle_recovery_provider.dart';

// Read-only lookup. No OTP, credentials, or presentation state are persisted.
final pendingHandleRecoveryProvider = FutureProvider.autoDispose
    .family<HandleRecoveryContext?, ({String tenantId, String handle})>((
      ref,
      target,
    ) async {
      final tenant = ref.watch(activeAppTenantProvider);
      final service = ref.watch(handleRecoveryServiceProvider);
      if (tenant.id != target.tenantId) return null;
      final ready = Completer<bool>();
      final timer = Timer(
        const Duration(milliseconds: 300),
        () => ready.complete(true),
      );
      ref.onDispose(() {
        timer.cancel();
        if (!ready.isCompleted) ready.complete(false);
      });
      if (!await ready.future) return null;
      final context = await service.inspectContext(handle: target.handle);
      return hasPendingHandleRecovery(context) ? context : null;
    });

bool hasPendingHandleRecovery(HandleRecoveryContext context) =>
    context.progress != null &&
    (context.allowedActions.isEmpty ||
        context.allowedActions.any(
          (action) => action != HandleRecoveryAction.startNew,
        ));

class PendingHandleRecoveryEntry extends ConsumerWidget {
  const PendingHandleRecoveryEntry({
    super.key,
    required this.handleController,
    required this.phoneController,
  });
  final TextEditingController handleController;
  final TextEditingController phoneController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supported = ref.watch(
      onboardingProvider.select(
        (state) =>
            state.didMethod == IdentityDidMethod.wba &&
            state.serverInfo?.supportsPhoneHandleRecovery == true,
      ),
    );
    if (!supported || ref.watch(onboardingProvider).authMode != 'phone') {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: handleController,
      builder: (context, value, _) {
        final handle = value.text.trim().toLowerCase();
        if (!RegExp(
          r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
        ).hasMatch(handle)) {
          return const SizedBox.shrink();
        }
        return Consumer(
          builder: (context, ref, _) {
            final tenant = ref.watch(activeAppTenantProvider);
            final target = (
              tenantId: tenant.id,
              handle: '$handle.${tenant.didHost.toLowerCase()}',
            );
            final provider = pendingHandleRecoveryProvider(target);
            return ref
                .watch(provider)
                .when(
                  // Typing only inspects local state; it has not started a
                  // recovery. Show an entry only after finding resumable work.
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => AppSecondaryButton(
                    key: const Key('onboarding-recovery-lookup-retry'),
                    label:
                        context.l10n.handleRecoveryErrorLocalStateUnavailable,
                    onPressed: () => ref.invalidate(provider),
                  ),
                  data: (progress) {
                    if (progress == null) return const SizedBox.shrink();
                    final label =
                        progress.allowedActions.contains(
                          HandleRecoveryAction.activateIdentity,
                        )
                        ? context.l10n.handleRecoveryEnterMessages
                        : context.l10n.handleRecoveryContinueExisting;
                    return Align(
                      alignment: Alignment.centerRight,
                      child: AppPressableText(
                        key: const Key('onboarding-continue-recovery'),
                        semanticLabel: label,
                        onTap: () async {
                          await AppNavigator.push<void>(
                            context,
                            (_) => HandleRecoveryPage(
                              initialHandle: target.handle,
                              initialPhone: phoneController.text.trim(),
                              allowPhoneInput: true,
                              autoRequestOtp: false,
                            ),
                          );
                          if (context.mounted) ref.invalidate(provider);
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: context.awikiTheme.secondaryText,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 12,
                                  color: context.awikiTheme.secondaryText,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
          },
        );
      },
    );
  }
}
