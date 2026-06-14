import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const bool _e2eEnabled = bool.fromEnvironment('AWIKI_E2E');
const String _runId = String.fromEnvironment('AWIKI_E2E_RUN_ID');
const String _platform = String.fromEnvironment('AWIKI_E2E_PLATFORM');
const String _appHandle = String.fromEnvironment('AWIKI_E2E_APP_HANDLE');
const String _cliHandle = String.fromEnvironment('AWIKI_E2E_CLI_HANDLE');
const String _otpPhone = String.fromEnvironment('DEV_OTP_PHONE');
const String _otpCode = String.fromEnvironment('DEV_OTP_CODE');
const String _cliBin = String.fromEnvironment('AWIKI_CLI_BIN');
const String _cliWorkspace = String.fromEnvironment(
  'AWIKI_CLI_WORKSPACE_HOME_DIR',
);
const String _cliHome = String.fromEnvironment('AWIKI_CLI_HOME_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Desktop App and CLI peer cover direct, group, and attachment basics',
    (tester) async {
      final config = _DesktopCliPeerSmokeConfig.fromEnvironment();
      final bootstrap = await AppBootstrap.create();
      addTearDown(() async {
        await bootstrap.appSessionService?.logout();
      });

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);

      final session = await _prepareAppIdentity(
        bootstrap.onboardingService!,
        config,
      );
      expect(session.authenticated, isTrue);

      await tester.pumpAndSettle();

      final messaging = bootstrap.messagingService!;
      final conversations = bootstrap.conversationService!;
      final groups = bootstrap.groupApplicationService!;
      final thread = AppThreadRef.direct(config.cliHandle);
      final messageNonce = _messageNonce();
      final appToCliText = 'e2e app to cli ${config.runId} $messageNonce';
      final cliToAppText = 'e2e cli to app ${config.runId} $messageNonce';

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
        ownerDid: session.did,
        expectedText: cliToAppText,
      );
      await _verifyGroupTextRegression(
        groups: groups,
        messaging: messaging,
        config: config,
        nonce: messageNonce,
      );
      await _verifyAttachmentRegression(
        messaging: messaging,
        thread: thread,
        config: config,
        nonce: messageNonce,
      );
    },
    skip: !_e2eEnabled,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<AppSession> _prepareAppIdentity(
  OnboardingService onboarding,
  _DesktopCliPeerSmokeConfig config,
) async {
  final recover = await _tryAppIdentityAction(
    () => onboarding.recoverHandle(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
    ),
  );
  if (recover.session != null) {
    return recover.session!;
  }
  if (!_looksRecoverableForRegister(recover.errorText)) {
    throw StateError(
      'App recover failed and did not look like a missing-handle error: '
      '${_sanitizeDiagnostic(recover.errorText)}',
    );
  }

  final register = await _tryAppIdentityAction(
    () => onboarding.registerHandleWithPhone(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
      nickName: 'AWiki E2E ${config.runId}',
    ),
  );
  if (register.session != null) {
    return register.session!;
  }
  throw StateError(
    'App register failed: ${_sanitizeDiagnostic(register.errorText)}',
  );
}

Future<_AppIdentityAttempt> _tryAppIdentityAction(
  Future<AppSession> Function() action,
) async {
  try {
    return _AppIdentityAttempt.session(await action());
  } on Object catch (error) {
    return _AppIdentityAttempt.error(error.toString());
  }
}

Future<void> _waitForCliHistory({
  required _DesktopCliPeerSmokeConfig config,
  required String peerHandle,
  required String expectedText,
}) async {
  await _poll(
    description: 'CLI history contains "$expectedText"',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'msg',
        'history',
        '--with',
        peerHandle,
        '--limit',
        '20',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedText);
    },
  );
}

Future<void> _waitForCliGroupMessages({
  required _DesktopCliPeerSmokeConfig config,
  required String groupDid,
  required String expectedText,
}) async {
  await _poll(
    description: 'CLI group messages contain "$expectedText"',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'group',
        'messages',
        '--group',
        groupDid,
        '--limit',
        '20',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedText);
    },
  );
}

Future<void> _waitForCliInbox({
  required _DesktopCliPeerSmokeConfig config,
  required String expectedText,
}) async {
  await _poll(
    description: 'CLI inbox contains "$expectedText"',
    action: () async {
      final result = await _runCli(config, const <String>[
        '--format',
        'json',
        'msg',
        'inbox',
        '--limit',
        '20',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedText);
    },
  );
}

Future<void> _waitForGroupMessages({
  required GroupApplicationService groups,
  required String groupDid,
  required String expectedText,
}) async {
  await _poll(
    description: 'App group messages contain "$expectedText"',
    action: () async {
      final messages = await groups.listMessages(groupDid, limit: 20);
      return messages.any((message) => message._matchesText(expectedText));
    },
  );
}

Future<void> _waitForAppHistory({
  required MessagingService messaging,
  required AppThreadRef thread,
  required String expectedText,
}) async {
  await _poll(
    description: 'App history contains "$expectedText"',
    action: () async {
      final messages = await messaging.loadHistory(thread, limit: 20);
      return messages.any((message) => message._matchesText(expectedText));
    },
  );
}

Future<ChatMessage> _waitForAppAttachment({
  required MessagingService messaging,
  required AppThreadRef thread,
  required String expectedCaption,
  required String expectedFilename,
}) async {
  ChatMessage? matched;
  await _poll(
    description:
        'App history contains attachment "$expectedFilename" with caption "$expectedCaption"',
    action: () async {
      final messages = await messaging.loadHistory(thread, limit: 50);
      for (final message in messages) {
        final attachment = message.attachment;
        if (attachment == null) {
          continue;
        }
        if (message.content == expectedCaption &&
            attachment.filename == expectedFilename) {
          matched = message;
          return true;
        }
      }
      return false;
    },
  );
  return matched!;
}

Future<void> _expectAppHistoryContainsExactlyOnce({
  required MessagingService messaging,
  required AppThreadRef thread,
  required List<String> expectedTexts,
}) async {
  final first = await messaging.loadHistory(thread, limit: 50);
  final second = await messaging.loadHistory(thread, limit: 50);
  for (final text in expectedTexts) {
    final firstMatches = first.where((message) => message._matchesText(text));
    final secondMatches = second.where((message) => message._matchesText(text));
    expect(
      firstMatches,
      hasLength(1),
      reason: 'App history should contain exactly one "$text" message.',
    );
    expect(
      secondMatches,
      hasLength(1),
      reason: 'A second App history refresh should not duplicate "$text".',
    );
  }
}

Future<void> _waitForAppConversationRefresh({
  required ConversationService conversations,
  required String ownerDid,
  required String expectedText,
}) async {
  await _poll(
    description: 'App conversation refresh contains "$expectedText"',
    action: () async {
      final items = await conversations.listConversations(
        ownerDid: ownerDid,
        limit: 20,
      );
      return items.any(
        (conversation) =>
            conversation.lastMessagePreview.contains(expectedText),
      );
    },
  );
}

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
    expectedTexts: <String>[appGroupText, cliGroupText],
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

Future<void> _poll({
  required String description,
  required Future<bool> Function() action,
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await action()) {
        return;
      }
    } on Object catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(interval);
  }
  final suffix = lastError == null
      ? ''
      : ' Last error: ${_sanitizeDiagnostic(lastError.toString())}';
  fail('Timed out waiting for $description.$suffix');
}

Future<_CliResult> _runCli(
  _DesktopCliPeerSmokeConfig config,
  List<String> args, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final result = await Process.run(
    config.cliBin,
    args,
    environment: <String, String>{
      ...Platform.environment,
      'HOME': config.cliHome,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': config.cliWorkspace,
    },
    runInShell: false,
  ).timeout(timeout);
  return _CliResult(
    exitCode: result.exitCode,
    stdout: ((result.stdout as String?) ?? '').trim(),
    stderr: ((result.stderr as String?) ?? '').trim(),
  );
}

bool _jsonContainsText(String output, String expectedText) {
  try {
    return _valueContainsText(jsonDecode(output), expectedText);
  } on Object {
    return output.contains(expectedText);
  }
}

bool _valueContainsText(Object? value, String expectedText) {
  if (value is String) {
    return value.contains(expectedText);
  }
  if (value is List) {
    return value.any((entry) => _valueContainsText(entry, expectedText));
  }
  if (value is Map) {
    return value.values.any((entry) => _valueContainsText(entry, expectedText));
  }
  return false;
}

String? _jsonStringAt(String output, List<Object> path) {
  Object? value;
  try {
    value = jsonDecode(output);
  } on Object {
    return null;
  }
  for (final segment in path) {
    if (value is Map) {
      value = value[segment];
      continue;
    }
    if (value is List && segment is int) {
      if (segment < 0 || segment >= value.length) {
        return null;
      }
      value = value[segment];
      continue;
    }
    return null;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  if (value is num) {
    return value.toString();
  }
  return null;
}

String _messageNonce() {
  final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
  return micros.toRadixString(36);
}

String _groupSlug(String runId, String nonce) {
  final raw = 'awiki-e2e-$runId-$nonce'.toLowerCase();
  final slug = raw
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  if (slug.length <= 48) {
    return slug;
  }
  return slug.substring(0, 48).replaceAll(RegExp(r'-$'), '');
}

String _normalizeIdentityRef(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.endsWith('.awiki.ai')) {
    return normalized.substring(0, normalized.length - '.awiki.ai'.length);
  }
  return normalized;
}

bool _looksRecoverableForRegister(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not found') ||
      lower.contains('handle_not_found') ||
      lower.contains('not_registered') ||
      lower.contains('not registered') ||
      lower.contains('404');
}

String _summarizeCliResult(_CliResult result) {
  final text = <String>[
    'exit=${result.exitCode}',
    if (result.stdout.isNotEmpty) 'stdout=${result.stdout}',
    if (result.stderr.isNotEmpty) 'stderr=${result.stderr}',
  ].join(' ');
  return _sanitizeDiagnostic(text);
}

String _sanitizeDiagnostic(String input) {
  var output = input;
  for (final secret in <String>[_otpPhone, _otpCode, _cliWorkspace, _cliHome]) {
    if (secret.trim().isNotEmpty) {
      output = output.replaceAll(secret, '<redacted>');
    }
  }
  output = output.replaceAll(
    RegExp(
      r'(otp|token|jwt|private[_-]?key|secret|authorization)=([^\s]+)',
      caseSensitive: false,
    ),
    '<redacted-key>=<redacted>',
  );
  output = output.replaceAllMapped(
    RegExp(r'(--otp|--phone)\s+([^\s]+)', caseSensitive: false),
    (match) => '${match.group(1)} <redacted>',
  );
  return output;
}

class _DesktopCliPeerSmokeConfig {
  const _DesktopCliPeerSmokeConfig({
    required this.runId,
    required this.platform,
    required this.appHandle,
    required this.cliHandle,
    required this.otpPhone,
    required this.otpCode,
    required this.cliBin,
    required this.cliWorkspace,
    required this.cliHome,
  });

  factory _DesktopCliPeerSmokeConfig.fromEnvironment() {
    return _DesktopCliPeerSmokeConfig(
      runId: _requiredDefine('AWIKI_E2E_RUN_ID', _runId),
      platform: _requiredDefine('AWIKI_E2E_PLATFORM', _platform),
      appHandle: _requiredDefine('AWIKI_E2E_APP_HANDLE', _appHandle),
      cliHandle: _requiredDefine('AWIKI_E2E_CLI_HANDLE', _cliHandle),
      otpPhone: _requiredDefine('DEV_OTP_PHONE', _otpPhone),
      otpCode: _requiredDefine('DEV_OTP_CODE', _otpCode),
      cliBin: _requiredDefine('AWIKI_CLI_BIN', _cliBin),
      cliWorkspace: _requiredDefine(
        'AWIKI_CLI_WORKSPACE_HOME_DIR',
        _cliWorkspace,
      ),
      cliHome: _requiredDefine('AWIKI_CLI_HOME_DIR', _cliHome),
    );
  }

  final String runId;
  final String platform;
  final String appHandle;
  final String cliHandle;
  final String otpPhone;
  final String otpCode;
  final String cliBin;
  final String cliWorkspace;
  final String cliHome;
}

class _AppIdentityAttempt {
  const _AppIdentityAttempt._({this.session, required this.errorText});

  factory _AppIdentityAttempt.session(AppSession session) {
    return _AppIdentityAttempt._(session: session, errorText: '');
  }

  factory _AppIdentityAttempt.error(String errorText) {
    return _AppIdentityAttempt._(errorText: errorText);
  }

  final AppSession? session;
  final String errorText;
}

class _CliResult {
  const _CliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

String _requiredDefine(String name, String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    throw StateError('$name is required for Desktop CLI peer E2E.');
  }
  return trimmed;
}

extension on ChatMessage {
  bool _matchesText(String expectedText) => content == expectedText;
}
