part of '../desktop_cli_peer_e2e.dart';

// Opt-in joint acceptance. The bridge contains public test identities and IDs
// only; product runners continue to own credentials, UI drivers and cleanup.
Future<void> _verifyDshGroupPair({
  required _DesktopAppRobot robot,
  required _GroupRegressionResult group,
  required _DesktopCliPeerSmokeConfig config,
  required String ownerDid,
  required _RecordingAttachmentOpenService attachmentOpenRecorder,
}) async {
  final root = Platform.environment['AWIKI_E2E_PRODUCT_PAIR_DIR'];
  if (root == null) return;
  expect(Platform.environment['AWIKI_E2E_ENCRYPTED_GROUP'], '1');
  Future<Map<String, dynamic>> wait(String name) async {
    final file = File('$root/$name');
    await robot.pumpUntil(
      description: 'public product handoff $name',
      timeout: const Duration(minutes: 12),
      condition: file.existsSync,
    );
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> publish(String name, Map<String, dynamic> value) async {
    final file = File('$root/$name.tmp');
    await file.writeAsString(jsonEncode(value), flush: true);
    await file.rename('$root/$name');
  }

  final dsh = await wait('dsh.json');
  final dshDid = dsh['did'] as String;
  final dshHandle = dsh['handle'] as String;
  final peer = await robot.container
      .read(directoryApplicationServiceProvider)
      .resolvePeer(dshHandle);
  expect(peer.did, dshDid);
  await robot.openConversationRow(group.conversationId);
  await robot.addGroupMember(
    dshHandle,
    expectedDisplayName: const PeerDisplayNameResolver().resolve(
      nickname: peer.profile?.displayName,
      fullHandle: peer.handle ?? dshHandle,
      did: dshDid,
    ),
  );
  await publish('app.json', {
    'did': ownerDid,
    'handle': groupHandleForDid(handle: config.appHandle, did: ownerDid),
    'groupDid': group.groupDid,
    'groupName': group.groupName,
  });
  await robot.sendTextWithKeyboardAction('pair-app-text');
  final text = await _waitForUiMessage(
    robot: robot,
    conversationId: group.conversationId,
    content: 'pair-app-text',
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  expect(text.isEncrypted, isTrue);
  await robot.stageAttachmentByDesktopDrop(
    filename: 'pair-app.txt',
    mimeType: 'text/plain',
    bytes: Uint8List.fromList(utf8.encode('pair app encrypted attachment\n')),
  );
  await robot.sendStagedAttachment(caption: 'pair-app-attachment');
  final attachment = await _waitForUiMessage(
    robot: robot,
    conversationId: group.conversationId,
    content: 'pair-app-attachment',
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  expect(attachment.isEncrypted, isTrue);
  final reply = await _waitForUiMessage(
    robot: robot,
    conversationId: group.conversationId,
    content: 'pair-dsh-text',
    senderDid: dshDid,
    sendState: MessageSendState.sent,
  );
  expect(reply.isEncrypted, isTrue);
  // Deterministic CLI peer response exercises a third member without any model.
  await _waitForCliGroupMessages(
    config: config,
    groupDid: group.groupDid,
    expectedText: 'pair-dsh-text',
    expectedMessageId: reply.remoteId!,
    expectedSenderDid: dshDid,
    expectedContentType: 'text/plain',
  );
  final scriptedReply = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--group',
    group.groupDid,
    '--text',
    'pair-scripted-agent',
    '--secure',
    'required',
  ]);
  expect(scriptedReply.exitCode, 0);
  final agentMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: group.conversationId,
    content: 'pair-scripted-agent',
    senderDid: group.cliMemberDid,
    sendState: MessageSendState.sent,
  );
  expect(agentMessage.isEncrypted, isTrue);
  final received = await _waitForUiMessage(
    robot: robot,
    conversationId: group.conversationId,
    content: 'pair-dsh-attachment',
    senderDid: dshDid,
    sendState: MessageSendState.sent,
  );
  expect(received.isEncrypted, isTrue);
  attachmentOpenRecorder.lastOpenedPath = null;
  await robot.tapOne(
    find.byKey(Key('chat-open-attachment:${received.localId}')),
    description: 'download DSH group attachment through UI',
  );
  await robot.pumpUntil(
    description: 'DSH group attachment downloaded',
    timeout: const Duration(minutes: 2),
    condition: () => attachmentOpenRecorder.lastOpenedPath != null,
  );
  expect(
    await File(attachmentOpenRecorder.lastOpenedPath!).readAsString(),
    'pair dsh encrypted attachment\n',
  );
  await publish('app-received.json', {'passed': true});
  final reverse = await wait('reverse.json');
  ConversationSummary? incoming;
  await robot.pumpUntil(
    description: 'DSH-created encrypted group appears',
    timeout: const Duration(minutes: 2),
    condition: () {
      final matches = robot.container
          .read(conversationListProvider)
          .conversations
          .where((item) => item.groupId == reverse['groupDid'])
          .toList();
      if (matches.length != 1) return false;
      incoming = matches.single;
      return true;
    },
  );
  await robot.openConversationRow(incoming!.conversationId);
  final reverseMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: incoming!.conversationId,
    content: 'pair-reverse-dsh',
    senderDid: dshDid,
    sendState: MessageSendState.sent,
  );
  expect(reverseMessage.isEncrypted, isTrue);
  await robot.sendTextWithKeyboardAction('pair-reverse-app');
  final reverseReply = await _waitForUiMessage(
    robot: robot,
    conversationId: incoming!.conversationId,
    content: 'pair-reverse-app',
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  expect(reverseReply.isEncrypted, isTrue);
  await wait('dsh-complete.json');
  await publish('app-complete.json', {'passed': true});
  await E2eScenarioProgressWriter.record(
    'app_dsh_group_pair_text_attachment_reverse_verified',
  );
}
