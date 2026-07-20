import 'package:awiki_me/src/application/root_key_transfer_service.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_test_support.dart';

void main() {
  test('user presence is required before the Core transfer boundary', () async {
    final transfer = FakeRootKeyTransferPort();
    final presence = FakeUserPresence(result: false);
    final service = RootKeyTransferService(
      transfer: transfer,
      userPresence: presence,
    );

    await expectLater(
      service.start(
        selector: testDid,
        recipientDeviceId: 'admin-new',
        messageId: 'root-message-1',
        presenceReason: 'Confirm transfer',
      ),
      throwsA(
        isA<RootKeyTransferException>().having(
          (error) => error.code,
          'code',
          'user_presence_denied',
        ),
      ),
    );

    expect(presence.calls, 1);
    expect(transfer.calls, 0);
  });

  test('validated acceptance contains no root or control payload', () async {
    final transfer = FakeRootKeyTransferPort();
    final presence = FakeUserPresence();
    final service = RootKeyTransferService(
      transfer: transfer,
      userPresence: presence,
    );

    final receipt = await service.start(
      selector: testDid,
      recipientDeviceId: 'admin-new',
      messageId: 'root-message-1',
      presenceReason: 'Confirm transfer',
    );

    expect(presence.calls, 1);
    expect(transfer.calls, 1);
    expect(transfer.lastUserPresenceConfirmed, isTrue);
    expect(receipt.recipientDeviceId, 'admin-new');
    expect(receipt.messageId, 'root-message-1');
    expect(receipt.toString(), isNot(contains('root_private_key')));
    expect(receipt.toString(), isNot(contains('system_type')));
  });

  test('mismatched delivery acceptance fails closed', () async {
    final service = RootKeyTransferService(
      transfer: _MismatchedTransfer(),
      userPresence: FakeUserPresence(),
    );

    await expectLater(
      service.start(
        selector: testDid,
        recipientDeviceId: 'admin-new',
        messageId: 'root-message-1',
        presenceReason: 'Confirm transfer',
      ),
      throwsA(
        isA<RootKeyTransferException>().having(
          (error) => error.code,
          'code',
          'root_transfer_response_mismatch',
        ),
      ),
    );
  });

  test('listing restart-safe progress does not prompt user presence', () async {
    final transfer = FakeRootKeyTransferPort()
      ..summaries = <RootKeyTransferSummary>[rootTransferSummary()];
    final presence = FakeUserPresence();
    final service = RootKeyTransferService(
      transfer: transfer,
      userPresence: presence,
    );

    final summaries = await service.list(selector: testDid);

    expect(presence.calls, 0);
    expect(transfer.listCalls, 1);
    expect(summaries.single.messageId, 'root-message-1');
  });

  test(
    'retry uses only the persisted message ID after fresh presence',
    () async {
      final transfer = FakeRootKeyTransferPort()
        ..summaries = <RootKeyTransferSummary>[rootTransferSummary()];
      final presence = FakeUserPresence();
      final service = RootKeyTransferService(
        transfer: transfer,
        userPresence: presence,
      );

      final summary = await service.retry(
        selector: testDid,
        messageId: 'root-message-1',
        presenceReason: 'Confirm retry',
      );

      expect(presence.calls, 1);
      expect(transfer.retryCalls, 1);
      expect(transfer.calls, 0);
      expect(transfer.lastMessageId, 'root-message-1');
      expect(transfer.lastUserPresenceConfirmed, isTrue);
      expect(summary.status, RootKeyTransferStatus.importing);
    },
  );
}

class _MismatchedTransfer extends FakeRootKeyTransferPort {
  @override
  Future<RootKeyTransferReceipt> sendRootKeyTransfer({
    required String selector,
    required String recipientDeviceId,
    required String messageId,
    required bool userPresenceConfirmed,
  }) {
    return super.sendRootKeyTransfer(
      selector: selector,
      recipientDeviceId: 'other-device',
      messageId: messageId,
      userPresenceConfirmed: userPresenceConfirmed,
    );
  }
}
