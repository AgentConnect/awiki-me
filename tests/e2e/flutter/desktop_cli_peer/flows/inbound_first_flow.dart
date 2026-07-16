part of '../desktop_cli_peer_e2e.dart';

// Catalog case: INBOUND-FIRST-CONV-E2E-001.
Future<void> _verifyInboundFirstDirectRegression({
  required _DesktopAppRobot robot,
  required MessagingService messaging,
  required ConversationService conversations,
  required String ownerDid,
  required AppSession session,
  required AppBootstrap bootstrap,
  required List<Override> providerOverrides,
  required String canonicalCliDid,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final cliDid = requireMatchingCliPeerDid(
    canonicalCliDid: canonicalCliDid,
    observedPeerDid: canonicalCliDid,
  );
  final peerHandles = <String>[
    config.cliHandle,
    '${config.cliHandle}.${config.environment.didDomain}',
  ];

  await robot.navigateToMessages();
  await robot.container.read(conversationListProvider.notifier).refresh();
  requireNoDirectConversationForPeer(
    conversations: await conversations.listConversations(ownerDid: ownerDid),
    peerDid: cliDid,
    peerHandles: peerHandles,
  );
  requireNoDirectConversationForPeer(
    conversations: robot.container.read(conversationListProvider).conversations,
    peerDid: cliDid,
    peerHandles: peerHandles,
  );
  await E2eScenarioProgressWriter.record('inbound_first_no_direct_baseline');

  await robot.navigateToContacts();
  final unreadBaseline = robot.container.read(
    conversationListProvider.select((state) => state.unreadCount),
  );
  final text = 'e2e inbound first ${config.runId} $nonce';
  final messageId = await _cliSendDirectText(config: config, text: text);

  ConversationSummary? inbound;
  E2eObservation observeInboundConversation() {
    final state = robot.container.read(conversationListProvider);
    final matches = state.conversations
        .where(
          (conversation) =>
              !conversation.isGroup &&
              conversation.targetDid?.trim() == cliDid.trim(),
        )
        .toList(growable: false);
    if (matches.isEmpty) {
      return const E2eObservation.pending('inbound_conversation_pending');
    }
    if (matches.length != 1) {
      return const E2eObservation.fatal('inbound_created_duplicate_peer_rows');
    }
    final candidate = matches.single;
    if (!candidate.conversationId.startsWith('dm:peer-scope:v1:') ||
        (candidate.peerPersonaId?.trim().isEmpty ?? true) ||
        candidate.resolutionState !=
            ConversationIdentityResolutionState.resolved) {
      return const E2eObservation.fatal(
        'inbound_conversation_not_canonical_resolved_persona',
      );
    }
    if (candidate.lastMessagePreview != text || candidate.unreadCount != 1) {
      return const E2eObservation.pending('inbound_preview_or_unread_pending');
    }
    if (state.unreadCount != unreadBaseline + 1) {
      return const E2eObservation.pending('inbound_total_unread_pending');
    }
    if (robot.expectedDirectDisplayName(candidate) !=
        _nicknameFixtureDisplayName) {
      return const E2eObservation.fatal(
        'inbound_first_row_did_not_use_peer_nickname',
      );
    }
    try {
      requireExactlyOneDirectConversationForPersona(
        conversations: state.conversations,
        conversationId: candidate.conversationId,
        peerPersonaId: candidate.peerPersonaId!,
        unreadCount: 1,
        lastMessage: text,
      );
    } on StateError {
      return const E2eObservation.fatal(
        'inbound_persona_conversation_not_exact_one',
      );
    }
    inbound = candidate;
    return const E2eObservation.pass();
  }

  await robot.pumpUntilObservation(
    description: 'inbound first canonical Direct projection',
    timeout: const Duration(seconds: 90),
    observe: observeInboundConversation,
  );
  await robot.assertStableFor(
    description: 'inbound first canonical Direct projection',
    observe: observeInboundConversation,
  );
  final conversation = inbound!;
  final conversationId = conversation.conversationId;
  final peerPersonaId = conversation.peerPersonaId!;

  await robot.navigateToMessages();
  await robot.expectConversationRowPresentation(
    conversationId: conversationId,
    expectedTitle: _nicknameFixtureDisplayName,
    expectedPreview: text,
    unreadCount: 1,
  );
  await robot.openConversationRowWithFirstVisibleTitle(
    conversationId: conversationId,
    expectedTitle: _nicknameFixtureDisplayName,
  );
  final received = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: text,
    messageId: messageId,
    senderDid: cliDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageContentVisible(received);
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline,
    expectedLastMessage: text,
  );

  final lookupConversation = await robot.startDirectConversation(
    config.cliHandle,
  );
  expect(lookupConversation.conversationId, conversationId);
  expect(lookupConversation.peerPersonaId, peerPersonaId);
  requireExactlyOneDirectConversationForPersona(
    conversations: robot.container.read(conversationListProvider).conversations,
    conversationId: conversationId,
    peerPersonaId: peerPersonaId,
    unreadCount: 0,
    lastMessage: text,
  );

  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversationId,
    expectedTitle: _nicknameFixtureDisplayName,
    expectedPreview: text,
    unreadCount: 0,
  );
  await robot.openConversationRowWithFirstVisibleTitle(
    conversationId: conversationId,
    expectedTitle: _nicknameFixtureDisplayName,
  );
  final searched = await robot.reopenConversationFromLocalSearch(
    query: _nicknameFixtureDisplayName,
    conversationId: conversationId,
    expectedTitle: _nicknameFixtureDisplayName,
  );
  expect(searched.peerPersonaId, peerPersonaId);

  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: messageId,
        content: text,
        conversationId: conversationId,
        senderDid: cliDid,
      ),
    ],
  );
  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: AppThreadRef.direct(config.cliHandle),
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: messageId,
        content: text,
        conversationId: conversationId,
      ),
    ],
  );
  await _expectCanonicalContactRowsExact(
    robot: robot,
    conversations: conversations,
    ownerDid: ownerDid,
    conversationId: conversationId,
    peerDid: cliDid,
  );
  await _expectSingleCanonicalContactOverlay(
    bootstrap: bootstrap,
    ownerDid: ownerDid,
    conversationId: conversationId,
    peerDid: cliDid,
  );
  await E2eScenarioProgressWriter.record(
    'inbound_first_lookup_recents_search_exact_one',
  );
}
