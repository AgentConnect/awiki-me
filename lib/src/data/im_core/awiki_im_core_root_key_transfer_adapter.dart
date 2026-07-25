// [INPUT]: Current identity-scoped client, exact recipient, opaque handle, and host presence.
// [OUTPUT]: Secret-free preparation/acceptance or closed public error.
// [POS]: Thin Dart adapter; root bytes and protocol internals remain inside Core.

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/ports/root_key_transfer_port.dart';
import '../../domain/entities/device_management.dart';
import 'awiki_im_core_runtime.dart';

typedef AwikiImCorePrepareRootKeyTransfer =
    Future<core.RootKeyTransferPreparation> Function({
      required String recipientDeviceId,
    });

typedef AwikiImCoreConfirmRootKeyTransfer =
    Future<core.RootKeyTransferSendResult> Function({
      required core.RootKeyTransferAuthorizationHandle authorizationHandle,
      required bool userPresenceConfirmed,
    });

typedef AwikiImCoreCurrentClientAuthority = Future<Object> Function();

typedef _PrepareScopedRootKeyTransfer =
    Future<_ScopedRootKeyTransferPreparation> Function({
      required String recipientDeviceId,
    });

typedef _ConfirmScopedRootKeyTransfer =
    Future<core.RootKeyTransferSendResult> Function({
      required core.RootKeyTransferAuthorizationHandle authorizationHandle,
      required bool userPresenceConfirmed,
      required Object expectedAuthority,
    });

class AwikiImCoreRootKeyTransferAdapter implements RootKeyTransferPort {
  AwikiImCoreRootKeyTransferAdapter({required AwikiImCoreRuntime runtime})
    : _prepare = (({required recipientDeviceId}) {
        return runtime.withCurrentClient((client) async {
          final result = await client.rootKeyTransfer.prepare(
            recipientDeviceId: recipientDeviceId,
          );
          return _ScopedRootKeyTransferPreparation(
            result: result,
            authority: client,
          );
        });
      }),
      _confirmAndSend =
          (({
            required authorizationHandle,
            required userPresenceConfirmed,
            required expectedAuthority,
          }) {
            return runtime.withCurrentClient((client) {
              if (!identical(client, expectedAuthority)) {
                throw const RootKeyTransferPortException(
                  code: 'root_transfer.state_changed',
                  retryable: true,
                );
              }
              return client.rootKeyTransfer.confirmAndSend(
                authorizationHandle: authorizationHandle,
                userPresenceConfirmed: userPresenceConfirmed,
              );
            });
          });

  factory AwikiImCoreRootKeyTransferAdapter.withOperations({
    required AwikiImCorePrepareRootKeyTransfer prepare,
    required AwikiImCoreConfirmRootKeyTransfer confirmAndSend,
    AwikiImCoreCurrentClientAuthority? currentClientAuthority,
  }) {
    final stableAuthority = Object();
    Future<Object> resolveAuthority() async => currentClientAuthority == null
        ? stableAuthority
        : currentClientAuthority();
    return AwikiImCoreRootKeyTransferAdapter._(
      prepare: ({required recipientDeviceId}) async {
        final authority = await resolveAuthority();
        final result = await prepare(recipientDeviceId: recipientDeviceId);
        return _ScopedRootKeyTransferPreparation(
          result: result,
          authority: authority,
        );
      },
      confirmAndSend:
          ({
            required authorizationHandle,
            required userPresenceConfirmed,
            required expectedAuthority,
          }) async {
            final currentAuthority = await resolveAuthority();
            if (!identical(currentAuthority, expectedAuthority)) {
              throw const RootKeyTransferPortException(
                code: 'root_transfer.state_changed',
                retryable: true,
              );
            }
            return confirmAndSend(
              authorizationHandle: authorizationHandle,
              userPresenceConfirmed: userPresenceConfirmed,
            );
          },
    );
  }

  AwikiImCoreRootKeyTransferAdapter._({
    required _PrepareScopedRootKeyTransfer prepare,
    required _ConfirmScopedRootKeyTransfer confirmAndSend,
  }) : _prepare = prepare,
       _confirmAndSend = confirmAndSend;

  final _PrepareScopedRootKeyTransfer _prepare;
  final _ConfirmScopedRootKeyTransfer _confirmAndSend;

  @override
  Future<RootKeyTransferPreparation> prepare({
    required String recipientDeviceId,
  }) async {
    final scoped = await _redactedCoreCall(
      () => _prepare(recipientDeviceId: recipientDeviceId),
    );
    final result = scoped.result;
    return RootKeyTransferPreparation(
      authorizationHandle: _CoreRootKeyTransferAuthorizationHandle(
        result.authorizationHandle,
        scoped.authority,
      ),
      recipient: RootKeyTransferRecipientSummary(
        did: result.recipient.did,
        deviceId: result.recipient.deviceId,
        signingKeyId: result.recipient.signingKeyId,
        e2eeKeyId: result.recipient.e2eeKeyId,
        registryVersion: result.recipient.registryVersion,
      ),
      expiresAt: _timestamp(result.expiresAt),
    );
  }

  @override
  Future<RootKeyTransferReceipt> confirmAndSend({
    required RootKeyTransferAuthorizationHandle authorizationHandle,
    required bool userPresenceConfirmed,
  }) async {
    if (authorizationHandle is! _CoreRootKeyTransferAuthorizationHandle) {
      throw const RootKeyTransferPortException(
        code: 'root_transfer.authorization_invalid',
        retryable: false,
      );
    }
    final result = await _redactedCoreCall(
      () => _confirmAndSend(
        authorizationHandle: authorizationHandle.value,
        userPresenceConfirmed: userPresenceConfirmed,
        expectedAuthority: authorizationHandle.authority,
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
}

class _CoreRootKeyTransferAuthorizationHandle
    implements RootKeyTransferAuthorizationHandle {
  const _CoreRootKeyTransferAuthorizationHandle(this.value, this.authority);

  final core.RootKeyTransferAuthorizationHandle value;
  final Object authority;

  @override
  String toString() => 'RootKeyTransferAuthorizationHandle(<redacted>)';
}

class _ScopedRootKeyTransferPreparation {
  const _ScopedRootKeyTransferPreparation({
    required this.result,
    required this.authority,
  });

  final core.RootKeyTransferPreparation result;
  final Object authority;
}

DateTime _timestamp(String value) {
  try {
    return DateTime.parse(value);
  } on FormatException {
    throw const RootKeyTransferPortException(
      code: 'root_transfer.temporarily_unavailable',
      retryable: true,
    );
  }
}

Future<T> _redactedCoreCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on core.RootKeyTransferException catch (error) {
    throw RootKeyTransferPortException(
      code: error.code,
      retryable: error.retryable,
    );
  } on RootKeyTransferPortException {
    rethrow;
  } on Object {
    throw const RootKeyTransferPortException(
      code: 'root_transfer.temporarily_unavailable',
      retryable: true,
    );
  }
}
