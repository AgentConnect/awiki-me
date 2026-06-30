import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/domain/entities/agent/agent_bootstrap.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_command.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_control_payloads.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';

Future<void> main(List<String> args) async {
  try {
    final result = await _run(args);
    stdout.writeln(jsonEncode(result));
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    if (error.showUsage) {
      stderr.writeln(_usage);
    }
    exitCode = error.exitCode;
  } on Object catch (error) {
    stderr.writeln(error.toString());
    exitCode = 1;
  }
}

Future<Map<String, Object?>> _run(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    return <String, Object?>{'usage': _usageLines};
  }
  final command = args.first;
  final options = _parseOptions(args.skip(1).toList(growable: false));
  return switch (command) {
    'create-agent' => _createAgent(options),
    'message-agent-bootstrap' => await _messageAgentBootstrap(options),
    'submit-task' => _submitTask(options),
    'parse-status' => await _parseStatus(options),
    'classify-payload' => await _classifyPayload(options),
    'parse-inventory' => await _parseInventory(options),
    _ => throw _UsageException('unknown command: $command'),
  };
}

Map<String, Object?> _createAgent(Map<String, String> options) {
  final driverConfig = _jsonObjectOption(options, 'driver-config-json');
  final payload = runtimeAgentCreatePayload(
    controllerDid: _required(options, 'controller-did'),
    registrationToken: _required(options, 'registration-token'),
    clientRequestId: options['client-request-id'] ?? agentCommandId('app_req'),
    runtime: options['runtime'] ?? 'hermes',
    displayName: options['name'] ?? options['display-name'] ?? 'Hermes',
    handle: options['handle'],
    workspace: options['workspace'],
    driverId: options['driver-id'],
    workspaceMode: options['workspace-mode'],
    defaultSandbox: options['default-sandbox'],
    defaultModel: options['default-model'],
    preferredLanguage: options['preferred-language'] ?? 'zh-Hans',
    driverConfig: driverConfig,
  );
  return <String, Object?>{'payload': payload};
}

Future<Map<String, Object?>> _messageAgentBootstrap(
  Map<String, String> options,
) async {
  final controllerDid = _required(options, 'controller-did');
  final daemonAgentDid = _required(options, 'daemon-agent-did');
  final appInstanceId = _required(options, 'app-instance-id');
  final runId = options['run-id'];
  final userSubkeyPackage = UserSubkeyPackage(
    userDid: controllerDid,
    verificationMethod: _required(options, 'verification-method'),
    publicKeyMultibase: _required(options, 'public-key-multibase'),
    privateKeyPem: await _readPrivateKeyPem(options),
    keyType: options['key-type'] ?? 'Multikey/Ed25519',
    keyAlgorithm: options['key-algorithm'] ?? 'Ed25519',
    privateKeyEncoding: options['private-key-encoding'] ?? 'pem',
    allowedScopes:
        _csvOption(options, 'allowed-scopes') ?? defaultMessageAgentScopes,
  );
  final envelope = DaemonBootstrapEnvelope(
    bootstrapId: messageAgentBootstrapAttemptId(
      userDid: controllerDid,
      appInstanceId: appInstanceId,
      runId: runId,
    ),
    idempotencyKey: messageAgentBootstrapAttemptIdempotencyKey(
      userDid: controllerDid,
      appInstanceId: appInstanceId,
      runId: runId,
    ),
    appInstanceId: appInstanceId,
    controllerDid: controllerDid,
    userHandle: options['user-handle'],
    runId: runId,
    userSubkeyPackage: userSubkeyPackage,
    desiredMessageAgent: DesiredMessageAgent(
      preferredLanguage: options['preferred-language'] ?? 'zh-Hans',
      ensureOnceKey: messageAgentEnsureOnceKey(
        userDid: controllerDid,
        appInstanceId: appInstanceId,
      ),
      runtimeRegistrationToken: options['runtime-registration-token'],
    ),
  );
  final payload = await DaemonSecureBootstrapEncryptor().encrypt(
    internalEnvelope: envelope,
    recipientDaemonDid: daemonAgentDid,
    recipientKey: DaemonBootstrapPublicKey(
      keyId: _required(options, 'recipient-key-id'),
      publicKeyB64u: _required(options, 'recipient-public-key-b64u'),
      publicKeyMultibase: options['recipient-public-key-multibase'],
      algorithm: options['recipient-key-algorithm'] ?? 'x25519',
    ),
  );
  return <String, Object?>{'payload': payload};
}

Map<String, Object?> _submitTask(Map<String, String> options) {
  final payload = runtimeTaskSubmitPayload(
    runtimeAgentDid: _required(options, 'runtime-agent-did'),
    text: _required(options, 'text'),
    commandId: options['command-id'],
    taskId: options['task-id'],
    conversationId: options['conversation-id'],
  );
  return <String, Object?>{'payload': payload};
}

Future<Map<String, Object?>> _parseStatus(Map<String, String> options) async {
  final payloadJson = await _readPayloadJson(options);
  final payload = AgentControlPayloads.decode(payloadJson);
  final runs = _list(payload?['runs']);
  final firstRun = runs.whereType<Map>().isEmpty
      ? const <String, Object?>{}
      : _objectMap(runs.whereType<Map>().first);
  return <String, Object?>{
    'is_control': AgentControlPayloads.isControl(payloadJson),
    'is_status': AgentControlPayloads.isStatus(payloadJson),
    'renderable': !AgentControlPayloads.isControl(payloadJson),
    'schema': payload?['schema'],
    'status_scope': payload?['status_scope'],
    'state': payload?['state'] ?? firstRun['status'],
    'run_id': payload?['run_id'] ?? firstRun['run_id'],
    'runtime_agent_did': firstRun['runtime_agent_did'],
    'daemon_agent_did': payload?['daemon_agent_did'],
    'message': payload?['message'],
  };
}

Future<Map<String, Object?>> _classifyPayload(
  Map<String, String> options,
) async {
  final payloadJson = await _readPayloadJson(options);
  final payload = AgentControlPayloads.decode(payloadJson);
  return <String, Object?>{
    'is_control': AgentControlPayloads.isControl(payloadJson),
    'is_command': AgentControlPayloads.isCommand(payloadJson),
    'is_status': AgentControlPayloads.isStatus(payloadJson),
    'renderable': !AgentControlPayloads.isControl(payloadJson),
    'schema': payload?['schema'],
    'command': payload?['command'],
  };
}

Future<Map<String, Object?>> _parseInventory(
  Map<String, String> options,
) async {
  final payloadJson = await _readPayloadJson(options);
  final decoded = jsonDecode(payloadJson);
  final agentsValue = decoded is Map ? decoded['agents'] : decoded;
  final agents = _list(agentsValue)
      .whereType<Map>()
      .map((item) => AgentSummary.fromJson(_objectMap(item)))
      .map(
        (agent) => <String, Object?>{
          'agent_did': agent.agentDid,
          'agent_kind': agent.kind == AgentKind.daemon ? 'daemon' : 'runtime',
          'daemon_agent_did': agent.daemonAgentDid,
          'runtime': agent.runtime,
          'handle': agent.handle,
          'display_name': agent.displayName,
          'active_state': agent.activeState,
          'status': agent.latest.status,
          'service': agent.latest.service,
          'diagnostics_summary': agent.latest.diagnosticsSummary,
        },
      )
      .toList(growable: false);
  return <String, Object?>{'agents': agents, 'count': agents.length};
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (!arg.startsWith('--')) {
      throw _UsageException('unexpected argument: $arg');
    }
    final equals = arg.indexOf('=');
    if (equals > 2) {
      options[arg.substring(2, equals)] = arg.substring(equals + 1);
      continue;
    }
    final name = arg.substring(2);
    if (name == 'stdin') {
      options[name] = 'true';
      continue;
    }
    if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
      throw _UsageException('missing value for --$name');
    }
    options[name] = args[index + 1];
    index += 1;
  }
  return options;
}

Future<String> _readPrivateKeyPem(Map<String, String> options) async {
  if (options.containsKey('private-key-pem-file')) {
    return File(_required(options, 'private-key-pem-file')).readAsString();
  }
  return _required(options, 'private-key-pem');
}

Future<String> _readPayloadJson(Map<String, String> options) async {
  if (options.containsKey('json')) {
    return _required(options, 'json');
  }
  if (options.containsKey('json-file')) {
    return File(_required(options, 'json-file')).readAsString();
  }
  if (options.containsKey('stdin')) {
    return stdin.transform(utf8.decoder).join();
  }
  throw const _UsageException(
    'one of --json, --json-file, or --stdin is required',
  );
}

String _required(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    throw _UsageException('missing required option --$name');
  }
  return value;
}

Map<String, Object?> _objectMap(Map<dynamic, dynamic> value) {
  return value.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value as Object?),
  );
}

List<Object?> _list(Object? value) {
  return value is List ? value : const <Object?>[];
}

List<String>? _csvOption(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, Object?>? _jsonObjectOption(
  Map<String, String> options,
  String name,
) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw _UsageException('--$name must decode to a JSON object');
  }
  return decoded.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value as Object?),
  );
}

const _usageLines = <String>[
  'daemon_control_probe.dart <command> [options]',
  '',
  'Commands:',
  '  create-agent --controller-did DID --registration-token TOKEN [--daemon-agent-did DID] [--runtime RUNTIME] [--driver-id DRIVER] [--name NAME] [--client-request-id ID] [--handle HANDLE] [--workspace PATH] [--workspace-mode MODE] [--default-sandbox MODE] [--default-model MODEL] [--driver-config-json JSON]',
  '  message-agent-bootstrap --controller-did DID --daemon-agent-did DID --app-instance-id ID --verification-method DID#daemon-key-1 --public-key-multibase KEY --private-key-pem-file PATH --recipient-key-id DID#key-3 --recipient-public-key-b64u KEY [--runtime-registration-token TOKEN] [--run-id ID]',
  '  submit-task --runtime-agent-did DID --text TEXT [--command-id ID] [--task-id ID] [--conversation-id ID]',
  '  parse-status (--json JSON | --json-file PATH | --stdin)',
  '  classify-payload (--json JSON | --json-file PATH | --stdin)',
  '  parse-inventory (--json JSON | --json-file PATH | --stdin)',
];

final _usage = _usageLines.join('\n');

final class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
  int get exitCode => 64;
  bool get showUsage => true;

  @override
  String toString() => message;
}
