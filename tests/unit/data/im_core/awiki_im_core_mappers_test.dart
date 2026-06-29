import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_mappers.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AwikiImCoreMappers();

  test('identity maps to app session and preserves JWT for legacy session', () {
    const identity = core.IdentitySummary(
      id: 'id-1',
      did: 'did:wba:awiki.ai:alice:e1_1234567890',
      handle: 'alice.awiki',
      displayName: 'Alice',
      localAlias: 'alice-local',
      isDefault: true,
      readyForAuth: true,
      readyForMessaging: true,
    );

    final session = mapper.appSessionFromIdentity(
      identity,
      authenticated: true,
      jwtToken: 'jwt-123',
    );
    final legacy = mapper.legacySessionFromAppSession(session);

    expect(session.identityId, 'id-1');
    expect(session.displayName, 'Alice');
    expect(session.authenticated, isTrue);
    expect(session.jwtToken, 'jwt-123');
    expect(legacy.credentialName, 'alice-local');
    expect(legacy.jwtToken, 'jwt-123');
  });

  test(
    'identity display name falls back through handle, alias, compact DID',
    () {
      const withHandle = core.IdentitySummary(
        id: 'id-handle',
        did: 'did:wba:awiki.ai:user:alice:e1_1234567890',
        handle: 'alice.awiki.ai',
        isDefault: false,
        readyForAuth: true,
        readyForMessaging: true,
      );
      const withAlias = core.IdentitySummary(
        id: 'id-alias',
        did: 'did:wba:awiki.ai:user:bob:e1_1234567890',
        localAlias: 'bob-local',
        isDefault: false,
        readyForAuth: true,
        readyForMessaging: true,
      );
      const withDidOnly = core.IdentitySummary(
        id: 'id-did',
        did: 'did:wba:awiki.ai:user:carol:e1_1234567890',
        isDefault: false,
        readyForAuth: true,
        readyForMessaging: true,
      );

      expect(
        mapper.appSessionFromIdentity(withHandle).displayName,
        'alice.awiki.ai',
      );
      expect(mapper.appSessionFromIdentity(withAlias).displayName, 'bob-local');
      expect(
        mapper.appSessionFromIdentity(withDidOnly).displayName,
        'did:wba:aw…567890',
      );
    },
  );

  test('daemon subkey package maps to bootstrap user subkey package', () {
    const package = core.DaemonSubkeyPrivatePackage(
      schema: 'awiki.daemon.user_subkey_package.v2',
      userDid: 'did:human:me',
      verificationMethod: 'did:human:me#daemon-key-1',
      keyType: 'Multikey/Ed25519',
      keyAlgorithm: 'Ed25519',
      publicKeyMultibase: 'zPublic',
      privateKeyEncoding: 'pem',
      privateKeyPem: 'pemPrivate',
      privateKeyMultibase: 'pemPrivate',
    );

    final mapped = mapper.userSubkeyPackageFromCore(package);

    expect(mapped.userDid, 'did:human:me');
    expect(mapped.verificationMethod, 'did:human:me#daemon-key-1');
    expect(mapped.keyType, 'Multikey/Ed25519');
    expect(mapped.publicKeyMultibase, 'zPublic');
    expect(mapped.privateKeyPem, 'pemPrivate');
  });

  test('thread refs map to SDK thread refs and message targets', () {
    expect(
      mapper.threadRefToCore(const AppThreadRef.direct('did:peer')),
      isA<core.DirectThreadRef>(),
    );
    expect(
      mapper.messageTargetToCore(const AppThreadRef.group('did:group')),
      isA<core.GroupMessageTarget>(),
    );
    expect(
      () => mapper.messageTargetToCore(const AppThreadRef.thread('thread-1')),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('message maps SDK DTO into app ChatMessage', () {
    const message = core.Message(
      id: 'msg-1',
      threadKind: 'direct',
      threadId: 'did:bob',
      direction: core.MessageDirection.outgoing,
      sender: 'did:alice',
      receiver: 'did:bob',
      body: core.MessageBodyView(text: 'hello', kind: 'text'),
      sentAt: '2026-05-23T09:00:00Z',
      metadata: core.MessageMetadata(deliveryState: 'sent', serverSequence: 42),
    );

    final mapped = mapper.chatMessageFromCore(message, ownerDid: 'did:alice');

    expect(mapped.localId, 'msg-1');
    expect(mapped.threadId, 'dm:did:alice:did:bob');
    expect(mapped.content, 'hello');
    expect(mapped.isMine, isTrue);
    expect(mapped.sendState, MessageSendState.sent);
    expect(mapped.serverSequence, 42);
  });

  test('scoped direct message keeps stable thread id and peer metadata', () {
    const message = core.Message(
      id: 'msg-scoped',
      threadKind: 'thread',
      threadId: 'dm:peer-scope:v1:abc123',
      direction: core.MessageDirection.incoming,
      sender: 'did:bob:new',
      receiver: 'did:alice',
      body: core.MessageBodyView(text: 'hello', kind: 'text'),
      sentAt: '2026-05-23T09:00:00Z',
      metadata: core.MessageMetadata(
        attributes: <core.MessageMetadataAttribute>[
          core.MessageMetadataAttribute(key: 'peer_user_id', value: 'user-bob'),
          core.MessageMetadataAttribute(
            key: 'peer_full_handle',
            value: 'Bob.AnPClaw.com',
          ),
          core.MessageMetadataAttribute(
            key: 'peer_current_did',
            value: 'did:bob:new',
          ),
        ],
      ),
    );

    final mapped = mapper.chatMessageFromCore(message, ownerDid: 'did:alice');
    final conversation = mapper.conversationFromCore(
      const core.Conversation(
        threadKind: 'thread',
        threadId: 'dm:peer-scope:v1:abc123',
        participants: <String>['bob.anpclaw.com'],
        unreadCount: 1,
        unreadMentionCount: 1,
        firstUnreadMentionMessageId: 'msg-mention-1',
        messageCount: 1,
        lastMessage: message,
      ),
      ownerDid: 'did:alice',
    );

    expect(mapped.threadId, 'dm:peer-scope:v1:abc123');
    expect(conversation.threadId, 'dm:peer-scope:v1:abc123');
    expect(conversation.targetPeer, 'bob.anpclaw.com');
    expect(conversation.targetDid, 'did:bob:new');
    expect(conversation.displayName, 'bob.anpclaw.com');
    expect(conversation.unreadMentionCount, 1);
    expect(conversation.firstUnreadMentionMessageId, 'msg-mention-1');
    expect(conversation.hasUnreadMention, isTrue);
  });

  test('control payload maps into non-renderable chat message', () {
    const payload =
        '{"schema":"awiki.agent.status.v1","status_scope":"daemon","daemon":{"status":"ready"}}';
    const message = core.Message(
      id: 'msg-control',
      threadKind: 'direct',
      threadId: 'did:daemon',
      direction: core.MessageDirection.incoming,
      sender: 'did:daemon',
      receiver: 'did:alice',
      body: core.MessageBodyView(payloadJson: payload, kind: 'payload'),
      sentAt: '2026-05-23T09:00:00Z',
      metadata: core.MessageMetadata(),
    );

    final mapped = mapper.chatMessageFromCore(message, ownerDid: 'did:alice');

    expect(mapped.payloadJson, payload);
    expect(mapped.isAgentControlPayload, isTrue);
    expect(mapped.hasRenderableContent, isFalse);
  });

  test('attachment manifest message maps into attachment chat message', () {
    const manifest =
        '{"attachments":[{"attachment_id":"att-1","filename":"report.pdf","mime_type":"application/pdf","size":"1024","access_info":{"object_uri":"https://objects.example/att-1"}}],"primary_attachment_id":"att-1","caption":"季度报告"}';
    const message = core.Message(
      id: 'msg-attachment',
      threadKind: 'direct',
      threadId: 'did:bob',
      direction: core.MessageDirection.incoming,
      sender: 'did:bob',
      receiver: 'did:alice',
      body: core.MessageBodyView(
        unsupportedContentType: 'application/anp-attachment-manifest+json',
      ),
      sentAt: '2026-05-23T09:00:00Z',
      metadata: core.MessageMetadata(
        contentType: 'application/anp-attachment-manifest+json',
        attributes: <core.MessageMetadataAttribute>[
          core.MessageMetadataAttribute(
            key: 'attachment_manifest',
            value: manifest,
          ),
        ],
      ),
    );

    final mapped = mapper.chatMessageFromCore(message, ownerDid: 'did:alice');

    expect(mapped.hasRenderableContent, isTrue);
    expect(mapped.hasDisplayableText, isFalse);
    expect(mapped.attachment?.attachmentId, 'att-1');
    expect(mapped.attachment?.filename, 'report.pdf');
    expect(mapped.attachment?.mimeType, 'application/pdf');
    expect(mapped.attachment?.sizeBytes, 1024);
    expect(mapped.attachment?.caption, '季度报告');
    expect(mapped.attachment?.objectUri, 'https://objects.example/att-1');
    expect(mapped.previewText, '季度报告');
  });

  test('attachment manifest mention payload maps into structured mentions', () {
    const manifest =
        '{"attachments":[{"attachment_id":"att-1","filename":"report.md","mime_type":"text/markdown","size":"1024"}],"primary_attachment_id":"att-1","caption":"@codex 看看这个文件","mention_payload":{"text":"@codex 看看这个文件","mentions":[{"id":"men_codex","range":{"start":0,"end":6,"unit":"unicode_code_point"},"target":{"kind":"agent","did":"did:agent:codex"},"mention_role":"addressee"}]}}';
    const message = core.Message(
      id: 'msg-attachment-mention',
      threadKind: 'group',
      threadId: 'group:did:test:group',
      direction: core.MessageDirection.outgoing,
      sender: 'did:alice',
      group: 'did:test:group',
      body: core.MessageBodyView(
        payloadJson: manifest,
        unsupportedContentType: 'application/anp-attachment-manifest+json',
      ),
      sentAt: '2026-05-23T09:00:00Z',
      metadata: core.MessageMetadata(
        contentType: 'application/anp-attachment-manifest+json',
      ),
    );

    final mapped = mapper.chatMessageFromCore(message, ownerDid: 'did:alice');

    expect(mapped.hasRenderableContent, isTrue);
    expect(mapped.originalType, 'application/anp-attachment-manifest+json');
    expect(mapped.attachment?.filename, 'report.md');
    expect(mapped.attachment?.caption, '@codex 看看这个文件');
    expect(mapped.content, '@codex 看看这个文件');
    expect(mapped.payloadJson, isNot(manifest));
    expect(
      ChatMentionPayload.tryParsePayloadJson(mapped.payloadJson)?.text,
      '@codex 看看这个文件',
    );
    expect(mapped.mentions, hasLength(1));
    expect(mapped.mentions.single.surface, '@codex');
    expect(mapped.mentions.single.target.kind, ChatMentionTargetKind.agent);
    expect(mapped.mentions.single.target.did, 'did:agent:codex');
  });

  test(
    'local history attachment manifest payload maps into attachment chat message',
    () {
      const manifest =
          '{"attachments":[{"attachment_id":"att-local","filename":"local.md","mime_type":"text/markdown","size":"24","access_info":{"object_uri":"https://objects.example/att-local"}}],"caption":"本地历史附件","primary_attachment_id":"att-local"}';
      const message = core.Message(
        id: 'msg-local-attachment',
        threadKind: 'group',
        threadId: 'group:did:test:group',
        direction: core.MessageDirection.incoming,
        sender: 'did:bob',
        group: 'did:test:group',
        body: core.MessageBodyView(payloadJson: manifest, kind: 'payload'),
        sentAt: '2026-05-23T09:00:00Z',
        metadata: core.MessageMetadata(
          contentType: 'application/anp-attachment-manifest+json',
        ),
      );

      final mapped = mapper.chatMessageFromCore(message, ownerDid: 'did:alice');

      expect(mapped.hasRenderableContent, isTrue);
      expect(mapped.originalType, 'application/anp-attachment-manifest+json');
      expect(mapped.content, '本地历史附件');
      expect(mapped.attachment?.attachmentId, 'att-local');
      expect(mapped.attachment?.filename, 'local.md');
      expect(mapped.attachment?.mimeType, 'text/markdown');
      expect(mapped.attachment?.objectUri, 'https://objects.example/att-local');
    },
  );

  test('message timestamps from SDK are normalized to local time', () {
    const message = core.Message(
      id: 'msg-local-time',
      threadKind: 'direct',
      threadId: 'did:bob',
      direction: core.MessageDirection.incoming,
      sender: 'did:bob',
      receiver: 'did:alice',
      body: core.MessageBodyView(text: 'hello'),
      sentAt: '2026-05-23T09:00:00Z',
      metadata: core.MessageMetadata(),
    );

    final mapped = mapper.chatMessageFromCore(message, ownerDid: 'did:alice');

    expect(mapped.createdAt, DateTime.parse('2026-05-23T09:00:00Z').toLocal());
    expect(mapped.createdAt.isUtc, isFalse);
  });

  test(
    'conversation overlay customizes display fields without becoming source',
    () {
      const conversation = core.Conversation(
        threadKind: 'direct',
        threadId: 'did:bob',
        title: 'Bob',
        participants: ['did:alice', 'did:bob'],
        unreadCount: 2,
        messageCount: 5,
        lastMessageAt: '2026-05-23T09:01:00Z',
        lastMessage: core.Message(
          id: 'msg-2',
          threadKind: 'direct',
          threadId: 'did:bob',
          direction: core.MessageDirection.incoming,
          sender: 'did:bob',
          body: core.MessageBodyView(text: 'hi'),
          metadata: core.MessageMetadata(),
        ),
      );

      final mapped = mapper.conversationFromCore(
        conversation,
        ownerDid: 'did:alice',
        overlay: ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'dm:alice:bob',
          customTitle: 'Pinned Bob',
          avatarSeed: 'seed-1',
          updatedAt: DateTime.utc(2026, 5, 23),
        ),
      );

      expect(mapped.displayName, 'Pinned Bob');
      expect(mapped.threadId, 'dm:did:alice:did:bob');
      expect(mapped.lastMessagePreview, 'hi');
      expect(mapped.avatarSeed, 'seed-1');
      expect(mapped.unreadCount, 2);
    },
  );

  test(
    'snapshot conversation maps core-only fields and app overlay stays local',
    () {
      const mentionPayload =
          '{"text":"@bob 看这里","mentions":[{"id":"m1","range":{"start":0,"end":4,"unit":"unicode_code_point"},"target":{"kind":"human","did":"did:bob","display_name":"Bob"},"mention_role":"addressee"}]}';
      const conversation = core.ConversationSnapshotItem(
        threadKind: 'thread',
        threadId: 'dm:peer-scope:v1:bob',
        participants: <String>['bob.awiki.test'],
        unreadCount: 3,
        unreadMentionCount: 1,
        firstUnreadMentionMessageId: 'msg-mention',
        messageCount: 7,
        lastMessageAt: '2026-05-23T09:01:00Z',
        lastMessage: core.ConversationSnapshotMessage(
          id: 'msg-mention',
          threadKind: 'thread',
          threadId: 'dm:peer-scope:v1:bob',
          direction: 'incoming',
          sender: 'did:bob:new',
          receiver: 'did:alice',
          body: core.ConversationSnapshotMessageBody(
            payloadJson: mentionPayload,
          ),
          sentAt: '2026-05-23T09:00:00Z',
          serverSequence: 42,
          contentType: 'application/json',
          attributes: <core.MessageMetadataAttribute>[
            core.MessageMetadataAttribute(
              key: 'peer_full_handle',
              value: 'Bob.AWiki.Test',
            ),
            core.MessageMetadataAttribute(
              key: 'peer_current_did',
              value: 'did:bob:new',
            ),
          ],
        ),
      );

      final mapped = mapper.conversationFromSnapshot(
        conversation,
        ownerDid: 'did:alice',
        overlay: ProductConversationOverlay(
          ownerDid: 'did:alice',
          threadId: 'dm:peer-scope:v1:bob',
          customTitle: 'Bob local',
          avatarSeed: 'seed-local',
          pinned: true,
          hidden: true,
          updatedAt: DateTime.utc(2026, 5, 23),
        ),
      );

      expect(mapped.threadId, 'dm:peer-scope:v1:bob');
      expect(mapped.displayName, 'Bob local');
      expect(mapped.avatarSeed, 'seed-local');
      expect(mapped.lastMessagePreview, '@bob 看这里');
      expect(mapped.targetPeer, 'bob.awiki.test');
      expect(mapped.targetDid, 'did:bob:new');
      expect(mapped.unreadCount, 3);
      expect(mapped.unreadMentionCount, 1);
      expect(mapped.firstUnreadMentionMessageId, 'msg-mention');
      expect(mapped.lastMessagePayloadJson, mentionPayload);
      expect(mapped.peerLifecycleState, ConversationPeerLifecycleState.active);
    },
  );

  test(
    'conversation preview uses attachment filename when there is no caption',
    () {
      const manifest =
          '{"attachments":[{"attachment_id":"att-2","filename":"diagram.png","mime_type":"image/png","size":"2048","access_info":{"object_uri":"https://objects.example/att-2"}}],"primary_attachment_id":"att-2"}';
      const conversation = core.Conversation(
        threadKind: 'direct',
        threadId: 'did:bob',
        participants: <String>['did:alice', 'did:bob'],
        unreadCount: 1,
        messageCount: 1,
        lastMessage: core.Message(
          id: 'msg-attachment-preview',
          threadKind: 'direct',
          threadId: 'did:bob',
          direction: core.MessageDirection.incoming,
          sender: 'did:bob',
          body: core.MessageBodyView(
            unsupportedContentType: 'application/anp-attachment-manifest+json',
          ),
          metadata: core.MessageMetadata(
            contentType: 'application/anp-attachment-manifest+json',
            attributes: <core.MessageMetadataAttribute>[
              core.MessageMetadataAttribute(
                key: 'attachment_manifest',
                value: manifest,
              ),
            ],
          ),
        ),
      );

      final mapped = mapper.conversationFromCore(
        conversation,
        ownerDid: 'did:alice',
      );

      expect(mapped.lastMessagePreview, '[附件] diagram.png');
    },
  );

  test('conversation preview suppresses agent control payload', () {
    const conversation = core.Conversation(
      threadKind: 'direct',
      threadId: 'did:daemon',
      participants: <String>['did:alice', 'did:daemon'],
      unreadCount: 1,
      messageCount: 1,
      lastMessage: core.Message(
        id: 'msg-control-preview',
        threadKind: 'direct',
        threadId: 'did:daemon',
        direction: core.MessageDirection.incoming,
        sender: 'did:daemon',
        body: core.MessageBodyView(
          text: 'hidden status',
          payloadJson:
              '{"schema":"awiki.agent.command.v1","command":"agent.status.query"}',
        ),
        metadata: core.MessageMetadata(),
      ),
    );

    final mapped = mapper.conversationFromCore(
      conversation,
      ownerDid: 'did:alice',
    );

    expect(mapped.lastMessagePreview, '');
  });

  test(
    'realtime direct message uses canonical chat and conversation thread',
    () {
      const event = core.RealtimeEvent(
        kind: 'message_received',
        message: core.Message(
          id: 'msg-cgw',
          threadKind: 'direct',
          threadId: 'did:cgw',
          direction: core.MessageDirection.incoming,
          sender: 'did:cgw',
          receiver: 'did:me',
          body: core.MessageBodyView(text: '你好'),
          sentAt: '2026-05-23T09:02:00Z',
          metadata: core.MessageMetadata(),
        ),
      );

      final update = mapper.realtimeUpdateFromCore(event, ownerDid: 'did:me');

      expect(update, isNotNull);
      expect(update!.message!.threadId, 'dm:did:cgw:did:me');
      expect(update.conversationHint!.threadId, 'dm:did:cgw:did:me');
      expect(update.conversationHint!.targetDid, 'did:cgw');
    },
  );

  test('realtime control payload is split away from normal updates', () {
    const event = core.RealtimeEvent(
      kind: 'message_received',
      message: core.Message(
        id: 'msg-control-realtime',
        threadKind: 'direct',
        threadId: 'did:daemon',
        direction: core.MessageDirection.incoming,
        sender: 'did:daemon',
        receiver: 'did:me',
        body: core.MessageBodyView(
          payloadJson:
              '{"schema":"awiki.agent.status.v1","status_scope":"daemon"}',
        ),
        metadata: core.MessageMetadata(),
      ),
    );

    final update = mapper.realtimeUpdateFromCore(event, ownerDid: 'did:me');

    expect(update, isNotNull);
    expect(update!.message, isNull);
    expect(update.agentControlPayload?['schema'], 'awiki.agent.status.v1');
    expect(update.agentControlPayload?['status_scope'], 'daemon');
  });

  test('direct conversation keeps an already canonical thread id', () {
    const conversation = core.Conversation(
      threadKind: 'direct',
      threadId: 'dm:did:alice:did:bob',
      participants: <String>[],
      unreadCount: 0,
      messageCount: 0,
    );

    final mapped = mapper.conversationFromCore(
      conversation,
      ownerDid: 'did:alice',
    );

    expect(mapped.threadId, 'dm:did:alice:did:bob');
    expect(mapped.targetDid, 'did:bob');
  });

  test('group messages and conversations keep group-prefixed thread ids', () {
    const message = core.Message(
      id: 'group-msg',
      threadKind: 'group',
      threadId: 'did:group',
      direction: core.MessageDirection.incoming,
      sender: 'did:bob',
      group: 'did:group',
      body: core.MessageBodyView(text: 'hello group'),
      metadata: core.MessageMetadata(),
    );
    const conversation = core.Conversation(
      threadKind: 'group',
      threadId: 'did:group',
      participants: <String>[],
      unreadCount: 1,
      messageCount: 1,
      lastMessage: message,
    );

    final mappedMessage = mapper.chatMessageFromCore(
      message,
      ownerDid: 'did:alice',
    );
    final mappedConversation = mapper.conversationFromCore(
      conversation,
      ownerDid: 'did:alice',
    );

    expect(mappedMessage.threadId, 'group:did:group');
    expect(mappedConversation.threadId, 'group:did:group');
    expect(mappedConversation.groupId, 'did:group');
  });

  test('group members derive handle from e1 DID when SDK handle is absent', () {
    final member = mapper.groupMemberFromCore(
      const core.GroupMember(
        did: 'did:wba:awiki.ai:user:bob:e1_member',
        role: 'member',
      ),
    );
    final compactMember = mapper.groupMemberFromCore(
      const core.GroupMember(did: 'did:wba:awiki.ai:alice:e1_member'),
    );

    expect(member.handle, 'bob');
    expect(member.did, 'did:wba:awiki.ai:user:bob:e1_member');
    expect(member.role, 'member');
    expect(compactMember.handle, 'alice');
  });

  test('group member infers agent subject type from WBA agent DID', () {
    final member = mapper.groupMemberFromCore(
      const core.GroupMember(
        did: 'did:wba:awiki.ai:agent:runtime:cgw010:e1_member',
        handle: 'hermes',
        role: 'member',
      ),
    );

    expect(member.subjectType.name, 'agent');
    expect(member.handle, 'hermes');
  });

  test('group member keeps human subject type from WBA human DID', () {
    final member = mapper.groupMemberFromCore(
      const core.GroupMember(
        did: 'did:wba:anpclaw.com:zhuocheng:e1_human',
        handle: 'zhuocheng',
        role: 'member',
      ),
    );

    expect(member.subjectType.name, 'human');
    expect(member.handle, 'zhuocheng');
  });

  test('group member derives short agent handle from WBA agent DID', () {
    final member = mapper.groupMemberFromCore(
      const core.GroupMember(
        did: 'did:wba:awiki.ai:agent:runtime:cgw010:e1_member',
        role: 'member',
      ),
    );

    expect(member.subjectType.name, 'agent');
    expect(member.handle, 'cgw010');
  });

  test('group member normalizes full handle to short handle', () {
    final member = mapper.groupMemberFromCore(
      const core.GroupMember(
        did: 'did:wba:awiki.ai:agent:runtime:cgw010:e1_member',
        handle: 'wba://Hermes.awiki.ai',
        role: 'member',
      ),
    );

    expect(member.subjectType.name, 'agent');
    expect(member.handle, 'Hermes');
  });

  test('profile and relationship DTOs map to app models', () {
    final profile = mapper.userProfileFromCore(
      const core.UserProfile(
        subject: 'did:alice',
        handle: 'alice.awiki',
        fullHandle: 'alice.awiki',
        displayName: 'Alice',
        bio: 'bio',
        tags: ['ai'],
        markdown: '# Alice',
        avatarUri: 'https://cdn.example/alice.png',
        profileUri: 'https://profiles.example/alice',
        subjectType: 'person',
      ),
    );
    final patch = mapper.profilePatchToCore(
      const ProfilePatch(
        displayName: 'New Alice',
        profileMarkdown: 'new md',
        avatarUri: 'https://cdn.example/new-alice.png',
      ),
    );
    final relationship = mapper.relationshipFromCore(
      const core.RelationStatus(
        peer: 'did:bob',
        relationship: 'following',
        displayName: 'Bob',
      ),
    );
    final relationshipPage = mapper.relationshipPageFromCore(
      const core.RelationshipPage(
        items: <core.RelationshipListItem>[
          core.RelationshipListItem(
            did: 'did:carol',
            handle: 'carol.awiki',
            avatarUri: 'https://cdn.example/carol.png',
            relationship: 'follower',
          ),
        ],
        hasMore: true,
      ),
      fallbackCursorOffset: 10,
    );

    expect(profile.nickName, 'Alice');
    expect(profile.displayName, 'Alice');
    expect(profile.avatarUri, 'https://cdn.example/alice.png');
    expect(profile.profileUri, 'https://profiles.example/alice');
    expect(profile.subjectType, 'person');
    expect(profile.handle, 'alice.awiki');
    expect(profile.fullHandle, 'alice.awiki');
    expect(profile.profileMarkdown, '# Alice');
    expect(patch.displayName, 'New Alice');
    expect(patch.markdown, 'new md');
    expect(patch.avatarUri, 'https://cdn.example/new-alice.png');
    expect(relationship.relationship, 'following');
    expect(relationshipPage.items.single.displayName, 'carol.awiki');
    expect(
      relationshipPage.items.single.avatarUri,
      'https://cdn.example/carol.png',
    );
    expect(relationshipPage.items.single.relationship, 'follower');
    expect(relationshipPage.nextCursor, '11');
  });

  test('profile display fields fall back without becoming identity source', () {
    final profile = mapper.userProfileFromCore(
      const core.UserProfile(
        subject: 'did:wba:awiki.ai:user:alice:e1_1234567890',
        handle: 'alice.awiki.ai',
        fullHandle: 'alice.awiki.ai',
        avatarUrl: 'https://cdn.example/legacy-avatar.png',
        profileUri: 'https://profiles.example/alice',
        subjectType: 'person',
      ),
    );

    expect(profile.did, 'did:wba:awiki.ai:user:alice:e1_1234567890');
    expect(profile.displayName, 'did:wba:aw…567890');
    expect(profile.nickName, 'did:wba:aw…567890');
    expect(profile.handle, 'alice.awiki.ai');
    expect(profile.fullHandle, 'alice.awiki.ai');
    expect(profile.avatarUri, 'https://cdn.example/legacy-avatar.png');
    expect(profile.profileUri, 'https://profiles.example/alice');
    expect(profile.subjectType, 'person');
  });

  test('relationship list display falls back to handle then compact DID', () {
    final page = mapper.relationshipPageFromCore(
      const core.RelationshipPage(
        items: <core.RelationshipListItem>[
          core.RelationshipListItem(
            did: 'did:wba:awiki.ai:user:bob:e1_1234567890',
            handle: 'bob.awiki.ai',
            avatarUrl: 'https://cdn.example/bob-legacy.png',
            relationship: 'following',
          ),
          core.RelationshipListItem(
            did: 'did:wba:awiki.ai:user:carol:e1_1234567890',
            relationship: 'follower',
          ),
        ],
        hasMore: false,
      ),
    );

    expect(page.items[0].did, 'did:wba:awiki.ai:user:bob:e1_1234567890');
    expect(page.items[0].handle, 'bob.awiki.ai');
    expect(page.items[0].displayName, 'bob.awiki.ai');
    expect(page.items[0].avatarUri, 'https://cdn.example/bob-legacy.png');
    expect(page.items[1].displayName, 'did:wba:aw…567890');
    expect(page.nextCursor, isNull);
  });

  test('group DTOs map display profile fields from Group Host summaries', () {
    final summary = mapper.groupFromCoreSummary(
      const core.GroupSummary(
        did: 'did:group',
        name: 'Legacy name',
        displayName: 'Project Group',
        avatarUri: 'https://cdn.example/group.png',
        memberCount: 7,
      ),
    );
    final snapshot = mapper.groupFromCoreSnapshot(
      const core.GroupSnapshot(
        did: 'did:group',
        displayName: 'Project Group Snapshot',
        avatarUri: 'https://cdn.example/group-snapshot.png',
        description: 'Group description',
        memberCount: 8,
      ),
    );

    expect(summary.displayName, 'Project Group');
    expect(summary.name, 'Project Group');
    expect(summary.avatarUri, 'https://cdn.example/group.png');
    expect(snapshot.displayName, 'Project Group Snapshot');
    expect(snapshot.avatarUri, 'https://cdn.example/group-snapshot.png');
    expect(snapshot.description, 'Group description');
  });

  test('realtime connection states map into existing app enum', () {
    expect(
      mapper.connectionStatusFromCore(
        const core.RealtimeConnectionState(state: 'connected'),
      ),
      RealtimeConnectionStatus.connected,
    );
    expect(
      mapper.connectionStatusFromCore(
        const core.RealtimeConnectionState(state: 'unknown'),
      ),
      RealtimeConnectionStatus.idle,
    );
  });
}
