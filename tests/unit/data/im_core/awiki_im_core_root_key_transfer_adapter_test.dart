import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/ports/root_key_transfer_port.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_root_key_transfer_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps only safe root-transfer delivery metadata', () async {
    late core.IdentitySelector capturedSelector;
    late String capturedRecipient;
    late String capturedMessageId;
    late bool capturedPresence;
    final adapter = AwikiImCoreRootKeyTransferAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      sendRootKeyTransfer:
          ({
            required selector,
            required recipientDeviceId,
            required messageId,
            required userPresenceConfirmed,
          }) async {
            capturedSelector = selector;
            capturedRecipient = recipientDeviceId;
            capturedMessageId = messageId;
            capturedPresence = userPresenceConfirmed;
            return const core.RootKeyTransferSendResult(
              did: 'did:wba:awiki.info:user:alice:e1_test',
              senderDeviceId: 'admin-current',
              recipientDeviceId: 'admin-new',
              messageId: 'root-message-1',
              acceptedAt: '2026-07-20T01:00:00Z',
            );
          },
    );

    final receipt = await adapter.sendRootKeyTransfer(
      selector: 'did:wba:awiki.info:user:alice:e1_test',
      recipientDeviceId: 'admin-new',
      messageId: 'root-message-1',
      userPresenceConfirmed: true,
    );

    expect(capturedSelector, isA<core.DidIdentitySelector>());
    expect(
      (capturedSelector as core.DidIdentitySelector).did,
      'did:wba:awiki.info:user:alice:e1_test',
    );
    expect(capturedRecipient, 'admin-new');
    expect(capturedMessageId, 'root-message-1');
    expect(capturedPresence, isTrue);
    expect(receipt.senderDeviceId, 'admin-current');
    expect(receipt.acceptedAt, DateTime.utc(2026, 7, 20, 1));
    expect(receipt.toString(), isNot(contains('root_private_key')));
    expect(receipt.toString(), isNot(contains('control_json')));
  });

  test('invalid accepted timestamp does not expose response content', () async {
    const secret = 'sensitive-response-marker-must-not-escape';
    final adapter = AwikiImCoreRootKeyTransferAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      sendRootKeyTransfer:
          ({
            required selector,
            required recipientDeviceId,
            required messageId,
            required userPresenceConfirmed,
          }) async => const core.RootKeyTransferSendResult(
            did: 'did:wba:awiki.info:user:alice:e1_test',
            senderDeviceId: 'admin-current',
            recipientDeviceId: 'admin-new',
            messageId: 'root-message-1',
            acceptedAt: secret,
          ),
    );

    Object? error;
    try {
      await adapter.sendRootKeyTransfer(
        selector: 'did:wba:awiki.info:user:alice:e1_test',
        recipientDeviceId: 'admin-new',
        messageId: 'root-message-1',
        userPresenceConfirmed: true,
      );
    } catch (caught) {
      error = caught;
    }

    expect(error, isA<FormatException>());
    expect(error.toString(), isNot(contains(secret)));
  });

  test('maps restart-safe list progress without control payloads', () async {
    late core.IdentitySelector capturedSelector;
    late bool capturedIncludeCompleted;
    final adapter = AwikiImCoreRootKeyTransferAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      listRootKeyTransfers:
          ({required selector, required includeCompleted}) async {
            capturedSelector = selector;
            capturedIncludeCompleted = includeCompleted;
            return const <core.RootKeyTransferSummary>[
              core.RootKeyTransferSummary(
                did: 'did:wba:awiki.info:user:alice:e1_test',
                messageId: 'root-message-1',
                senderDeviceId: 'admin-current',
                recipientDeviceId: 'admin-new',
                status: core.RootKeyTransferStatus.awaitingImport,
                createdAt: '2026-07-20T01:00:00Z',
                acceptedAt: '2026-07-20T01:00:01Z',
                retryable: true,
              ),
            ];
          },
    );

    final summaries = await adapter.listRootKeyTransfers(
      selector: 'did:wba:awiki.info:user:alice:e1_test',
      includeCompleted: true,
    );

    expect(capturedSelector, isA<core.DidIdentitySelector>());
    expect(capturedIncludeCompleted, isTrue);
    expect(summaries.single.status.name, 'awaitingImport');
    expect(summaries.single.createdAt, DateTime.utc(2026, 7, 20, 1));
    expect(summaries.single.acceptedAt, DateTime.utc(2026, 7, 20, 1, 0, 1));
    expect(summaries.single.retryable, isTrue);
    expect(summaries.single.toString(), isNot(contains('root_private_key')));
  });

  test(
    'retry forwards only the exact persisted message ID and presence',
    () async {
      late String capturedMessageId;
      late bool capturedPresence;
      final adapter = AwikiImCoreRootKeyTransferAdapter.withCoreInstance(
        coreInstance: _unusedCore,
        retryRootKeyTransfer:
            ({
              required selector,
              required messageId,
              required userPresenceConfirmed,
            }) async {
              capturedMessageId = messageId;
              capturedPresence = userPresenceConfirmed;
              return const core.RootKeyTransferSummary(
                did: 'did:wba:awiki.info:user:alice:e1_test',
                messageId: 'persisted-message',
                senderDeviceId: 'admin-current',
                recipientDeviceId: 'admin-new',
                status: core.RootKeyTransferStatus.importing,
                createdAt: '2026-07-20T01:00:00Z',
                retryable: false,
              );
            },
      );

      final summary = await adapter.retryRootKeyTransfer(
        selector: 'did:wba:awiki.info:user:alice:e1_test',
        messageId: 'persisted-message',
        userPresenceConfirmed: true,
      );

      expect(capturedMessageId, 'persisted-message');
      expect(capturedPresence, isTrue);
      expect(summary.status.name, 'importing');
      expect(summary.retryable, isFalse);
    },
  );

  test('Core errors expose only stable code and capability', () async {
    const secret = 'root-or-service-detail-must-not-escape';
    final adapter = AwikiImCoreRootKeyTransferAdapter.withCoreInstance(
      coreInstance: _unusedCore,
      sendRootKeyTransfer:
          ({
            required selector,
            required recipientDeviceId,
            required messageId,
            required userPresenceConfirmed,
          }) async => throw const core.AwikiImCoreException(
            code: 'unsupported_capability',
            message: secret,
            capability: rootKeyTransferSessionEstablishmentPendingCapability,
            serviceDataJson: secret,
          ),
    );

    Object? caught;
    try {
      await adapter.sendRootKeyTransfer(
        selector: 'did:wba:awiki.info:user:alice:e1_test',
        recipientDeviceId: 'admin-new',
        messageId: 'root-message-1',
        userPresenceConfirmed: true,
      );
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<RootKeyTransferPortException>());
    expect(
      (caught! as RootKeyTransferPortException).capability,
      rootKeyTransferSessionEstablishmentPendingCapability,
    );
    expect(caught.toString(), isNot(contains(secret)));
  });
}

Future<core.AwikiImCore> _unusedCore() {
  throw StateError('Core access was not expected by this test.');
}
