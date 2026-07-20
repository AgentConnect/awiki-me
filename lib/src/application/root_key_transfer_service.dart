// [INPUT]: A safe IM Core root-transfer port and platform user-presence confirmation.
// [OUTPUT]: Validated restart-safe progress, delivery acceptance, or a stable secret-free error code.
// [POS]: High-risk application policy for listing, starting, and retrying management-device root import.

import '../domain/entities/device_management.dart';
import 'ports/root_key_transfer_port.dart';
import 'ports/user_presence_port.dart';

class RootKeyTransferException implements Exception {
  const RootKeyTransferException(this.code);

  final String code;

  @override
  String toString() => 'RootKeyTransferException($code)';
}

class RootKeyTransferService {
  const RootKeyTransferService({
    required RootKeyTransferPort transfer,
    required UserPresencePort userPresence,
  }) : _transfer = transfer,
       _userPresence = userPresence;

  final RootKeyTransferPort _transfer;
  final UserPresencePort _userPresence;

  Future<List<RootKeyTransferSummary>> list({
    required String selector,
    bool includeCompleted = true,
  }) async {
    final normalizedSelector = _required(selector, 'selector');
    final summaries = await _transfer.listRootKeyTransfers(
      selector: normalizedSelector,
      includeCompleted: includeCompleted,
    );
    final messageIds = <String>{};
    for (final summary in summaries) {
      _validateSummary(summary, selector: normalizedSelector);
      if (!messageIds.add(summary.messageId)) {
        throw const RootKeyTransferException(
          'root_transfer_duplicate_message_id',
        );
      }
    }
    return List<RootKeyTransferSummary>.unmodifiable(summaries);
  }

  Future<RootKeyTransferReceipt> start({
    required String selector,
    required String recipientDeviceId,
    required String messageId,
    required String presenceReason,
  }) async {
    final normalizedSelector = _required(selector, 'selector');
    final normalizedRecipient = _required(
      recipientDeviceId,
      'recipient_device_id',
    );
    final normalizedMessageId = _required(messageId, 'message_id');
    final confirmed = await _userPresence.confirm(
      reason: _required(presenceReason, 'presence_reason'),
    );
    if (!confirmed) {
      throw const RootKeyTransferException('user_presence_denied');
    }

    final receipt = await _transfer.sendRootKeyTransfer(
      selector: normalizedSelector,
      recipientDeviceId: normalizedRecipient,
      messageId: normalizedMessageId,
      userPresenceConfirmed: true,
    );
    if (receipt.did.trim().isEmpty ||
        receipt.senderDeviceId.trim().isEmpty ||
        (_isDid(normalizedSelector) && receipt.did != normalizedSelector) ||
        receipt.recipientDeviceId != normalizedRecipient ||
        receipt.messageId != normalizedMessageId) {
      throw const RootKeyTransferException('root_transfer_response_mismatch');
    }
    return receipt;
  }

  Future<RootKeyTransferSummary> retry({
    required String selector,
    required String messageId,
    required String presenceReason,
  }) async {
    final normalizedSelector = _required(selector, 'selector');
    final normalizedMessageId = _required(messageId, 'message_id');
    final confirmed = await _userPresence.confirm(
      reason: _required(presenceReason, 'presence_reason'),
    );
    if (!confirmed) {
      throw const RootKeyTransferException('user_presence_denied');
    }

    final summary = await _transfer.retryRootKeyTransfer(
      selector: normalizedSelector,
      messageId: normalizedMessageId,
      userPresenceConfirmed: true,
    );
    _validateSummary(summary, selector: normalizedSelector);
    if (summary.messageId != normalizedMessageId) {
      throw const RootKeyTransferException('root_transfer_response_mismatch');
    }
    return summary;
  }
}

void _validateSummary(
  RootKeyTransferSummary summary, {
  required String selector,
}) {
  if (summary.did.trim().isEmpty ||
      summary.senderDeviceId.trim().isEmpty ||
      summary.recipientDeviceId.trim().isEmpty ||
      summary.messageId.trim().isEmpty ||
      (_isDid(selector) && summary.did != selector)) {
    throw const RootKeyTransferException('root_transfer_response_mismatch');
  }
}

bool _isDid(String selector) => selector.startsWith('did:');

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw RootKeyTransferException('invalid_$field');
  }
  return normalized;
}
