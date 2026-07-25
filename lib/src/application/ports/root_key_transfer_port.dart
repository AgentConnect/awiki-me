// [INPUT]: Exact recipient or opaque authorization plus host-confirmed user presence.
// [OUTPUT]: Secret-free preparation/acceptance or the closed root-transfer error union.
// [POS]: Identity-scoped AWiki Me boundary to IM Core root transfer.

import '../../domain/entities/device_management.dart';

class RootKeyTransferPortException implements Exception {
  const RootKeyTransferPortException({
    required this.code,
    required this.retryable,
  });

  final String code;
  final bool retryable;

  @override
  String toString() =>
      'RootKeyTransferPortException(code: $code, retryable: $retryable)';
}

abstract interface class RootKeyTransferPort {
  Future<RootKeyTransferPreparation> prepare({
    required String recipientDeviceId,
  });

  Future<RootKeyTransferReceipt> confirmAndSend({
    required RootKeyTransferAuthorizationHandle authorizationHandle,
    required bool userPresenceConfirmed,
  });
}
