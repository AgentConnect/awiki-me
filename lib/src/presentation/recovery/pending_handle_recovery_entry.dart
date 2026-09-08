import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/tenant/app_tenant.dart';
import '../../domain/entities/handle_recovery.dart';
import '../../l10n/l10n.dart';
import '../onboarding/onboarding_provider.dart';
import '../shared/widgets/app_widgets.dart';
import 'handle_recovery_page.dart';
import 'handle_recovery_provider.dart';

// Read-only lookup. No OTP, credentials, or presentation state are persisted.
final pendingHandleRecoveryProvider = FutureProvider.autoDispose
    .family<HandleRecoveryProgress?, ({String tenantId, String handle})>((
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
      return service.restoreForHandle(target.handle);
    });

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
        (state) => state.serverInfo?.supportsPhoneHandleRecovery == true,
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
                  loading: () => Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(context.l10n.handleRecoveryChecking),
                  ),
                  error: (_, _) => AppSecondaryButton(
                    key: const Key('onboarding-recovery-lookup-retry'),
                    label:
                        context.l10n.handleRecoveryErrorLocalStateUnavailable,
                    onPressed: () => ref.invalidate(provider),
                  ),
                  data: (progress) => progress == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: AppPrimaryButton(
                            key: const Key('onboarding-continue-recovery'),
                            label: progress.isCompleted
                                ? context.l10n.handleRecoveryEnterMessages
                                : context.l10n.handleRecoveryContinueExisting,
                            onPressed: () async {
                              await Navigator.of(context).push<void>(
                                CupertinoPageRoute(
                                  builder: (_) => HandleRecoveryPage(
                                    initialHandle: target.handle,
                                    initialPhone: phoneController.text.trim(),
                                    allowPhoneInput: true,
                                    autoRequestOtp: false,
                                  ),
                                ),
                              );
                              if (context.mounted) ref.invalidate(provider);
                            },
                          ),
                        ),
                );
          },
        );
      },
    );
  }
}
