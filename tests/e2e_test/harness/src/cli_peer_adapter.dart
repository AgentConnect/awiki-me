import 'dart:convert';
import 'dart:io';

import 'agent_im_config.dart';
import 'secret_redactor.dart';

abstract interface class AgentImCliCommandRunner {
  Future<AgentImCliCommandResult> run(
    String executable,
    List<String> args, {
    required Directory workingDirectory,
    Map<String, String>? environment,
    File? logFile,
    Duration timeout = const Duration(minutes: 5),
  });
}

class AgentImCliCommandResult {
  const AgentImCliCommandResult({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}

typedef AgentImEnvReader = String? Function(String name);

final class AgentImCliPeerAdapter {
  AgentImCliPeerAdapter({
    required this.config,
    required this.cliRepo,
    required this.binary,
    required this.workspace,
    required this.reportDir,
    required this.runner,
    required this.dryRun,
    AgentImEnvReader? envReader,
    this.redactor = const SecretRedactor(),
  }) : envReader = envReader ?? ((name) => Platform.environment[name]);

  final AgentImDelegatedConfig config;
  final Directory cliRepo;
  final File binary;
  final Directory workspace;
  final Directory reportDir;
  final AgentImCliCommandRunner runner;
  final bool dryRun;
  final AgentImEnvReader envReader;
  final SecretRedactor redactor;

  AgentImCliPeerPlan buildPlan({
    required String runId,
    required String targetHandle,
    required String messageText,
  }) {
    return AgentImCliPeerPlan(
      runId: runId,
      peerHandle: config.accounts.peerUser.handle,
      targetHandle: targetHandle,
      workspace: workspace.path,
      binary: binary.path,
      commands: AgentImCliPeerAdapterPlan.commands(
        config: config,
        runId: runId,
        targetHandle: targetHandle,
        messageText: messageText,
      ),
    );
  }

  Future<AgentImCliPeerFlowResult> runOrdinaryMessageFlow({
    required String runId,
    required String targetHandle,
    required String messageText,
  }) async {
    final commandLabels = <String>[];
    await initWorkspace();
    commandLabels.add('initWorkspace');
    await loginOrRestorePeer();
    commandLabels.add('loginOrRestorePeer');
    final sendResult = await sendOrdinaryMessage(
      runId: runId,
      targetHandle: targetHandle,
      messageText: messageText,
    );
    commandLabels.add('sendOrdinaryMessage');
    return AgentImCliPeerFlowResult(
      runId: runId,
      peerHandle: config.accounts.peerUser.handle,
      targetHandle: targetHandle,
      workspace: workspace.path,
      commandLabels: commandLabels,
      sendResult: sendResult,
    );
  }

  Future<void> initWorkspace() async {
    workspace.createSync(recursive: true);
    await _run('cli-peer-init', const <String>[
      'init',
    ], timeout: const Duration(minutes: 2));
    if (dryRun) {
      return;
    }
    _rewriteCliConfig();
  }

  Future<void> loginOrRestorePeer() async {
    if (!dryRun && await _refreshExistingPeerSession()) {
      return;
    }

    final account = config.accounts.peerUser;
    final phone = _secretFromEnv(account.phoneEnv, 'peer phone');
    final otp = _secretFromEnv(account.otpEnv, 'peer OTP');
    try {
      await _recoverPeer(account: account, phone: phone, otp: otp);
    } on Object {
      await _registerPeer(account: account, phone: phone, otp: otp);
    }
    await _refreshPeerSession();
  }

  Future<bool> _refreshExistingPeerSession() async {
    try {
      await _refreshPeerSession();
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _refreshPeerSession() async {
    final account = config.accounts.peerUser;
    await _run('cli-peer-refresh-token', <String>[
      '--format',
      'json',
      '--identity',
      account.handle,
      'id',
      'refresh-token',
    ], timeout: const Duration(minutes: 2));
    await _run('cli-peer-id-status', <String>[
      '--format',
      'json',
      '--identity',
      account.handle,
      'id',
      'status',
    ], timeout: const Duration(minutes: 2));
  }

  Future<void> _recoverPeer({
    required AgentImAccountConfig account,
    required String phone,
    required String otp,
  }) {
    return _run('cli-peer-id-recover', <String>[
      '--format',
      'json',
      '--identity',
      account.handle,
      'id',
      'recover',
      '--handle',
      account.handle,
      '--phone',
      phone,
      '--otp',
      otp,
    ], timeout: const Duration(minutes: 3));
  }

  Future<void> _registerPeer({
    required AgentImAccountConfig account,
    required String phone,
    required String otp,
  }) {
    return _run('cli-peer-id-register', <String>[
      '--format',
      'json',
      '--identity',
      account.handle,
      'id',
      'register',
      '--handle',
      account.handle,
      '--phone',
      phone,
      '--otp',
      otp,
    ], timeout: const Duration(minutes: 3));
  }

  Future<AgentImCliPeerSendResult> sendOrdinaryMessage({
    required String runId,
    required String targetHandle,
    required String messageText,
  }) async {
    final messageId = _messageIdForRun(runId);
    final result = await _run('cli-peer-msg-send', <String>[
      '--format',
      'json',
      '--identity',
      config.accounts.peerUser.handle,
      'msg',
      'send',
      '--to',
      targetHandle,
      '--text',
      messageText,
      '--client-message-id',
      messageId,
      '--idempotency-key',
      messageId,
    ], timeout: config.timeouts.messageProcess);
    return AgentImCliPeerSendResult(
      targetHandle: targetHandle,
      requestedMessageId: messageId,
      stdoutSummary: _safeJsonSummary(result.stdoutText),
    );
  }

  Future<AgentImCliCommandResult> _run(
    String label,
    List<String> args, {
    required Duration timeout,
  }) {
    final homeDir = Directory('${workspace.path}/home')
      ..createSync(recursive: true);
    return runner.run(
      binary.path,
      args,
      workingDirectory: cliRepo,
      environment: <String, String>{
        'AWIKI_CLI_WORKSPACE_HOME_DIR': workspace.path,
        'HOME': homeDir.path,
      },
      logFile: File('${reportDir.path}/$label.log'),
      timeout: timeout,
    );
  }

  String _secretFromEnv(String envName, String description) {
    if (dryRun) {
      return r'$' + envName;
    }
    final value = envReader(envName)?.trim();
    if (value == null || value.isEmpty) {
      throw AgentImCliPeerFailure(
        'Missing $description environment variable: $envName',
      );
    }
    return value;
  }

  void _rewriteCliConfig() {
    final configFile = File('${workspace.path}/config.yaml');
    if (!configFile.existsSync()) {
      throw AgentImCliPeerFailure(
        'CLI peer config file was not created: ${configFile.path}',
      );
    }
    var text = configFile.readAsStringSync();
    text = _replaceYamlValue(text, 'service_base_url', config.service.baseUrl);
    text = _replaceYamlValue(text, 'did_domain', config.service.didDomain);
    text = _replaceYamlValue(
      text,
      'anp_service_endpoint',
      '${config.service.baseUrl}/anp-im/rpc',
    );
    text = _replaceYamlValue(
      text,
      'anp_service_did',
      'did:wba:${config.service.didDomain}',
    );
    text = _replaceYamlValue(text, 'mail_service_url', config.service.baseUrl);
    configFile.writeAsStringSync(text);
  }

  Object? _safeJsonSummary(String stdoutText) {
    final trimmed = stdoutText.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(trimmed);
      return redactor.redactJson(decoded);
    } on FormatException {
      return redactor.redact(trimmed);
    }
  }
}

final class AgentImCliPeerAdapterPlan {
  const AgentImCliPeerAdapterPlan._();

  static String defaultOrdinaryMessageText(String runId) =>
      'Agent IM E2E ordinary message runId=$runId';

  static List<AgentImCliPeerPlannedCommand> commands({
    required AgentImDelegatedConfig config,
    required String runId,
    required String targetHandle,
    required String messageText,
  }) {
    final account = config.accounts.peerUser;
    return <AgentImCliPeerPlannedCommand>[
      const AgentImCliPeerPlannedCommand(
        label: 'initialize configured CLI peer workspace',
        args: <String>['init'],
        usesEnvVars: <String>[],
      ),
      AgentImCliPeerPlannedCommand(
        label: 'refresh existing CLI peer token',
        args: <String>[
          '--format',
          'json',
          '--identity',
          account.handle,
          'id',
          'refresh-token',
        ],
        usesEnvVars: const <String>[],
      ),
      AgentImCliPeerPlannedCommand(
        label: 'verify existing CLI peer identity status',
        args: <String>[
          '--format',
          'json',
          '--identity',
          account.handle,
          'id',
          'status',
        ],
        usesEnvVars: const <String>[],
      ),
      AgentImCliPeerPlannedCommand(
        label: 'recover CLI peer identity when reuse fails',
        args: <String>[
          '--format',
          'json',
          '--identity',
          account.handle,
          'id',
          'recover',
          '--handle',
          account.handle,
          '--phone',
          r'$' + account.phoneEnv,
          '--otp',
          r'$' + account.otpEnv,
        ],
        usesEnvVars: <String>[account.phoneEnv, account.otpEnv],
      ),
      AgentImCliPeerPlannedCommand(
        label: 'register CLI peer identity when recover finds no handle',
        args: <String>[
          '--format',
          'json',
          '--identity',
          account.handle,
          'id',
          'register',
          '--handle',
          account.handle,
          '--phone',
          r'$' + account.phoneEnv,
          '--otp',
          r'$' + account.otpEnv,
        ],
        usesEnvVars: <String>[account.phoneEnv, account.otpEnv],
      ),
      AgentImCliPeerPlannedCommand(
        label: 'send ordinary non-E2EE runId message',
        args: <String>[
          '--format',
          'json',
          '--identity',
          account.handle,
          'msg',
          'send',
          '--to',
          targetHandle,
          '--text',
          messageText,
          '--client-message-id',
          _messageIdForRun(runId),
          '--idempotency-key',
          _messageIdForRun(runId),
        ],
        usesEnvVars: const <String>[],
      ),
    ];
  }
}

final class AgentImCliPeerPlan {
  const AgentImCliPeerPlan({
    required this.runId,
    required this.peerHandle,
    required this.targetHandle,
    required this.workspace,
    required this.binary,
    required this.commands,
  });

  final String runId;
  final String peerHandle;
  final String targetHandle;
  final String workspace;
  final String binary;
  final List<AgentImCliPeerPlannedCommand> commands;

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'peerHandle': peerHandle,
    'targetHandle': targetHandle,
    'workspace': workspace,
    'binary': binary,
    'commands': [for (final command in commands) command.toJson(binary)],
  };
}

final class AgentImCliPeerPlannedCommand {
  const AgentImCliPeerPlannedCommand({
    required this.label,
    required this.args,
    required this.usesEnvVars,
  });

  final String label;
  final List<String> args;
  final List<String> usesEnvVars;

  Map<String, Object?> toJson(String binary) => <String, Object?>{
    'label': label,
    'command': [binary, ...args].map(_shellQuote).join(' '),
    'usesEnvVars': usesEnvVars,
  };
}

final class AgentImCliPeerFlowResult {
  const AgentImCliPeerFlowResult({
    required this.runId,
    required this.peerHandle,
    required this.targetHandle,
    required this.workspace,
    required this.commandLabels,
    required this.sendResult,
  });

  final String runId;
  final String peerHandle;
  final String targetHandle;
  final String workspace;
  final List<String> commandLabels;
  final AgentImCliPeerSendResult sendResult;

  Map<String, Object?> toJson() => <String, Object?>{
    'runId': runId,
    'peerHandle': peerHandle,
    'targetHandle': targetHandle,
    'workspace': workspace,
    'commandLabels': commandLabels,
    'sendResult': sendResult.toJson(),
  };
}

final class AgentImCliPeerSendResult {
  const AgentImCliPeerSendResult({
    required this.targetHandle,
    required this.requestedMessageId,
    required this.stdoutSummary,
  });

  final String targetHandle;
  final String requestedMessageId;
  final Object? stdoutSummary;

  String? get messageId =>
      _findStringByKey(stdoutSummary, const <String>{
        'message_id',
        'messageId',
        'id',
      }) ??
      requestedMessageId;

  Map<String, Object?> toJson() => <String, Object?>{
    'targetHandle': targetHandle,
    'requestedMessageId': requestedMessageId,
    'stdoutSummary': stdoutSummary,
    if (messageId != null) 'messageId': messageId,
  };
}

final class AgentImCliPeerFailure implements Exception {
  const AgentImCliPeerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

String _replaceYamlValue(String text, String key, String value) {
  final lines = text.split('\n');
  var replaced = false;
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('$key:')) {
      final indent = line.substring(0, line.length - trimmed.length);
      lines[index] = '$indent$key: $value';
      replaced = true;
    }
  }
  if (!replaced) {
    throw AgentImCliPeerFailure('Cannot find key "$key" in CLI config.yaml.');
  }
  return lines.join('\n');
}

String _shellQuote(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:=@+,$-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

String _messageIdForRun(String runId) {
  final safe = runId
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'msg_agent_im_${safe.isEmpty ? 'run' : safe}';
}

String? _findStringByKey(Object? value, Set<String> keys) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final entryValue = entry.value;
      if (keys.contains(key) && entryValue is String && entryValue.isNotEmpty) {
        return entryValue;
      }
    }
    for (final entry in value.entries) {
      final found = _findStringByKey(entry.value, keys);
      if (found != null) {
        return found;
      }
    }
  }
  if (value is List) {
    for (final item in value) {
      final found = _findStringByKey(item, keys);
      if (found != null) {
        return found;
      }
    }
  }
  return null;
}
