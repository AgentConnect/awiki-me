import 'package:awiki_me/src/im_core/awiki_im_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IM Core DTO freeze', () {
    test('common enums keep the Phase 1 frozen values', () {
      expect(ImThreadKind.values.map((value) => value.name), <String>[
        'direct',
        'group',
      ]);
      expect(ImMessageDirection.values.map((value) => value.name), <String>[
        'inbound',
        'outbound',
        'system',
      ]);
      expect(ImMessageKind.values.map((value) => value.name), <String>[
        'text',
        'attachment',
        'system',
        'directCipher',
        'directInit',
        'groupCipher',
        'unknown',
      ]);
      expect(ImSendState.values.map((value) => value.name), <String>[
        'draft',
        'queued',
        'sending',
        'sent',
        'delivered',
        'failed',
      ]);
      expect(ImReadState.values.map((value) => value.name), <String>[
        'unread',
        'read',
      ]);
      expect(ImSecurityMode.values.map((value) => value.name), <String>[
        'transportProtected',
        'directE2ee',
        'groupE2ee',
      ]);
      expect(ImConnectionState.values.map((value) => value.name), <String>[
        'idle',
        'connecting',
        'connected',
        'reconnecting',
        'disconnected',
        'failed',
      ]);
      expect(ImRuntimeMode.values.map((value) => value.name), <String>[
        'fake',
        'http',
        'websocket',
      ]);
      expect(ImEventKind.values.map((value) => value.name), <String>[
        'messageReceived',
        'messageUpdated',
        'conversationUpdated',
        'groupUpdated',
        'outboxUpdated',
        'connectionChanged',
        'syncCompleted',
        'warning',
        'error',
      ]);
    });

    test(
      'page, thread, attachment, message, and conversation preserve fields',
      () {
        final createdAt = DateTime.utc(2026, 5, 15, 10, 30);
        final acceptedAt = DateTime.utc(2026, 5, 15, 10, 31);
        const peer = ImPeerRef(
          did: 'did:wba:example:bob:e1_bob',
          handle: 'bob.example',
          displayName: 'Bob',
        );
        const thread = ImThreadRef(
          threadId:
              'dm:did:wba:example:alice:e1_alice:did:wba:example:bob:e1_bob',
          kind: ImThreadKind.direct,
          peerDid: 'did:wba:example:bob:e1_bob',
          peerHandle: 'bob.example',
        );
        final attachment = ImAttachmentDto(
          attachmentId: 'att-1',
          fileName: 'hello.txt',
          mimeType: 'text/plain',
          sizeBytes: 12,
          localPath: '/tmp/hello.txt',
          downloadUrl: Uri.parse('https://example.test/hello.txt'),
          objectId: 'obj-1',
          sha256: 'abc123',
          metadata: const <String, Object?>{'caption': 'hello'},
        );
        final message = ImMessageDto(
          localId: 'local-1',
          remoteId: 'remote-1',
          thread: thread,
          direction: ImMessageDirection.outbound,
          kind: ImMessageKind.attachment,
          securityMode: ImSecurityMode.transportProtected,
          sendState: ImSendState.sent,
          readState: ImReadState.read,
          senderDid: 'did:wba:example:alice:e1_alice',
          senderHandle: 'alice.example',
          senderDisplayName: 'Alice',
          receiverDid: 'did:wba:example:bob:e1_bob',
          plaintextText: 'hello',
          content: const <String, Object?>{'text': 'hello'},
          attachments: <ImAttachmentDto>[attachment],
          createdAt: createdAt,
          acceptedAt: acceptedAt,
          serverSequence: 42,
          operationId: 'op-1',
          errorCode: 'none',
          retryHint: 'never',
          metadata: const <String, Object?>{'source': 'test'},
        );
        final conversation = ImConversationDto(
          thread: thread,
          displayName: 'Bob',
          lastMessagePreview: 'hello',
          lastMessageAt: acceptedAt,
          unreadCount: 3,
          securityMode: ImSecurityMode.transportProtected,
          avatarSeed: 'bob',
          metadata: const <String, Object?>{'pinned': true},
        );
        final page = ImPage<ImMessageDto>(
          items: <ImMessageDto>[message],
          nextCursor: '1',
          hasMore: true,
        );

        expect(peer.did, 'did:wba:example:bob:e1_bob');
        expect(peer.handle, 'bob.example');
        expect(peer.displayName, 'Bob');
        expect(page.items.single, same(message));
        expect(page.nextCursor, '1');
        expect(page.hasMore, isTrue);
        expect(message.localId, 'local-1');
        expect(message.remoteId, 'remote-1');
        expect(message.thread, same(thread));
        expect(message.kind, ImMessageKind.attachment);
        expect(message.securityMode, ImSecurityMode.transportProtected);
        expect(message.sendState, ImSendState.sent);
        expect(message.readState, ImReadState.read);
        expect(message.senderDid, 'did:wba:example:alice:e1_alice');
        expect(message.senderHandle, 'alice.example');
        expect(message.senderDisplayName, 'Alice');
        expect(message.receiverDid, 'did:wba:example:bob:e1_bob');
        expect(message.groupId, isNull);
        expect(message.plaintextText, 'hello');
        expect(message.content['text'], 'hello');
        expect(message.attachments.single.fileName, 'hello.txt');
        expect(message.createdAt, createdAt);
        expect(message.acceptedAt, acceptedAt);
        expect(message.serverSequence, 42);
        expect(message.operationId, 'op-1');
        expect(message.errorCode, 'none');
        expect(message.retryHint, 'never');
        expect(message.metadata['source'], 'test');
        expect(conversation.thread, same(thread));
        expect(conversation.displayName, 'Bob');
        expect(conversation.lastMessagePreview, 'hello');
        expect(conversation.lastMessageAt, acceptedAt);
        expect(conversation.unreadCount, 3);
        expect(conversation.avatarSeed, 'bob');
      },
    );

    test(
      'group, policy, member, status, capabilities, and events preserve fields',
      () {
        final now = DateTime.utc(2026, 5, 15, 11);
        const policy = ImGroupPolicyDto(
          discoverability: 'private',
          admissionMode: 'open-join',
          messageSecurityProfile: ImSecurityMode.transportProtected,
          attachmentsAllowed: true,
          maxMembers: 100,
          memberMaxMessages: 10,
          memberMaxTotalChars: 2000,
        );
        const member = ImGroupMemberDto(
          userId: 'user-1',
          did: 'did:wba:example:alice:e1_alice',
          handle: 'alice.example',
          role: 'owner',
          status: 'active',
          profileUrl: 'https://example.test/alice',
        );
        final group = ImGroupDto(
          groupId: 'group-1',
          groupDid: 'did:wba:example:group:e1_group',
          name: 'Core Group',
          description: 'Phase 1',
          slug: 'core-group',
          goal: 'freeze api',
          rules: 'be kind',
          messagePrompt: 'discuss',
          docUrl: 'https://example.test/doc',
          policy: policy,
          myRole: 'owner',
          membershipStatus: 'active',
          memberCount: 1,
          lastMessageAt: now,
          metadata: const <String, Object?>{'fixture': true},
        );
        const error = ImErrorDto(
          code: ImErrorCode.transportUnavailable,
          message: 'offline',
          hint: 'retry',
          retryable: true,
          details: <String, Object?>{'scope': 'test'},
        );
        const warning = ImWarningDto(
          code: 'cache-stale',
          message: 'cache is stale',
          hint: 'sync',
          details: <String, Object?>{'age': 10},
        );
        final connection = ImConnectionStateDto(
          state: ImConnectionState.connected,
          runtimeMode: ImRuntimeMode.fake,
          changedAt: now,
          lastErrorCode: 'none',
          lastErrorMessage: 'none',
        );
        const status = ImEngineStatusDto(
          initialized: true,
          hasSession: true,
          runtimeMode: ImRuntimeMode.fake,
          connectionState: ImConnectionState.connected,
          storePath: 'memory://fake-im-core',
          schemaVersion: 1,
          lastError: error,
          metadata: <String, Object?>{'fake': true},
        );
        const capabilities = ImCapabilitiesDto(
          runtimeMode: ImRuntimeMode.fake,
          localCache: true,
          outbox: true,
          realtime: true,
          attachments: true,
          advancedAttachments: false,
          directSecure: false,
          groupE2ee: false,
          migration: false,
          metadata: <String, Object?>{'reserved': true},
        );
        final warningEvent = ImEventDto(
          eventId: 'event-warning',
          kind: ImEventKind.warning,
          occurredAt: now,
          group: group,
          connectionState: connection,
          warning: warning,
          metadata: const <String, Object?>{'origin': 'test'},
        );
        final errorEvent = ImEventDto(
          eventId: 'event-error',
          kind: ImEventKind.error,
          occurredAt: now,
          error: error,
        );

        expect(group.policy, same(policy));
        expect(group.memberCount, 1);
        expect(member.profileUrl, 'https://example.test/alice');
        expect(status.lastError, same(error));
        expect(status.metadata['fake'], isTrue);
        expect(capabilities.advancedAttachments, isFalse);
        expect(capabilities.directSecure, isFalse);
        expect(capabilities.groupE2ee, isFalse);
        expect(capabilities.migration, isFalse);
        expect(warningEvent.kind, ImEventKind.warning);
        expect(warningEvent.warning, same(warning));
        expect(warningEvent.error, isNull);
        expect(errorEvent.kind, ImEventKind.error);
        expect(errorEvent.error, same(error));
      },
    );
  });
}
