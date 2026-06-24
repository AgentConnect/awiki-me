import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/agent_inventory_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/presentation/agents/agents_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _codexAgentRunConfigPath =
    '.e2e/codex-agent/current/run_config.json';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Codex Agent full UI sends deterministic prompt and shows visible reply',
    (tester) async {
      final config = _CodexAgentRealBackendConfig.tryLoad();
      if (config == null || !config.enabled || !config.realBackend) {
        return;
      }
      if (!File(config.daemonBinary).existsSync()) {
        fail('daemon binary was not found: ${config.daemonBinary}');
      }
      debugDefaultTargetPlatformOverride = config.targetPlatform;
      await tester.binding.setSurfaceSize(const Size(1400, 900));

      final bootstrap = await AppBootstrap.create(
        environment: config.environment,
        appStateRoot: config.appStateRoot,
      );
      Process? daemon;
      try {
        await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
        await _pumpFrame(tester);
        expect(find.byType(AppShell), findsOneWidget);

        final session = await _prepareRealAppIdentity(
          bootstrap.onboardingService!,
          config,
        );
        await ProviderScope.containerOf(tester.element(find.byType(AppShell)))
            .read(appRuntimeProvider.notifier)
            .activateSession(session.toLegacySessionIdentity());
        await _pumpFrame(tester);

        final appContainer = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        final install = await _installRealDaemon(
          config: config,
          inventory: appContainer.read(agentInventoryPortProvider),
          controllerDid: session.did,
        );
        daemon = await _startRealDaemon(config: config);
        await _waitForFile(config.daemonReadyFile);

        final agents = appContainer.read(agentsProvider.notifier);
        await _waitForAgentInventoryEntry(
          tester: tester,
          agents: agents,
          agentDid: install.daemonDid,
          handle: install.handle,
        );

        await _tapFirstFound(tester, <Finder>[
          find.bySemanticsIdentifier('e2e-agents-tab'),
          find.bySemanticsLabel('智能体'),
          find.bySemanticsLabel('Agents'),
          find.text('智能体'),
          find.text('Agents'),
        ]);
        agents.select(install.daemonDid);
        await _pumpFrame(tester);
        await _waitForDaemonGenericCliCapability(
          tester: tester,
          agents: agents,
          daemonDid: install.daemonDid,
        );

        final runtimeHandle = _codexRuntimeHandle(config.runId);
        await agents.createRuntimeAgent(
          install.daemonDid,
          options: RuntimeAgentCreateOptions(
            kind: RuntimeAgentKind.codex,
            handle: runtimeHandle,
            displayName: 'Codex E2E',
            workspaceMode: runtimeWorkspaceModeRouteRoot,
            sandbox: runtimeSandboxReadOnly,
          ),
        );
        await _pumpUntil(
          tester,
          () => !ProviderScope.containerOf(
            tester.element(find.byType(AppShell)),
          ).read(agentsProvider).isActing,
          timeout: const Duration(seconds: 30),
          description: 'Codex runtime create action to finish',
        );
        final stateAfterCreate = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        ).read(agentsProvider);
        if (stateAfterCreate.error != null) {
          fail(
            'Codex runtime create failed: ${stateAfterCreate.error}. '
            'Raw error: ${stateAfterCreate.debugLastError}. '
            'Agents: ${_agentsDebugSummary(stateAfterCreate)}',
          );
        }

        final runtime = await _waitForRuntimeAgentByHandle(
          tester: tester,
          agents: agents,
          daemonDid: install.daemonDid,
          handle: runtimeHandle,
        );
        agents.select(runtime.agentDid);
        await _pumpFrame(tester);
        await _tapFirstFound(tester, <Finder>[find.text('打开聊天')]);
        await _pumpFrame(tester);
        expect(find.text('Codex E2E'), findsWidgets);

        await _sendPromptThroughUi(tester, config.prompt);
        await _waitForDaemonCodexFinalSent(
          daemonStateRoot: config.daemonStateRoot,
          runtimeAgentDid: runtime.agentDid,
          prompt: config.prompt,
          expectedReply: config.expectedReply,
        );
        await _waitForAppIncomingCodexReply(
          messaging: bootstrap.messagingService!,
          runtimeAgentDid: runtime.agentDid,
          expectedReply: config.expectedReply,
        );
        await _waitForVisibleCodexReply(
          tester: tester,
          expectedReply: config.expectedReply,
        );
      } finally {
        if (daemon != null) {
          _terminateProcess(daemon);
        }
        await bootstrap.appSessionService?.logout();
        debugDefaultTargetPlatformOverride = null;
        await tester.binding.setSurfaceSize(null);
      }
    },
    skip: !_CodexAgentRealBackendConfig.shouldRun,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<AppSession> _prepareRealAppIdentity(
  OnboardingService onboarding,
  _CodexAgentRealBackendConfig config,
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
      'App recover failed: ${_sanitizeDiagnostic(recover.errorText, config)}',
    );
  }
  final register = await _tryAppIdentityAction(
    () => onboarding.registerHandleWithPhone(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
      nickName: 'Codex Agent E2E ${config.runId}',
    ),
  );
  if (register.session != null) {
    return register.session!;
  }
  throw StateError(
    'App register failed: ${_sanitizeDiagnostic(register.errorText, config)}',
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

Future<_DaemonInstallResult> _installRealDaemon({
  required _CodexAgentRealBackendConfig config,
  required AgentInventoryPort inventory,
  required String controllerDid,
}) async {
  final token = await inventory.issueDaemonToken(
    controllerDid: controllerDid,
    clientPlatform: 'linux',
    handle: config.daemonHandle,
  );
  final result = await _runProcess(
    config.daemonBinary,
    <String>[
      'install',
      '--token',
      token.token,
      '--base-url',
      config.environment.baseUrl,
      '--no-service',
      '--print-json',
      '--state-root',
      config.daemonStateRoot,
    ],
    environment: _daemonEnvironment(config),
    timeout: const Duration(minutes: 2),
    secrets: <String>[token.token, ...config.secrets],
  );
  if (result.exitCode != 0) {
    throw StateError(
      'daemon install failed: ${result.sanitizedSummary(config)}',
    );
  }
  final json = jsonDecode(result.stdout);
  if (json is! Map) {
    throw StateError('daemon install did not return a JSON object.');
  }
  return _DaemonInstallResult(
    daemonDid: json['daemon_agent_did']?.toString() ?? '',
    handle: json['handle']?.toString() ?? config.daemonHandle,
  );
}

Future<Process> _startRealDaemon({
  required _CodexAgentRealBackendConfig config,
}) async {
  final readyFile = File(config.daemonReadyFile);
  if (readyFile.existsSync()) {
    readyFile.deleteSync();
  }
  final process = await Process.start(
    config.daemonBinary,
    <String>[
      'foreground',
      '--state-root',
      config.daemonStateRoot,
      '--ready-file',
      config.daemonReadyFile,
      '--max-runtime-ms',
      '180000',
      '--poll-interval-ms',
      '100',
    ],
    environment: _daemonEnvironment(config),
    includeParentEnvironment: true,
    runInShell: false,
  );
  process.stdout.transform(utf8.decoder).listen((_) {}, onError: (_) {});
  process.stderr.transform(utf8.decoder).listen((_) {}, onError: (_) {});
  return process;
}

Map<String, String> _daemonEnvironment(_CodexAgentRealBackendConfig config) {
  final environment = _loadDaemonEnvFile(config);
  environment.addAll(<String, String>{
    'AWIKI_DAEMON_SERVICE_BASE_URL': config.environment.baseUrl,
    'AWIKI_DAEMON_USER_SERVICE_BASE_URL': config.environment.userServiceUrl,
    'AWIKI_DAEMON_MESSAGE_SERVICE_BASE_URL':
        config.environment.messageServiceUrl,
    'AWIKI_DAEMON_DID_DOMAIN': config.environment.didDomain,
    'AWIKI_DAEMON_ALLOW_PLAIN_CONTROL': '1',
  });
  return environment;
}

Map<String, String> _loadDaemonEnvFile(_CodexAgentRealBackendConfig config) {
  final path = config.daemonEnvFile;
  if (path == null || path.trim().isEmpty) {
    return <String, String>{};
  }
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'daemon env file was configured but not found: '
      '${_sanitizeDiagnostic(path, config)}',
    );
  }
  return _parseDaemonEnvFile(file.readAsLinesSync(), path);
}

List<String> _daemonEnvFileSecretValues(String? path) {
  if (path == null || path.trim().isEmpty) {
    return const <String>[];
  }
  final file = File(path);
  if (!file.existsSync()) {
    return const <String>[];
  }
  return _parseDaemonEnvFile(
    file.readAsLinesSync(),
    path,
  ).values.where((value) => value.trim().isNotEmpty).toList(growable: false);
}

Map<String, String> _parseDaemonEnvFile(List<String> lines, String path) {
  final values = <String, String>{};
  for (var index = 0; index < lines.length; index += 1) {
    var line = lines[index].trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('export ')) {
      line = line.substring('export '.length).trimLeft();
    }
    final equals = line.indexOf('=');
    if (equals <= 0) {
      throw StateError('Invalid daemon env file line ${index + 1} in $path.');
    }
    final key = line.substring(0, equals).trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      throw StateError(
        'Invalid daemon env variable name on line ${index + 1} in $path.',
      );
    }
    values[key] = _decodeEnvValue(line.substring(equals + 1).trim());
  }
  return values;
}

String _decodeEnvValue(String value) {
  if (value.length >= 2) {
    final quote = value.codeUnitAt(0);
    final last = value.codeUnitAt(value.length - 1);
    if ((quote == 0x22 && last == 0x22) || (quote == 0x27 && last == 0x27)) {
      final inner = value.substring(1, value.length - 1);
      if (quote == 0x22) {
        return inner
            .replaceAll(r'\"', '"')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\t', '\t')
            .replaceAll(r'\\', '\\');
      }
      return inner.replaceAll(r"'\''", "'");
    }
  }
  return value;
}

Future<void> _waitForAgentInventoryEntry({
  required WidgetTester tester,
  required AgentsController agents,
  required String agentDid,
  required String handle,
}) async {
  Object? lastState;
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await agents.load();
    await _pumpFrame(tester);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(agentsProvider);
    lastState = _agentsDebugSummary(state);
    final agent = _agentByDid(state, agentDid);
    if (agent != null && agent.handle == handle) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for agent inventory entry $agentDid/$handle. '
    'Last agents: ${lastState ?? '<none>'}',
  );
}

Future<void> _waitForDaemonGenericCliCapability({
  required WidgetTester tester,
  required AgentsController agents,
  required String daemonDid,
}) async {
  Object? lastState;
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await agents.load();
    agents.select(daemonDid);
    await _pumpFrame(tester);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(agentsProvider);
    lastState = _agentsDebugSummary(state);
    final daemon = _agentByDid(state, daemonDid);
    if (daemon != null && _daemonSupportsCodex(daemon)) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for daemon generic-cli capability for $daemonDid. '
    'Last agents: ${lastState ?? '<none>'}',
  );
}

Future<AgentSummary> _waitForRuntimeAgentByHandle({
  required WidgetTester tester,
  required AgentsController agents,
  required String daemonDid,
  required String handle,
}) async {
  Object? lastState;
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await agents.load();
    await _pumpFrame(tester);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    ).read(agentsProvider);
    lastState = _agentsDebugSummary(state);
    for (final agent in state.agents) {
      if (agent.isRuntime &&
          agent.daemonAgentDid == daemonDid &&
          agent.handle == handle &&
          agent.runtime == 'generic-cli') {
        return agent;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  fail(
    'Timed out waiting for Codex runtime handle=$handle. '
    'Last agents: ${lastState ?? '<none>'}',
  );
}

Future<void> _sendPromptThroughUi(WidgetTester tester, String prompt) async {
  final input = find.bySemanticsIdentifier('e2e-chat-input');
  await _pumpUntil(
    tester,
    () => input.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 15),
    description: 'Codex chat input to become visible',
  );
  await tester.enterText(input, prompt);
  await _pumpFrame(tester);
  await _tapFirstFound(tester, <Finder>[
    find.bySemanticsIdentifier('e2e-chat-send-button'),
  ]);
  await _pumpFrame(tester);
}

Future<void> _waitForDaemonCodexFinalSent({
  required String daemonStateRoot,
  required String runtimeAgentDid,
  required String prompt,
  required String expectedReply,
}) async {
  final dbPath = '${daemonStateRoot.replaceAll(RegExp(r'/+$'), '')}/daemon.db';
  String lastState = 'daemon.db not found';
  await _poll(
    description: 'daemon sent Codex runtime final reply "$expectedReply"',
    action: () async {
      final dbFile = File(dbPath);
      if (!dbFile.existsSync()) {
        lastState = 'daemon.db not found at $dbPath';
        return false;
      }
      final db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      try {
        final rows = await db.rawQuery(
          '''
          SELECT t.task_id, t.status AS task_status,
                 r.run_id, r.runtime_plugin_id, r.status AS run_status,
                 f.status AS final_status, f.final_text AS final_text,
                 f.message_id AS final_message_id,
                 f.recipient_did AS recipient_did,
                 f.final_source AS final_source
          FROM runtime_task t
          LEFT JOIN runtime_run r ON r.task_id = t.task_id
          LEFT JOIN runtime_final_outbox f ON f.run_id = r.run_id
          WHERE t.agent_did = ? AND t.task_text LIKE ?
          ORDER BY t.created_at_ms DESC
          LIMIT 1
          ''',
          <Object?>[runtimeAgentDid, '%$prompt%'],
        );
        if (rows.isEmpty) {
          lastState = 'no runtime task for runtime=$runtimeAgentDid prompt';
          return false;
        }
        final row = rows.first;
        lastState = jsonEncode(row);
        return row['runtime_plugin_id'] == 'generic-cli' &&
            row['run_status'] == 'finished' &&
            row['final_status'] == 'sent' &&
            row['final_message_id'] != null &&
            row['final_text'] == expectedReply;
      } finally {
        await db.close();
      }
    },
    timeout: const Duration(seconds: 150),
    interval: const Duration(seconds: 1),
    lastError: () => lastState,
  );
}

Future<ChatMessage> _waitForAppIncomingCodexReply({
  required MessagingService messaging,
  required String runtimeAgentDid,
  required String expectedReply,
}) async {
  ChatMessage? matched;
  Object? lastState;
  await _poll(
    description: 'App local history contains incoming Codex reply',
    action: () async {
      final messages = await messaging.loadHistory(
        AppThreadRef.direct(runtimeAgentDid),
        limit: 50,
      );
      lastState = _chatHistoryDebugSummary(messages);
      for (final message in messages) {
        if (!message.isMine &&
            message.senderDid == runtimeAgentDid &&
            message.content == expectedReply) {
          matched = message;
          return true;
        }
      }
      return false;
    },
    timeout: const Duration(seconds: 90),
    interval: const Duration(seconds: 2),
    lastError: () => lastState,
  );
  return matched!;
}

Future<void> _waitForVisibleCodexReply({
  required WidgetTester tester,
  required String expectedReply,
}) async {
  await _pumpUntil(
    tester,
    () {
      final found = find.text(expectedReply).evaluate().isNotEmpty;
      return found;
    },
    timeout: const Duration(seconds: 90),
    description: 'Codex reply bubble visible in App UI',
    lastError: () =>
        'App history already contained the Codex reply; '
        'the visible chat bubble did not render in time.',
  );
  expect(find.text(expectedReply), findsOneWidget);
}

String _chatHistoryDebugSummary(List<ChatMessage> messages) {
  return jsonEncode(
    messages
        .map(
          (message) => <String, Object?>{
            'remoteId': message.remoteId,
            'senderDid': _shortDid(message.senderDid),
            'isMine': message.isMine,
            'content': message.content,
            'sendState': message.sendState.name,
          },
        )
        .toList(),
  );
}

Future<void> _tapFirstFound(WidgetTester tester, List<Finder> finders) async {
  for (final finder in finders) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.first);
      await _pumpFrame(tester);
      return;
    }
  }
  fail('None of the expected UI targets were found: $finders');
}

Future<void> _pumpFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _waitForFile(String path) async {
  await _poll(
    description: 'file exists: $path',
    action: () async => File(path).existsSync(),
    timeout: const Duration(seconds: 30),
    interval: const Duration(milliseconds: 250),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
  String description = 'UI condition',
  Object? Function()? lastError,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
  final detail = lastError == null ? null : lastError();
  fail(
    'Timed out waiting for $description.'
    '${detail == null ? '' : ' Last error: $detail'}',
  );
}

Future<void> _poll({
  required String description,
  required Future<bool> Function() action,
  Duration timeout = const Duration(seconds: 90),
  Duration interval = const Duration(seconds: 2),
  Object? Function()? lastError,
}) async {
  final deadline = DateTime.now().add(timeout);
  Object? caughtError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await action()) {
        return;
      }
    } on Object catch (error) {
      caughtError = error;
    }
    await Future<void>.delayed(interval);
  }
  final detail = lastError == null ? caughtError : lastError() ?? caughtError;
  fail(
    'Timed out waiting for $description.'
    '${detail == null ? '' : ' Last error: $detail'}',
  );
}

AgentSummary? _agentByDid(AgentsState state, String agentDid) {
  final normalized = agentDid.trim();
  for (final agent in state.agents) {
    if (agent.agentDid == normalized) {
      return agent;
    }
  }
  return null;
}

String _agentsDebugSummary(AgentsState state) {
  return jsonEncode(
    state.agents.map((agent) {
      final diagnostics = agent.latest.diagnosticsSummary;
      final configSummary = diagnostics['config_summary'];
      return <String, Object?>{
        'did': _shortDid(agent.agentDid),
        'kind': agent.kind.name,
        'daemon': _shortDid(agent.daemonAgentDid),
        'runtime': agent.runtime,
        'handle': agent.handle,
        'displayName': agent.displayName,
        'status': agent.latest.status,
        'activeState': agent.activeState,
        'diagnosticsKeys': diagnostics.keys.toList()..sort(),
        'configSummaryKeys': configSummary is Map
            ? (configSummary.keys.map((key) => key.toString()).toList()..sort())
            : const <String>[],
      };
    }).toList(),
  );
}

String? _shortDid(String? did) {
  if (did == null || did.length <= 32) {
    return did;
  }
  return '${did.substring(0, 24)}...${did.substring(did.length - 6)}';
}

bool _daemonSupportsCodex(AgentSummary daemon) {
  final config = _objectMap(daemon.latest.diagnosticsSummary['config_summary']);
  final genericCli = _objectMap(config['generic_cli']);
  final schemaVersion = _intValue(genericCli['capability_schema_version']);
  final drivers = _stringSet(genericCli['supported_drivers']);
  return schemaVersion == 1 && drivers.contains('codex');
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
}

Set<String> _stringSet(Object? value) {
  if (value is! Iterable) {
    return const <String>{};
  }
  return value.map((item) => item.toString()).toSet();
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '');
}

String _codexRuntimeHandle(String runId) {
  final suffix = runId
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final nonce = DateTime.now().toUtc().millisecondsSinceEpoch.toRadixString(36);
  final handle = 'codex-e2e-${suffix.isEmpty ? 'run' : suffix}-$nonce';
  if (handle.length <= 63) {
    return handle;
  }
  return handle.substring(0, 63).replaceAll(RegExp(r'-$'), 'x');
}

String _defaultCodexExpectedReply(String runId) {
  final suffix = runId
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'OK-CODEX-${suffix.isEmpty ? 'E2E' : suffix}';
}

String _defaultCodexPrompt(String runId) {
  return 'Reply exactly ${_defaultCodexExpectedReply(runId)} and nothing else';
}

bool _looksRecoverableForRegister(String output) {
  final lower = output.toLowerCase();
  return lower.contains('not found') ||
      lower.contains('handle_not_found') ||
      lower.contains('not_registered') ||
      lower.contains('not registered') ||
      lower.contains('404');
}

String _sanitizeDiagnostic(String input, _CodexAgentRealBackendConfig config) {
  var output = input;
  for (final secret in config.secrets) {
    final trimmed = secret.trim();
    if (trimmed.isNotEmpty) {
      output = output.replaceAll(trimmed, '<redacted>');
    }
  }
  return output.replaceAll(
    RegExp(
      r'(otp|token|jwt|private[_-]?key|secret|authorization)=([^\s]+)',
      caseSensitive: false,
    ),
    '<redacted-key>=<redacted>',
  );
}

void _terminateProcess(Process process) {
  if (process.kill(ProcessSignal.sigterm)) {
    return;
  }
  process.kill(ProcessSignal.sigkill);
}

class _CodexAgentRealBackendConfig {
  const _CodexAgentRealBackendConfig({
    required this.runId,
    required this.platform,
    required this.environment,
    required this.appHandle,
    required this.otpPhone,
    required this.otpCode,
    required this.appStateRoot,
    required this.daemonBinary,
    required this.daemonStateRoot,
    required this.daemonReadyFile,
    required this.daemonHandle,
    required this.daemonEnvFile,
    required this.enabled,
    required this.realBackend,
    required this.prompt,
    required this.expectedReply,
  });

  static bool get shouldRun {
    final config = tryLoad();
    return config != null && config.enabled && config.realBackend;
  }

  static _CodexAgentRealBackendConfig? tryLoad() {
    final file = File(_codexAgentRunConfigPath);
    if (!file.existsSync()) {
      return null;
    }
    final raw = jsonDecode(file.readAsStringSync());
    if (raw is! Map) {
      throw StateError('$_codexAgentRunConfigPath must be a JSON object.');
    }
    final map = _stringKeyMap(raw, path: _codexAgentRunConfigPath);
    final codexAgent = _optionalMapAt(map, 'codexAgent');
    final enabled = _boolConfig(codexAgent, 'enabled');
    final realBackend = _boolConfig(codexAgent, 'realBackend');
    if (!enabled || !realBackend) {
      return null;
    }
    final service = _mapAt(map, 'service');
    final otp = _mapAt(map, 'otp');
    final accounts = _mapAt(map, 'accounts');
    final appUser = _mapAt(accounts, 'appUser');
    final app = _mapAt(map, 'app');
    final daemon = _mapAt(map, 'daemon');
    final baseUrl = _requiredConfig(service, 'baseUrl', 'service.baseUrl');
    final didDomain = _requiredConfig(
      service,
      'didDomain',
      'service.didDomain',
    );
    final runId = _requiredConfig(map, 'runId', 'runId');
    final expectedReply =
        _optionalConfig(codexAgent, 'expectedReply') ??
        _defaultCodexExpectedReply(runId);
    return _CodexAgentRealBackendConfig(
      runId: runId,
      platform: _requiredConfig(map, 'platform', 'platform'),
      environment: AwikiEnvironmentConfig(
        baseUrl: baseUrl,
        userServiceUrl: _optionalConfig(service, 'userServiceUrl') ?? baseUrl,
        messageServiceUrl:
            _optionalConfig(service, 'messageServiceUrl') ?? baseUrl,
        mailServiceUrl: _optionalConfig(service, 'mailServiceUrl') ?? baseUrl,
        didDomain: didDomain,
        anpServiceUrl:
            _optionalConfig(service, 'anpServiceUrl') ?? '$baseUrl/anp-im/rpc',
        anpServiceDid:
            _optionalConfig(service, 'anpServiceDid') ?? 'did:wba:$didDomain',
        agentImEnabled: true,
      ),
      appHandle: _requiredConfig(appUser, 'handle', 'accounts.appUser.handle'),
      otpPhone: _requiredConfig(otp, 'phone', 'otp.phone'),
      otpCode: _requiredConfig(otp, 'code', 'otp.code'),
      appStateRoot: _requiredConfig(app, 'stateRoot', 'app.stateRoot'),
      daemonBinary: _requiredConfig(daemon, 'binary', 'daemon.binary'),
      daemonStateRoot: _requiredConfig(daemon, 'stateRoot', 'daemon.stateRoot'),
      daemonReadyFile: _requiredConfig(daemon, 'readyFile', 'daemon.readyFile'),
      daemonHandle:
          _optionalConfig(daemon, 'handle') ??
          'codex-agent-daemon-${DateTime.now().millisecondsSinceEpoch}',
      daemonEnvFile: _optionalConfig(daemon, 'envFile'),
      enabled: enabled,
      realBackend: realBackend,
      prompt:
          _optionalConfig(codexAgent, 'prompt') ?? _defaultCodexPrompt(runId),
      expectedReply: expectedReply,
    );
  }

  final String runId;
  final String platform;
  final AwikiEnvironmentConfig environment;
  final String appHandle;
  final String otpPhone;
  final String otpCode;
  final String appStateRoot;
  final String daemonBinary;
  final String daemonStateRoot;
  final String daemonReadyFile;
  final String daemonHandle;
  final String? daemonEnvFile;
  final bool enabled;
  final bool realBackend;
  final String prompt;
  final String expectedReply;

  TargetPlatform get targetPlatform {
    return platform == 'linux' ? TargetPlatform.linux : TargetPlatform.macOS;
  }

  List<String> get secrets => <String>[
    otpPhone,
    otpCode,
    appStateRoot,
    daemonStateRoot,
    daemonReadyFile,
    if (daemonEnvFile != null) daemonEnvFile!,
    ..._daemonEnvFileSecretValues(daemonEnvFile),
  ].where((value) => value.trim().isNotEmpty).toList(growable: false);
}

class _DaemonInstallResult {
  const _DaemonInstallResult({required this.daemonDid, required this.handle});

  final String daemonDid;
  final String handle;
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

class _ProcessResult {
  const _ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.secrets = const <String>[],
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final List<String> secrets;

  String sanitizedSummary(_CodexAgentRealBackendConfig config) {
    return _sanitizeDiagnostic(
      'exit=$exitCode stdout=$stdout stderr=$stderr',
      config,
    );
  }
}

Future<_ProcessResult> _runProcess(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
  Duration timeout = const Duration(seconds: 45),
  List<String> secrets = const <String>[],
}) async {
  final result = await Process.run(
    executable,
    args,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    runInShell: false,
  ).timeout(timeout);
  return _ProcessResult(
    exitCode: result.exitCode,
    stdout: ((result.stdout as String?) ?? '').trim(),
    stderr: ((result.stderr as String?) ?? '').trim(),
    secrets: secrets,
  );
}

Map<String, Object?> _stringKeyMap(Object? value, {required String path}) {
  if (value is! Map) {
    throw StateError('$path must be a JSON object.');
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

Map<String, Object?> _mapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is Map) {
    return _stringKeyMap(value, path: key);
  }
  throw StateError('$key must be configured as an object.');
}

Map<String, Object?> _optionalMapAt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is Map) {
    return _stringKeyMap(value, path: key);
  }
  throw StateError('$key must be configured as an object.');
}

String _requiredConfig(Map<String, Object?> map, String key, String name) {
  final value = _optionalConfig(map, key);
  if (value == null) {
    throw StateError('$name is required in $_codexAgentRunConfigPath.');
  }
  return value;
}

String? _optionalConfig(Map<String, Object?> map, String key) {
  final raw = map[key];
  final value = raw?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

bool _boolConfig(Map<String, Object?> map, String key) {
  final raw = map[key];
  return raw == true || raw?.toString().toLowerCase() == 'true';
}
