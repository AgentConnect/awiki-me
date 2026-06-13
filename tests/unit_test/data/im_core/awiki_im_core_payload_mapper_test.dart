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
}
