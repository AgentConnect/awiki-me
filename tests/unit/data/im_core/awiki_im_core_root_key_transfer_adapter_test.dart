import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/root_key_transfer_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_root_key_transfer_adapter.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';

const _did = 'did:wba:awiki.info:user:alice:e1_test';

void main() {
  test('maps only the frozen secret-free preparation fields', () async {
    late String capturedRecipient;
    final adapter = AwikiImCoreRootKeyTransferAdapter.withOperations(
      prepare: ({required recipientDeviceId}) async {
        capturedRecipient = recipientDeviceId;
        return const core.RootKeyTransferPreparation(
          authorizationHandle: _CoreAuthorizationHandle(),
          recipient: core.RootKeyTransferRecipientSummary(
            did: _did,
            deviceId: 'member-new',
            signingKeyId: 'member-new#signing',
            e2eeKeyId: 'member-new#e2ee',
            registryVersion: 7,
          ),
          expiresAt: '2030-07-24T00:02:00Z',
        );
      },
      confirmAndSend: _unusedConfirm,
    );

    final preparation = await adapter.prepare(recipientDeviceId: 'member-new');

    expect(capturedRecipient, 'member-new');
    expect(preparation.recipient.deviceId, 'member-new');
    expect(preparation.recipient.registryVersion, 7);
    expect(preparation.authorizationHandle.toString(), contains('<redacted>'));
    expect(preparation.toString(), isNot(contains('opaque-handle')));
  });

  test('confirm returns safe acceptance and forwards opaque handle', () async {
    late core.RootKeyTransferAuthorizationHandle capturedHandle;
    late bool capturedPresence;
    final adapter = AwikiImCoreRootKeyTransferAdapter.withOperations(
      prepare: _corePreparation,
      confirmAndSend:
          ({
            required authorizationHandle,
            required userPresenceConfirmed,
          }) async {
            capturedHandle = authorizationHandle;
            capturedPresence = userPresenceConfirmed;
            return const core.RootKeyTransferSendResult(
              did: _did,
              senderDeviceId: 'admin-current',
              recipientDeviceId: 'member-new',
              messageId: 'root-transfer-message-1',
              acceptedAt: '2026-07-24T00:00:00.000000Z',
            );
          },
    );
    final preparation = await adapter.prepare(recipientDeviceId: 'member-new');

    final receipt = await adapter.confirmAndSend(
      authorizationHandle: preparation.authorizationHandle,
      userPresenceConfirmed: true,
    );

    expect(capturedHandle, isA<_CoreAuthorizationHandle>());
    expect(capturedPresence, isTrue);
    expect(receipt.messageId, 'root-transfer-message-1');
    expect(receipt.toString(), isNot(contains('ciphertext')));
  });

  test('maps the closed Core error without diagnostic details', () async {
    final adapter = AwikiImCoreRootKeyTransferAdapter.withOperations(
      prepare: ({required recipientDeviceId}) async {
        throw const core.RootKeyTransferException(
          code: 'root_transfer.prekey_unavailable',
          retryable: true,
        );
      },
      confirmAndSend: _unusedConfirm,
    );

    Object? caught;
    try {
      await adapter.prepare(recipientDeviceId: 'member-new');
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<RootKeyTransferPortException>());
    final failure = caught! as RootKeyTransferPortException;
    expect(failure.code, 'root_transfer.prekey_unavailable');
    expect(failure.retryable, isTrue);
    expect(failure.toString(), isNot(contains('prekey_bundle')));
  });

  test('rejects a handle that did not come from this adapter', () async {
    final adapter = AwikiImCoreRootKeyTransferAdapter.withOperations(
      prepare: _corePreparation,
      confirmAndSend: _unusedConfirm,
    );

    await expectLater(
      adapter.confirmAndSend(
        authorizationHandle: const _ForeignAuthorizationHandle(),
        userPresenceConfirmed: true,
      ),
      throwsA(
        isA<RootKeyTransferPortException>().having(
          (error) => error.code,
          'code',
          'root_transfer.authorization_invalid',
        ),
      ),
    );
  });

  test('identity switch rejects the old handle before Core confirm', () async {
    var currentAuthority = Object();
    var confirmCalls = 0;
    final adapter = AwikiImCoreRootKeyTransferAdapter.withOperations(
      prepare: _corePreparation,
      confirmAndSend:
          ({
            required authorizationHandle,
            required userPresenceConfirmed,
          }) async {
            confirmCalls += 1;
            throw StateError('confirm must not run after identity switch');
          },
      currentClientAuthority: () async => currentAuthority,
    );
    final preparation = await adapter.prepare(recipientDeviceId: 'member-new');

    currentAuthority = Object();

    await expectLater(
      adapter.confirmAndSend(
        authorizationHandle: preparation.authorizationHandle,
        userPresenceConfirmed: true,
      ),
      throwsA(
        isA<RootKeyTransferPortException>()
            .having(
              (error) => error.code,
              'code',
              'root_transfer.state_changed',
            )
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
    expect(confirmCalls, 0);
  });
}

class _CoreAuthorizationHandle
    implements core.RootKeyTransferAuthorizationHandle {
  const _CoreAuthorizationHandle();
}

class _ForeignAuthorizationHandle
    implements RootKeyTransferAuthorizationHandle {
  const _ForeignAuthorizationHandle();
}

Future<core.RootKeyTransferPreparation> _corePreparation({
  required String recipientDeviceId,
}) async {
  return core.RootKeyTransferPreparation(
    authorizationHandle: const _CoreAuthorizationHandle(),
    recipient: core.RootKeyTransferRecipientSummary(
      did: _did,
      deviceId: recipientDeviceId,
      signingKeyId: 'member-new#signing',
      e2eeKeyId: 'member-new#e2ee',
      registryVersion: 7,
    ),
    expiresAt: '2030-07-24T00:02:00Z',
  );
}

Future<core.RootKeyTransferSendResult> _unusedConfirm({
  required core.RootKeyTransferAuthorizationHandle authorizationHandle,
  required bool userPresenceConfirmed,
}) {
  throw StateError('confirm was not expected');
}
