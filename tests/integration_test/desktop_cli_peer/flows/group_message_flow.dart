part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyGroupTextRegression({
  required GroupApplicationService groups,
  required MessagingService messaging,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final groupName = 'AWiki E2E ${config.runId} $nonce';
  final group = await groups.createGroup(
    name: groupName,
    slug: _groupSlug(config.runId, nonce),
    description: 'AWiki Me desktop E2E group ${config.runId}',
    goal: 'Verify basic App and CLI peer group messaging.',
    rules: 'Only automated non-production E2E messages.',
  );
  expect(group.groupId.trim(), isNotEmpty);
  expect(group.displayName, isNotEmpty);

  await groups.addMember(groupDid: group.groupId, memberRef: config.cliHandle);
  await _waitForGroupMember(
    groups: groups,
    groupDid: group.groupId,
    memberRef: config.cliHandle,
  );

  final appGroupText = 'e2e app group ${config.runId} $nonce';
  final appGroupMentionText =
      '@agents e2e app group mention ${config.runId} $nonce';
  final cliGroupText = 'e2e cli group ${config.runId} $nonce';
  final groupThread = AppThreadRef.group(group.groupId);

  final appGroupMessage = await messaging.sendText(
    thread: groupThread,
    content: appGroupText,
  );
  expect(appGroupMessage.content, appGroupText);

  await _waitForGroupMessages(
    groups: groups,
    groupDid: group.groupId,
    expectedText: appGroupText,
  );
  await _waitForCliGroupMessages(
    config: config,
    groupDid: group.groupId,
    expectedText: appGroupText,
  );

  final mentionMessage = await messaging.sendMentionText(
    thread: groupThread,
    text: appGroupMentionText,
    mentions: const <ChatMentionDraft>[
      ChatMentionDraft(
        localId: 'men_agents_e2e',
        surface: '@agents',
        start: 0,
        end: 7,
        target: ChatMentionTargetDraft.groupSelector(
          ChatMentionSelector.agents,
        ),
      ),
    ],
    idempotencyKey: 'app-group-mention-${config.runId}-$nonce',
  );
  expect(mentionMessage.content, appGroupMentionText);
  expect(mentionMessage.mentions, hasLength(1));
  expect(
    mentionMessage.payloadJson,
    allOf(contains('"mentions"'), isNot(contains('"schema"'))),
  );

  await _waitForGroupMessages(
    groups: groups,
    groupDid: group.groupId,
    expectedText: appGroupMentionText,
  );
  await _waitForCliGroupMessages(
    config: config,
    groupDid: group.groupId,
    expectedText: appGroupMentionText,
  );

  final cliGroupSend = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--group',
    group.groupId,
    '--text',
    cliGroupText,
  ]);
  if (cliGroupSend.exitCode != 0) {
    fail('CLI group msg send failed: ${_summarizeCliResult(cliGroupSend)}');
  }

  await _waitForGroupMessages(
    groups: groups,
    groupDid: group.groupId,
    expectedText: cliGroupText,
  );
  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: groupThread,
    expectedTexts: <String>[appGroupText, appGroupMentionText, cliGroupText],
  );
}

Future<void> _waitForGroupMember({
  required GroupApplicationService groups,
  required String groupDid,
  required String memberRef,
}) async {
  await _poll(
    description: 'Group members contain "$memberRef"',
    action: () async {
      final members = await groups.listMembers(groupDid, limit: 20);
      final normalizedRef = _normalizeIdentityRef(memberRef);
      return members.any((member) {
        final fields = <String>[
          member.did,
          member.handle,
          member.userId,
        ].map(_normalizeIdentityRef).where((field) => field.isNotEmpty);
        return fields.any(
          (field) =>
              field == normalizedRef ||
              field.contains(normalizedRef) ||
              normalizedRef.contains(field),
        );
      });
    },
  );
}
