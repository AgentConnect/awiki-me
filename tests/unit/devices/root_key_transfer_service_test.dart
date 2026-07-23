import 'dart:async';

import 'package:awiki_me/src/application/ports/root_key_transfer_port.dart';
import 'package:awiki_me/src/application/ports/user_presence_port.dart';
import 'package:awiki_me/src/application/root_key_transfer_service.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';

const _did = 'did:wba:awiki.info:user:alice:e1_test';

void main() {
  test(
    'prepare verifies the exact just-joined member before confirmation',
    () async {
      final transfer = _FakeTransfer();
      final presence = _FakePresence();
      final service = RootKeyTransferService(
        transfer: transfer,
        userPresence: presence,
      );

      final result = await service.prepare(
        expectedDid: _did,
        recipient: _recipient(),
      );

      expect(transfer.preparedRecipientDeviceId, 'member-new');
      expect(result.recipient.signingKeyId, 'member-new#signing');
      expect(presence.calls, 0);
      expect(result.toString(), contains('<redacted>'));
      expect(result.toString(), isNot(contains('opaque-authorization')));
    },
  );

  test('prepare fails closed when Core returns a different device', () async {
    final transfer = _FakeTransfer()
      ..preparation = _preparation(deviceId: 'different-device');
    final service = RootKeyTransferService(
      transfer: transfer,
      userPresence: _FakePresence(),
    );

    await expectLater(
      service.prepare(expectedDid: _did, recipient: _recipient()),
      throwsA(
        isA<RootKeyTransferException>().having(
          (error) => error.code,
          'code',
          'root_transfer.state_changed',
        ),
      ),
    );
  });

  test(
    'confirm performs one presence prompt and returns safe acceptance',
    () async {
      final transfer = _FakeTransfer();
      final presence = _FakePresence();
      final service = RootKeyTransferService(
        transfer: transfer,
        userPresence: presence,
      );

      final receipt = await service.confirmAndSend(
        expectedDid: _did,
        sender: _sender(),
        preparation: transfer.preparation,
        presenceReason: 'Confirm root transfer',
        contextStillValid: () => true,
      );

      expect(presence.calls, 1);
      expect(transfer.confirmCalls, 1);
      expect(transfer.confirmedPresence, isTrue);
      expect(receipt.messageId, 'root-transfer-message-1');
      expect(receipt.toString(), isNot(contains('root_private_key')));
    },
  );

  test(
    'presence denial is passed to Core exactly once to consume handle',
    () async {
      final transfer = _FakeTransfer()
        ..confirmError = const RootKeyTransferPortException(
          code: 'root_transfer.user_presence_denied',
          retryable: false,
        );
      final presence = _FakePresence(result: false);
      final service = RootKeyTransferService(
        transfer: transfer,
        userPresence: presence,
      );

      await expectLater(
        service.confirmAndSend(
          expectedDid: _did,
          sender: _sender(),
          preparation: transfer.preparation,
          presenceReason: 'Confirm root transfer',
          contextStillValid: () => true,
        ),
        throwsA(isA<RootKeyTransferPortException>()),
      );
      expect(presence.calls, 1);
      expect(transfer.confirmCalls, 1);
      expect(transfer.confirmedPresence, isFalse);
    },
  );

  test('receipt route mismatch stays inside the closed error union', () async {
    final transfer = _FakeTransfer()..receiptDid = 'did:wba:other.test:bob';
    final service = RootKeyTransferService(
      transfer: transfer,
      userPresence: _FakePresence(),
    );

    await expectLater(
      service.confirmAndSend(
        expectedDid: _did,
        sender: _sender(),
        preparation: transfer.preparation,
        presenceReason: 'Confirm root transfer',
        contextStillValid: () => true,
      ),
      throwsA(
        isA<RootKeyTransferException>()
            .having(
              (error) => error.code,
              'code',
              'root_transfer.state_changed',
            )
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
  });

  test(
    'context change during user presence consumes without sending',
    () async {
      final transfer = _FakeTransfer()
        ..confirmError = const RootKeyTransferPortException(
          code: 'root_transfer.user_presence_denied',
          retryable: false,
        );
      final presence = _DeferredPresence();
      final service = RootKeyTransferService(
        transfer: transfer,
        userPresence: presence,
      );
      var contextValid = true;

      final pending = service.confirmAndSend(
        expectedDid: _did,
        sender: _sender(),
        preparation: transfer.preparation,
        presenceReason: 'Confirm root transfer',
        contextStillValid: () => contextValid,
      );
      await presence.started.future;
      contextValid = false;
      presence.complete(true);

      await expectLater(
        pending,
        throwsA(
          isA<RootKeyTransferException>().having(
            (error) => error.code,
            'code',
            'root_transfer.state_changed',
          ),
        ),
      );
      expect(transfer.confirmCalls, 1);
      expect(transfer.confirmedPresence, isFalse);
    },
  );
}

class _AuthorizationHandle implements RootKeyTransferAuthorizationHandle {
  const _AuthorizationHandle();

  @override
  String toString() => 'RootKeyTransferAuthorizationHandle(<redacted>)';
}

class _FakeTransfer implements RootKeyTransferPort {
  RootKeyTransferPreparation preparation = _preparation();
  Object? confirmError;
  String? preparedRecipientDeviceId;
  int confirmCalls = 0;
  bool? confirmedPresence;
  String receiptDid = _did;

  @override
  Future<RootKeyTransferPreparation> prepare({
    required String recipientDeviceId,
  }) async {
    preparedRecipientDeviceId = recipientDeviceId;
    return preparation;
  }

  @override
  Future<RootKeyTransferReceipt> confirmAndSend({
    required RootKeyTransferAuthorizationHandle authorizationHandle,
    required bool userPresenceConfirmed,
  }) async {
    confirmCalls += 1;
    confirmedPresence = userPresenceConfirmed;
    if (confirmError != null) throw confirmError!;
    return RootKeyTransferReceipt(
      did: receiptDid,
      senderDeviceId: 'admin-current',
      recipientDeviceId: preparation.recipient.deviceId,
      messageId: 'root-transfer-message-1',
      acceptedAt: DateTime.utc(2026, 7, 24),
    );
  }
}

class _FakePresence implements UserPresencePort {
  _FakePresence({this.result = true});

  final bool result;
  int calls = 0;

  @override
  Future<bool> confirm({required String reason}) async {
    calls += 1;
    return result;
  }
}

class _DeferredPresence implements UserPresencePort {
  final started = Completer<void>();
  final _result = Completer<bool>();

  void complete(bool result) => _result.complete(result);

  @override
  Future<bool> confirm({required String reason}) {
    started.complete();
    return _result.future;
  }
}

RootKeyTransferPreparation _preparation({String deviceId = 'member-new'}) {
  return RootKeyTransferPreparation(
    authorizationHandle: const _AuthorizationHandle(),
    recipient: RootKeyTransferRecipientSummary(
      did: _did,
      deviceId: deviceId,
      signingKeyId: 'member-new#signing',
      e2eeKeyId: 'member-new#e2ee',
      registryVersion: 7,
    ),
    expiresAt: DateTime.utc(2030),
  );
}

DeviceSummary _recipient() => const DeviceSummary(
  protocolDeviceId: 'member-new',
  signingKeyId: 'member-new#signing',
  e2eeKeyId: 'member-new#e2ee',
  status: DeviceStatus.active,
  role: DeviceRole.member,
  managementReady: false,
  isCurrent: false,
);

DeviceSummary _sender() => const DeviceSummary(
  protocolDeviceId: 'admin-current',
  signingKeyId: 'admin-current#signing',
  e2eeKeyId: 'admin-current#e2ee',
  status: DeviceStatus.active,
  role: DeviceRole.admin,
  managementReady: true,
  isCurrent: true,
);
