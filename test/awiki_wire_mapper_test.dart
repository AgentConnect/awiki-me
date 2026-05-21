import 'package:awiki_me/src/data/awiki_sdk/awiki_wire_mapper.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
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

  test('maps direct.incoming meta body envelope', () {
    final message = mapper.toChatMessage(<String, Object?>{
      'meta': <String, Object?>{
        'message_id': 'msg-3',
        'sender_did': 'did:wba:awiki.ai:user:bob',
        'target': <String, Object?>{
          'kind': 'agent',
          'did': 'did:wba:awiki.ai:user:alice',
        },
        'created_at': '2026-05-06T03:00:00Z',
      },
      'body': <String, Object?>{'text': 'new ws hello'},
    }, ownerDid: 'did:wba:awiki.ai:user:alice');

    expect(message.remoteId, 'msg-3');
    expect(message.senderDid, 'did:wba:awiki.ai:user:bob');
    expect(message.receiverDid, 'did:wba:awiki.ai:user:alice');
    expect(message.content, 'new ws hello');
    expect(
      message.threadId,
      'dm:did:wba:awiki.ai:user:alice:did:wba:awiki.ai:user:bob',
    );
  });

  test('maps group.incoming meta body envelope', () {
    final message = mapper.toChatMessage(<String, Object?>{
      'meta': <String, Object?>{
        'message_id': 'msg-4',
        'sender_did': 'did:wba:awiki.ai:user:bob',
      },
      'body': <String, Object?>{
        'text': 'new group ws hello',
        'group_did': 'did:wba:awiki.ai:group:two',
        'group_event_seq': '12',
      },
    }, ownerDid: 'did:wba:awiki.ai:user:alice');

    expect(message.remoteId, 'msg-4');
    expect(message.groupId, 'did:wba:awiki.ai:group:two');
    expect(message.threadId, 'group:did:wba:awiki.ai:group:two');
    expect(message.content, 'new group ws hello');
    expect(message.serverSequence, 12);
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

  test('builds group conversation title from nested group profile', () {
    final conversations = mapper.conversationsFromInbox(
      ownerDid: 'did:wba:awiki.ai:user:alice',
      messages: <Map<String, Object?>>[
        <String, Object?>{
          'message_id': 'group-message',
          'sender_did': 'did:wba:awiki.ai:user:bob',
          'group_did': 'did:wba:awiki.ai:group:funding',
          'text': 'group hello',
          'created_at': '2026-05-06T02:00:00Z',
          'group_profile': <String, Object?>{'display_name': '融资协作群'},
        },
      ],
    );

    expect(conversations, hasLength(1));
    expect(conversations.single.isGroup, isTrue);
    expect(conversations.single.displayName, '融资协作群');
  });

  test('maps group summary name from nested body group profile', () {
    final group = mapper.toGroupSummary(<String, Object?>{
      'body': <String, Object?>{
        'group_did': 'did:wba:awiki.ai:group:funding',
        'group_profile': <String, Object?>{
          'display_name': '融资协作群',
          'description': '融资协作',
        },
      },
      'member_count': '3',
    });

    expect(group.groupId, 'did:wba:awiki.ai:group:funding');
    expect(group.name, '融资协作群');
    expect(group.description, '融资协作');
    expect(group.memberCount, 3);
  });

  test('preserves friendly cached group name when inbox only has group id', () {
    final previous = ConversationSummary(
      threadId: 'group:did:wba:awiki.ai:group:funding',
      displayName: '融资协作群',
      lastMessagePreview: 'old',
      lastMessageAt: DateTime(2026, 5, 6, 1),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:wba:awiki.ai:group:funding',
    );
    final incoming = ConversationSummary(
      threadId: previous.threadId,
      displayName: 'Group did:wba:awiki.ai:group:funding',
      lastMessagePreview: 'new',
      lastMessageAt: DateTime(2026, 5, 6, 2),
      unreadCount: 1,
      isGroup: true,
      groupId: previous.groupId,
    );

    final merged = mapper.mergeConversations(
      <ConversationSummary>[previous],
      <ConversationSummary>[incoming],
    );

    expect(merged.single.displayName, '融资协作群');
    expect(merged.single.lastMessagePreview, 'new');
    expect(merged.single.unreadCount, 1);
  });
}
