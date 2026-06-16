import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_mappers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AwikiImCoreMappers();

  test('control payload message is not renderable chat content', () {
    const payload =
        '{"schema":"awiki.daemon.bootstrap.v1","bootstrap_id":"boot_1"}';
    const message = core.Message(
      id: 'msg-control',
      threadKind: 'direct',
      threadId: 'did:agent:daemon',
      direction: core.MessageDirection.incoming,
      sender: 'did:agent:daemon',
      receiver: 'did:human:me',
      body: core.MessageBodyView(payloadJson: payload, kind: 'payload'),
      sentAt: '2026-06-04T09:00:00Z',
      metadata: core.MessageMetadata(),
    );

    final mapped = mapper.chatMessageFromCore(
      message,
      ownerDid: 'did:human:me',
    );

    expect(mapped.payloadJson, payload);
    expect(mapped.isAgentControlPayload, isTrue);
    expect(mapped.hasRenderableContent, isFalse);
  });

  test(
    'realtime control payload is projected outside normal message stream',
    () {
      const event = core.RealtimeEvent(
        kind: 'message_received',
        message: core.Message(
          id: 'msg-control-realtime',
          threadKind: 'direct',
          threadId: 'did:agent:daemon',
          direction: core.MessageDirection.incoming,
          sender: 'did:agent:daemon',
          receiver: 'did:human:me',
          body: core.MessageBodyView(
            payloadJson:
                '{"schema":"awiki.agent.status.v1","status_scope":"daemon"}',
            kind: 'payload',
          ),
          sentAt: '2026-06-04T09:00:00Z',
          metadata: core.MessageMetadata(),
        ),
      );

      final update = mapper.realtimeUpdateFromCore(
        event,
        ownerDid: 'did:human:me',
      );

      expect(update, isNotNull);
      expect(update!.message, isNull);
      expect(update.conversation, isNull);
      expect(update.agentControlPayload?['schema'], 'awiki.agent.status.v1');
    },
  );

  test('runtime agent normal text remains renderable and updates recents', () {
    const event = core.RealtimeEvent(
      kind: 'message_received',
      message: core.Message(
        id: 'msg-runtime',
        threadKind: 'direct',
        threadId: 'did:agent:runtime',
        direction: core.MessageDirection.incoming,
        sender: 'did:agent:runtime',
        receiver: 'did:human:me',
        body: core.MessageBodyView(text: 'Hermes reply'),
        sentAt: '2026-06-04T09:00:00Z',
        metadata: core.MessageMetadata(),
      ),
    );

    final update = mapper.realtimeUpdateFromCore(
      event,
      ownerDid: 'did:human:me',
    );

    expect(update, isNotNull);
    expect(update!.agentControlPayload, isNull);
    expect(update.message?.content, 'Hermes reply');
    expect(update.message?.hasRenderableContent, isTrue);
    expect(update.conversation?.targetDid, 'did:agent:runtime');
    expect(update.conversation?.lastMessagePreview, 'Hermes reply');
  });

  test('mention payload projects payload text and typed mention ranges', () {
    const payload = '''{
    "text":"@所有 Agents 请总结",
    "mentions":[
      {
        "id":"men_1",
        "range":{"start":0,"end":10,"unit":"unicode_code_point"},
        "target":{"kind":"group_selector","selector":"agents"},
        "mention_role":"addressee"
      }
    ]
  }''';
    const message = core.Message(
      id: 'msg-mention',
      threadKind: 'group',
      threadId: 'group:did:wba:awiki.info:group:mention',
      direction: core.MessageDirection.incoming,
      sender: 'did:wba:awiki.info:user:peer',
      group: 'did:wba:awiki.info:group:mention',
      body: core.MessageBodyView(payloadJson: payload, kind: 'payload'),
      sentAt: '2026-06-14T12:00:00Z',
      metadata: core.MessageMetadata(contentType: 'application/json'),
    );

    final mapped = mapper.chatMessageFromCore(
      message,
      ownerDid: 'did:wba:awiki.info:user:me',
    );

    expect(mapped.content, '@所有 Agents 请总结');
    expect(mapped.originalType, 'application/json');
    expect(mapped.hasRenderableContent, isTrue);
    expect(mapped.hasValidMentions, isTrue);
    expect(mapped.mentions, hasLength(1));
    expect(mapped.mentions.single.surface, '@所有 Agents');
    expect(mapped.mentions.single.target.selector?.wireValue, 'agents');
  });

  test('invalid mention range falls back to text without highlight', () {
    const payload = '''{
    "text":"@所有 Agents 请总结",
    "mentions":[
      {
        "id":"men_bad",
        "range":{"start":0,"end":99,"unit":"unicode_code_point"},
        "target":{"kind":"group_selector","selector":"agents"},
        "mention_role":"addressee"
      }
    ]
  }''';
    const message = core.Message(
      id: 'msg-mention-invalid',
      threadKind: 'group',
      threadId: 'group:did:wba:awiki.info:group:mention',
      direction: core.MessageDirection.incoming,
      sender: 'did:wba:awiki.info:user:peer',
      group: 'did:wba:awiki.info:group:mention',
      body: core.MessageBodyView(payloadJson: payload, kind: 'payload'),
      sentAt: '2026-06-14T12:00:00Z',
      metadata: core.MessageMetadata(contentType: 'application/json'),
    );

    final mapped = mapper.chatMessageFromCore(
      message,
      ownerDid: 'did:wba:awiki.info:user:me',
    );

    expect(mapped.content, '@所有 Agents 请总结');
    expect(mapped.mentions, isEmpty);
    expect(mapped.hasRenderableContent, isTrue);
  });

  test('conversation preview uses mention payload text', () {
    const payload = '''{
    "text":"@所有人 请看这里",
    "mentions":[
      {
        "id":"men_all",
        "range":{"start":0,"end":4,"unit":"unicode_code_point"},
        "target":{"kind":"group_selector","selector":"all"},
        "mention_role":"addressee"
      }
    ]
  }''';
    final conversation = mapper.conversationFromCore(
      const core.Conversation(
        threadKind: 'group',
        threadId: 'group:did:wba:awiki.info:group:mention',
        unreadCount: 1,
        messageCount: 1,
        lastMessage: core.Message(
          id: 'msg-preview',
          threadKind: 'group',
          threadId: 'group:did:wba:awiki.info:group:mention',
          direction: core.MessageDirection.incoming,
          sender: 'did:wba:awiki.info:user:peer',
          group: 'did:wba:awiki.info:group:mention',
          body: core.MessageBodyView(payloadJson: payload, kind: 'payload'),
          metadata: core.MessageMetadata(contentType: 'application/json'),
        ),
      ),
      ownerDid: 'did:wba:awiki.info:user:me',
    );

    expect(conversation.lastMessagePreview, '@所有人 请看这里');
    expect(conversation.lastMessagePayloadJson, payload);
  });
}
