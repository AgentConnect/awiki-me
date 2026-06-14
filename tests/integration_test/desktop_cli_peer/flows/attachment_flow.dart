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

  final appAttachmentMessage = await messaging.sendAttachment(
    thread: thread,
    attachment: AttachmentDraft(
      filename: appAttachmentFilename,
      mimeType: 'text/plain',
      bytes: appAttachmentBytes,
      sizeBytes: appAttachmentBytes.length,
    ),
    caption: appAttachmentCaption,
    idempotencyKey: 'app-attachment-${config.runId}-$nonce',
  );
  final appAttachment = appAttachmentMessage.attachment;
  expect(appAttachment, isNotNull);
  expect(appAttachment!.filename, appAttachmentFilename);
  expect(appAttachment.mimeType, 'text/plain');
  expect(appAttachment.sizeBytes, appAttachmentBytes.length);
  expect(appAttachmentMessage.content, appAttachmentCaption);

  await _waitForCliHistory(
    config: config,
    peerHandle: config.appHandle,
    expectedText: appAttachmentCaption,
  );

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

  final cliAttachmentFilename = 'awiki-e2e-cli-$nonce.txt';
  final cliAttachmentText = 'AWiki E2E CLI attachment ${config.runId} $nonce\n';
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

  final cliAttachmentMessage = await _waitForAppAttachment(
    messaging: messaging,
    thread: thread,
    expectedCaption: cliAttachmentCaption,
    expectedFilename: cliAttachmentFilename,
  );
  final receivedAttachment = cliAttachmentMessage.attachment!;
  expect(receivedAttachment.mimeType, 'text/plain');
  expect(receivedAttachment.sizeBytes, utf8.encode(cliAttachmentText).length);

  final appDownload = File('${downloadDir.path}/from-cli-$nonce.txt');
  final downloadResult = await messaging.downloadAttachment(
    thread: thread,
    messageId: cliSentMessageId!,
    attachmentId: cliSentAttachmentId!,
    localPath: appDownload.path,
  );
  expect(downloadResult.filename, cliAttachmentFilename);
  expect(downloadResult.mimeType, 'text/plain');
  expect(downloadResult.sizeBytes, utf8.encode(cliAttachmentText).length);
  expect(await appDownload.readAsString(), cliAttachmentText);
}
