import 'package:awiki_me/src/data/awiki_sdk/awiki_wire_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = AwikiWireMapper();

  test('maps direct message aliases to ChatMessage and stable dm thread', () {
    final message = mapper.toChatMessage(<String, Object?>{
      'message_id': 'msg-1',
      'sender_did': 'did:wba:awiki.ai:user:bob',
      'target_did': 'did:wba:awiki.ai:user:alice',
      'body': <String, Object?>{'text': 'hello'},
      'accepted_at': '2026-05-06T01:02:03Z',
      'seq': '7',
    }, ownerDid: 'did:wba:awiki.ai:user:alice');

    expect(message.remoteId, 'msg-1');
    expect(message.senderDid, 'did:wba:awiki.ai:user:bob');
    expect(message.receiverDid, 'did:wba:awiki.ai:user:alice');
    expect(message.content, 'hello');
    expect(message.serverSequence, 7);
    expect(
      message.threadId,
      'dm:did:wba:awiki.ai:user:alice:did:wba:awiki.ai:user:bob',
    );
  });

  test('maps group message aliases to group thread', () {
    final message = mapper.toChatMessage(<String, Object?>{
      'id': 'msg-2',
      'sender_did': 'did:wba:awiki.ai:user:bob',
      'group_did': 'did:wba:awiki.ai:group:one',
      'text': 'group hello',
      'group_event_seq': '11',
    }, ownerDid: 'did:wba:awiki.ai:user:alice');

    expect(message.remoteId, 'msg-2');
    expect(message.groupId, 'did:wba:awiki.ai:group:one');
    expect(message.threadId, 'group:did:wba:awiki.ai:group:one');
    expect(message.content, 'group hello');
    expect(message.serverSequence, 11);
  });

  test('builds conversations from inbox messages', () {
    final conversations = mapper.conversationsFromInbox(
      ownerDid: 'did:wba:awiki.ai:user:alice',
      messages: <Map<String, Object?>>[
        <String, Object?>{
          'message_id': 'old',
          'sender_did': 'did:wba:awiki.ai:user:bob',
          'target_did': 'did:wba:awiki.ai:user:alice',
          'text': 'old',
          'created_at': '2026-05-06T01:00:00Z',
        },
        <String, Object?>{
          'message_id': 'new',
          'sender_did': 'did:wba:awiki.ai:user:bob',
          'target_did': 'did:wba:awiki.ai:user:alice',
          'text': 'new',
          'created_at': '2026-05-06T02:00:00Z',
        },
      ],
    );

    expect(conversations, hasLength(1));
    expect(conversations.single.lastMessagePreview, 'new');
    expect(conversations.single.unreadCount, 2);
  });
}
