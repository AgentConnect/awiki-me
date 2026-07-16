part of '../desktop_cli_peer_e2e.dart';

class _DirectRegressionResult {
  const _DirectRegressionResult({
    required this.conversationId,
    required this.peerPersonaId,
    required this.peerDid,
    required this.displayName,
  });

  final String conversationId;
  final String peerPersonaId;
  final String peerDid;
  final String displayName;
}

Future<_DirectRegressionResult> _verifyDirectTextRegression({
  required _DesktopAppRobot robot,
  required _FailOnceMessagingService messaging,
  required ConversationService conversations,
  required AppThreadRef thread,
  required String ownerDid,
  required AppSession session,
  required AppBootstrap bootstrap,
  required List<Override> providerOverrides,
  required String canonicalCliDid,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final appToCliText = 'e2e app to cli ${config.runId} $nonce';
  final cliToAppText = 'e2e cli to app ${config.runId} $nonce';
  final cliToAppNextText = 'e2e cli to app next ${config.runId} $nonce';
  final retryText = 'e2e app retry ${config.runId} $nonce';
  final sameBodyText = 'e2e same body distinct ids ${config.runId} $nonce';

  await E2eScenarioProgressWriter.record('direct_start_conversation');
  final conversation = await robot.startDirectConversation(
    config.cliHandle,
    expectedPrimaryDisplayName: config.expectedCliPeerDisplayName,
  );
  final conversationId = conversation.conversationId;
  expect(
    conversationId.startsWith('dm:peer-scope:v1:'),
    isTrue,
    reason:
        'A handle-resolved Direct conversation must be canonical before the first message arrives.',
  );
  final cliDid = requireMatchingCliPeerDid(
    canonicalCliDid: canonicalCliDid,
    observedPeerDid: conversation.targetDid ?? '',
  );
  final expectedPeerName = robot.expectedDirectDisplayName(conversation);
  expect(expectedPeerName.trim(), isNotEmpty);
  await robot.expectConversationRowPresentation(
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
    expectedPreview: '',
    unreadCount: 0,
  );
  await robot.expectSelectedConversationHeader(expectedPeerName);
  await E2eScenarioProgressWriter.record('direct_canonical_conversation_open');

  final committedEmpty = await conversations.listConversations(
    ownerDid: ownerDid,
  );
  requireExactlyOneDirectConversationForPersona(
    conversations: committedEmpty,
    conversationId: conversationId,
    peerPersonaId: conversation.peerPersonaId!,
    unreadCount: 0,
    lastMessage: '',
  );

  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
  );
  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
  );
  await robot.openConversationRowWithFirstVisibleTitle(
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
  );
  final searchedConversation = await robot.reopenConversationFromLocalSearch(
    query: expectedPeerName,
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
  );
  expect(searchedConversation.peerPersonaId, conversation.peerPersonaId);
  await E2eScenarioProgressWriter.record('direct_empty_restart_exact_one');

  await robot.sendText(appToCliText);
  await E2eScenarioProgressWriter.record('direct_app_send_submitted');
  final appMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: appToCliText,
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  final appMessageId = appMessage.remoteId!;
  await robot.expectMessageContentVisible(appMessage);
  await E2eScenarioProgressWriter.record('direct_app_send_visible');
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedLastMessage: appToCliText,
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
    expectedPreview: appToCliText,
    unreadCount: 0,
  );
  await _waitForCliInbox(
    config: config,
    expectedText: appToCliText,
    expectedMessageId: appMessageId,
    expectedSenderDid: ownerDid,
    expectedReceiverDid: cliDid,
    expectedContentType: 'text/plain',
  );
  await _waitForCliHistory(
    config: config,
    peerHandle: config.appHandle,
    expectedText: appToCliText,
    expectedMessageId: appMessageId,
    expectedSenderDid: ownerDid,
    expectedReceiverDid: cliDid,
    expectedContentType: 'text/plain',
  );
  await E2eScenarioProgressWriter.record('direct_app_send_cli_verified');

  await robot.navigateToContacts();
  final unreadBaseline = robot.container.read(
    conversationListProvider.select((state) => state.unreadCount),
  );
  final cliSentMessageId = await _cliSendDirectText(
    config: config,
    text: cliToAppText,
  );
  await E2eScenarioProgressWriter.record('direct_cli_send_accepted');
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: conversationId,
    expectedText: cliToAppText,
    expectedConversationUnread: 1,
    expectedTotalUnread: unreadBaseline + 1,
  );
  final macOSBadge = find.byKey(const Key('mac-messages-unread-badge'));
  final otherBadge = find.byKey(const Key('mobile-messages-unread-badge'));
  await robot.pumpUntil(
    description: 'global messages unread badge',
    condition: () {
      final macOSCount = macOSBadge.evaluate().length;
      final otherCount = otherBadge.evaluate().length;
      return (macOSCount == 1 && otherCount == 0) ||
          (macOSCount == 0 && otherCount == 1);
    },
  );
  final badgeVariant = requireDesktopPlatformVariant(
    macOSCount: macOSBadge.evaluate().length,
    otherCount: otherBadge.evaluate().length,
    element: 'global messages unread badge',
  );
  final badge = badgeVariant == DesktopPlatformVariant.macOS
      ? macOSBadge
      : otherBadge;
  expect(
    find.descendant(
      of: badge,
      matching: find.text(_unreadBadgeLabel(unreadBaseline + 1)),
    ),
    findsOneWidget,
  );
  await E2eScenarioProgressWriter.record('direct_unread_increment_verified');

  // Restart before opening the conversation so the list itself must restore
  // the exact unread state from the real remote backend. Then open the row
  // through the product UI and prove the read watermark clears it.
  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await E2eScenarioProgressWriter.record('direct_widget_restart_completed');
  await robot.expectConversationUnreadBadge(
    conversationId: conversationId,
    unreadCount: 1,
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
    expectedPreview: cliToAppText,
    unreadCount: 1,
  );
  await robot.openConversationRowWithFirstVisibleTitle(
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
  );
  await robot.expectSelectedConversationHeader(expectedPeerName);
  final received = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: cliToAppText,
    messageId: cliSentMessageId,
    senderDid: cliDid,
    sendState: MessageSendState.sent,
  );
  expect(received.remoteId, cliSentMessageId);
  await robot.expectMessageContentVisible(received);
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline,
  );

  // A second incoming message proves the read watermark does not suppress the
  // next unread increment after the first exact clear.
  await robot.navigateToContacts();
  final nextMessageId = await _cliSendDirectText(
    config: config,
    text: cliToAppNextText,
  );
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: conversationId,
    expectedText: cliToAppNextText,
    expectedConversationUnread: 1,
    expectedTotalUnread: unreadBaseline + 1,
  );
  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await robot.expectConversationUnreadBadge(
    conversationId: conversationId,
    unreadCount: 1,
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
    expectedPreview: cliToAppNextText,
    unreadCount: 1,
  );
  await robot.openConversationRow(conversationId);
  await robot.expectSelectedConversationHeader(expectedPeerName);
  final nextReceived = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: cliToAppNextText,
    messageId: nextMessageId,
    senderDid: cliDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageContentVisible(nextReceived);
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline,
  );

  // The fixture fails one transport attempt and emits a failed local timeline
  // patch. The retry button is the only action that reaches awiki.info.
  messaging.failNextConversationText();
  await robot.sendText(retryText);
  final failed = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: retryText,
    senderDid: ownerDid,
    sendState: MessageSendState.failed,
    requireCanonicalRemoteId: false,
  );
  expect(failed.remoteId, isNull);
  await robot.expectMessageContentVisible(failed);
  final retryAttemptsBefore = messaging.delegatedConversationTextAttempts;
  await robot.retryFailedText();
  await robot.pumpUntil(
    description: 'real retry transport outcome',
    condition: () =>
        messaging.delegatedConversationTextAttempts ==
            retryAttemptsBefore + 1 &&
        !messaging.conversationTextAttemptPending,
  );
  final retryFailureCode = messaging.lastConversationTextFailureCode;
  if (retryFailureCode != null) {
    fail(
      'Real retry transport failed with typed code "$retryFailureCode": '
      '${messaging.lastConversationTextFailureDetail}',
    );
  }
  final retried = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: retryText,
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageContentVisible(retried);
  final retryMessageId = retried.remoteId!;
  await _waitForCliInbox(
    config: config,
    expectedText: retryText,
    expectedMessageId: retryMessageId,
    expectedSenderDid: ownerDid,
    expectedReceiverDid: cliDid,
    expectedContentType: 'text/plain',
  );

  final sameBodyFirstId = await _cliSendDirectText(
    config: config,
    text: sameBodyText,
  );
  await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: sameBodyText,
    messageId: sameBodyFirstId,
    senderDid: cliDid,
    sendState: MessageSendState.sent,
  );
  final sameBodySecondId = await _cliSendDirectText(
    config: config,
    text: sameBodyText,
  );
  List<ChatMessage> sameBodyMessages = const <ChatMessage>[];
  E2eObservation observeSameBodyMessages() {
    final matches = _uiMessages(robot, conversationId)
        .where((message) => message.content == sameBodyText)
        .toList(growable: false);
    if (matches.length < 2) {
      return const E2eObservation.pending('second_same_body_message_pending');
    }
    if (matches.length > 2) {
      return const E2eObservation.fatal('extra_same_body_message');
    }
    final observation = observeExactMessageSequence(
      messages: matches,
      expected: <ExactMessageExpectation>[
        ExactMessageExpectation(
          canonicalId: sameBodyFirstId,
          content: sameBodyText,
          conversationId: conversationId,
          senderDid: cliDid,
        ),
        ExactMessageExpectation(
          canonicalId: sameBodySecondId,
          content: sameBodyText,
          conversationId: conversationId,
          senderDid: cliDid,
        ),
      ],
      isRunOwned: (_) => true,
    );
    if (observation.status != E2eObservationStatus.pass) {
      return observation;
    }
    sameBodyMessages = matches;
    return const E2eObservation.pass();
  }

  await robot.pumpUntilObservation(
    description: 'two distinct canonical messages with the same body',
    timeout: const Duration(seconds: 90),
    observe: observeSameBodyMessages,
    failureLayer: 'app_projection',
  );
  for (final message in sameBodyMessages) {
    await robot.expectMessageContentVisible(message);
  }
  expectVisibleMessageOrder(
    tester: robot.tester,
    localIds: sameBodyMessages.map((message) => message.localId).toList(),
  );
  await robot.assertStableFor(
    description: 'two same-body Direct messages',
    observe: observeSameBodyMessages,
    failureLayer: 'app_projection',
  );
  await E2eScenarioProgressWriter.record(
    'direct_same_body_distinct_ids_verified',
  );

  await robot.simulateReconnect();
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: appMessageId,
        content: appToCliText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: cliSentMessageId,
        content: cliToAppText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: nextMessageId,
        content: cliToAppNextText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: retryMessageId,
        content: retryText,
        conversationId: conversationId,
      ),
    ],
  );

  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  final restartedConversation = await robot.startDirectConversation(
    config.cliHandle,
    expectedPrimaryDisplayName: config.expectedCliPeerDisplayName,
  );
  expect(restartedConversation.conversationId, conversationId);
  expect(
    robot.expectedDirectDisplayName(restartedConversation),
    expectedPeerName,
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversationId,
    expectedTitle: expectedPeerName,
    expectedPreview: sameBodyText,
    unreadCount: 0,
  );
  await robot.expectSelectedConversationHeader(expectedPeerName);
  await robot.pumpUntilObservation(
    description: 'same-body messages after App-shell rebuild',
    timeout: const Duration(seconds: 90),
    observe: observeSameBodyMessages,
    failureLayer: 'app_projection',
  );
  await robot.assertStableFor(
    description: 'same-body messages after App-shell rebuild',
    observe: observeSameBodyMessages,
    failureLayer: 'app_projection',
  );
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: appMessageId,
        content: appToCliText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: cliSentMessageId,
        content: cliToAppText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: nextMessageId,
        content: cliToAppNextText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: retryMessageId,
        content: retryText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: sameBodyFirstId,
        content: sameBodyText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: sameBodySecondId,
        content: sameBodyText,
        conversationId: conversationId,
      ),
    ],
  );

  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: thread,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: appMessageId,
        content: appToCliText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: cliSentMessageId,
        content: cliToAppText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: nextMessageId,
        content: cliToAppNextText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: retryMessageId,
        content: retryText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: sameBodyFirstId,
        content: sameBodyText,
        conversationId: conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: sameBodySecondId,
        content: sameBodyText,
        conversationId: conversationId,
      ),
    ],
  );
  final refreshedConversation = await _waitForAppConversationRefresh(
    conversations: conversations,
    ownerDid: ownerDid,
    expectedText: sameBodyText,
    expectedConversationId: conversationId,
  );
  await _expectCanonicalContactRowsExact(
    robot: robot,
    conversations: conversations,
    ownerDid: ownerDid,
    conversationId: conversationId,
    peerDid: cliDid,
  );
  await _waitForAppConversationLatestInTimeline(
    messaging: messaging,
    conversation: refreshedConversation,
    expectedText: sameBodyText,
    expectedMessageId: sameBodySecondId,
  );
  return _DirectRegressionResult(
    conversationId: conversationId,
    peerPersonaId: conversation.peerPersonaId!,
    peerDid: cliDid,
    displayName: expectedPeerName,
  );
}

Future<String> _cliSendDirectText({
  required _DesktopCliPeerSmokeConfig config,
  required String text,
}) async {
  final result = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--to',
    config.appHandle,
    '--text',
    text,
  ]);
  if (result.exitCode != 0) {
    fail('CLI msg send failed: ${_summarizeCliResult(result)}');
  }
  final messageId = _jsonStringAt(result.stdout, const <Object>[
    'data',
    'message',
    'id',
  ]);
  if (messageId == null) {
    fail('CLI msg send did not return canonical id.');
  }
  return messageId;
}

Future<ChatMessage> _waitForUiMessage({
  required _DesktopAppRobot robot,
  required String conversationId,
  required String content,
  String? messageId,
  String? senderDid,
  MessageSendState? sendState,
  bool requireCanonicalRemoteId = true,
}) async {
  ChatMessage? matched;
  // Fail immediately if the oracle was accidentally pointed at a different
  // selected conversation; polling must never turn that into a fallback.
  _uiMessages(robot, conversationId);
  await robot.pumpUntilObservation(
    description: 'UI timeline exact message "$content"',
    timeout: const Duration(seconds: 90),
    observe: () {
      final messages = _uiMessages(robot, conversationId);
      final bodyMatches = messages
          .where((message) => message.content == content)
          .toList(growable: false);
      if (bodyMatches.isEmpty) {
        return const E2eObservation.pending('message_not_visible');
      }
      if (bodyMatches.length != 1) {
        return const E2eObservation.fatal('duplicate_message_body');
      }
      final candidate = bodyMatches.single;
      final canonicalId = candidate.remoteId ?? candidate.localId;
      if (messageId != null && canonicalId != messageId) {
        final remoteId = candidate.remoteId?.trim() ?? '';
        return remoteId.isEmpty
            ? const E2eObservation.pending('canonical_message_id_pending')
            : const E2eObservation.fatal('wrong_canonical_message_id');
      }
      if (senderDid != null && candidate.senderDid.trim() != senderDid.trim()) {
        return const E2eObservation.fatal('wrong_message_sender');
      }
      if (requireCanonicalRemoteId &&
          (candidate.remoteId?.trim().isEmpty ?? true)) {
        return const E2eObservation.pending('canonical_message_id_pending');
      }
      if (sendState != null && candidate.sendState != sendState) {
        if (sendState == MessageSendState.sent &&
            candidate.sendState == MessageSendState.sending) {
          return const E2eObservation.pending('terminal_send_state_pending');
        }
        return const E2eObservation.fatal('wrong_message_send_state');
      }
      matched = requireExactlyOneMessage(
        messages: messages,
        content: content,
        messageId: messageId,
        senderDid: senderDid,
        sendState: sendState,
        requireCanonicalRemoteId: requireCanonicalRemoteId,
      );
      return const E2eObservation.pass();
    },
  );
  return matched!;
}

List<ChatMessage> _uiMessages(_DesktopAppRobot robot, String conversationId) {
  final notifier = robot.container.read(chatThreadsProvider.notifier);
  final requestedId = conversationId.trim();
  final selected = robot.container.read(selectedConversationProvider);
  if (selected == null) {
    throw StateError(
      'Cannot inspect UI messages for "$requestedId" without a selected '
      'conversation.',
    );
  }
  final selectedConversationId = selected.trim();
  if (requestedId.isEmpty || selectedConversationId != requestedId) {
    throw StateError(
      'Requested UI conversation "$requestedId" does not match selected '
      'conversation "$selectedConversationId".',
    );
  }
  final canonical = notifier.thread(requestedId).messages;
  if (canonical.isNotEmpty) {
    return canonical;
  }
  return canonical;
}

Future<void> _waitForUiUnreadClosedLoop({
  required _DesktopAppRobot robot,
  required String conversationId,
  required String expectedText,
  required int expectedConversationUnread,
  required int expectedTotalUnread,
}) {
  return robot.pumpUntilObservation(
    description:
        'conversation $conversationId unread=$expectedConversationUnread '
        'and total unread=$expectedTotalUnread',
    timeout: const Duration(seconds: 90),
    observe: () {
      final state = robot.container.read(conversationListProvider);
      final observation = _observeConversationProjection(
        conversations: state.conversations,
        conversationId: conversationId,
        expectedUnread: expectedConversationUnread,
        expectedLastMessage: expectedText,
      );
      if (observation.status != E2eObservationStatus.pass) {
        return observation;
      }
      if (state.unreadCount != expectedTotalUnread) {
        return const E2eObservation.pending('total_unread_not_converged');
      }
      return const E2eObservation.pass();
    },
  );
}

Future<void> _waitForUiConversationUnread({
  required _DesktopAppRobot robot,
  required String conversationId,
  required int expectedUnread,
  int? expectedTotalUnread,
  String? expectedLastMessage,
}) {
  return robot.pumpUntilObservation(
    description: 'conversation $conversationId unread=$expectedUnread',
    timeout: const Duration(seconds: 90),
    observe: () {
      final state = robot.container.read(conversationListProvider);
      if (expectedTotalUnread != null) {
        if (state.unreadCount != expectedTotalUnread) {
          return const E2eObservation.pending('total_unread_not_converged');
        }
      }
      return _observeConversationProjection(
        conversations: state.conversations,
        conversationId: conversationId,
        expectedUnread: expectedUnread,
        expectedLastMessage: expectedLastMessage,
      );
    },
  );
}

Future<void> _assertUiMessagesExactlyOnce({
  required _DesktopAppRobot robot,
  required String conversationId,
  required List<ExactMessageExpectation> expected,
}) async {
  final runOwnedContents = expected.map((item) => item.content).toSet();
  E2eObservation observeExactSequence() {
    final stable = _uiMessages(robot, conversationId);
    final sequence = observeExactMessageSequence(
      messages: stable,
      expected: expected,
      isRunOwned: (message) => runOwnedContents.contains(message.content),
    );
    if (sequence.status != E2eObservationStatus.pass) {
      return sequence;
    }
    try {
      requireNoRunOwnedMessageLeakage(
        messages: robot.container
            .read(chatThreadsProvider)
            .values
            .expand((thread) => thread.messages),
        targetConversationId: conversationId,
        isRunOwned: (message) => runOwnedContents.contains(message.content),
      );
    } on StateError {
      return const E2eObservation.fatal('message_leakage');
    }
    return const E2eObservation.pass();
  }

  await robot.pumpUntilObservation(
    description: 'run-owned direct message sequence',
    timeout: const Duration(seconds: 90),
    observe: observeExactSequence,
  );
  final actualMessages = requireExactMessageSequence(
    messages: _uiMessages(robot, conversationId),
    expected: expected,
    isRunOwned: (message) => runOwnedContents.contains(message.content),
  );
  for (final message in actualMessages) {
    await robot.expectMessageContentVisible(message);
  }
  expectVisibleMessageOrder(
    tester: robot.tester,
    localIds: actualMessages.map((message) => message.localId).toList(),
  );
  await robot.assertStableFor(
    description: 'run-owned direct message sequence',
    observe: observeExactSequence,
  );
}

E2eObservation _observeConversationProjection({
  required Iterable<ConversationSummary> conversations,
  required String conversationId,
  required int expectedUnread,
  String? expectedLastMessage,
}) {
  final rows = conversations.toList(growable: false);
  final canonicalMatches = rows
      .where((item) => item.conversationId.trim() == conversationId.trim())
      .toList(growable: false);
  if (canonicalMatches.isEmpty) {
    return const E2eObservation.pending('canonical_conversation_missing');
  }
  if (canonicalMatches.length != 1) {
    return const E2eObservation.fatal('duplicate_canonical_conversation');
  }
  final conversation = canonicalMatches.single;
  if (conversation.isGroup) {
    final groupDid = conversation.canonicalGroupDid?.trim() ?? '';
    if (groupDid.isEmpty) {
      return const E2eObservation.fatal('resolved_group_identity_missing');
    }
    final semanticCount = rows
        .where(
          (item) => item.isGroup && item.canonicalGroupDid?.trim() == groupDid,
        )
        .length;
    if (semanticCount != 1) {
      return const E2eObservation.fatal('duplicate_group_conversation');
    }
  } else {
    final personaId = conversation.peerPersonaId?.trim() ?? '';
    if (personaId.isEmpty) {
      return const E2eObservation.fatal('resolved_peer_persona_missing');
    }
    final semanticCount = rows
        .where(
          (item) =>
              !item.isGroup &&
              item.resolutionState ==
                  ConversationIdentityResolutionState.resolved &&
              item.peerPersonaId?.trim() == personaId,
        )
        .length;
    if (semanticCount != 1) {
      return const E2eObservation.fatal('duplicate_persona_conversation');
    }
  }
  if (conversation.unreadCount != expectedUnread) {
    return const E2eObservation.pending('conversation_unread_not_converged');
  }
  if (expectedLastMessage != null &&
      conversation.lastMessagePreview.trim() != expectedLastMessage.trim()) {
    return const E2eObservation.pending('conversation_preview_not_converged');
  }
  return const E2eObservation.pass();
}

String _unreadBadgeLabel(int count) => count > 99 ? '99+' : '$count';
