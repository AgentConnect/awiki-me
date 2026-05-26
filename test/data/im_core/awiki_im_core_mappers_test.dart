import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/models/product_local_models.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_mappers.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/profile_patch.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AwikiImCoreMappers();

  test('identity maps to app session and legacy session without JWT', () {
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
    );
    final legacy = mapper.legacySessionFromAppSession(session);

    expect(session.identityId, 'id-1');
    expect(session.displayName, 'Alice');
    expect(session.authenticated, isTrue);
    expect(legacy.credentialName, 'alice-local');
    expect(legacy.jwtToken, isNull);
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
      expect(update!.message.threadId, 'dm:did:cgw:did:me');
      expect(update.conversation.threadId, 'dm:did:cgw:did:me');
      expect(update.conversation.targetDid, 'did:cgw');
    },
  );

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

  test('profile and relationship DTOs map to app models', () {
    final profile = mapper.userProfileFromCore(
      const core.UserProfile(
        subject: 'did:alice',
        handle: 'alice.awiki',
        displayName: 'Alice',
        bio: 'bio',
        tags: ['ai'],
        markdown: '# Alice',
      ),
    );
    final patch = mapper.profilePatchToCore(
      const ProfilePatch(nickName: 'New Alice', profileMarkdown: 'new md'),
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
            relationship: 'follower',
          ),
        ],
        hasMore: true,
      ),
      fallbackCursorOffset: 10,
    );

    expect(profile.nickName, 'Alice');
    expect(profile.profileMarkdown, '# Alice');
    expect(patch.displayName, 'New Alice');
    expect(patch.markdown, 'new md');
    expect(relationship.relationship, 'following');
    expect(relationshipPage.items.single.displayName, 'carol.awiki');
    expect(relationshipPage.items.single.relationship, 'follower');
    expect(relationshipPage.nextCursor, '11');
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
