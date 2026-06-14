import 'dart:io';

import 'agent_im_config.dart';
import 'cli_peer_adapter.dart';
import 'secret_redactor.dart';

const agentImRequiredRemoteStages = <String>[
  'daemon_bootstrap_received',
  'delegated_key_imported',
  'hermes_agent_ready',
  'cli_message_received',
  'hermes_runtime_finished',
  'summary_return_sent',
];

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
        label: 'daemon sqlite evidence by runId',
        executable: 'ssh',
        args: <String>[alias, _daemonSqliteEvidenceScript(runId)],
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
    final observedStages = _extractStages(entries);
    final missingStages = <String>[
      for (final stage in agentImRequiredRemoteStages)
        if (!observedStages.contains(stage)) stage,
    ];
    return AgentImRemoteEvidenceResult(
      entries: entries,
      observedStages: observedStages,
      missingStages: missingStages,
    );
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
  const AgentImRemoteEvidenceResult({
    required this.entries,
    required this.observedStages,
    required this.missingStages,
  });

  final List<AgentImRemoteEvidenceEntry> entries;
  final Set<String> observedStages;
  final List<String> missingStages;

  bool get passed => missingStages.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'passed': passed,
    'requiredStages': agentImRequiredRemoteStages,
    'observedStages': observedStages.toList()..sort(),
    'missingStages': missingStages,
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

String agentImBootstrapReadyWaitScript(String runId) {
  return [
    'RUN_ID=${_singleQuote(runId)}',
    r'''find_db() {
  for p in \
    "${AWIKI_DAEMON_STATE_ROOT:-}/daemon.db" \
    "${AWIKI_DEAMON_STATE_ROOT:-}/daemon.db" \
    "$HOME/.awiki-daemon/deamon/state/daemon.db" \
    "$HOME/.awiki-deamon/deamon/state/daemon.db" \
    "$HOME/awiki-space/awiki-cli-rs2/.awiki-daemon/deamon/state/daemon.db" \
    "$HOME/work/agents/awiki-space/awiki-cli-rs2/.awiki-daemon/deamon/state/daemon.db"; do
    [ -n "$p" ] && [ -f "$p" ] && { echo "$p"; return 0; }
  done
  find "$HOME" -maxdepth 5 -type f -name daemon.db 2>/dev/null | head -n 1
}
DB="$(find_db)"
echo "E2E_WAIT bootstrap_ready runId=$RUN_ID db=${DB:-<missing>}"
if [ -z "$DB" ] || [ ! -f "$DB" ]; then
  echo "E2E_WAIT bootstrap_ready missing_db"
  exit 1
fi
if command -v sqlite3 >/dev/null 2>&1; then
  q() { sqlite3 -readonly "$DB" "$1" 2>/dev/null || true; }
elif command -v python3 >/dev/null 2>&1; then
  q() {
    python3 - "$DB" "$1" <<'PYSQL' 2>/dev/null || true
import sqlite3
import sys

db_path, sql = sys.argv[1], sys.argv[2]
connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    for row in connection.execute(sql):
        print("|".join("" if value is None else str(value) for value in row))
finally:
    connection.close()
PYSQL
  }
else
  echo "E2E_WAIT bootstrap_ready missing_sqlite_reader"
  exit 1
fi
count_gt_zero() {
  value="$(q "$1" | tail -n 1 | tr -dc '0-9')"
  [ -n "$value" ] && [ "$value" -gt 0 ]
}
deadline=$(( $(date +%s) + 120 ))
while [ "$(date +%s)" -le "$deadline" ]; do
  USER_DID="$(q "SELECT json_extract(detail_json,'$.user_did') FROM audit_log WHERE event_type='daemon.bootstrap.received' AND COALESCE(detail_json,'') LIKE '%$RUN_ID%' ORDER BY created_at_ms DESC LIMIT 1;")"
  APP_INSTANCE="$(q "SELECT json_extract(detail_json,'$.app_instance_id') FROM audit_log WHERE event_type='daemon.bootstrap.received' AND COALESCE(detail_json,'') LIKE '%$RUN_ID%' ORDER BY created_at_ms DESC LIMIT 1;")"
  if [ -n "$USER_DID" ] && [ -n "$APP_INSTANCE" ] && \
     count_gt_zero "SELECT COUNT(*) FROM user_delegated_identity WHERE user_did='$USER_DID' AND app_instance_id='$APP_INSTANCE' AND status='paired_key_received';" && \
     count_gt_zero "SELECT COUNT(*) FROM app_message_agent_binding WHERE user_did='$USER_DID' AND app_instance_id='$APP_INSTANCE' AND role='app_message_handler' AND revoked_at_ms IS NULL AND status IN ('message_agent_ready','message_agent_active','message_agent_ensuring');"; then
    ACTIVE_TOTAL="$(q "SELECT COUNT(*) FROM app_message_agent_binding WHERE user_did='$USER_DID' AND role='app_message_handler' AND revoked_at_ms IS NULL AND status IN ('message_agent_ready','message_agent_active','message_agent_ensuring');" | tail -n 1 | tr -dc '0-9')"
    if [ "${ACTIVE_TOTAL:-0}" -eq 1 ]; then
      echo "E2E_WAIT bootstrap_ready pass appInstance=$APP_INSTANCE activeBindings=$ACTIVE_TOTAL"
      exit 0
    fi
    echo "E2E_WAIT bootstrap_ready pending activeBindings=${ACTIVE_TOTAL:-unknown}"
  fi
  sleep 2
done
echo "E2E_WAIT bootstrap_ready timeout"
q "SELECT app_instance_id, runtime_agent_did, status, revoked_at_ms FROM app_message_agent_binding WHERE COALESCE(user_did,'') = COALESCE('$USER_DID','') AND role='app_message_handler' ORDER BY updated_at_ms DESC LIMIT 8;"
exit 1
''',
  ].join('; ');
}

String _daemonSqliteEvidenceScript(String runId) {
  final messageId = 'msg_agent_im_$runId';
  return [
    'RUN_ID=${_singleQuote(runId)}',
    'MSG_ID=${_singleQuote(messageId)}',
    r'''find_db() {
  for p in \
    "${AWIKI_DAEMON_STATE_ROOT:-}/daemon.db" \
    "${AWIKI_DEAMON_STATE_ROOT:-}/daemon.db" \
    "$HOME/.awiki-daemon/deamon/state/daemon.db" \
    "$HOME/.awiki-deamon/deamon/state/daemon.db" \
    "$HOME/awiki-space/awiki-cli-rs2/.awiki-daemon/deamon/state/daemon.db" \
    "$HOME/work/agents/awiki-space/awiki-cli-rs2/.awiki-daemon/deamon/state/daemon.db"; do
    [ -n "$p" ] && [ -f "$p" ] && { echo "$p"; return 0; }
  done
  find "$HOME" -maxdepth 5 -type f -name daemon.db 2>/dev/null | head -n 1
}
DB="$(find_db)"
echo "remote-daemon-sqlite runId=$RUN_ID messageId=$MSG_ID db=${DB:-<missing>}"
if [ -z "$DB" ] || [ ! -f "$DB" ]; then
  echo "E2E_STAGE daemon_sqlite_db missing"
  exit 0
fi
if command -v sqlite3 >/dev/null 2>&1; then
  q() { sqlite3 -readonly "$DB" "$1" 2>/dev/null || true; }
elif command -v python3 >/dev/null 2>&1; then
  q() {
    python3 - "$DB" "$1" <<'PYSQL' 2>/dev/null || true
import sqlite3
import sys

db_path, sql = sys.argv[1], sys.argv[2]
connection = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
try:
    for row in connection.execute(sql):
        print("|".join("" if value is None else str(value) for value in row))
finally:
    connection.close()
PYSQL
  }
else
  echo "E2E_STAGE sqlite_reader missing"
  exit 0
fi
count_gt_zero() {
  value="$(q "$1" | tail -n 1 | tr -dc '0-9')"
  [ -n "$value" ] && [ "$value" -gt 0 ]
}
BOOTSTRAP_DETAIL="$(q "SELECT COALESCE(detail_json,'') FROM audit_log WHERE event_type='daemon.bootstrap.received' AND COALESCE(detail_json,'') LIKE '%$RUN_ID%' ORDER BY created_at_ms DESC LIMIT 1;")"
if [ -n "$BOOTSTRAP_DETAIL" ]; then
  echo "E2E_STAGE daemon_bootstrap_received pass"
else
  echo "E2E_STAGE daemon_bootstrap_received missing"
fi
USER_DID="$(q "SELECT json_extract(detail_json,'$.user_did') FROM audit_log WHERE event_type='daemon.bootstrap.received' AND COALESCE(detail_json,'') LIKE '%$RUN_ID%' ORDER BY created_at_ms DESC LIMIT 1;")"
APP_INSTANCE="$(q "SELECT json_extract(detail_json,'$.app_instance_id') FROM audit_log WHERE event_type='daemon.bootstrap.received' AND COALESCE(detail_json,'') LIKE '%$RUN_ID%' ORDER BY created_at_ms DESC LIMIT 1;")"
if [ -n "$USER_DID" ] && [ -n "$APP_INSTANCE" ] && count_gt_zero "SELECT COUNT(*) FROM user_delegated_identity WHERE user_did='$USER_DID' AND app_instance_id='$APP_INSTANCE' AND status='paired_key_received';"; then
  echo "E2E_STAGE delegated_key_imported pass"
else
  echo "E2E_STAGE delegated_key_imported missing"
fi
if [ -n "$USER_DID" ] && [ -n "$APP_INSTANCE" ] && count_gt_zero "SELECT COUNT(*) FROM app_message_agent_binding WHERE user_did='$USER_DID' AND app_instance_id='$APP_INSTANCE' AND role='app_message_handler' AND revoked_at_ms IS NULL AND status IN ('message_agent_ready','message_agent_active','message_agent_ensuring');"; then
  echo "E2E_STAGE hermes_agent_ready pass"
else
  echo "E2E_STAGE hermes_agent_ready missing"
fi
if count_gt_zero "SELECT COUNT(*) FROM processed_message WHERE message_id='$MSG_ID';" || count_gt_zero "SELECT COUNT(*) FROM message_event WHERE message_id='$MSG_ID';"; then
  echo "E2E_STAGE cli_message_received pass"
else
  echo "E2E_STAGE cli_message_received missing"
fi
if count_gt_zero "SELECT COUNT(*) FROM runtime_task t JOIN runtime_run r ON r.task_id=t.task_id JOIN app_message_agent_binding b ON b.runtime_agent_did=t.agent_did WHERE t.task_text LIKE '%$MSG_ID%' AND r.status='finished' AND b.user_did='$USER_DID' AND b.app_instance_id='$APP_INSTANCE' AND b.revoked_at_ms IS NULL;"; then
  echo "E2E_STAGE hermes_runtime_finished pass"
else
  echo "E2E_STAGE hermes_runtime_finished missing"
fi
if count_gt_zero "SELECT COUNT(*) FROM message_sync_outbox WHERE status='sent' AND app_instance_id='$APP_INSTANCE' AND payload_json LIKE '%runtime_final%' AND payload_json LIKE '%$MSG_ID%';"; then
  echo "E2E_STAGE summary_return_sent pass"
else
  echo "E2E_STAGE summary_return_sent missing"
fi
q "SELECT event_type, COALESCE(run_id,''), COALESCE(detail_json,'') FROM audit_log WHERE COALESCE(detail_json,'') LIKE '%$RUN_ID%' OR COALESCE(detail_json,'') LIKE '%$MSG_ID%' ORDER BY created_at_ms DESC LIMIT 20;"
''',
  ].join('; ');
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
  final messageId = 'msg_agent_im_$runId';
  return '($journalctl $unitArgs --since ${_singleQuote('2 hours ago')} '
      '--no-pager 2>/dev/null || true) | '
      'grep -E ${_singleQuote('$runId|$messageId')} | tail -n 120 || true';
}

Set<String> _extractStages(List<AgentImRemoteEvidenceEntry> entries) {
  final stages = <String>{};
  final pattern = RegExp(r'^E2E_STAGE\s+([A-Za-z0-9_.-]+)\s+pass\b');
  for (final entry in entries) {
    for (final line in entry.stdoutSummary.split('\n')) {
      final match = pattern.firstMatch(line.trim());
      if (match != null) {
        stages.add(match.group(1)!);
      }
    }
  }
  return stages;
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
