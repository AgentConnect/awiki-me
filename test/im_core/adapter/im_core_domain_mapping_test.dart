import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/group_summary.dart';
import 'package:awiki_me/src/domain/entities/realtime_update.dart';
import 'package:awiki_me/src/im_core/awiki_im_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('test-only IM Core to domain mapping fixtures', () {
    test(
      'message, conversation, group, and member DTOs map into domain models',
      () {
        final now = DateTime.utc(2026, 5, 15, 12);
        const aliceDid = 'did:wba:example:alice:e1_alice';
        const bobDid = 'did:wba:example:bob:e1_bob';
        final thread = ImThreadRef(
          threadId: _directThreadId(aliceDid, bobDid),
          kind: ImThreadKind.direct,
          peerDid: bobDid,
        );
        final message = ImMessageDto(
          localId: 'local-1',
          remoteId: 'remote-1',
          thread: thread,
          direction: ImMessageDirection.outbound,
          kind: ImMessageKind.text,
          securityMode: ImSecurityMode.transportProtected,
          sendState: ImSendState.sent,
          readState: ImReadState.read,
          senderDid: aliceDid,
          senderDisplayName: 'Alice',
          receiverDid: bobDid,
          plaintextText: 'hello',
          createdAt: now,
          serverSequence: 7,
        );
        final conversation = ImConversationDto(
          thread: thread,
          displayName: 'Bob',
          lastMessagePreview: 'hello',
          lastMessageAt: now,
          unreadCount: 2,
          securityMode: ImSecurityMode.transportProtected,
          avatarSeed: bobDid,
        );
        const policy = ImGroupPolicyDto(
          discoverability: 'private',
          admissionMode: 'open-join',
          messageSecurityProfile: ImSecurityMode.transportProtected,
        );
        final group = ImGroupDto(
          groupId: 'group-1',
          name: 'SDK Group',
          description: 'Phase 1',
          policy: policy,
          myRole: 'owner',
          memberCount: 2,
          lastMessageAt: now,
        );
        const member = ImGroupMemberDto(
          userId: 'user-2',
          did: bobDid,
          handle: 'bob.example',
          role: 'member',
          status: 'active',
          profileUrl: 'https://example.test/bob',
        );

        final domainMessage = _toChatMessage(message, ownerDid: aliceDid);
        final domainConversation = _toConversationSummary(conversation);
        final domainGroup = _toGroupSummary(group);
        final domainMember = _toGroupMemberSummary(member);

        expect(domainMessage.localId, 'local-1');
        expect(domainMessage.remoteId, 'remote-1');
        expect(domainMessage.threadId, thread.threadId);
        expect(domainMessage.senderDid, aliceDid);
        expect(domainMessage.senderName, 'Alice');
        expect(domainMessage.receiverDid, bobDid);
        expect(domainMessage.content, 'hello');
        expect(domainMessage.createdAt, now);
        expect(domainMessage.isMine, isTrue);
        expect(domainMessage.sendState, MessageSendState.sent);
        expect(domainMessage.serverSequence, 7);
        expect(domainMessage.isEncrypted, isFalse);
        expect(domainMessage.originalType, 'text');

        expect(domainConversation.threadId, thread.threadId);
        expect(domainConversation.displayName, 'Bob');
        expect(domainConversation.lastMessagePreview, 'hello');
        expect(domainConversation.lastMessageAt, now);
        expect(domainConversation.unreadCount, 2);
        expect(domainConversation.isGroup, isFalse);
        expect(domainConversation.targetDid, bobDid);
        expect(domainConversation.groupId, isNull);
        expect(domainConversation.avatarSeed, bobDid);

        expect(domainGroup.groupId, 'group-1');
        expect(domainGroup.name, 'SDK Group');
        expect(domainGroup.description, 'Phase 1');
        expect(domainGroup.memberCount, 2);
        expect(domainGroup.lastMessageAt, now);
        expect(domainGroup.myRole, 'owner');

        expect(domainMember.userId, 'user-2');
        expect(domainMember.did, bobDid);
        expect(domainMember.handle, 'bob.example');
        expect(domainMember.role, 'member');
        expect(domainMember.profileUrl, 'https://example.test/bob');
      },
    );

    test(
      'event DTOs can map to RealtimeUpdate without production providers',
      () {
        final now = DateTime.utc(2026, 5, 15, 12, 30);
        const aliceDid = 'did:wba:example:alice:e1_alice';
        const bobDid = 'did:wba:example:bob:e1_bob';
        final thread = ImThreadRef(
          threadId: _directThreadId(aliceDid, bobDid),
          kind: ImThreadKind.direct,
          peerDid: bobDid,
        );
        final message = ImMessageDto(
          localId: 'local-2',
          remoteId: 'remote-2',
          thread: thread,
          direction: ImMessageDirection.inbound,
          kind: ImMessageKind.text,
          securityMode: ImSecurityMode.transportProtected,
          sendState: ImSendState.delivered,
          readState: ImReadState.unread,
          senderDid: bobDid,
          receiverDid: aliceDid,
          plaintextText: 'hello alice',
          createdAt: now,
        );
        final conversation = ImConversationDto(
          thread: thread,
          displayName: 'Bob',
          lastMessagePreview: 'hello alice',
          lastMessageAt: now,
          unreadCount: 1,
          securityMode: ImSecurityMode.transportProtected,
        );
        final event = ImEventDto(
          eventId: 'event-1',
          kind: ImEventKind.messageReceived,
          occurredAt: now,
          message: message,
          conversation: conversation,
        );

        final update = _toRealtimeUpdate(event, ownerDid: aliceDid);

        expect(update.message.isMine, isFalse);
        expect(update.message.senderDid, bobDid);
        expect(update.conversation.unreadCount, 1);
        expect(update.group, isNull);
      },
    );

    test(
      'thread IDs and row identities remain compatible with current conventions',
      () {
        const aliceDid = 'did:wba:example:alice:e1_alice';
        const bobDid = 'did:wba:example:bob:e1_bob';
        final directThread = ImThreadRef(
          threadId: _directThreadId(bobDid, aliceDid),
          kind: ImThreadKind.direct,
          peerDid: bobDid,
        );
        const groupThread = ImThreadRef(
          threadId: 'group:group-1',
          kind: ImThreadKind.group,
          groupId: 'group-1',
        );
        final now = DateTime.utc(2026, 5, 15, 13);
        final duplicateA = _messageFixture(
          localId: 'local-a',
          remoteId: 'remote-shared',
          operationId: 'op-1',
          thread: directThread,
          now: now,
        );
        final duplicateB = _messageFixture(
          localId: 'local-b',
          remoteId: 'remote-shared',
          operationId: 'op-2',
          thread: directThread,
          now: now,
        );
        final pending = _messageFixture(
          localId: 'local-pending',
          remoteId: null,
          operationId: 'op-pending',
          sendState: ImSendState.sending,
          thread: directThread,
          now: now,
        );
        final accepted = _messageFixture(
          localId: 'local-pending',
          remoteId: 'remote-accepted',
          operationId: 'op-pending',
          sendState: ImSendState.sent,
          thread: directThread,
          now: now,
        );

        expect(directThread.threadId, 'dm:$aliceDid:$bobDid');
        expect(groupThread.threadId, 'group:group-1');
        expect(_remoteRowIdentity(duplicateA), _remoteRowIdentity(duplicateB));
        expect(_canReplacePending(pending, accepted), isTrue);
      },
    );
  });
}

ChatMessage _toChatMessage(ImMessageDto message, {required String ownerDid}) {
  return ChatMessage(
    localId: message.localId,
    remoteId: message.remoteId,
    threadId: message.thread.threadId,
    senderDid: message.senderDid,
    senderName: message.senderDisplayName ?? message.senderHandle,
    receiverDid: message.receiverDid,
    groupId: message.groupId,
    content: message.plaintextText ?? message.content['text']?.toString() ?? '',
    originalType: message.kind.name,
    createdAt: message.createdAt,
    isMine:
        message.direction == ImMessageDirection.outbound ||
        message.senderDid == ownerDid,
    serverSequence: message.serverSequence,
    isEncrypted: message.securityMode != ImSecurityMode.transportProtected,
    sendState: _toDomainSendState(message.sendState),
  );
}

ConversationSummary _toConversationSummary(ImConversationDto conversation) {
  return ConversationSummary(
    threadId: conversation.thread.threadId,
    displayName: conversation.displayName,
    lastMessagePreview: conversation.lastMessagePreview,
    lastMessageAt: conversation.lastMessageAt,
    unreadCount: conversation.unreadCount,
    isGroup: conversation.thread.kind == ImThreadKind.group,
    targetDid: conversation.thread.peerDid,
    groupId: conversation.thread.groupId,
    avatarSeed: conversation.avatarSeed,
  );
}

GroupSummary _toGroupSummary(ImGroupDto group) {
  return GroupSummary(
    groupId: group.groupId,
    name: group.name,
    description: group.description,
    memberCount: group.memberCount,
    lastMessageAt: group.lastMessageAt,
    myRole: group.myRole,
  );
}

GroupMemberSummary _toGroupMemberSummary(ImGroupMemberDto member) {
  return GroupMemberSummary(
    userId: member.userId ?? member.did,
    did: member.did,
    handle: member.handle ?? member.did,
    role: member.role,
    profileUrl: member.profileUrl,
  );
}

RealtimeUpdate _toRealtimeUpdate(ImEventDto event, {required String ownerDid}) {
  final message = event.message;
  final conversation = event.conversation;
  if (message == null || conversation == null) {
    throw StateError(
      'RealtimeUpdate mapping requires message and conversation payloads.',
    );
  }
  return RealtimeUpdate(
    message: _toChatMessage(message, ownerDid: ownerDid),
    conversation: _toConversationSummary(conversation),
    group: event.group == null ? null : _toGroupSummary(event.group!),
  );
}

MessageSendState _toDomainSendState(ImSendState state) {
  return switch (state) {
    ImSendState.failed => MessageSendState.failed,
    ImSendState.sent || ImSendState.delivered => MessageSendState.sent,
    ImSendState.draft ||
    ImSendState.queued ||
    ImSendState.sending => MessageSendState.sending,
  };
}

String _directThreadId(String leftDid, String rightDid) {
  final parts = <String>[leftDid, rightDid]..sort();
  return 'dm:${parts[0]}:${parts[1]}';
}

String _remoteRowIdentity(ImMessageDto message) =>
    message.remoteId ?? message.localId;

bool _canReplacePending(ImMessageDto pending, ImMessageDto accepted) {
  return pending.operationId != null &&
      pending.operationId == accepted.operationId &&
      pending.thread.threadId == accepted.thread.threadId;
}

ImMessageDto _messageFixture({
  required String localId,
  required String? remoteId,
  required String operationId,
  required ImThreadRef thread,
  required DateTime now,
  ImSendState sendState = ImSendState.sent,
}) {
  return ImMessageDto(
    localId: localId,
    remoteId: remoteId,
    thread: thread,
    direction: ImMessageDirection.outbound,
    kind: ImMessageKind.text,
    securityMode: ImSecurityMode.transportProtected,
    sendState: sendState,
    readState: ImReadState.read,
    senderDid: 'did:wba:example:alice:e1_alice',
    receiverDid: thread.peerDid,
    plaintextText: 'fixture',
    createdAt: now,
    operationId: operationId,
  );
}
