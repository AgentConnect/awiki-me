part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyAttachmentRegression({
  required _DesktopAppRobot robot,
  required MessagingService messaging,
  required _RecordingAttachmentOpenService attachmentOpenRecorder,
  required String ownerDid,
  required AppThreadRef thread,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final conversation = await robot.startDirectConversation(config.cliHandle);
  final conversationId = conversation.effectiveConversationId;
  final cliDid = conversation.targetDid!.trim();
  final fixtureDir = Directory('${config.cliWorkspace}/fixtures')
    ..createSync(recursive: true);
  final downloadDir = Directory('${config.cliWorkspace}/downloads')
    ..createSync(recursive: true);

  final appAttachmentText = 'AWiki E2E app attachment ${config.runId} $nonce\n';
  final appAttachmentFilename = 'awiki-e2e-app-$nonce.txt';
  final appAttachmentCaption = 'e2e app attachment ${config.runId} $nonce';
  final appAttachmentBytes = Uint8List.fromList(utf8.encode(appAttachmentText));
  final appAttachmentSha256Hex = _sha256Hex(appAttachmentBytes);
  final appAttachmentDigestB64u = _sha256B64u(appAttachmentBytes);

  await robot.stageAttachmentByDesktopDrop(
    filename: appAttachmentFilename,
    mimeType: 'text/plain',
    bytes: appAttachmentBytes,
  );
  final pendingAttachment = find.byKey(
    const Key('chat-pending-attachment-preview'),
  );
  expect(pendingAttachment, findsOneWidget);
  expect(
    find.descendant(
      of: pendingAttachment,
      matching: find.text(appAttachmentFilename),
    ),
    findsOneWidget,
  );
  await robot.sendStagedAttachment(caption: appAttachmentCaption);
  final appAttachmentMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: appAttachmentCaption,
    senderDid: ownerDid,
    sendState: MessageSendState.sent,
  );
  final appAttachment = appAttachmentMessage.attachment;
  expect(appAttachment, isNotNull);
  expect(appAttachment!.filename, appAttachmentFilename);
  expect(appAttachment.mimeType, 'text/plain');
  expect(appAttachment.sizeBytes, appAttachmentBytes.length);
  await robot.expectMessageContentVisible(
    appAttachmentMessage,
    expectedText: appAttachmentFilename,
  );
  final appAttachmentMessageId = appAttachmentMessage.remoteId!;

  final cliAppAttachment = await _waitForCliAttachmentMessage(
    config: config,
    peerHandle: config.appHandle,
    expectedText: appAttachmentCaption,
    expectedMessageId: appAttachmentMessageId,
    expectedAttachmentId: appAttachment.attachmentId,
    expectedFilename: appAttachmentFilename,
    expectedSenderDid: ownerDid,
    expectedReceiverDid: cliDid,
  );
  expect(cliAppAttachment.digestB64u, appAttachmentDigestB64u);

  final cliDownload = File('${downloadDir.path}/from-app-$nonce.txt');
  final cliDownloadResult = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'attachment',
    'download',
    '--with',
    config.appHandle,
    '--message-id',
    appAttachmentMessageId,
    '--attachment-id',
    appAttachment.attachmentId,
    '--output',
    cliDownload.path,
  ], timeout: const Duration(minutes: 2));
  if (cliDownloadResult.exitCode != 0) {
    fail(
      'CLI attachment download failed: '
      '${_summarizeCliResult(cliDownloadResult)}',
    );
  }
  expect(await cliDownload.readAsString(), appAttachmentText);
  expect(await _fileSha256Hex(cliDownload), appAttachmentSha256Hex);
  expect(
    _jsonStringAt(cliDownloadResult.stdout, const <Object>[
      'data',
      'attachment',
      'digest',
      'value_b64u',
    ]),
    appAttachmentDigestB64u,
  );

  final cliAttachmentFilename = 'awiki-e2e-cli-$nonce.txt';
  final cliAttachmentText = 'AWiki E2E CLI attachment ${config.runId} $nonce\n';
  final cliAttachmentBytes = Uint8List.fromList(utf8.encode(cliAttachmentText));
  final cliAttachmentSha256Hex = _sha256Hex(cliAttachmentBytes);
  final cliAttachmentDigestB64u = _sha256B64u(cliAttachmentBytes);
  final cliAttachmentFile = File('${fixtureDir.path}/$cliAttachmentFilename')
    ..writeAsStringSync(cliAttachmentText);
  final cliAttachmentCaption = 'e2e cli attachment ${config.runId} $nonce';
  final cliAttachmentSend = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--to',
    config.appHandle,
    '--text',
    cliAttachmentCaption,
    '--file',
    cliAttachmentFile.path,
    '--mime-type',
    'text/plain',
  ], timeout: const Duration(minutes: 2));
  if (cliAttachmentSend.exitCode != 0) {
    fail(
      'CLI attachment send failed: ${_summarizeCliResult(cliAttachmentSend)}',
    );
  }
  final cliSentMessageId = _jsonStringAt(
    cliAttachmentSend.stdout,
    const <Object>['data', 'message', 'id'],
  );
  final cliSentAttachmentId = _jsonStringAt(
    cliAttachmentSend.stdout,
    const <Object>['data', 'attachment', 'attachment_id'],
  );
  if (cliSentMessageId == null || cliSentAttachmentId == null) {
    fail('CLI attachment send returned incomplete canonical ids.');
  }
  expect(
    _jsonStringAt(cliAttachmentSend.stdout, const <Object>[
      'data',
      'attachment',
      'digest',
      'value_b64u',
    ]),
    cliAttachmentDigestB64u,
  );

  final cliAttachmentMessage = await _waitForUiMessage(
    robot: robot,
    conversationId: conversationId,
    content: cliAttachmentCaption,
    messageId: cliSentMessageId,
    senderDid: cliDid,
    sendState: MessageSendState.sent,
  );
  final receivedAttachment = cliAttachmentMessage.attachment;
  expect(receivedAttachment, isNotNull);
  expect(receivedAttachment!.attachmentId, cliSentAttachmentId);
  expect(receivedAttachment.filename, cliAttachmentFilename);
  expect(receivedAttachment.mimeType, 'text/plain');
  expect(receivedAttachment.sizeBytes, cliAttachmentBytes.length);
  await robot.expectMessageContentVisible(
    cliAttachmentMessage,
    expectedText: cliAttachmentFilename,
  );

  final openButton = find.byKey(
    Key('chat-open-attachment:${cliAttachmentMessage.localId}'),
  );
  await robot.tapOne(
    openButton,
    description: 'received attachment open button',
  );
  await robot.pumpUntil(
    description: 'received attachment is downloaded for preview',
    timeout: const Duration(minutes: 2),
    condition: () =>
        (attachmentOpenRecorder.lastOpenedPath?.trim().isNotEmpty ?? false),
  );
  final openedFile = File(attachmentOpenRecorder.lastOpenedPath!);
  expect(await openedFile.exists(), isTrue);
  expect(await openedFile.readAsString(), cliAttachmentText);
  expect(await _fileSha256Hex(openedFile), cliAttachmentSha256Hex);

  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: thread,
    expectedTexts: <String>[appAttachmentCaption, cliAttachmentCaption],
  );
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String _sha256B64u(List<int> bytes) {
  return base64UrlEncode(sha256.convert(bytes).bytes).replaceAll('=', '');
}

Future<String> _fileSha256Hex(File file) async {
  return sha256.bind(file.openRead()).first.then((digest) => digest.toString());
}
