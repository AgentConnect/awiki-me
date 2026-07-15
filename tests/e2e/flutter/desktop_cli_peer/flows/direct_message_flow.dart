part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyDirectTextRegression({
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

  await E2eScenarioProgressWriter.record('direct_start_conversation');
  final conversation = await robot.startDirectConversation(config.cliHandle);
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
  await E2eScenarioProgressWriter.record('direct_canonical_conversation_open');

  final committedEmpty = await conversations.listConversations(
    ownerDid: ownerDid,
  );
  requireExactlyOneConversation(
    conversations: committedEmpty,
    conversationId: conversationId,
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
  await robot.openConversationRow(conversationId);
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
  await robot.openConversationRow(conversationId);
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
  await robot.openConversationRow(conversationId);
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

  await robot.simulateReconnect();
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <String, String>{
      appToCliText: appMessageId,
      cliToAppText: cliSentMessageId,
      cliToAppNextText: nextMessageId,
      retryText: retryMessageId,
    },
  );

  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  final restartedConversation = await robot.startDirectConversation(
    config.cliHandle,
  );
  expect(restartedConversation.conversationId, conversationId);
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversationId,
    expected: <String, String>{
      appToCliText: appMessageId,
      cliToAppText: cliSentMessageId,
      cliToAppNextText: nextMessageId,
      retryText: retryMessageId,
    },
  );

  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: thread,
    expectedTexts: <String>[
      appToCliText,
      cliToAppText,
      cliToAppNextText,
      retryText,
    ],
  );
  final refreshedConversation = await _waitForAppConversationRefresh(
    conversations: conversations,
    ownerDid: ownerDid,
    expectedText: retryText,
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
    expectedText: retryText,
    expectedMessageId: retryMessageId,
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
  await robot.pumpUntil(
    description: 'UI timeline exact message "$content"',
    timeout: const Duration(seconds: 90),
    condition: () {
      final messages = _uiMessages(robot, conversationId);
      matched = requireExactlyOneMessage(
        messages: messages,
        content: content,
        messageId: messageId,
        senderDid: senderDid,
        sendState: sendState,
        requireCanonicalRemoteId: requireCanonicalRemoteId,
      );
      return true;
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
  return robot.pumpUntil(
    description:
        'conversation $conversationId unread=$expectedConversationUnread '
        'and total unread=$expectedTotalUnread',
    timeout: const Duration(seconds: 90),
    condition: () {
      final state = robot.container.read(conversationListProvider);
      requireUnreadTotal(
        actual: state.unreadCount,
        expected: expectedTotalUnread,
      );
      requireExactlyOneConversation(
        conversations: state.conversations,
        conversationId: conversationId,
        unreadCount: expectedConversationUnread,
        lastMessage: expectedText,
      );
      return true;
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
  return robot.pumpUntil(
    description: 'conversation $conversationId unread=$expectedUnread',
    timeout: const Duration(seconds: 90),
    condition: () {
      final state = robot.container.read(conversationListProvider);
      if (expectedTotalUnread != null) {
        requireUnreadTotal(
          actual: state.unreadCount,
          expected: expectedTotalUnread,
        );
      }
      requireExactlyOneConversation(
        conversations: state.conversations,
        conversationId: conversationId,
        unreadCount: expectedUnread,
        lastMessage: expectedLastMessage,
      );
      return true;
    },
  );
}

Future<void> _assertUiMessagesExactlyOnce({
  required _DesktopAppRobot robot,
  required String conversationId,
  required Map<String, String> expected,
}) async {
  for (final entry in expected.entries) {
    final message = await _waitForUiMessage(
      robot: robot,
      conversationId: conversationId,
      content: entry.key,
      messageId: entry.value,
      sendState: MessageSendState.sent,
    );
    await robot.expectMessageContentVisible(message);
  }
  await robot.tester.pump(const Duration(seconds: 2));
  final stable = _uiMessages(robot, conversationId);
  for (final entry in expected.entries) {
    requireExactlyOneMessage(
      messages: stable,
      content: entry.key,
      messageId: entry.value,
      sendState: MessageSendState.sent,
    );
  }
}

String _unreadBadgeLabel(int count) => count > 99 ? '99+' : '$count';
