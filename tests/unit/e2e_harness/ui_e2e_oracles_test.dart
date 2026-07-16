import 'dart:convert';

import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/flutter/desktop_cli_peer/support/ui_oracles.dart';

void main() {
  test('first visible title oracle rejects transient identity fallbacks', () {
    expect(
      observeFirstVisibleConversationTitle(
        targetSelected: false,
        visibleTitles: const <String>['old conversation'],
        expectedTitle: 'Alice nickname',
      ).status,
      E2eObservationStatus.pending,
    );
    expect(
      observeFirstVisibleConversationTitle(
        targetSelected: true,
        visibleTitles: const <String>[],
        expectedTitle: 'Alice nickname',
      ).status,
      E2eObservationStatus.pending,
    );
    for (final wrong in const <String>[
      'alice.awiki.info',
      'e1_compact_did',
      'Unknown',
    ]) {
      final observation = observeFirstVisibleConversationTitle(
        targetSelected: true,
        visibleTitles: <String>[wrong],
        expectedTitle: 'Alice nickname',
      );
      expect(observation.status, E2eObservationStatus.fatal);
      expect(observation.code, 'wrong_first_visible_conversation_title');
    }
    expect(
      observeFirstVisibleConversationTitle(
        targetSelected: true,
        visibleTitles: const <String>['Alice nickname', 'Alice nickname'],
        expectedTitle: 'Alice nickname',
      ).code,
      'conversation_title_not_exact_one',
    );
    expect(
      observeFirstVisibleConversationTitle(
        targetSelected: true,
        visibleTitles: const <String>['Alice nickname'],
        expectedTitle: 'Alice nickname',
      ).status,
      E2eObservationStatus.pass,
    );
  });

  testWidgets('scoped display-name oracle rejects any wrong App surface', (
    tester,
  ) async {
    const expected = 'Peer nickname';
    const surfaces = <String>[
      'conversation-row-title',
      'chat-header-title',
      'contact-row-title',
      'group-message-sender',
    ];
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: <Widget>[
            Text(expected, key: Key('conversation-row-title')),
            Text(expected, key: Key('chat-header-title')),
            Text(expected, key: Key('contact-row-title')),
            Text(expected, key: Key('group-message-sender')),
          ],
        ),
      ),
    );

    for (final surface in surfaces) {
      Iterable<Widget> widgets() =>
          find.byKey(Key(surface)).evaluate().map((element) => element.widget);
      expect(
        observeExactScopedText(
          widgets: widgets(),
          expectedText: expected,
          pendingCode: 'pending',
          exactOneCode: 'not_exact_one',
          mismatchCode: 'display_name_mismatch',
        ).status,
        E2eObservationStatus.pass,
      );
      final wrong = observeExactScopedText(
        widgets: widgets(),
        expectedText: 'Wrong name',
        pendingCode: 'pending',
        exactOneCode: 'not_exact_one',
        mismatchCode: 'display_name_mismatch',
      );
      expect(wrong.status, E2eObservationStatus.fatal);
      expect(wrong.code, 'display_name_mismatch');
    }
  });

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

  test('contact-first oracle rejects an existing DID or Handle Direct', () {
    final group = ConversationSummary(
      threadId: 'group:one',
      conversationId: 'group:one',
      displayName: 'Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 16),
      unreadCount: 0,
      isGroup: true,
      groupId: 'did:test:group',
    );
    expect(
      () => requireNoDirectConversationForPeer(
        conversations: <ConversationSummary>[group],
        peerDid: 'did:test:peer',
        peerHandles: const <String>['peer.awiki.info'],
      ),
      returnsNormally,
    );

    ConversationSummary direct({String? did, String? handle}) =>
        ConversationSummary(
          threadId: 'dm:one',
          conversationId: 'dm:peer-scope:v1:one',
          displayName: 'Peer',
          lastMessagePreview: '',
          lastMessageAt: DateTime(2026, 7, 16),
          unreadCount: 0,
          isGroup: false,
          targetDid: did,
          targetPeer: handle ?? '',
        );
    for (final existing in <ConversationSummary>[
      direct(did: 'did:test:peer'),
      direct(handle: '@PEER.AWIKI.INFO'),
    ]) {
      expect(
        () => requireNoDirectConversationForPeer(
          conversations: <ConversationSummary>[existing],
          peerDid: 'did:test:peer',
          peerHandles: const <String>['peer.awiki.info'],
        ),
        throwsStateError,
      );
    }
  });

  ChatMessage message({
    String localId = 'local-1',
    String? remoteId = 'remote-1',
    String? conversationId,
    String content = 'exact body',
    String senderDid = 'did:test:sender',
    String? senderPeerPersonaId,
    String? receiverDid = 'did:test:receiver',
    String? groupDid,
    int? serverSequence,
    DateTime? createdAt,
    bool? isMine,
    MessageSendState sendState = MessageSendState.sent,
    List<ChatMessageMention> mentions = const <ChatMessageMention>[],
  }) {
    return ChatMessage(
      localId: localId,
      remoteId: remoteId,
      conversationId: conversationId,
      senderPeerPersonaId: senderPeerPersonaId,
      threadId: groupDid == null ? 'dm:peer' : 'group:$groupDid',
      senderDid: senderDid,
      receiverDid: receiverDid,
      groupId: groupDid,
      content: content,
      createdAt: createdAt ?? DateTime(2026, 7, 10),
      isMine: isMine ?? senderDid == 'did:test:sender',
      sendState: sendState,
      serverSequence: serverSequence,
      mentions: mentions,
    );
  }

  test('group sender label oracle follows the visible message cluster', () {
    final first = message(
      localId: 'remote-first',
      remoteId: 'remote-first',
      senderDid: 'did:test:peer',
      groupDid: 'did:test:group',
      isMine: false,
    );
    final second = message(
      localId: 'remote-second',
      remoteId: 'remote-second',
      senderDid: 'did:test:peer',
      groupDid: 'did:test:group',
      isMine: false,
    );
    final otherSender = message(
      localId: 'remote-other',
      remoteId: 'remote-other',
      senderDid: 'did:test:other',
      groupDid: 'did:test:group',
      isMine: false,
    );

    expect(
      requireGroupSenderLabelAnchor(
        messages: <ChatMessage>[first, second, otherSender],
        target: second,
      ).localId,
      'remote-first',
    );
    expect(
      requireGroupSenderLabelAnchor(
        messages: <ChatMessage>[first, second, otherSender],
        target: otherSender,
      ).localId,
      'remote-other',
    );
    expect(
      () => requireGroupSenderLabelAnchor(
        messages: <ChatMessage>[first],
        target: message(localId: 'missing', isMine: false),
      ),
      throwsStateError,
    );
  });

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
    'CLI exact-message oracle distinguishes pending duplicate and mismatch',
    () {
      String output(List<Map<String, Object?>> messages) =>
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{'messages': messages},
          });
      final exact = <String, Object?>{
        'message_id': 'remote-1',
        'content': 'exact body',
        'sender_did': 'did:test:sender',
        'group_did': 'did:test:group',
        'content_type': 'text/plain',
      };

      expect(
        observeCliExactMessage(
          output: output(const <Map<String, Object?>>[]),
          expectedText: 'exact body',
        ).status,
        E2eObservationStatus.pending,
      );
      expect(
        observeCliExactMessage(
          output: output(<Map<String, Object?>>[
            exact,
            <String, Object?>{...exact, 'message_id': 'remote-2'},
          ]),
          expectedText: 'exact body',
        ).code,
        'cli_duplicate_exact_message',
      );
      expect(
        observeCliExactMessage(
          output: output(<Map<String, Object?>>[exact]),
          expectedText: 'exact body',
          expectedMessageId: 'wrong-id',
        ).code,
        'cli_message_id_mismatch',
      );
      expect(
        observeCliExactMessage(
          output: output(<Map<String, Object?>>[exact]),
          expectedText: 'exact body',
          expectedMessageId: 'remote-1',
          expectedSenderDid: 'did:test:sender',
          expectedGroupDid: 'did:test:group',
          expectedContentType: 'text/plain',
        ).status,
        E2eObservationStatus.pass,
      );
    },
  );

  test('message sequence oracle validates complete ordered run-owned set', () {
    final messages = <ChatMessage>[
      message(
        localId: 'local-unrelated',
        remoteId: 'remote-unrelated',
        content: 'old history',
      ),
      message(
        localId: 'local-1',
        remoteId: 'remote-1',
        conversationId: 'dm:canonical',
        content: 'run body',
        senderPeerPersonaId: 'persona:sender',
        serverSequence: 10,
      ),
      message(
        localId: 'local-2',
        remoteId: 'remote-2',
        conversationId: 'dm:canonical',
        content: 'run body',
        senderPeerPersonaId: 'persona:sender',
        serverSequence: 11,
      ),
    ];
    final expected = <ExactMessageExpectation>[
      const ExactMessageExpectation(
        canonicalId: 'remote-1',
        content: 'run body',
        conversationId: 'dm:canonical',
        senderDid: 'did:test:sender',
        senderPeerPersonaId: 'persona:sender',
        serverSequence: 10,
      ),
      const ExactMessageExpectation(
        canonicalId: 'remote-2',
        content: 'run body',
        conversationId: 'dm:canonical',
        senderDid: 'did:test:sender',
        senderPeerPersonaId: 'persona:sender',
        serverSequence: 11,
      ),
    ];

    final actual = requireExactMessageSequence(
      messages: messages,
      expected: expected,
      isRunOwned: (item) => item.content == 'run body',
    );
    expect(actual.map((item) => item.remoteId), <String?>[
      'remote-1',
      'remote-2',
    ]);

    expect(
      () => requireExactMessageSequence(
        messages: <ChatMessage>[messages[0], messages[2], messages[1]],
        expected: expected,
        isRunOwned: (item) => item.content == 'run body',
      ),
      throwsStateError,
      reason: 'Swapping two run-owned messages must fail.',
    );
    expect(
      () => requireExactMessageSequence(
        messages: <ChatMessage>[...messages, messages[1]],
        expected: expected,
        isRunOwned: (item) => item.content == 'run body',
      ),
      throwsStateError,
      reason: 'A duplicate canonical message must fail.',
    );
    expect(
      () => requireExactMessageSequence(
        messages: <ChatMessage>[messages[0], messages[1]],
        expected: expected,
        isRunOwned: (item) => item.content == 'run body',
      ),
      throwsStateError,
      reason: 'A missing run-owned message must fail.',
    );
  });

  test('sequence observation allows distinct ids with the same body', () {
    const body = 'same body run-1';
    final first = message(
      localId: 'local-1',
      remoteId: 'remote-1',
      content: body,
      conversationId: 'dm:1',
      sendState: MessageSendState.sent,
    );
    final second = message(
      localId: 'local-2',
      remoteId: 'remote-2',
      content: body,
      conversationId: 'dm:1',
      sendState: MessageSendState.sent,
    );
    const expected = <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: 'remote-1',
        content: body,
        conversationId: 'dm:1',
      ),
      ExactMessageExpectation(
        canonicalId: 'remote-2',
        content: body,
        conversationId: 'dm:1',
      ),
    ];

    expect(
      observeExactMessageSequence(
        messages: <ChatMessage>[first],
        expected: expected,
        isRunOwned: (item) => item.content == body,
      ).status,
      E2eObservationStatus.pending,
    );
    expect(
      observeExactMessageSequence(
        messages: <ChatMessage>[first, second],
        expected: expected,
        isRunOwned: (item) => item.content == body,
      ).status,
      E2eObservationStatus.pass,
    );
    expect(
      observeExactMessageSequence(
        messages: <ChatMessage>[second, first],
        expected: expected,
        isRunOwned: (item) => item.content == body,
      ).status,
      E2eObservationStatus.fatal,
    );
  });

  test('latest timeline observation allows equal bodies with distinct ids', () {
    final first = message(
      localId: 'local-1',
      remoteId: 'remote-1',
      conversationId: 'dm:canonical',
      content: 'same body',
    );
    final second = message(
      localId: 'local-2',
      remoteId: 'remote-2',
      conversationId: 'dm:canonical',
      content: 'same body',
    );

    final observation = observeConversationLatestInTimeline(
      messages: <ChatMessage>[second, first],
      latestSnapshot: second,
      conversationId: 'dm:canonical',
      expectedText: 'same body',
      expectedMessageId: 'remote-2',
    );

    expect(observation.status, E2eObservationStatus.pass);
  });

  test('latest timeline observation rejects duplicate canonical ids', () {
    final first = message(
      localId: 'local-1',
      remoteId: 'remote-2',
      conversationId: 'dm:canonical',
      content: 'same body',
    );
    final duplicate = message(
      localId: 'local-2',
      remoteId: 'remote-2',
      conversationId: 'dm:canonical',
      content: 'same body',
    );

    final observation = observeConversationLatestInTimeline(
      messages: <ChatMessage>[first, duplicate],
      latestSnapshot: first,
      conversationId: 'dm:canonical',
      expectedText: 'same body',
      expectedMessageId: 'remote-2',
    );

    expect(observation.status, E2eObservationStatus.fatal);
    expect(observation.code, 'duplicate_canonical_timeline_message_id');
  });

  test(
    'message leakage oracle rejects run-owned content in another thread',
    () {
      final target = message(
        localId: 'local-target',
        remoteId: 'remote-target',
        conversationId: 'dm:canonical',
        content: 'run body',
      );
      final leaked = message(
        localId: 'local-leaked',
        remoteId: 'remote-leaked',
        conversationId: 'group:other',
        content: 'run body',
      );

      expect(
        () => requireNoRunOwnedMessageLeakage(
          messages: <ChatMessage>[target],
          targetConversationId: 'dm:canonical',
          isRunOwned: (item) => item.content == 'run body',
        ),
        returnsNormally,
      );
      expect(
        () => requireNoRunOwnedMessageLeakage(
          messages: <ChatMessage>[target, leaked],
          targetConversationId: 'dm:canonical',
          isRunOwned: (item) => item.content == 'run body',
        ),
        throwsStateError,
      );
    },
  );

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

  test('Direct semantic oracle rejects a second row for one Persona', () {
    ConversationSummary direct(String id) => ConversationSummary(
      conversationId: id,
      threadId: id,
      displayName: 'Peer',
      lastMessagePreview: 'hello',
      lastMessageAt: DateTime(2026, 7, 10),
      unreadCount: 1,
      isGroup: false,
      targetDid: 'did:test:peer',
      peerPersonaId: 'persona:test:peer',
    );

    final canonical = direct('dm:peer-scope:v1:canonical');
    expect(
      requireExactlyOneDirectConversationForPersona(
        conversations: <ConversationSummary>[canonical],
        conversationId: canonical.conversationId,
        peerPersonaId: 'persona:test:peer',
        unreadCount: 1,
        lastMessage: 'hello',
      ),
      same(canonical),
    );
    expect(
      () => requireExactlyOneDirectConversationForPersona(
        conversations: <ConversationSummary>[
          canonical,
          direct('dm:legacy-or-other-alias'),
        ],
        conversationId: canonical.conversationId,
        peerPersonaId: 'persona:test:peer',
        unreadCount: 1,
        lastMessage: 'hello',
      ),
      throwsStateError,
    );
  });

  test('Group semantic oracle rejects a second row for one Group DID', () {
    ConversationSummary group(String id) => ConversationSummary(
      conversationId: id,
      threadId: id,
      displayName: 'Group',
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 10),
      unreadCount: 0,
      isGroup: true,
      canonicalGroupDid: 'did:test:group',
      groupId: 'did:test:group',
    );

    final canonical = group('group:did:test:group');
    expect(
      requireExactlyOneGroupConversation(
        conversations: <ConversationSummary>[canonical],
        conversationId: canonical.conversationId,
        canonicalGroupDid: 'did:test:group',
        unreadCount: 0,
      ),
      same(canonical),
    );
    expect(
      () => requireExactlyOneGroupConversation(
        conversations: <ConversationSummary>[
          canonical,
          group('group:duplicate'),
        ],
        conversationId: canonical.conversationId,
        canonicalGroupDid: 'did:test:group',
        unreadCount: 0,
      ),
      throwsStateError,
    );
  });

  test('conversation order oracle rejects duplicates and swapped rows', () {
    ConversationSummary conversation(String id) => ConversationSummary(
      conversationId: id,
      threadId: id,
      displayName: id,
      lastMessagePreview: '',
      lastMessageAt: DateTime(2026, 7, 10),
      unreadCount: 0,
      isGroup: id.startsWith('group:'),
    );

    final direct = conversation('dm:canonical');
    final group = conversation('group:canonical');
    expect(
      () => requireRelativeConversationOrder(
        conversations: <ConversationSummary>[direct, group],
        expectedConversationIds: const <String>[
          'dm:canonical',
          'group:canonical',
        ],
      ),
      returnsNormally,
    );
    expect(
      () => requireRelativeConversationOrder(
        conversations: <ConversationSummary>[group, direct],
        expectedConversationIds: const <String>[
          'dm:canonical',
          'group:canonical',
        ],
      ),
      throwsStateError,
    );
    expect(
      () => requireRelativeConversationOrder(
        conversations: <ConversationSummary>[direct, direct, group],
        expectedConversationIds: const <String>[
          'dm:canonical',
          'group:canonical',
        ],
      ),
      throwsStateError,
    );
  });

  test(
    'App projection order wrapper preserves strict oracle verdict',
    () async {
      ConversationSummary conversation(String id) => ConversationSummary(
        conversationId: id,
        threadId: id,
        displayName: id,
        lastMessagePreview: '',
        lastMessageAt: DateTime(2026, 7, 10),
        unreadCount: 0,
        isGroup: id.startsWith('group:'),
      );

      final direct = conversation('dm:canonical');
      final group = conversation('group:canonical');
      await requireAppProjectionRelativeConversationOrder(
        conversations: <ConversationSummary>[direct, group],
        expectedConversationIds: const <String>[
          'dm:canonical',
          'group:canonical',
        ],
      );
      await expectLater(
        requireAppProjectionRelativeConversationOrder(
          conversations: <ConversationSummary>[group, direct],
          expectedConversationIds: const <String>[
            'dm:canonical',
            'group:canonical',
          ],
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

  testWidgets('conversation row oracle is scoped and rejects stale UI', (
    tester,
  ) async {
    const conversationId = 'dm:canonical';
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: <Widget>[
            KeyedSubtree(
              key: Key('conversation-row:dm:canonical'),
              child: Column(
                children: <Widget>[
                  KeyedSubtree(
                    key: Key('conversation-row-title:dm:canonical'),
                    child: Text('Nickname'),
                  ),
                  KeyedSubtree(
                    key: Key('conversation-row-preview:dm:canonical'),
                    child: Text('latest message'),
                  ),
                ],
              ),
            ),
            Text('stale message'),
          ],
        ),
      ),
    );

    expect(
      () => expectExactConversationRowUi(
        conversationId: conversationId,
        expectedTitle: 'Nickname',
        expectedPreview: 'latest message',
      ),
      returnsNormally,
    );
    expect(
      () => expectExactConversationRowUi(
        conversationId: conversationId,
        expectedTitle: 'Nickname',
        expectedPreview: 'stale message',
      ),
      throwsA(isA<TestFailure>()),
    );
    expect(
      () => expectExactConversationRowUi(
        conversationId: conversationId,
        expectedTitle: 'Wrong title',
        expectedPreview: 'latest message',
      ),
      throwsA(isA<TestFailure>()),
    );
    expect(
      () => expectExactConversationRowUi(
        conversationId: conversationId,
        expectedTitle: 'Nickname',
        expectedPreview: 'latest message',
        expectedUnreadLabel: 'Unread 1',
      ),
      throwsA(isA<TestFailure>()),
      reason: 'A missing positive unread badge must fail.',
    );

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: KeyedSubtree(
          key: Key('conversation-row:dm:canonical'),
          child: Column(
            children: <Widget>[
              KeyedSubtree(
                key: Key('conversation-row-title:dm:canonical'),
                child: Text('Nickname'),
              ),
              KeyedSubtree(
                key: Key('conversation-row-preview:dm:canonical'),
                child: Text('latest message'),
              ),
              KeyedSubtree(
                key: Key('conversation-preview-tag-unread'),
                child: Text('Unread 1'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      () => expectExactConversationRowUi(
        conversationId: conversationId,
        expectedTitle: 'Nickname',
        expectedPreview: 'latest message',
        expectedUnreadLabel: 'Unread 1',
      ),
      returnsNormally,
    );
    expect(
      () => expectExactConversationRowUi(
        conversationId: conversationId,
        expectedTitle: 'Nickname',
        expectedPreview: 'latest message',
      ),
      throwsA(isA<TestFailure>()),
      reason: 'A zero-unread row must reject a stale visible badge.',
    );
    expect(
      () => expectExactConversationRowUi(
        conversationId: conversationId,
        expectedTitle: 'Nickname',
        expectedPreview: 'latest message',
        expectedUnreadLabel: 'Unread 2',
      ),
      throwsA(isA<TestFailure>()),
      reason: 'An unread badge that differs by one must fail.',
    );
  });

  testWidgets('visible conversation order oracle checks row geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: <Widget>[
            SizedBox(key: Key('conversation-row:dm:canonical'), height: 40),
            SizedBox(key: Key('conversation-row:group:canonical'), height: 40),
          ],
        ),
      ),
    );

    expect(
      () => expectVisibleConversationOrder(
        tester: tester,
        conversationIds: const <String>['dm:canonical', 'group:canonical'],
      ),
      returnsNormally,
    );
    expect(
      () => expectVisibleConversationOrder(
        tester: tester,
        conversationIds: const <String>['group:canonical', 'dm:canonical'],
      ),
      throwsStateError,
    );
  });
}
