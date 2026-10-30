import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/l10n.dart';
import '../../domain/entities/pin_recovery.dart';
import '../shared/widgets/app_widgets.dart';
import 'pin_recovery_provider.dart';
import 'pin_recovery_page.dart';

/// Available before ordinary login: the dedicated SMS flow discovers only
/// server-authorized targets, without reusing an ordinary account Join grant.
class PinRecoveryEntry extends ConsumerWidget {
  const PinRecoveryEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(pinRecoveryAvailableProvider)) {
      return const SizedBox.shrink();
    }
    final pending =
        ref.watch(pendingPinRecoveryProvider).valueOrNull ??
        const <PinRecoveryProgress>[];
    void open([PinRecoveryProgress? operation]) => Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PinRecoveryPage(initialOperation: operation),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSecondaryButton(
          key: const Key('pin-recovery-entry'),
          label: context.l10n.pinRecoveryJoin,
          onPressed: open,
        ),
        for (final operation in pending.where(
          (p) => p.kind == PinRecoveryKind.recover,
        ))
          AppSecondaryButton(
            key: Key('pin-recovery-pending-${operation.operationId}'),
            label:
                '${context.l10n.pinRecoveryResume} · ${operation.target.fullHandle}',
            onPressed: () => open(operation),
          ),
      ],
    );
  }
}
