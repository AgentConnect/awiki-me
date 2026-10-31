import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_services.dart';
import '../../application/pin_recovery_service.dart';
import '../../application/ports/pin_recovery_core_port.dart';
import '../../domain/entities/pin_recovery.dart';
import '../../domain/entities/session_identity.dart';

final pinRecoveryCorePortProvider = Provider<PinRecoveryCorePort?>(
  (ref) => null,
);
final pinRecoveryServiceProvider = Provider<PinRecoveryService?>((ref) {
  final port = ref.watch(pinRecoveryCorePortProvider);
  return port == null
      ? null
      : PinRecoveryService(
          core: port,
          userPresence: ref.watch(userPresencePortProvider),
        );
});
final pinRecoveryAvailableProvider = Provider<bool>(
  (ref) => ref.watch(pinRecoveryServiceProvider)?.isAvailable ?? false,
);
final pendingPinRecoveryProvider = FutureProvider<List<PinRecoveryProgress>>(
  (ref) async =>
      await ref.watch(pinRecoveryServiceProvider)?.listPending() ?? const [],
);

/// One-shot presentation intent after local activation. Skipping never creates
/// a Core operation and never becomes a durable reminder or pending backup.
final pinBackupOfferProvider = StateProvider<SessionIdentity?>((ref) => null);

final pinBackupStatusProvider = FutureProvider.autoDispose
    .family<PinBackupStatus, (String, String)>((ref, owner) async {
      final service = ref.watch(pinRecoveryServiceProvider);
      if (service == null) {
        return PinBackupStatus(did: owner.$2, state: PinBackupState.unknown);
      }
      try {
        final status = await service.backupStatus(owner.$1);
        if (status.did != owner.$2) {
          return PinBackupStatus(
            did: owner.$2,
            state: PinBackupState.unknown,
            errorCode: 'target_mismatch',
          );
        }
        return status;
      } catch (_) {
        return PinBackupStatus(
          did: owner.$2,
          state: PinBackupState.unknown,
          errorCode: 'status_unavailable',
        );
      }
    });
