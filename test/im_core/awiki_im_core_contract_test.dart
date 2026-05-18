import 'dart:async';

import 'package:awiki_me/src/im_core/awiki_im_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AwikiImClient contract', () {
    test('barrel exports the frozen client surface and fake', () async {
      final AwikiImClient client = FakeAwikiImClient();
      addTearDown(client.close);

      expect(client.events, isA<Stream<ImEventDto>>());
      expect(client.connectionStates, isA<Stream<ImConnectionStateDto>>());
      expect(client.conversations, isA<ImConversationApi>());
      expect(client.messages, isA<ImMessageApi>());
      expect(client.groups, isA<ImGroupApi>());
      expect(client.realtime, isA<ImRealtimeApi>());
      expect(client.attachments, isA<ImAttachmentApi>());
      expect(client.outbox, isA<ImOutboxApi>());
      expect(client.localStore, isA<ImLocalStoreApi>());
      expect(client.directSecure, isA<ImDirectSecureApi>());
      expect(client.groupE2ee, isA<ImGroupE2eeApi>());
      expect(client.migration, isA<ImMigrationApi>());
      expect(client.advancedAttachments, isA<ImAdvancedAttachmentApi>());

      await client.initialize(
        const ImClientConfig(workspaceId: 'contract-workspace'),
      );
      await client.setSession(
        const ImSessionContext(
          credentialName: 'alice',
          did: 'did:wba:example:alice:e1_alice',
        ),
      );
      await client.updateAuth(const ImAuthUpdate(jwtToken: 'updated'));
      await client.clearSession();

      final status = await client.status();
      expect(status.initialized, isTrue);
      expect(status.hasSession, isFalse);
      expect(status.runtimeMode, ImRuntimeMode.fake);
    });

    test('all reserved API methods fail with typed disabled errors', () async {
      final client = FakeAwikiImClient();
      addTearDown(client.close);

      await client.initialize(
        const ImClientConfig(workspaceId: 'contract-workspace'),
      );

      final matcher = throwsA(
        isA<ImException>()
            .having(
              (error) => error.error.code,
              'code',
              ImErrorCode.featureDisabled,
            )
            .having((error) => error.error.retryable, 'retryable', isFalse),
      );
      Future<void> expectDisabled(dynamic future) async {
        await expectLater(future, matcher);
      }

      await expectDisabled(client.directSecure.status());
      await expectDisabled(
        client.directSecure.init(
          const ImDirectSecurePeerRequest(
            peerDidOrHandle: 'did:wba:example:bob:e1_bob',
          ),
        ),
      );
      await expectDisabled(
        client.directSecure.repair(
          const ImDirectSecurePeerRequest(
            peerDidOrHandle: 'did:wba:example:bob:e1_bob',
          ),
        ),
      );
      await expectDisabled(
        client.directSecure.failed(const ImListOutboxRequest()),
      );
      await expectDisabled(client.directSecure.retry('outbox-1'));
      await expectDisabled(client.directSecure.drop('outbox-1'));

      await expectDisabled(
        client.groupE2ee.status(const ImGroupE2eeStatusRequest()),
      );
      await expectDisabled(
        client.groupE2ee.publishKeyPackage(
          const ImGroupE2eePublishKeyPackageRequest(groupId: 'group-1'),
        ),
      );
      await expectDisabled(
        client.groupE2ee.pending(
          const ImGroupE2eeNoticeRequest(groupId: 'group-1'),
        ),
      );
      await expectDisabled(
        client.groupE2ee.repair(
          const ImGroupE2eeNoticeRequest(groupId: 'group-1'),
        ),
      );
      await expectDisabled(
        client.groupE2ee.recoverMember(
          const ImGroupE2eeMemberRequest(
            groupId: 'group-1',
            memberDidOrHandle: 'did:wba:example:bob:e1_bob',
          ),
        ),
      );
      await expectDisabled(
        client.groupE2ee.processLeaveRequest(
          const ImGroupE2eeProcessLeaveRequest(
            groupId: 'group-1',
            memberDidOrHandle: 'did:wba:example:bob:e1_bob',
          ),
        ),
      );
      await expectDisabled(
        client.groupE2ee.updateKey(
          const ImGroupE2eeMemberRequest(
            groupId: 'group-1',
            memberDidOrHandle: 'did:wba:example:bob:e1_bob',
          ),
        ),
      );
      await expectDisabled(
        client.groupE2ee.rejoin(
          const ImGroupE2eeRejoinRequest(
            groupId: 'group-1',
            memberDidOrHandle: 'did:wba:example:bob:e1_bob',
          ),
        ),
      );

      await expectDisabled(
        client.migration.plan(const ImMigrationPlanRequest()),
      );
      await expectDisabled(client.migration.run(const ImMigrationRunRequest()));
      await expectDisabled(client.migration.syncState());
      await expectDisabled(
        client.migration.repairSync(const ImSyncRepairRequest()),
      );
      await expectDisabled(
        client.migration.exportStore(
          const ImExportStoreRequest(outputPath: '/tmp/im-export.json'),
        ),
      );
      await expectDisabled(
        client.migration.importStore(
          const ImImportStoreRequest(inputPath: '/tmp/im-export.json'),
        ),
      );

      await expectDisabled(
        client.advancedAttachments.createUploadSession(
          const ImAttachmentUploadSessionRequest(fileName: 'reserved.bin'),
        ),
      );
      await expectDisabled(
        client.advancedAttachments.resumeTransfer('transfer-1'),
      );
      await expectDisabled(
        client.advancedAttachments.cancelTransfer('transfer-1'),
      );
    });

    test('fake capabilities mark reserved features disabled', () async {
      final client = FakeAwikiImClient();
      addTearDown(client.close);

      await client.initialize(
        const ImClientConfig(workspaceId: 'contract-workspace'),
      );

      final capabilities = await client.capabilities();
      expect(capabilities.runtimeMode, ImRuntimeMode.fake);
      expect(capabilities.localCache, isTrue);
      expect(capabilities.outbox, isTrue);
      expect(capabilities.realtime, isTrue);
      expect(capabilities.attachments, isTrue);
      expect(capabilities.advancedAttachments, isFalse);
      expect(capabilities.directSecure, isFalse);
      expect(capabilities.groupE2ee, isFalse);
      expect(capabilities.migration, isFalse);
      expect(
        capabilities.metadata['reserved'],
        containsAll(<String>[
          'advancedAttachments',
          'directSecure',
          'groupE2ee',
          'migration',
        ]),
      );
    });
  });
}
