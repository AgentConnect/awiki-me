import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Desktop App and CLI peer exchange one direct message each',
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
      final thread = AppThreadRef.direct(config.cliHandle);
      final appToCliText = 'e2e app to cli ${config.runId}';
      final cliToAppText = 'e2e cli to app ${config.runId}';

      final appMessage = await messaging.sendText(
        thread: thread,
        content: appToCliText,
      );
      expect(appMessage.content, appToCliText);

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
    },
    skip: !_e2eEnabled,
    timeout: const Timeout(Duration(minutes: 6)),
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
  List<String> args,
) async {
  final result = await Process.run(
    config.cliBin,
    args,
    environment: <String, String>{
      ...Platform.environment,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': config.cliWorkspace,
    },
    runInShell: false,
  ).timeout(const Duration(seconds: 45));
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
    return value == expectedText;
  }
  if (value is List) {
    return value.any((entry) => _valueContainsText(entry, expectedText));
  }
  if (value is Map) {
    return value.values.any((entry) => _valueContainsText(entry, expectedText));
  }
  return false;
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
  for (final secret in <String>[_otpPhone, _otpCode, _cliWorkspace]) {
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
