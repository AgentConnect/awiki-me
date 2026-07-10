part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyGroupTextRegression({
  required _DesktopAppRobot robot,
  required GroupApplicationService groups,
  required MessagingService messaging,
  required String ownerDid,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final groupName = 'AWiki E2E ${config.runId} $nonce';
  final conversation = await robot.createGroup(groupName);
  final groupDid = conversation.groupId!.trim();
  expect(groupDid, isNotEmpty);

  await robot.addGroupMember(config.cliHandle);
  final cliMember = await _findGroupMember(
    groups: groups,
    groupDid: groupDid,
    memberRef: config.cliHandle,
  );
  expect(cliMember.did.trim(), isNotEmpty);

  final appGroupText = 'e2e app group ${config.runId} $nonce';
  final cliGroupText = 'e2e cli group ${config.runId} $nonce';
  final groupThread = AppThreadRef.group(groupDid);

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
  expect(find.text(appGroupText), findsOneWidget);
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
  requireSingleMentionTarget(message: appMention, targetDid: cliMember.did);
  final appMentionId = appMention.remoteId!;
  expect(find.text(appMentionText, findRichText: true), findsOneWidget);
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
    expectedMessageId: appMentionId,
    expectedTargetDid: cliMember.did,
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
  await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.effectiveConversationId,
    content: cliGroupText,
    messageId: cliGroupMessageId,
    senderDid: cliMember.did,
    sendState: MessageSendState.sent,
  );
  expect(find.text(cliGroupText), findsOneWidget);

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
  if (cliMentionId == null) {
    fail('CLI structured group mention returned no canonical message id.');
  }
  final cliMention = await _waitForUiMessage(
    robot: robot,
    conversationId: conversation.effectiveConversationId,
    content: cliMentionText,
    messageId: cliMentionId,
    senderDid: cliMember.did,
    sendState: MessageSendState.sent,
  );
  requireSingleMentionTarget(message: cliMention, targetDid: ownerDid);
  expect(find.text(cliMentionText, findRichText: true), findsOneWidget);

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
      final matches = _cliMessagesWithExactText(
        result.stdout,
        expectedText,
        expectedMessageId: expectedMessageId,
      );
      if (matches.length != 1) {
        return false;
      }
      final payload = _cliMessagePayload(matches.single);
      final mentions = payload?['mentions'];
      if (mentions is! List || mentions.length != 1) {
        return false;
      }
      final mention = mentions.single;
      if (mention is! Map) {
        return false;
      }
      final target = mention['target'];
      return target is Map && target['did'] == expectedTargetDid;
    },
  );
}

Map<String, Object?>? _cliMessagePayload(Map<String, Object?> message) {
  for (final value in <Object?>[
    message['payload'],
    message['content'],
    message['body'],
  ]) {
    if (value is Map) {
      final map = _cliStringKeyMap(value);
      if (map['text'] is String && map['mentions'] is List) {
        return map;
      }
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          final map = _cliStringKeyMap(decoded);
          if (map['text'] is String && map['mentions'] is List) {
            return map;
          }
        }
      } on FormatException {
        // Continue through alternate wire fields.
      }
    }
  }
  return null;
}
