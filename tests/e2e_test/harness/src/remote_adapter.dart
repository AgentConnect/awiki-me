import 'dart:io';

import 'agent_im_config.dart';
import 'cli_peer_adapter.dart';
import 'secret_redactor.dart';

final class RemoteEvidenceCommand {
  const RemoteEvidenceCommand({
    required this.label,
    required this.executable,
    required this.args,
  });

  final String label;
  final String executable;
  final List<String> args;

  String get command => [executable, ...args].map(_shellQuote).join(' ');

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'command': command,
  };
}

final class AgentImRemoteAdapter {
  const AgentImRemoteAdapter(this.config);

  final AgentImDelegatedConfig config;

  List<RemoteEvidenceCommand> planEvidenceCommands(String runId) {
    if (!config.remote.collectLogs) {
      return const <RemoteEvidenceCommand>[];
    }
    final alias = config.remote.sshAlias;
    return <RemoteEvidenceCommand>[
      RemoteEvidenceCommand(
        label: 'remote health summary',
        executable: 'ssh',
        args: <String>[alias, _healthScript(runId)],
      ),
      RemoteEvidenceCommand(
        label: 'daemon and hermes logs by runId',
        executable: 'ssh',
        args: <String>[
          alias,
          _journalctlByRunIdScript(
            runId: runId,
            userUnits: const <String>[
              'awiki-deamon.service',
              'hermes-gateway.service',
            ],
            systemUnits: const <String>[],
          ),
        ],
      ),
      RemoteEvidenceCommand(
        label: 'message-service fanout logs by runId',
        executable: 'ssh',
        args: <String>[
          alias,
          _journalctlByRunIdScript(
            runId: runId,
            userUnits: const <String>[],
            systemUnits: const <String>['message-service.service'],
          ),
        ],
      ),
      RemoteEvidenceCommand(
        label: 'user-service delegated DID logs by runId',
        executable: 'ssh',
        args: <String>[
          alias,
          _journalctlByRunIdScript(
            runId: runId,
            userUnits: const <String>[],
            systemUnits: const <String>['user-service.service'],
          ),
        ],
      ),
    ];
  }
}

final class AgentImRemoteEvidenceCollector {
  const AgentImRemoteEvidenceCollector({
    this.redactor = const SecretRedactor(),
  });

  final SecretRedactor redactor;

  Future<AgentImRemoteEvidenceResult> collect({
    required List<RemoteEvidenceCommand> commands,
    required AgentImCliCommandRunner runner,
    required Directory workingDirectory,
    required Directory reportDir,
  }) async {
    final entries = <AgentImRemoteEvidenceEntry>[];
    for (final command in commands) {
      final logFile = File(
        '${reportDir.path}/remote-${_slug(command.label)}.log',
      );
      final result = await runner.run(
        command.executable,
        command.args,
        workingDirectory: workingDirectory,
        logFile: logFile,
        timeout: const Duration(minutes: 2),
      );
      entries.add(
        AgentImRemoteEvidenceEntry(
          label: command.label,
          command: command.command,
          logFile: logFile.path,
          stdoutSummary: _summary(result.stdoutText),
          stderrSummary: _summary(result.stderrText),
        ),
      );
    }
    return AgentImRemoteEvidenceResult(entries: entries);
  }

  String _summary(String text) {
    final redacted = redactor.redact(text.trim());
    if (redacted.length <= 2000) {
      return redacted;
    }
    return '${redacted.substring(0, 2000)}\n<TRUNCATED>';
  }
}

final class AgentImRemoteEvidenceResult {
  const AgentImRemoteEvidenceResult({required this.entries});

  final List<AgentImRemoteEvidenceEntry> entries;

  Map<String, Object?> toJson() => <String, Object?>{
    'count': entries.length,
    'entries': [for (final entry in entries) entry.toJson()],
  };
}

final class AgentImRemoteEvidenceEntry {
  const AgentImRemoteEvidenceEntry({
    required this.label,
    required this.command,
    required this.logFile,
    required this.stdoutSummary,
    required this.stderrSummary,
  });

  final String label;
  final String command;
  final String logFile;
  final String stdoutSummary;
  final String stderrSummary;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'command': command,
    'logFile': logFile,
    'stdoutSummary': stdoutSummary,
    'stderrSummary': stderrSummary,
  };
}

String _healthScript(String runId) => [
  'echo remote-health runId=${_singleQuote(runId)}',
  'date -u +%Y-%m-%dT%H:%M:%SZ',
  _listUnitsScript('--user'),
  _listUnitsScript(''),
].join('; ');

String _listUnitsScript(String scope) {
  final systemctl = scope.isEmpty ? 'systemctl' : 'systemctl $scope';
  return '($systemctl --no-pager --no-legend list-units --type=service '
      '2>/dev/null || true) | grep -Ei '
      r"'awiki|hermes|message-service|user-service|molt-message|deamon|daemon'"
      " | sed -E 's/[[:space:]]+/ /g' || true";
}

String _journalctlByRunIdScript({
  required String runId,
  required List<String> userUnits,
  required List<String> systemUnits,
}) {
  final parts = <String>[];
  if (userUnits.isNotEmpty) {
    parts.add(_journalctlPart(runId: runId, scope: '--user', units: userUnits));
  }
  if (systemUnits.isNotEmpty) {
    parts.add(_journalctlPart(runId: runId, scope: '', units: systemUnits));
  }
  if (parts.isEmpty) {
    return 'true';
  }
  return parts.join('; ');
}

String _journalctlPart({
  required String runId,
  required String scope,
  required List<String> units,
}) {
  final unitArgs = units.map((unit) => '-u ${_singleQuote(unit)}').join(' ');
  final journalctl = scope.isEmpty ? 'journalctl' : 'journalctl $scope';
  return '($journalctl $unitArgs --since ${_singleQuote('2 hours ago')} '
      '--no-pager 2>/dev/null || true) | grep -F ${_singleQuote(runId)} '
      '| tail -n 120 || true';
}

String _slug(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

String _singleQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

String _shellQuote(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:=@+,$-]+$').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}
