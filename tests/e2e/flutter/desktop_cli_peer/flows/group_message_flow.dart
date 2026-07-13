part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyGroupTextRegression({
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
    conversationId: conversation.effectiveConversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
  );

  final ownerMember = await _findGroupMember(
    groups: groups,
    groupDid: groupDid,
    memberRef: appFullHandle,
  );
  expect(
    _normalizeIdentityRef(ownerMember.did),
    _normalizeIdentityRef(ownerDid),
  );

  await robot.addGroupMember(cliFullHandle);
  await _waitForUiConversationUnread(
    robot: robot,
    conversationId: conversation.effectiveConversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
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
    conversationId: conversation.effectiveConversationId,
    expectedUnread: 0,
    expectedLastMessage: '',
  );
  await robot.openConversationRow(conversation.effectiveConversationId);
  await E2eScenarioProgressWriter.record(
    'group_empty_member_restart_exact_one',
  );

  await robot.sendText(appGroupText);
  final appGroupMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.effectiveConversationId,
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
    suffix: 'e2e app group mention ${config.runId} $nonce',
  );
  final appMention = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.effectiveConversationId,
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
    expectedMentionSurface: appMentionText.split(' ').first,
    expectedMessageId: appMentionId,
    expectedTargetDid: cliMemberDid,
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
  final cliGroupMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.effectiveConversationId,
    content: cliGroupText,
    messageId: cliGroupMessageId,
    senderDid: cliMemberDid,
    sendState: MessageSendState.sent,
  );
  await robot.expectMessageContentVisible(cliGroupMessage);

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
    conversationId: conversation.effectiveConversationId,
    content: cliMentionText,
    messageId: cliMentionId,
    senderDid: cliMemberDid,
    sendState: MessageSendState.sent,
  );
  requireSingleMentionTarget(message: cliMention, targetDid: ownerDid);
  await robot.expectMessageContentVisible(cliMention);

  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: groupThread,
    expectedTexts: <String>[
      appGroupText,
      appMentionText,
      cliGroupText,
      cliMentionText,
    ],
  );

  final recovery = await groups.resumeRebindRecovery();
  expect(recovery.blocked, 0);
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
