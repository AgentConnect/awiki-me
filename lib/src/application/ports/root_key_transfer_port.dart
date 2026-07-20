// [INPUT]: Identity selector, exact recipient/message IDs, and host-confirmed user presence for mutations.
// [OUTPUT]: Secret-free root-control delivery acceptance and restart-safe progress summaries.
// [POS]: AWiki Me boundary to IM Core's default-off management-device root transfer.

import '../../domain/entities/device_management.dart';

const rootKeyTransferSessionEstablishmentPendingCapability =
    'p5-v2-session-establishment-pending';

/// Redacted Core failure safe to project into application policy.
class RootKeyTransferPortException implements Exception {
  const RootKeyTransferPortException({required this.code, this.capability});

  final String code;
  final String? capability;

  @override
  String toString() =>
      'RootKeyTransferPortException($code${capability == null ? '' : ', $capability'})';
}

/// The encrypted RootKeyEnvelope, imported ACK, and root bytes stay in Core.
abstract interface class RootKeyTransferPort {
  Future<List<RootKeyTransferSummary>> listRootKeyTransfers({
    required String selector,
    required bool includeCompleted,
  });

  Future<RootKeyTransferReceipt> sendRootKeyTransfer({
    required String selector,
    required String recipientDeviceId,
    required String messageId,
    required bool userPresenceConfirmed,
  });

  Future<RootKeyTransferSummary> retryRootKeyTransfer({
    required String selector,
    required String messageId,
    required bool userPresenceConfirmed,
  });
}
