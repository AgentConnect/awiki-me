part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyDirectTextRegression({
  required MessagingService messaging,
  required ConversationService conversations,
  required AppThreadRef thread,
  required String ownerDid,
  required _DesktopCliPeerSmokeConfig config,
  required String nonce,
}) async {
  final appToCliText = 'e2e app to cli ${config.runId} $nonce';
  final cliToAppText = 'e2e cli to app ${config.runId} $nonce';

  final appMessage = await messaging.sendText(
    thread: thread,
    content: appToCliText,
  );
  expect(appMessage.content, appToCliText);

  await _waitForAppHistory(
    messaging: messaging,
    thread: thread,
    expectedText: appToCliText,
  );
  await _waitForCliInbox(config: config, expectedText: appToCliText);
  await _waitForCliHistory(
    config: config,
    peerHandle: config.appHandle,
    expectedText: appToCliText,
  );

  final cliSend = await _runCli(config, <String>[
    '--format',
    'json',
    'msg',
    'send',
    '--to',
    config.appHandle,
    '--text',
    cliToAppText,
  ]);
  if (cliSend.exitCode != 0) {
    fail('CLI msg send failed: ${_summarizeCliResult(cliSend)}');
  }

  await _waitForAppHistory(
    messaging: messaging,
    thread: thread,
    expectedText: cliToAppText,
  );
  await _expectAppHistoryContainsExactlyOnce(
    messaging: messaging,
    thread: thread,
    expectedTexts: <String>[appToCliText, cliToAppText],
  );
  await _waitForAppConversationRefresh(
    conversations: conversations,
    ownerDid: ownerDid,
    expectedText: cliToAppText,
  );
}
