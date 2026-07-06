part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyAttachmentRegression({
  required MessagingService messaging,
  required AppThreadRef thread,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
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
  final cliDid = await _currentCliDid(config);
  final appAttachmentClientMessageId =
      'msg-awiki-e2e-attachment-${config.runId}-$nonce';
  expect(cliDid.trim(), isNotEmpty);

  final appAttachmentMessage = await messaging.sendConversationAttachment(
    conversation: AppConversationReadRef.fromConversationId('dm:$cliDid'),
    attachment: AttachmentDraft(
      filename: appAttachmentFilename,
      mimeType: 'text/plain',
      bytes: appAttachmentBytes,
      sizeBytes: appAttachmentBytes.length,
    ),
    caption: appAttachmentCaption,
    clientMessageId: appAttachmentClientMessageId,
    idempotencyKey: 'op-$appAttachmentClientMessageId',
  );
  final appAttachment = appAttachmentMessage.attachment;
  expect(appAttachment, isNotNull);
  expect(appAttachment!.filename, appAttachmentFilename);
  expect(appAttachment.mimeType, 'text/plain');
  expect(appAttachment.sizeBytes, appAttachmentBytes.length);
  expect(appAttachmentMessage.content, appAttachmentCaption);
  final appAttachmentMessageId =
      appAttachmentMessage.remoteId ?? appAttachmentMessage.localId;

  final cliAppAttachment = await _waitForCliAttachmentMessage(
    config: config,
    peerHandle: config.appHandle,
    expectedText: appAttachmentCaption,
    expectedMessageId: appAttachmentMessageId,
    expectedAttachmentId: appAttachment.attachmentId,
    expectedFilename: appAttachmentFilename,
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
    appAttachmentMessage.remoteId ?? appAttachmentMessage.localId,
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
  expect(cliSentMessageId, isNotNull);
  expect(cliSentAttachmentId, isNotNull);
  expect(
    _jsonStringAt(cliAttachmentSend.stdout, const <Object>[
      'data',
      'attachment',
      'digest',
      'value_b64u',
    ]),
    cliAttachmentDigestB64u,
  );

  final cliAttachmentMessage = await _waitForAppAttachment(
    messaging: messaging,
    thread: thread,
    expectedCaption: cliAttachmentCaption,
    expectedFilename: cliAttachmentFilename,
    expectedMessageId: cliSentMessageId,
    expectedAttachmentId: cliSentAttachmentId,
  );
  final receivedAttachment = cliAttachmentMessage.attachment!;
  expect(cliAttachmentMessage.remoteId, cliSentMessageId);
  expect(receivedAttachment.attachmentId, cliSentAttachmentId);
  expect(receivedAttachment.mimeType, 'text/plain');
  expect(receivedAttachment.sizeBytes, cliAttachmentBytes.length);

  final appDownload = File('${downloadDir.path}/from-cli-$nonce.txt');
  final downloadResult = await messaging.downloadAttachment(
    thread: thread,
    messageId: cliSentMessageId!,
    attachmentId: cliSentAttachmentId!,
    localPath: appDownload.path,
  );
  expect(downloadResult.filename, cliAttachmentFilename);
  expect(downloadResult.mimeType, 'text/plain');
  expect(downloadResult.sizeBytes, cliAttachmentBytes.length);
  expect(await appDownload.readAsString(), cliAttachmentText);
  expect(await _fileSha256Hex(appDownload), cliAttachmentSha256Hex);
  if (downloadResult.bytes != null) {
    expect(_sha256Hex(downloadResult.bytes!), cliAttachmentSha256Hex);
  }
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String _sha256B64u(List<int> bytes) {
  return base64UrlEncode(sha256.convert(bytes).bytes).replaceAll('=', '');
}

Future<String> _fileSha256Hex(File file) async {
  return sha256.bind(file.openRead()).first.then((digest) => digest.toString());
}
