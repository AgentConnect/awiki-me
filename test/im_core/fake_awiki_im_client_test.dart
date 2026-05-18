import 'package:awiki_me/src/im_core/awiki_im_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FakeAwikiImClient', () {
    test(
      'lifecycle, auth, realtime, status, and capabilities are deterministic',
      () async {
        final client = FakeAwikiImClient();
        addTearDown(client.close);
        final states = <ImConnectionStateDto>[];
        final subscription = client.connectionStates.listen(states.add);
        addTearDown(subscription.cancel);

        await client.initialize(
          const ImClientConfig(
            workspaceId: 'fake-workspace',
            storePath: 'memory://test-store',
          ),
        );
        await client.setSession(
          const ImSessionContext(
            credentialName: 'alice',
            did: 'did:wba:example:alice:e1_alice',
            handle: 'alice.example',
            displayName: 'Alice',
            jwtToken: 'initial',
          ),
        );
        await client.updateAuth(const ImAuthUpdate(jwtToken: 'updated'));
        await client.realtime.connect(const ImRealtimeConnectRequest());
        await client.realtime.disconnect();
        await pumpEventQueue();

        final status = await client.status();
        final capabilities = await client.capabilities();

        expect(status.initialized, isTrue);
        expect(status.hasSession, isTrue);
        expect(status.connectionState, ImConnectionState.disconnected);
        expect(status.storePath, 'memory://test-store');
        expect(status.schemaVersion, 1);
        expect(capabilities.runtimeMode, ImRuntimeMode.fake);
        expect(
          states.map((state) => state.state),
          contains(ImConnectionState.idle),
        );
        expect(
          states.map((state) => state.state),
          contains(ImConnectionState.connected),
        );
        expect(
          states.map((state) => state.state),
          contains(ImConnectionState.disconnected),
        );

        await client.clearSession();
        final cleared = await client.status();
        expect(cleared.hasSession, isFalse);
      },
    );

    test('empty lists and local-store stats are deterministic', () async {
      final client = FakeAwikiImClient();
      addTearDown(client.close);

      await _initializeAlice(client);
      const directThread = ImThreadRef(
        threadId:
            'dm:did:wba:example:alice:e1_alice:did:wba:example:bob:e1_bob',
        kind: ImThreadKind.direct,
        peerDid: 'did:wba:example:bob:e1_bob',
      );

      expect(
        (await client.conversations.list(
          const ImListConversationsRequest(),
        )).items,
        isEmpty,
      );
      expect(
        (await client.messages.list(
          const ImListMessagesRequest(thread: directThread),
        )).items,
        isEmpty,
      );
      expect(
        (await client.outbox.list(const ImListOutboxRequest())).items,
        isEmpty,
      );
      final stats = await client.localStore.stats();
      expect(stats.messageCount, 0);
      expect(stats.conversationCount, 0);
      expect(stats.groupCount, 0);
      expect(stats.outboxCount, 0);
      expect(stats.unreadCount, 0);
    });

    test(
      'direct and group messages update conversations and history',
      () async {
        final client = FakeAwikiImClient();
        addTearDown(client.close);
        final events = <ImEventDto>[];
        final subscription = client.events.listen(events.add);
        addTearDown(subscription.cancel);

        await _initializeAlice(client);

        final direct = await client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'hello bob',
            clientOperationId: 'op-direct-1',
          ),
        );
        expect(direct.accepted, isTrue);
        expect(direct.finalAcceptance, isTrue);
        expect(direct.remoteMessageId, isNotNull);
        expect(direct.operationId, 'op-direct-1');
        expect(direct.deliveryState, ImSendState.sent.name);
        expect(direct.message.thread.kind, ImThreadKind.direct);
        expect(
          direct.message.thread.threadId,
          'dm:did:wba:example:alice:e1_alice:did:wba:example:bob:e1_bob',
        );
        expect(direct.message.receiverDid, 'did:wba:example:bob:e1_bob');
        expect(direct.message.senderDisplayName, 'Alice');

        final directHistory = await client.messages.list(
          ImListMessagesRequest(thread: direct.message.thread),
        );
        expect(directHistory.items.single.localId, direct.message.localId);

        final conversations = await client.conversations.list(
          const ImListConversationsRequest(),
        );
        expect(conversations.items, hasLength(1));
        expect(conversations.items.single.lastMessagePreview, 'hello bob');
        expect(conversations.items.single.unreadCount, 0);

        final group = await client.groups.create(
          const ImCreateGroupRequest(
            name: 'SDK Group',
            description: 'test group',
          ),
        );
        final updatedGroup = await client.groups.addMember(
          ImGroupMemberMutationRequest(
            groupId: group.groupId,
            memberDidOrHandle: 'did:wba:example:bob:e1_bob',
          ),
        );
        expect(updatedGroup.memberCount, 2);

        final groupResult = await client.messages.send(
          ImSendMessageRequest(
            target: ImSendTarget(groupId: group.groupId),
            text: 'hello group',
          ),
        );
        expect(groupResult.message.thread.kind, ImThreadKind.group);
        expect(groupResult.message.thread.threadId, 'group:${group.groupId}');
        expect(groupResult.message.groupId, group.groupId);

        final groupHistory = await client.groups.listMessages(
          ImListGroupMessagesRequest(groupId: group.groupId),
        );
        expect(groupHistory.items.single.plaintextText, 'hello group');

        await pumpEventQueue();
        expect(
          events.map((event) => event.kind),
          contains(ImEventKind.messageUpdated),
        );
      },
    );

    test(
      'pagination, mark-read, delete thread, and outbox drop are stable',
      () async {
        final client = FakeAwikiImClient();
        addTearDown(client.close);

        await _initializeAlice(client);

        final first = await client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'page one',
          ),
        );
        await client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'page two',
          ),
        );
        await client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'page three',
          ),
        );
        await client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(
              peerDidOrHandle: 'did:wba:example:carol:e1_carol',
            ),
            text: 'other thread',
          ),
        );

        final firstPage = await client.messages.list(
          ImListMessagesRequest(thread: first.message.thread, limit: 2),
        );
        expect(
          firstPage.items.map((message) => message.plaintextText),
          <String>['page one', 'page two'],
        );
        expect(firstPage.nextCursor, '2');
        expect(firstPage.hasMore, isTrue);

        final secondPage = await client.messages.list(
          ImListMessagesRequest(
            thread: first.message.thread,
            limit: 2,
            cursor: firstPage.nextCursor,
          ),
        );
        expect(secondPage.items.single.plaintextText, 'page three');
        expect(secondPage.nextCursor, isNull);
        expect(secondPage.hasMore, isFalse);

        final conversationsPage = await client.conversations.list(
          const ImListConversationsRequest(limit: 1),
        );
        expect(conversationsPage.items, hasLength(1));
        expect(conversationsPage.nextCursor, '1');
        expect(conversationsPage.hasMore, isTrue);

        await client.conversations.markThreadRead(
          first.message.thread.threadId,
        );
        final readConversation = await client.conversations.get(
          first.message.thread.threadId,
        );
        expect(readConversation?.unreadCount, 0);

        final failed = await client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'drop me',
            metadata: <String, Object?>{'forceFail': true},
          ),
        );
        expect(failed.accepted, isFalse);
        final outboxBeforeDrop = await client.outbox.list(
          const ImListOutboxRequest(failedOnly: true),
        );
        expect(outboxBeforeDrop.items, hasLength(1));
        await client.outbox.drop(outboxBeforeDrop.items.single.outboxId);
        expect(
          (await client.outbox.list(const ImListOutboxRequest())).items,
          isEmpty,
        );

        await client.conversations.deleteLocalThread(
          first.message.thread.threadId,
        );
        expect(
          await client.conversations.get(first.message.thread.threadId),
          isNull,
        );
        expect(
          (await client.messages.list(
            ImListMessagesRequest(thread: first.message.thread),
          )).items,
          isEmpty,
        );
      },
    );

    test(
      'attachments, outbox, local store, sync, and clearing work in memory',
      () async {
        final client = FakeAwikiImClient();
        addTearDown(client.close);
        final events = <ImEventDto>[];
        final subscription = client.events.listen(events.add);
        addTearDown(subscription.cancel);

        await _initializeAlice(client);

        final attachmentResult = await client.attachments.sendAttachment(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'see attachment',
            attachments: <ImAttachmentInput>[
              ImAttachmentInput(
                fileName: 'hello.txt',
                mimeType: 'text/plain',
                bytes: <int>[104, 105],
              ),
            ],
          ),
        );
        expect(attachmentResult.message.kind, ImMessageKind.attachment);
        expect(attachmentResult.message.attachments.single.sizeBytes, 2);

        final download = await client.attachments.download(
          ImAttachmentDownloadRequest(
            thread: attachmentResult.message.thread,
            messageId: attachmentResult.message.localId,
            outputPath: '/tmp/hello.txt',
          ),
        );
        expect(download.outputPath, '/tmp/hello.txt');
        expect(download.attachment.fileName, 'hello.txt');
        await expectLater(
          client.attachments.transferEvents(download.transferId),
          emits(
            isA<ImAttachmentTransferEventDto>().having(
              (event) => event.state,
              'state',
              'completed',
            ),
          ),
        );

        final failed = await client.messages.send(
          const ImSendMessageRequest(
            target: ImSendTarget(peerDidOrHandle: 'did:wba:example:bob:e1_bob'),
            text: 'force failure',
            metadata: <String, Object?>{'forceFail': true},
          ),
        );
        expect(failed.accepted, isFalse);
        expect(failed.message.sendState, ImSendState.failed);
        expect(failed.message.errorCode, ImErrorCode.transportUnavailable.name);

        final failedOutbox = await client.outbox.list(
          const ImListOutboxRequest(failedOnly: true),
        );
        expect(failedOutbox.items, hasLength(1));
        final retry = await client.outbox.retry(
          failedOutbox.items.single.outboxId,
        );
        expect(retry.accepted, isTrue);
        expect(
          (await client.outbox.list(const ImListOutboxRequest())).items,
          isEmpty,
        );

        await client.messages.sync(
          ImSyncRequest(threadId: attachmentResult.message.thread.threadId),
        );
        await pumpEventQueue();
        expect(
          events.map((event) => event.kind),
          contains(ImEventKind.syncCompleted),
        );

        final stats = await client.localStore.stats();
        expect(stats.messageCount, 3);
        expect(stats.conversationCount, 1);
        expect(stats.outboxCount, 0);
        expect(stats.storePath, 'memory://fake-im-core');

        await client.localStore.clear(const ImClearStoreRequest());
        final cleared = await client.localStore.stats();
        expect(cleared.messageCount, 0);
        expect(cleared.conversationCount, 0);
        expect(cleared.groupCount, 0);
        expect(cleared.outboxCount, 0);
        await client.localStore.compact();
      },
    );
  });
}

Future<void> _initializeAlice(FakeAwikiImClient client) async {
  await client.initialize(const ImClientConfig(workspaceId: 'fake-workspace'));
  await client.setSession(
    const ImSessionContext(
      credentialName: 'alice',
      did: 'did:wba:example:alice:e1_alice',
      handle: 'alice.example',
      displayName: 'Alice',
    ),
  );
}
