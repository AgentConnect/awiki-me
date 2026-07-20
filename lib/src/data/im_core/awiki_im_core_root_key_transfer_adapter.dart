// [INPUT]: AWiki Me identity/device/message identifiers and host user-presence assertions for mutations.
// [OUTPUT]: Secret-free IM Core delivery metadata and restart-safe transfer summaries.
// [POS]: Thin Dart adapter; root bytes and encrypted control JSON never cross this file boundary.

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/root_key_transfer_port.dart';
import '../../domain/entities/device_management.dart';
import 'awiki_im_core_runtime.dart';

typedef AwikiImCoreRootInstance = Future<core.AwikiImCore> Function();

typedef AwikiImCoreSendRootKeyTransfer =
    Future<core.RootKeyTransferSendResult> Function({
      required core.IdentitySelector selector,
      required String recipientDeviceId,
      required String messageId,
      required bool userPresenceConfirmed,
    });

typedef AwikiImCoreListRootKeyTransfers =
    Future<List<core.RootKeyTransferSummary>> Function({
      required core.IdentitySelector selector,
      required bool includeCompleted,
    });

typedef AwikiImCoreRetryRootKeyTransfer =
    Future<core.RootKeyTransferSummary> Function({
      required core.IdentitySelector selector,
      required String messageId,
      required bool userPresenceConfirmed,
    });

class AwikiImCoreRootKeyTransferAdapter implements RootKeyTransferPort {
  AwikiImCoreRootKeyTransferAdapter({required AwikiImCoreRuntime runtime})
    : this.withCoreInstance(coreInstance: runtime.coreInstance);

  AwikiImCoreRootKeyTransferAdapter.withCoreInstance({
    required AwikiImCoreRootInstance coreInstance,
    AwikiImCoreSendRootKeyTransfer? sendRootKeyTransfer,
    AwikiImCoreListRootKeyTransfers? listRootKeyTransfers,
    AwikiImCoreRetryRootKeyTransfer? retryRootKeyTransfer,
  }) : _sendRootKeyTransfer =
           sendRootKeyTransfer ??
           (({
             required selector,
             required recipientDeviceId,
             required messageId,
             required userPresenceConfirmed,
           }) async {
             final instance = await coreInstance();
             return instance.sendRootKeyTransfer(
               selector: selector,
               recipientDeviceId: recipientDeviceId,
               messageId: messageId,
               userPresenceConfirmed: userPresenceConfirmed,
             );
           }),
       _listRootKeyTransfers =
           listRootKeyTransfers ??
           (({required selector, required includeCompleted}) async {
             final instance = await coreInstance();
             return instance.listRootKeyTransfers(
               selector: selector,
               includeCompleted: includeCompleted,
             );
           }),
       _retryRootKeyTransfer =
           retryRootKeyTransfer ??
           (({
             required selector,
             required messageId,
             required userPresenceConfirmed,
           }) async {
             final instance = await coreInstance();
             return instance.retryRootKeyTransfer(
               selector: selector,
               messageId: messageId,
               userPresenceConfirmed: userPresenceConfirmed,
             );
           });

  final AwikiImCoreSendRootKeyTransfer _sendRootKeyTransfer;
  final AwikiImCoreListRootKeyTransfers _listRootKeyTransfers;
  final AwikiImCoreRetryRootKeyTransfer _retryRootKeyTransfer;

  @override
  Future<List<RootKeyTransferSummary>> listRootKeyTransfers({
    required String selector,
    required bool includeCompleted,
  }) async {
    final summaries = await _redactedCoreCall(
      () => _listRootKeyTransfers(
        selector: _identitySelector(selector),
        includeCompleted: includeCompleted,
      ),
    );
    return summaries.map(_summary).toList(growable: false);
  }

  @override
  Future<RootKeyTransferReceipt> sendRootKeyTransfer({
    required String selector,
    required String recipientDeviceId,
    required String messageId,
    required bool userPresenceConfirmed,
  }) async {
    final result = await _redactedCoreCall(
      () => _sendRootKeyTransfer(
        selector: _identitySelector(selector),
        recipientDeviceId: recipientDeviceId,
        messageId: messageId,
        userPresenceConfirmed: userPresenceConfirmed,
      ),
    );
    return RootKeyTransferReceipt(
      did: result.did,
      senderDeviceId: result.senderDeviceId,
      recipientDeviceId: result.recipientDeviceId,
      messageId: result.messageId,
      acceptedAt: _timestamp(result.acceptedAt),
    );
  }

  @override
  Future<RootKeyTransferSummary> retryRootKeyTransfer({
    required String selector,
    required String messageId,
    required bool userPresenceConfirmed,
  }) async {
    final summary = await _redactedCoreCall(
      () => _retryRootKeyTransfer(
        selector: _identitySelector(selector),
        messageId: messageId,
        userPresenceConfirmed: userPresenceConfirmed,
      ),
    );
    return _summary(summary);
  }
}

RootKeyTransferSummary _summary(core.RootKeyTransferSummary value) {
  return RootKeyTransferSummary(
    did: value.did,
    senderDeviceId: value.senderDeviceId,
    recipientDeviceId: value.recipientDeviceId,
    messageId: value.messageId,
    status: switch (value.status) {
      core.RootKeyTransferStatus.pendingDelivery =>
        RootKeyTransferStatus.pendingDelivery,
      core.RootKeyTransferStatus.awaitingImport =>
        RootKeyTransferStatus.awaitingImport,
      core.RootKeyTransferStatus.importing => RootKeyTransferStatus.importing,
      core.RootKeyTransferStatus.failed => RootKeyTransferStatus.failed,
      core.RootKeyTransferStatus.completed => RootKeyTransferStatus.completed,
    },
    createdAt: _timestamp(value.createdAt),
    acceptedAt: _optionalTimestamp(value.acceptedAt),
    completedAt: _optionalTimestamp(value.completedAt),
    retryable: value.retryable,
  );
}

core.IdentitySelector _identitySelector(String value) {
  final selector = value.trim();
  if (selector.isEmpty) {
    throw const FormatException('invalid_identity_selector');
  }
  if (selector == 'default') {
    return const core.IdentitySelector.defaultIdentity();
  }
  if (selector.startsWith('did:')) {
    return core.IdentitySelector.did(selector);
  }
  if (selector.startsWith('@')) {
    return core.IdentitySelector.localAlias(selector.substring(1));
  }
  if (selector.contains('.')) {
    return core.IdentitySelector.handle(selector);
  }
  return core.IdentitySelector.id(selector);
}

DateTime _timestamp(String value) {
  try {
    return DateTime.parse(value);
  } on FormatException {
    throw const FormatException('invalid_root_transfer_timestamp');
  }
}

DateTime? _optionalTimestamp(String? value) =>
    value == null ? null : _timestamp(value);

Future<T> _redactedCoreCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on core.AwikiImCoreException catch (error) {
    throw RootKeyTransferPortException(
      code: error.code,
      capability:
          error.capability ==
              rootKeyTransferSessionEstablishmentPendingCapability
          ? error.capability
          : null,
    );
  }
}
