import 'dart:convert';
import 'dart:io';

import 'agent_im_config.dart';
import 'cli_peer_adapter.dart';
import 'secret_redactor.dart';

final class AgentImAppProbeAdapter {
  AgentImAppProbeAdapter({
    required this.config,
    required this.configFile,
    required this.appRepo,
    required this.reportDir,
    required this.runner,
    required this.dryRun,
    this.redactor = const SecretRedactor(),
  });

  final AgentImDelegatedConfig config;
  final File configFile;
  final Directory appRepo;
  final Directory reportDir;
  final AgentImCliCommandRunner runner;
  final bool dryRun;
  final SecretRedactor redactor;

  Future<AgentImAppProbeBootstrapResult> bootstrap({
    required String runId,
  }) async {
    final result = await _run('app-probe-bootstrap', <String>[
      'bootstrap',
      '--config',
      _configPath(),
      '--run-id',
      runId,
    ], timeout: config.timeouts.bootstrap);
    return AgentImAppProbeBootstrapResult.fromJson(_decodeJson(result));
  }

  Future<AgentImAppProbeReturnResult> waitForReturn({
    required String runId,
    String? sourceMessageId,
  }) async {
    final args = <String>[
      'wait-return',
      '--config',
      _configPath(),
      '--run-id',
      runId,
      if (sourceMessageId != null && sourceMessageId.trim().isNotEmpty) ...[
        '--source-message-id',
        sourceMessageId.trim(),
      ],
    ];
    final result = await _run(
      'app-probe-wait-return',
      args,
      timeout: config.timeouts.messageProcess + const Duration(seconds: 15),
    );
    return AgentImAppProbeReturnResult.fromJson(_decodeJson(result));
  }

  Future<AgentImCliCommandResult> _run(
    String label,
    List<String> args, {
    required Duration timeout,
  }) {
    return runner.run(
      _dartExecutable(),
      <String>['run', 'tool/agent_im_real_e2e_probe.dart', ...args],
      workingDirectory: appRepo,
      environment: <String, String>{
        if (_macOsDylibPath() != null)
          'AWIKI_IM_CORE_DYLIB': _macOsDylibPath()!,
        'AWIKI_BASE_URL': config.service.baseUrl,
        'AWIKI_USER_SERVICE_URL': config.service.userServiceUrl,
        'AWIKI_MESSAGE_SERVICE_URL': config.service.messageServiceUrl,
        'AWIKI_DID_DOMAIN': config.service.didDomain,
      },
      logFile: File('${reportDir.path}/$label.log'),
      timeout: timeout,
    );
  }

  String? _macOsDylibPath() {
    if (!Platform.isMacOS) {
      return null;
    }
    final candidates = <File>[
      File(
        '${appRepo.parent.path}/awiki-cli-rs2/target/release/libawiki_im_core.dylib',
      ),
      File(
        '${appRepo.parent.path}/awiki-cli-rs2/target/debug/libawiki_im_core.dylib',
      ),
    ];
    for (final candidate in candidates) {
      if (candidate.existsSync()) {
        return candidate.absolute.path;
      }
    }
    return candidates.first.absolute.path;
  }

  String _configPath() => configFile.absolute.path;

  String _dartExecutable() {
    final flutterRoot = Platform.environment['FLUTTER_ROOT']?.trim();
    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      final dart = File('$flutterRoot/bin/dart');
      if (dart.existsSync()) {
        return dart.path;
      }
    }
    const localFlutterDart = '/Users/cs/development/flutter/bin/dart';
    if (File(localFlutterDart).existsSync()) {
      return localFlutterDart;
    }
    return 'dart';
  }

  Map<String, Object?> _decodeJson(AgentImCliCommandResult result) {
    final text = result.stdoutText.trim();
    if (text.isEmpty) {
      throw const AgentImAppProbeFailure('App probe produced empty stdout.');
    }
    final jsonText = _extractJsonObject(text);
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        return decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value as Object?),
        );
      }
    } on Object catch (error) {
      throw AgentImAppProbeFailure('App probe stdout was not JSON: $error');
    }
    throw const AgentImAppProbeFailure(
      'App probe stdout was not a JSON object.',
    );
  }

  String _extractJsonObject(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{')) {
      return trimmed;
    }
    final start = trimmed.indexOf('{');
    if (start < 0) {
      throw const AgentImAppProbeFailure(
        'App probe stdout did not contain a JSON object.',
      );
    }
    return trimmed.substring(start).trim();
  }
}

final class AgentImAppProbeBootstrapResult {
  const AgentImAppProbeBootstrapResult({
    required this.runId,
    required this.appDid,
    required this.appHandle,
    required this.daemonDid,
    required this.appInstanceId,
    required this.bootstrap,
    required this.raw,
  });

  factory AgentImAppProbeBootstrapResult.fromJson(Map<String, Object?> json) {
    return AgentImAppProbeBootstrapResult(
      runId: json['runId']?.toString() ?? '',
      appDid: json['appDid']?.toString() ?? '',
      appHandle: json['appHandle']?.toString() ?? '',
      daemonDid: json['daemonDid']?.toString() ?? '',
      appInstanceId: json['appInstanceId']?.toString() ?? '',
      bootstrap: _map(json['bootstrap']),
      raw: json,
    );
  }

  final String runId;
  final String appDid;
  final String appHandle;
  final String daemonDid;
  final String appInstanceId;
  final Map<String, Object?> bootstrap;
  final Map<String, Object?> raw;

  bool get sent => bootstrap['sent'] == true;
  bool get hiddenFromChat => bootstrap['hiddenFromChat'] == true;
  String? get idempotencyKey => bootstrap['idempotencyKey']?.toString();

  Map<String, Object?> toJson() => raw;
}

final class AgentImAppProbeReturnResult {
  const AgentImAppProbeReturnResult({
    required this.runId,
    required this.daemonDid,
    required this.sourceMessageId,
    required this.returnEvidence,
    required this.raw,
  });

  factory AgentImAppProbeReturnResult.fromJson(Map<String, Object?> json) {
    return AgentImAppProbeReturnResult(
      runId: json['runId']?.toString() ?? '',
      daemonDid: json['daemonDid']?.toString() ?? '',
      sourceMessageId: json['sourceMessageId']?.toString(),
      returnEvidence: _map(json['returnEvidence']),
      raw: json,
    );
  }

  final String runId;
  final String daemonDid;
  final String? sourceMessageId;
  final Map<String, Object?> returnEvidence;
  final Map<String, Object?> raw;

  bool get detected => returnEvidence['detected'] == true;
  Map<String, Object?>? get matched {
    final value = returnEvidence['matched'];
    return value is Map ? _map(value) : null;
  }

  bool get hiddenFromChat {
    final current = matched;
    if (current == null) {
      return false;
    }
    return current['isControl'] == true &&
        (current['hiddenFromChat'] == true || current['renderable'] == false);
  }

  String? get matchedSchema => matched?['schema']?.toString();

  Map<String, Object?> toJson() => raw;
}

final class AgentImAppProbeFailure implements Exception {
  const AgentImAppProbeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, Object?> _map(Object? value) {
  if (value is Map) {
    return value.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
  }
  return const <String, Object?>{};
}
