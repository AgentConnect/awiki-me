part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyCrossConversationCorrectness({
  required _DesktopAppRobot robot,
  required MessagingService messaging,
  required AppSession session,
  required AppBootstrap bootstrap,
  required List<Override> providerOverrides,
  required _DirectRegressionResult direct,
  required _GroupRegressionResult group,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  if (direct.displayName != config.expectedCliPeerDisplayName ||
      group.cliMemberDisplayName != config.expectedCliPeerDisplayName ||
      direct.peerDid != group.cliMemberDid) {
    fail(
      'The same peer must use one nickname projection across identity lookup, '
      'Direct, Contacts, group members, system events, and group senders.',
    );
  }

  final directFirstText = 'e2e multi direct first ${config.runId} $nonce';
  final groupText = 'e2e multi group ${config.runId} $nonce';
  final directSecondText = 'e2e multi direct second ${config.runId} $nonce';

  robot.failureCaseId = 'UNREAD-MULTI-E2E-001';
  await robot.navigateToContacts();
  final unreadBaseline = robot.container.read(
    conversationListProvider.select((state) => state.unreadCount),
  );

  final directFirstId = await _cliSendDirectText(
    config: config,
    text: directFirstText,
  );
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: direct.conversationId,
    expectedText: directFirstText,
    expectedConversationUnread: 1,
    expectedTotalUnread: unreadBaseline + 1,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: group.conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline + 1,
  );
  await requireAppProjectionRelativeConversationOrder(
    conversations: robot.container.read(conversationListProvider).conversations,
    expectedConversationIds: <String>[
      direct.conversationId,
      group.conversationId,
    ],
    caseId: 'CONV-LIST-E2E-001',
  );

  final groupSend = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--group',
    group.groupDid,
    '--text',
    groupText,
  ]);
  if (groupSend.exitCode != 0) {
    fail(
      'CLI multi-conversation group send failed: '
      '${_summarizeCliResult(groupSend)}',
    );
  }
  final groupMessageId = _jsonStringAt(groupSend.stdout, const <Object>[
    'data',
    'message',
    'id',
  ]);
  if (groupMessageId == null) {
    fail('CLI multi-conversation group send returned no canonical id.');
  }
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: group.conversationId,
    expectedText: groupText,
    expectedConversationUnread: 1,
    expectedTotalUnread: unreadBaseline + 2,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: direct.conversationId,
    expectedUnread: 1,
    expectedTotalUnread: unreadBaseline + 2,
    expectedLastMessage: directFirstText,
  );
  await requireAppProjectionRelativeConversationOrder(
    conversations: robot.container.read(conversationListProvider).conversations,
    expectedConversationIds: <String>[
      group.conversationId,
      direct.conversationId,
    ],
    caseId: 'CONV-LIST-E2E-001',
  );

  final directSecondId = await _cliSendDirectText(
    config: config,
    text: directSecondText,
  );
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: direct.conversationId,
    expectedText: directSecondText,
    expectedConversationUnread: 2,
    expectedTotalUnread: unreadBaseline + 3,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: group.conversationId,
    expectedUnread: 1,
    expectedTotalUnread: unreadBaseline + 3,
    expectedLastMessage: groupText,
  );
  await requireAppProjectionRelativeConversationOrder(
    conversations: robot.container.read(conversationListProvider).conversations,
    expectedConversationIds: <String>[
      direct.conversationId,
      group.conversationId,
    ],
    caseId: 'CONV-LIST-E2E-001',
  );

  robot.failureCaseId = 'CONV-LIST-E2E-001';
  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await robot.expectConversationRowPresentation(
    conversationId: direct.conversationId,
    expectedTitle: direct.displayName,
    expectedPreview: directSecondText,
    unreadCount: 2,
  );
  await robot.expectConversationRowPresentation(
    conversationId: group.conversationId,
    expectedTitle: group.groupName,
    expectedPreview: groupText,
    unreadCount: 1,
  );
  await robot.expectConversationRowsInOrder(<String>[
    direct.conversationId,
    group.conversationId,
  ]);

  robot.failureCaseId = 'DISPLAY-NAME-E2E-001';
  await robot.openConversationRow(group.conversationId);
  await robot.expectSelectedConversationHeader(group.groupName);
  final visibleGroupMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: group.conversationId,
    content: groupText,
    messageId: groupMessageId,
    senderDid: group.cliMemberDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageContentVisible(visibleGroupMessage);
  await robot.expectMessageSenderIdentityProjection(
    conversationId: group.conversationId,
    message: visibleGroupMessage,
    expectedName: group.cliMemberDisplayName,
  );
  robot.failureCaseId = 'MSG-SEQUENCE-E2E-001';
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: group.conversationId,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: groupMessageId,
        content: groupText,
        conversationId: group.conversationId,
        senderDid: group.cliMemberDid,
      ),
    ],
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: group.conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline + 2,
    expectedLastMessage: groupText,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: direct.conversationId,
    expectedUnread: 2,
    expectedTotalUnread: unreadBaseline + 2,
    expectedLastMessage: directSecondText,
  );

  await robot.openConversationRow(direct.conversationId);
  await robot.expectSelectedConversationHeader(direct.displayName);
  robot.failureCaseId = 'MSG-SEQUENCE-E2E-001';
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: direct.conversationId,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: directFirstId,
        content: directFirstText,
        conversationId: direct.conversationId,
        senderDid: direct.peerDid,
      ),
      ExactMessageExpectation(
        canonicalId: directSecondId,
        content: directSecondText,
        conversationId: direct.conversationId,
        senderDid: direct.peerDid,
      ),
    ],
  );
  robot.failureCaseId = 'UNREAD-MULTI-E2E-001';
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: direct.conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline,
    expectedLastMessage: directSecondText,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: group.conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline,
    expectedLastMessage: groupText,
  );

  robot.failureCaseId = 'MSG-SEQUENCE-E2E-001';
  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: AppThreadRef.direct(config.cliHandle),
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: directFirstId,
        content: directFirstText,
        conversationId: direct.conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: directSecondId,
        content: directSecondText,
        conversationId: direct.conversationId,
      ),
    ],
  );
  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: AppThreadRef.group(group.groupDid),
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: groupMessageId,
        content: groupText,
        conversationId: group.conversationId,
      ),
    ],
  );

  robot.failureCaseId = 'UNREAD-MULTI-E2E-001';
  E2eObservation observeStableClearedState() {
    final state = robot.container.read(conversationListProvider);
    if (state.unreadCount != unreadBaseline) {
      return const E2eObservation.fatal('multi_unread_total_rebounded');
    }
    try {
      requireExactlyOneDirectConversationForPersona(
        conversations: state.conversations,
        conversationId: direct.conversationId,
        peerPersonaId: direct.peerPersonaId,
        unreadCount: 0,
        lastMessage: directSecondText,
      );
      requireExactlyOneGroupConversation(
        conversations: state.conversations,
        conversationId: group.conversationId,
        canonicalGroupDid: group.groupDid,
        unreadCount: 0,
        lastMessage: groupText,
      );
      requireRelativeConversationOrder(
        conversations: state.conversations,
        expectedConversationIds: <String>[
          direct.conversationId,
          group.conversationId,
        ],
      );
    } on StateError {
      return const E2eObservation.fatal(
        'multi_conversation_projection_became_unstable',
      );
    }
    return const E2eObservation.pass();
  }

  await robot.assertStableFor(
    description: 'multi-conversation ordering, unread, and canonical identity',
    observe: observeStableClearedState,
  );

  final burstTexts = List<String>.generate(
    3,
    (index) => 'e2e hidden burst ${index + 1} ${config.runId} $nonce',
    growable: false,
  );
  final burstIds = <String>[];
  robot.failureCaseId = 'MSG-SEQUENCE-E2E-001';
  await robot.openConversationRow(group.conversationId);
  await robot.navigateToContacts();
  await robot.enterHiddenLifecycle();
  for (final text in burstTexts) {
    burstIds.add(await _cliSendDirectText(config: config, text: text));
  }
  await robot.resumeFromHiddenLifecycle();
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: direct.conversationId,
    expectedText: burstTexts.last,
    expectedConversationUnread: burstTexts.length,
    expectedTotalUnread: unreadBaseline + burstTexts.length,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: group.conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline + burstTexts.length,
    expectedLastMessage: groupText,
  );
  await robot.navigateToMessages();
  await robot.expectConversationRowPresentation(
    conversationId: direct.conversationId,
    expectedTitle: direct.displayName,
    expectedPreview: burstTexts.last,
    unreadCount: burstTexts.length,
  );

  await robot.openConversationRow(direct.conversationId);
  final burstExpected = List<ExactMessageExpectation>.generate(
    burstTexts.length,
    (index) => ExactMessageExpectation(
      canonicalId: burstIds[index],
      content: burstTexts[index],
      conversationId: direct.conversationId,
      senderDid: direct.peerDid,
    ),
    growable: false,
  );
  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: direct.conversationId,
    expected: burstExpected,
  );
  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: AppThreadRef.direct(config.cliHandle),
    expected: burstExpected,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: direct.conversationId,
    expectedUnread: 0,
    expectedTotalUnread: unreadBaseline,
    expectedLastMessage: burstTexts.last,
  );
  await robot.expectConversationUnreadBadge(
    conversationId: direct.conversationId,
    unreadCount: 0,
  );
  await robot.assertStableFor(
    description: 'hidden burst order and read state remain stable',
    observe: () {
      final state = robot.container.read(conversationListProvider);
      if (state.unreadCount != unreadBaseline) {
        return const E2eObservation.fatal(
          'hidden_burst_total_unread_rebounded',
        );
      }
      try {
        requireExactlyOneDirectConversationForPersona(
          conversations: state.conversations,
          conversationId: direct.conversationId,
          peerPersonaId: direct.peerPersonaId,
          unreadCount: 0,
          lastMessage: burstTexts.last,
        );
      } on StateError {
        return const E2eObservation.fatal(
          'hidden_burst_conversation_became_unstable',
        );
      }
      return const E2eObservation.pass();
    },
  );
  await E2eScenarioProgressWriter.record(
    'cross_conversation_and_hidden_burst_sequence_verified',
  );
  robot.failureCaseId = null;
}
