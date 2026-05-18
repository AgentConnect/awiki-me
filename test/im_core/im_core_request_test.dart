import 'package:awiki_me/src/im_core/awiki_im_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IM Core request and result freeze', () {
    test('send targets and message requests preserve direct/group intent', () {
      const directTarget = ImSendTarget(
        peerDidOrHandle: 'did:wba:example:bob:e1_bob',
      );
      const groupTarget = ImSendTarget(groupId: 'group-1');
      const directRequest = ImSendMessageRequest(
        target: directTarget,
        text: 'hello',
        messageType: 'text',
        securityMode: ImSecurityMode.transportProtected,
        clientOperationId: 'op-1',
        metadata: <String, Object?>{'source': 'test'},
      );
      const attachmentRequest = ImSendMessageRequest(
        target: groupTarget,
        attachments: <ImAttachmentInput>[
          ImAttachmentInput(
            fileName: 'hello.txt',
            mimeType: 'text/plain',
            bytes: <int>[104, 105],
            caption: 'hello',
          ),
        ],
      );

      expect(
        directRequest.target.peerDidOrHandle,
        'did:wba:example:bob:e1_bob',
      );
      expect(directRequest.target.groupId, isNull);
      expect(directRequest.text, 'hello');
      expect(directRequest.messageType, 'text');
      expect(directRequest.securityMode, ImSecurityMode.transportProtected);
      expect(directRequest.clientOperationId, 'op-1');
      expect(directRequest.metadata['source'], 'test');
      expect(attachmentRequest.target.groupId, 'group-1');
      expect(attachmentRequest.attachments.single.fileName, 'hello.txt');
      expect(attachmentRequest.attachments.single.bytes, <int>[104, 105]);
    });

    test(
      'list, mark-read, sync, attachment, and outbox requests preserve fields',
      () {
        const thread = ImThreadRef(
          threadId: 'group:group-1',
          kind: ImThreadKind.group,
          groupId: 'group-1',
        );
        const listMessages = ImListMessagesRequest(
          thread: thread,
          limit: 20,
          cursor: '10',
          sinceSequence: 7,
          includeLocalPending: false,
        );
        const markRead = ImMarkReadRequest(
          messageIds: <String>['local-1', 'remote-1'],
          threadId: 'group:group-1',
        );
        const sync = ImSyncRequest(
          scope: ImThreadKind.group,
          threadId: 'group:group-1',
          limit: 25,
          pullRemote: true,
          processRealtimeBacklog: false,
        );
        const download = ImAttachmentDownloadRequest(
          thread: thread,
          messageId: 'remote-1',
          attachmentId: 'attachment-1',
          outputPath: '/tmp/attachment.bin',
        );
        const outbox = ImListOutboxRequest(
          limit: 10,
          cursor: '5',
          failedOnly: true,
        );

        expect(listMessages.thread, same(thread));
        expect(listMessages.limit, 20);
        expect(listMessages.cursor, '10');
        expect(listMessages.sinceSequence, 7);
        expect(listMessages.includeLocalPending, isFalse);
        expect(markRead.messageIds, <String>['local-1', 'remote-1']);
        expect(markRead.threadId, 'group:group-1');
        expect(sync.scope, ImThreadKind.group);
        expect(sync.threadId, 'group:group-1');
        expect(sync.limit, 25);
        expect(sync.pullRemote, isTrue);
        expect(sync.processRealtimeBacklog, isFalse);
        expect(download.attachmentId, 'attachment-1');
        expect(download.outputPath, '/tmp/attachment.bin');
        expect(outbox.failedOnly, isTrue);
      },
    );

    test('group mutation requests preserve required fields', () {
      const create = ImCreateGroupRequest(
        name: 'SDK Group',
        description: 'Phase 1',
        slug: 'sdk-group',
        goal: 'freeze API',
        rules: 'be kind',
        messagePrompt: 'discuss',
        metadata: <String, Object?>{'fixture': true},
      );
      const join = ImJoinGroupRequest(groupId: 'group-1', reason: 'test');
      const mutate = ImGroupMemberMutationRequest(
        groupId: 'group-1',
        memberDidOrHandle: 'did:wba:example:bob:e1_bob',
        role: 'moderator',
        reason: 'promote',
      );
      const leave = ImLeaveGroupRequest(groupId: 'group-1', reason: 'done');
      const update = ImUpdateGroupRequest(
        groupId: 'group-1',
        name: 'Updated Group',
        description: 'Updated',
        docUrl: 'https://example.test/doc',
        metadata: <String, Object?>{'updated': true},
      );
      const members = ImListGroupMembersRequest(groupId: 'group-1', limit: 30);
      const messages = ImListGroupMessagesRequest(
        groupId: 'group-1',
        limit: 40,
        cursor: '20',
      );

      expect(create.name, 'SDK Group');
      expect(create.description, 'Phase 1');
      expect(create.metadata['fixture'], isTrue);
      expect(join.groupId, 'group-1');
      expect(mutate.memberDidOrHandle, 'did:wba:example:bob:e1_bob');
      expect(mutate.role, 'moderator');
      expect(leave.reason, 'done');
      expect(update.docUrl, 'https://example.test/doc');
      expect(update.metadata['updated'], isTrue);
      expect(members.limit, 30);
      expect(messages.cursor, '20');
    });
  });
}
