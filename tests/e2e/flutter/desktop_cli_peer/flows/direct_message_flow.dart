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
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final appToCliText = 'e2e app to cli ${config.runId} $nonce';
  final cliToAppText = 'e2e cli to app ${config.runId} $nonce';
  final cliToAppNextText = 'e2e cli to app next ${config.runId} $nonce';
  final retryText = 'e2e app retry ${config.runId} $nonce';

  final conversation = await robot.startDirectConversation(config.cliHandle);
  final conversationId = conversation.effectiveConversationId;
  final cliDid = conversation.targetDid!.trim();

  // Opening an empty direct chat may be presentation-only until the first
  // message is persisted. Do not require a conversation-list row before the
  // product has created one through the outbound send.
  await robot.sendText(appToCliText);
  final appMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: appToCliText,
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  final appMessageId = appMessage.remoteId!;
  await robot.expectMessageContentVisible(appMessage);
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

  await robot.navigateToContacts();
  final unreadBaseline = robot.container.read(
    conversationListProvider.select((state) => state.unreadCount),
  );
  final cliSentMessageId = await _cliSendDirectText(
    config: config,
    text: cliToAppText,
  );
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: conversationId,
    expectedText: cliToAppText,
    expectedConversationUnread: 1,
    expectedTotalUnread: unreadBaseline + 1,
  );
  final badge = find.byKey(const Key('mac-messages-unread-badge'));
  expect(badge, findsOneWidget);
  expect(
    find.descendant(
      of: badge,
      matching: find.text(_unreadBadgeLabel(unreadBaseline + 1)),
    ),
    findsOneWidget,
  );

  // Restart before opening the conversation so the list itself must restore
  // the exact unread state from the real remote backend. Then open the row
  // through the product UI and prove the read watermark clears it.
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
  await robot.retryFailedText();
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
  expect(restartedConversation.effectiveConversationId, conversationId);
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
      try {
        matched = requireExactlyOneMessage(
          messages: messages,
          content: content,
          messageId: messageId,
          senderDid: senderDid,
          sendState: sendState,
          requireCanonicalRemoteId: requireCanonicalRemoteId,
        );
        return true;
      } on StateError {
        return false;
      }
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
  final selectedConversationId = selected.effectiveConversationId.trim();
  final selectedThreadId = selected.threadId.trim();
  if (requestedId.isEmpty ||
      (selectedConversationId != requestedId &&
          selectedThreadId != requestedId)) {
    throw StateError(
      'Requested UI conversation "$requestedId" does not match selected '
      'conversation "$selectedConversationId" / thread '
      '"$selectedThreadId".',
    );
  }
  final canonical = notifier.thread(requestedId).messages;
  if (canonical.isNotEmpty) {
    return canonical;
  }
  if (selectedThreadId.isNotEmpty && selectedThreadId != requestedId) {
    return notifier.thread(selectedThreadId).messages;
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
      try {
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
      } on StateError {
        return false;
      }
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
      try {
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
      } on StateError {
        return false;
      }
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
