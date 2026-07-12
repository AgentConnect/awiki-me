import 'dart:convert';

import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/desktop_cli_peer/support/ui_oracles.dart';

void main() {
  test('desktop platform oracle requires exactly one variant', () {
    expect(
      requireDesktopPlatformVariant(
        macOSCount: 1,
        otherCount: 0,
        element: 'test entry',
      ),
      DesktopPlatformVariant.macOS,
    );
    expect(
      requireDesktopPlatformVariant(
        macOSCount: 0,
        otherCount: 1,
        element: 'test entry',
      ),
      DesktopPlatformVariant.other,
    );
    expect(
      () => requireDesktopPlatformVariant(
        macOSCount: 0,
        otherCount: 0,
        element: 'test entry',
      ),
      throwsStateError,
    );
    expect(
      () => requireDesktopPlatformVariant(
        macOSCount: 1,
        otherCount: 1,
        element: 'test entry',
      ),
      throwsStateError,
    );
  });

  ChatMessage message({
    String localId = 'local-1',
    String? remoteId = 'remote-1',
    String content = 'exact body',
    String senderDid = 'did:test:sender',
    String? receiverDid = 'did:test:receiver',
    String? groupDid,
    MessageSendState sendState = MessageSendState.sent,
    List<ChatMessageMention> mentions = const <ChatMessageMention>[],
  }) {
    return ChatMessage(
      localId: localId,
      remoteId: remoteId,
      threadId: groupDid == null ? 'dm:peer' : 'group:$groupDid',
      senderDid: senderDid,
      receiverDid: receiverDid,
      groupId: groupDid,
      content: content,
      createdAt: DateTime(2026, 7, 10),
      isMine: senderDid == 'did:test:sender',
      sendState: sendState,
      mentions: mentions,
    );
  }

  test('message oracle requires canonical exact-one and terminal fields', () {
    final found = requireExactlyOneMessage(
      messages: <ChatMessage>[message()],
      content: 'exact body',
      messageId: 'remote-1',
      senderDid: 'did:test:sender',
      receiverDid: 'did:test:receiver',
      sendState: MessageSendState.sent,
    );

    expect(found.remoteId, 'remote-1');
  });

  test('CLI peer identity oracle is exact and redacts mismatch details', () {
    expect(
      requireMatchingCliPeerDid(
        canonicalCliDid: ' did:test:cli ',
        observedPeerDid: 'did:test:cli',
      ),
      'did:test:cli',
    );

    final mismatch = throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        'CLI peer identity mismatch.',
      ),
    );
    expect(
      () => requireMatchingCliPeerDid(
        canonicalCliDid: 'did:test:cli',
        observedPeerDid: 'did:test:other',
      ),
      mismatch,
    );
    expect(
      () => requireMatchingCliPeerDid(
        canonicalCliDid: '',
        observedPeerDid: 'did:test:other',
      ),
      mismatch,
    );
    expect(
      () => requireMatchingCliPeerDid(
        canonicalCliDid: 'did:test:cli',
        observedPeerDid: '',
      ),
      mismatch,
    );
  });

  test('message oracle rejects duplicate content instead of using first', () {
    expect(
      () => requireExactlyOneMessage(
        messages: <ChatMessage>[
          message(localId: 'local-1', remoteId: 'remote-1'),
          message(localId: 'local-2', remoteId: 'remote-2'),
        ],
        content: 'exact body',
      ),
      throwsStateError,
    );
  });

  test('expected message id cannot hide duplicate body with another id', () {
    expect(
      () => requireExactlyOneMessage(
        messages: <ChatMessage>[
          message(localId: 'local-1', remoteId: 'remote-1'),
          message(localId: 'local-2', remoteId: 'remote-2'),
        ],
        content: 'exact body',
        messageId: 'remote-1',
      ),
      throwsStateError,
    );

    final output = jsonEncode(<String, Object?>{
      'data': <String, Object?>{
        'messages': <Map<String, Object?>>[
          <String, Object?>{'message_id': 'remote-1', 'content': 'exact body'},
          <String, Object?>{'message_id': 'remote-2', 'content': 'exact body'},
        ],
      },
    });
    expect(
      cliMessagesWithExactText(
        output,
        expectedText: 'exact body',
        expectedMessageId: 'remote-1',
      ),
      hasLength(2),
    );
  });

  test(
    'incoming conversation oracle rejects missing duplicate or wrong row',
    () {
      final conversation = ConversationSummary(
        conversationId: 'dm:did:test:peer',
        threadId: 'dm:did:test:peer',
        displayName: 'Peer',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 7, 10),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:test:peer',
      );
      final wrongConversation = ConversationSummary(
        conversationId: 'dm:did:test:other',
        threadId: 'dm:did:test:other',
        displayName: 'Other',
        lastMessagePreview: 'hello',
        lastMessageAt: DateTime(2026, 7, 10),
        unreadCount: 1,
        isGroup: false,
        targetDid: 'did:test:other',
      );
      expect(
        requireExactlyOneConversation(
          conversations: <ConversationSummary>[conversation],
          conversationId: 'dm:did:test:peer',
          unreadCount: 1,
          lastMessage: 'hello',
        ),
        same(conversation),
      );
      expect(
        () => requireExactlyOneConversation(
          conversations: const <ConversationSummary>[],
          conversationId: 'dm:did:test:peer',
          unreadCount: 1,
          lastMessage: 'hello',
        ),
        throwsStateError,
      );
      try {
        requireExactlyOneConversation(
          conversations: <ConversationSummary>[wrongConversation],
          conversationId: 'dm:did:test:peer',
          unreadCount: 1,
          lastMessage: 'hello',
        );
        fail('wrong canonical conversation must fail');
      } on StateError catch (error) {
        expect(error.message, contains('canonical_matches=0'));
        expect(error.message, contains('semantic_matches=1'));
        expect(error.message, contains('candidate_rows=1'));
        expect(error.message, isNot(contains('did:test')));
        expect(error.message, isNot(contains('hello')));
      }
      expect(
        () => requireExactlyOneConversation(
          conversations: <ConversationSummary>[wrongConversation],
          conversationId: 'dm:did:test:peer',
          unreadCount: 1,
          lastMessage: 'hello',
        ),
        throwsStateError,
      );
      expect(
        () => requireExactlyOneConversation(
          conversations: <ConversationSummary>[conversation],
          conversationId: 'dm:did:test:peer',
          unreadCount: 0,
        ),
        throwsStateError,
      );
      expect(
        () => requireExactlyOneConversation(
          conversations: <ConversationSummary>[conversation],
          conversationId: 'dm:did:test:peer',
          unreadCount: 1,
          lastMessage: 'wrong body',
        ),
        throwsStateError,
      );
      expect(
        () => requireExactlyOneConversation(
          conversations: <ConversationSummary>[conversation, conversation],
          conversationId: 'dm:did:test:peer',
          unreadCount: 1,
        ),
        throwsStateError,
      );
    },
  );

  test('mention oracle verifies one valid structured target', () {
    const content = '@peer hello';
    final withMention = message(
      content: content,
      groupDid: 'did:test:group',
      receiverDid: null,
      mentions: const <ChatMessageMention>[
        ChatMessageMention(
          id: 'mention-1',
          surface: '@peer',
          start: 0,
          end: 5,
          target: ChatMentionTargetDraft.member(
            kind: ChatMentionTargetKind.human,
            did: 'did:test:peer',
          ),
        ),
      ],
    );

    expect(
      () => requireSingleMentionTarget(
        message: withMention,
        targetDid: 'did:test:peer',
      ),
      returnsNormally,
    );
    expect(
      () => requireSingleMentionTarget(
        message: withMention,
        targetDid: 'did:test:other',
      ),
      throwsStateError,
    );
  });

  test('CLI relationship state derives exact directional combinations', () {
    Map<String, Object?> status({
      bool following = false,
      bool follower = false,
      bool friend = false,
      String relationship = 'none',
      Object? combined,
    }) => <String, Object?>{
      'relationship': relationship,
      'is_following': following,
      'is_follower': follower,
      'is_friend': friend,
      'is_blocked': false,
      'is_blocked_by': false,
      if (combined != null) 'status': combined,
    };

    expect(
      cliRelationshipState(
        jsonEncode(<String, Object?>{
          'data': <String, Object?>{
            'did': 'did:test:peer',
            'is_following': false,
          },
        }),
      ),
      isNull,
    );
    expect(
      cliRelationshipState(jsonEncode(<String, Object?>{'data': status()})),
      'none',
    );
    expect(
      cliRelationshipState(
        jsonEncode(<String, Object?>{'data': status(follower: true)}),
      ),
      'follower',
    );
    expect(
      cliRelationshipState(
        jsonEncode(<String, Object?>{
          'data': status(following: true, relationship: 'following'),
        }),
      ),
      'following',
    );
    expect(
      cliRelationshipState(
        jsonEncode(<String, Object?>{
          'data': status(
            following: true,
            follower: true,
            friend: true,
            relationship: 'following',
            combined: 'friend',
          ),
        }),
      ),
      'friend',
    );
    expect(
      cliRelationshipState(
        jsonEncode(<String, Object?>{
          'data': status(follower: true, friend: true),
        }),
      ),
      isNull,
    );
    expect(
      cliRelationshipState(
        jsonEncode(<String, Object?>{
          'data': status(follower: true, relationship: 'unexpected'),
        }),
      ),
      isNull,
    );
  });

  test('CLI mention oracle validates full text, range, target, and role', () {
    Map<String, Object?> cliMention({
      String text = '@peer hello',
      int start = 0,
      int end = 5,
      String unit = 'unicode_code_point',
      String targetDid = 'did:test:peer',
      String targetKind = 'human',
      String role = 'addressee',
    }) {
      return <String, Object?>{
        'message_id': 'remote-mention',
        'payload': jsonEncode(<String, Object?>{
          'text': text,
          'mentions': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'mention-1',
              'range': <String, Object?>{
                'start': start,
                'end': end,
                'unit': unit,
              },
              'target': <String, Object?>{'kind': targetKind, 'did': targetDid},
              'mention_role': role,
            },
          ],
        }),
      };
    }

    bool matches(Map<String, Object?> value) {
      return cliMessageHasExactSingleMention(
        message: value,
        expectedText: '@peer hello',
        expectedMentionSurface: '@peer',
        expectedTargetDid: 'did:test:peer',
        expectedTargetKind: 'human',
        expectedMentionRole: 'addressee',
      );
    }

    expect(matches(cliMention()), isTrue);
    expect(matches(cliMention(text: '@peer wrong')), isFalse);
    expect(matches(cliMention(start: 1)), isFalse);
    expect(matches(cliMention(end: 4)), isFalse);
    expect(matches(cliMention(unit: 'utf16_code_unit')), isFalse);
    expect(matches(cliMention(targetDid: 'did:test:other')), isFalse);
    expect(matches(cliMention(targetKind: 'agent')), isFalse);
    expect(matches(cliMention(role: 'cc')), isFalse);
  });

  testWidgets(
    'scoped visible-message oracle ignores an identical recents preview',
    (tester) async {
      const body = 'same preview and bubble';
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              Text(body, key: Key('conversation-preview')),
              KeyedSubtree(
                key: Key('chat-message-content:target-message'),
                child: Text(body),
              ),
            ],
          ),
        ),
      );

      expect(find.text(body), findsNWidgets(2));
      expect(
        () => expectExactlyOneVisibleMessageContent(
          localId: 'target-message',
          expectedText: body,
        ),
        returnsNormally,
      );
    },
  );

  testWidgets(
    'scoped visible-message oracle rejects wrong or duplicate bubbles',
    (tester) async {
      const body = 'target body';
      void expectOracleFailure() {
        expect(
          () => expectExactlyOneVisibleMessageContent(
            localId: 'target-message',
            expectedText: body,
          ),
          throwsA(isA<TestFailure>()),
        );
      }

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: KeyedSubtree(
            key: Key('chat-message-content:wrong-message'),
            child: Text(body),
          ),
        ),
      );
      expectOracleFailure();

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: KeyedSubtree(
            key: Key('chat-message-content:target-message'),
            child: Text('wrong body'),
          ),
        ),
      );
      expectOracleFailure();

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              SizedBox(
                child: KeyedSubtree(
                  key: Key('chat-message-content:target-message'),
                  child: Text(body),
                ),
              ),
              SizedBox(
                child: KeyedSubtree(
                  key: Key('chat-message-content:target-message'),
                  child: Text(body),
                ),
              ),
            ],
          ),
        ),
      );
      expectOracleFailure();

      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: KeyedSubtree(
            key: Key('chat-message-content:target-message'),
            child: Column(children: <Widget>[Text(body), Text(body)]),
          ),
        ),
      );
      expectOracleFailure();
    },
  );
}
