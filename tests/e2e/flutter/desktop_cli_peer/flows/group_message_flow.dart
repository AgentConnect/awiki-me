part of '../desktop_cli_peer_e2e.dart';

class _GroupRegressionResult {
  const _GroupRegressionResult({
    required this.conversationId,
    required this.groupDid,
    required this.groupName,
    required this.cliMemberDid,
    required this.cliMemberDisplayName,
    required this.cliMessageId,
    required this.cliMessageText,
  });

  final String conversationId;
  final String groupDid;
  final String groupName;
  final String cliMemberDid;
  final String cliMemberDisplayName;
  final String cliMessageId;
  final String cliMessageText;
}

Future<_GroupRegressionResult> _verifyGroupTextRegression({
  required _DesktopAppRobot robot,
  required GroupApplicationService groups,
  required MessagingService messaging,
  required AppSession session,
  required AppBootstrap bootstrap,
  required List<Override> providerOverrides,
  required String ownerDid,
  required String canonicalCliDid,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final appFullHandle = groupHandleForDid(
    handle: config.appHandle,
    did: ownerDid,
  );
  if (appFullHandle == null) {
    fail('App Handle cannot be qualified from its authenticated DID.');
  }
  final cliHandle = config.cliHandle.trim().toLowerCase();
  final cliFullHandle = cliHandle.contains('.')
      ? cliHandle
      : '$cliHandle.${config.environment.didDomain}';
  final groupName = 'AWiki E2E ${config.runId} $nonce';
  final conversation = await robot.createGroup(groupName);
  final groupDid = conversation.groupId!.trim();
  expect(groupDid, isNotEmpty);
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversation.conversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversation.conversationId,
    expectedTitle: groupName,
    expectedPreview: '',
    unreadCount: 0,
  );
  await robot.expectSelectedConversationHeader(groupName);

  final ownerMember = await _findGroupMember(
    groups: groups,
    groupDid: groupDid,
    memberRef: appFullHandle,
  );
  expect(
    _normalizeIdentityRef(ownerMember.did),
    _normalizeIdentityRef(ownerDid),
  );

  await robot.addGroupMember(
    cliFullHandle,
    expectedDisplayName: config.expectedCliPeerDisplayName,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversation.conversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversation.conversationId,
    expectedTitle: groupName,
    expectedPreview: '',
    unreadCount: 0,
  );
  final cliMember = await _findGroupMember(
    groups: groups,
    groupDid: groupDid,
    memberRef: cliFullHandle,
  );
  final cliMemberDid = requireMatchingCliPeerDid(
    canonicalCliDid: canonicalCliDid,
    observedPeerDid: cliMember.did,
  );
  final cliProfile = robot.container
      .read(peerDisplayProfileProvider)
      .forDid(cliMemberDid);
  final expectedCliMemberName = config.expectedCliPeerDisplayName;
  if (!config.e2eCase.runsDisplayNameFallback) {
    final cliMemberNickname = cliProfile?.displayName?.trim() ?? '';
    final compactCliDid = PeerDisplayNameResolver.compactDid(cliMemberDid);
    if (cliMemberNickname.isEmpty ||
        cliMemberNickname.startsWith('did:') ||
        cliMemberNickname == compactCliDid ||
        cliMemberNickname != expectedCliMemberName) {
      fail(
        'The remote group display-name fixture must expose the exact nickname '
        'configured for the product-name oracle.',
      );
    }
  } else if (expectedCliMemberName != cliFullHandle) {
    fail('The Handle fallback oracle must use the exact full Handle.');
  }
  await robot.expectGroupMemberDisplayName(
    member: cliMember,
    expectedName: expectedCliMemberName,
  );
  await robot.expectMemberAddedSystemEvent(
    conversationId: conversation.conversationId,
    subjectDid: cliMemberDid,
    expectedMemberName: expectedCliMemberName,
  );

  final appGroupText = 'e2e app group ${config.runId} $nonce';
  final cliGroupText = 'e2e cli group ${config.runId} $nonce';
  final groupThread = AppThreadRef.group(groupDid);

  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversation.conversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
  );
  await robot.openConversationRow(conversation.conversationId);
  await robot.expectSelectedConversationHeader(groupName);
  await E2eScenarioProgressWriter.record(
    'group_empty_member_restart_exact_one',
  );

  await robot.sendText(appGroupText);
  final appGroupMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.conversationId,
    content: appGroupText,
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  final appGroupMessageId = appGroupMessage.remoteId!;
  expect(appGroupMessage.groupId, groupDid);
  await robot.expectMessageContentVisible(appGroupMessage);
  await _waitForGroupMessages(
    groups: groups,
    groupDid: groupDid,
    expectedText: appGroupText,
    expectedMessageId: appGroupMessageId,
  );
  await _waitForCliGroupMessages(
    config: config,
    groupDid: groupDid,
    expectedText: appGroupText,
    expectedMessageId: appGroupMessageId,
    expectedSenderDid: ownerDid,
    expectedContentType: 'text/plain',
  );

  final appMentionText = await robot.sendMention(
    handle: config.cliHandle,
    expectedDid: cliMemberDid,
    expectedDisplayName: expectedCliMemberName,
    suffix: 'e2e app group mention ${config.runId} $nonce',
  );
  final appMention = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.conversationId,
    content: appMentionText,
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  requireSingleMentionTarget(message: appMention, targetDid: cliMemberDid);
  final appMentionId = appMention.remoteId!;
  await robot.expectMessageContentVisible(appMention);
  await _waitForCliGroupMessages(
    config: config,
    groupDid: groupDid,
    expectedText: appMentionText,
    expectedMessageId: appMentionId,
    expectedSenderDid: ownerDid,
    expectedContentType: 'application/json',
  );
  await _waitForCliMentionMetadata(
    config: config,
    groupDid: groupDid,
    expectedText: appMentionText,
    expectedMentionSurface: '@$expectedCliMemberName',
    expectedMessageId: appMentionId,
    expectedTargetDid: cliMemberDid,
  );

  await robot.navigateToContacts();
  final groupUnreadBaseline = robot.container.read(
    conversationListProvider.select((state) => state.unreadCount),
  );

  final cliGroupSend = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--group',
    groupDid,
    '--text',
    cliGroupText,
  ]);
  if (cliGroupSend.exitCode != 0) {
    fail('CLI group msg send failed: ${_summarizeCliResult(cliGroupSend)}');
  }
  final cliGroupMessageId = _jsonStringAt(cliGroupSend.stdout, const <Object>[
    'data',
    'message',
    'id',
  ]);
  if (cliGroupMessageId == null) {
    fail('CLI group send did not return canonical message id.');
  }
  await _waitForUiUnreadClosedLoop(
    robot: robot,
    conversationId: conversation.conversationId,
    expectedText: cliGroupText,
    expectedConversationUnread: 1,
    expectedTotalUnread: groupUnreadBaseline + 1,
  );
  await robot.restart(
    bootstrap: bootstrap,
    providerOverrides: providerOverrides,
    session: session,
  );
  await robot.expectConversationRowPresentation(
    conversationId: conversation.conversationId,
    expectedTitle: groupName,
    expectedPreview: cliGroupText,
    unreadCount: 1,
  );
  await robot.openConversationRow(conversation.conversationId);
  await robot.expectSelectedConversationHeader(groupName);
  final cliGroupMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.conversationId,
    content: cliGroupText,
    messageId: cliGroupMessageId,
    senderDid: cliMemberDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageContentVisible(cliGroupMessage);
  await robot.expectMessageSenderIdentityProjection(
    conversationId: conversation.conversationId,
    message: cliGroupMessage,
    expectedName: expectedCliMemberName,
  );
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversation.conversationId,
    expectedUnread: 0,
    expectedTotalUnread: groupUnreadBaseline,
    expectedLastMessage: cliGroupText,
  );

  final cliMentionSurface = '@${config.appHandle}';
  final cliMentionText =
      '$cliMentionSurface e2e cli group mention ${config.runId} $nonce';
  final cliMentionPayload = jsonEncode(<String, Object?>{
    'text': cliMentionText,
    'mentions': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'men-app-${config.runId}-$nonce',
        'range': <String, Object?>{
          'start': 0,
          'end': cliMentionSurface.runes.length,
          'unit': 'unicode_code_point',
        },
        'target': <String, Object?>{'kind': 'human', 'did': ownerDid},
        'mention_role': 'addressee',
      },
    ],
  });
  final cliMentionSend = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--group',
    groupDid,
    '--payload',
    cliMentionPayload,
    '--client-message-id',
    'msg-cli-mention-${config.runId}-$nonce',
    '--idempotency-key',
    'op-cli-mention-${config.runId}-$nonce',
  ]);
  if (cliMentionSend.exitCode != 0) {
    fail(
      'CLI structured group mention failed: '
      '${_summarizeCliResult(cliMentionSend)}',
    );
  }
  final cliMentionId = _jsonStringAt(cliMentionSend.stdout, const <Object>[
    'data',
    'message',
    'id',
  ]);
  final cliMentionType = _jsonStringAt(cliMentionSend.stdout, const <Object>[
    'data',
    'message',
    'type',
  ]);
  if (cliMentionId == null) {
    fail('CLI structured group mention returned no canonical message id.');
  }
  if (cliMentionType != 'application/json') {
    fail(
      'CLI structured group mention did not return the exact '
      'application/json message type.',
    );
  }
  final cliMention = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.conversationId,
    content: cliMentionText,
    messageId: cliMentionId,
    senderDid: cliMemberDid,
    sendState: MessageSendState.sent,
  );
  requireSingleMentionTarget(message: cliMention, targetDid: ownerDid);
  await robot.expectMessageContentVisible(cliMention);

  await _assertUiMessagesExactlyOnce(
    robot: robot,
    conversationId: conversation.conversationId,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: appGroupMessageId,
        content: appGroupText,
        conversationId: conversation.conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: appMentionId,
        content: appMentionText,
        conversationId: conversation.conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: cliGroupMessageId,
        content: cliGroupText,
        conversationId: conversation.conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: cliMentionId,
        content: cliMentionText,
        conversationId: conversation.conversationId,
      ),
    ],
  );

  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: groupThread,
    expected: <ExactMessageExpectation>[
      ExactMessageExpectation(
        canonicalId: appGroupMessageId,
        content: appGroupText,
        conversationId: conversation.conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: appMentionId,
        content: appMentionText,
        conversationId: conversation.conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: cliGroupMessageId,
        content: cliGroupText,
        conversationId: conversation.conversationId,
      ),
      ExactMessageExpectation(
        canonicalId: cliMentionId,
        content: cliMentionText,
        conversationId: conversation.conversationId,
      ),
    ],
  );

  final recovery = await groups.resumeRebindRecovery();
  expect(recovery.blocked, 0);
  return _GroupRegressionResult(
    conversationId: conversation.conversationId,
    groupDid: groupDid,
    groupName: groupName,
    cliMemberDid: cliMemberDid,
    cliMemberDisplayName: expectedCliMemberName,
    cliMessageId: cliGroupMessageId,
    cliMessageText: cliGroupText,
  );
}

Future<GroupMemberSummary> _findGroupMember({
  required GroupApplicationService groups,
  required String groupDid,
  required String memberRef,
}) async {
  GroupMemberSummary? matched;
  await _poll(
    description: 'Group contains exactly one member "$memberRef"',
    action: () async {
      final members = await groups.listMembers(groupDid, limit: 50);
      final normalizedRef = _normalizeIdentityRef(memberRef);
      final exact = members
          .where((member) {
            final did = _normalizeIdentityRef(member.did);
            final handle = _normalizeIdentityRef(member.handle);
            return did == normalizedRef || handle == normalizedRef;
          })
          .toList(growable: false);
      if (exact.length != 1 || exact.single.did.trim().isEmpty) {
        return false;
      }
      matched = exact.single;
      return true;
    },
  );
  return matched!;
}

Future<void> _waitForCliMentionMetadata({
  required _DesktopCliPeerSmokeConfig config,
  required String groupDid,
  required String expectedText,
  required String expectedMentionSurface,
  required String expectedMessageId,
  required String expectedTargetDid,
}) async {
  await _poll(
    description:
        'CLI group history preserves mention target $expectedTargetDid',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'group',
        'messages',
        '--group',
        groupDid,
        '--limit',
        '50',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      final matches = cliMessagesWithExactText(
        result.stdout,
        expectedText: expectedText,
        expectedMessageId: expectedMessageId,
      );
      if (matches.length != 1) {
        return false;
      }
      return cliMessageHasExactSingleMention(
        message: matches.single,
        expectedText: expectedText,
        expectedMentionSurface: expectedMentionSurface,
        expectedTargetDid: expectedTargetDid,
        expectedTargetKind: 'human',
        expectedMentionRole: 'addressee',
        expectedRangeUnit: 'unicode_code_point',
      );
    },
  );
}
