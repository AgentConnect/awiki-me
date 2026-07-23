// [INPUT]: Current Join target, safe Core preparation, and one platform user-presence confirmation.
// [OUTPUT]: Validated exact-device preparation or secret-free delivery acceptance.
// [POS]: Application policy for the single-recipient post-Join root transfer.

import '../domain/entities/device_management.dart';
import 'ports/root_key_transfer_port.dart';
import 'ports/user_presence_port.dart';

class RootKeyTransferException implements Exception {
  const RootKeyTransferException(this.code, {this.retryable = false});

  final String code;
  final bool retryable;

  @override
  String toString() =>
      'RootKeyTransferException(code: $code, retryable: $retryable)';
}

class RootKeyTransferService {
  const RootKeyTransferService({
    required RootKeyTransferPort transfer,
    required UserPresencePort userPresence,
  }) : _transfer = transfer,
       _userPresence = userPresence;

  final RootKeyTransferPort _transfer;
  final UserPresencePort _userPresence;

  Future<RootKeyTransferPreparation> prepare({
    required String expectedDid,
    required DeviceSummary recipient,
  }) async {
    _validateRecipientEligibility(recipient);
    final preparation = await _transfer.prepare(
      recipientDeviceId: recipient.protocolDeviceId,
    );
    final target = preparation.recipient;
    if (target.did != _required(expectedDid) ||
        target.deviceId != recipient.protocolDeviceId ||
        target.signingKeyId != recipient.signingKeyId ||
        target.e2eeKeyId != recipient.e2eeKeyId ||
        target.registryVersion < 1) {
      throw const RootKeyTransferException(
        'root_transfer.state_changed',
        retryable: true,
      );
    }
    return preparation;
  }

  Future<RootKeyTransferReceipt> confirmAndSend({
    required String expectedDid,
    required DeviceSummary sender,
    required RootKeyTransferPreparation preparation,
    required String presenceReason,
    required bool Function() contextStillValid,
  }) async {
    if (!sender.isCurrent || !sender.canManageDevices) {
      throw const RootKeyTransferException('root_transfer.sender_not_eligible');
    }
    final confirmed = await _userPresence.confirm(
      reason: _required(presenceReason),
    );
    if (confirmed && !contextStillValid()) {
      await discard(preparation);
      throw const RootKeyTransferException(
        'root_transfer.state_changed',
        retryable: true,
      );
    }
    final receipt = await _transfer.confirmAndSend(
      authorizationHandle: preparation.authorizationHandle,
      userPresenceConfirmed: confirmed,
    );
    if (!confirmed) {
      throw const RootKeyTransferException(
        'root_transfer.user_presence_denied',
      );
    }
    if (receipt.did != _required(expectedDid) ||
        receipt.senderDeviceId != sender.protocolDeviceId ||
        receipt.recipientDeviceId != preparation.recipient.deviceId ||
        receipt.messageId.trim().isEmpty) {
      throw const RootKeyTransferException(
        'root_transfer.state_changed',
        retryable: true,
      );
    }
    return receipt;
  }

  Future<void> discard(RootKeyTransferPreparation preparation) async {
    try {
      await _transfer.confirmAndSend(
        authorizationHandle: preparation.authorizationHandle,
        userPresenceConfirmed: false,
      );
    } on Object {
      // Discard is best-effort. The App drops its only handle reference even
      // when Core has already consumed or expired the authorization.
    }
  }
}

void _validateRecipientEligibility(DeviceSummary recipient) {
  if (recipient.isCurrent ||
      recipient.status != DeviceStatus.active ||
      recipient.role != DeviceRole.member ||
      recipient.managementReady) {
    throw const RootKeyTransferException(
      'root_transfer.recipient_not_eligible',
    );
  }
}

String _required(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw const RootKeyTransferException('root_transfer.invalid_request');
  }
  return normalized;
}
