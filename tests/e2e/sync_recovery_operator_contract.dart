// Fixed managed-release execution and readiness boundary for App-pair operators.

import 'dart:convert';

import 'account_state_operator_contract.dart';

const List<String> reviewedSyncRecoveryOperatorCommand = <String>[
  'ssh',
  'ali',
  '--',
  'sudo',
  '-n',
  '/usr/bin/env',
  'PYTHONDONTWRITEBYTECODE=1',
  '/usr/bin/python3.11',
  '/opt/awiki/services/message-service/current/scripts/'
      'prepare_sync_v2_recovery_test.py',
  '--config',
  '/etc/awiki/message-service.toml',
  '--apply',
];

const List<String> reviewedLocalSyncRecoveryOperatorCommand = <String>[
  'sudo',
  '-n',
  '/usr/bin/env',
  'PYTHONDONTWRITEBYTECODE=1',
  '/usr/bin/python3.11',
  '/opt/awiki/services/message-service/current/scripts/'
      'prepare_sync_v2_recovery_test.py',
  '--config',
  '/etc/awiki/message-service.toml',
  '--apply',
];

List<String> reviewedSyncRecoveryOperatorCommandForMode(String mode) =>
    switch (mode) {
      'ali' => reviewedSyncRecoveryOperatorCommand,
      'local' => reviewedLocalSyncRecoveryOperatorCommand,
      _ => throw ArgumentError.value(
        mode,
        'mode',
        'operator mode is not reviewed',
      ),
    };

// All probes are metadata or sudo permission queries; none executes --apply.
List<({String label, List<String> command})> reviewedOperatorPreflightChecks({
  required String mode,
  required String operatingSystem,
  required bool accountState,
}) {
  reviewedSyncRecoveryOperatorCommandForMode(mode);
  if (mode == 'local' && operatingSystem != 'linux') {
    throw const FormatException(
      'operator_preflight.local_requires_linux_service_host: select SSH mode ali',
    );
  }
  final prefix = mode == 'ali'
      ? <String>[
          'ssh',
          '-o',
          'BatchMode=yes',
          '-o',
          'ConnectTimeout=10',
          'ali',
          '--',
        ]
      : <String>[];
  final checks = <({String label, List<String> command})>[];
  for (final entry in <(String, List<String>, String)>[
    ('recovery', reviewedLocalSyncRecoveryOperatorCommand, '--config'),
    if (accountState)
      ('account_state', reviewedLocalAccountStateOperatorCommand, '--env-file'),
  ]) {
    final (label, apply, configFlag) = entry;
    final scriptIndex = apply.indexWhere((value) => value.endsWith('.py'));
    for (final requirement in <(String, String, String)>[
      ('interpreter', '-x', apply[scriptIndex - 1]),
      ('script', '-f', apply[scriptIndex]),
      ('config', '-f', apply[apply.indexOf(configFlag) + 1]),
    ]) {
      checks.add((
        label: '$label.${requirement.$1}',
        command: [...prefix, '/usr/bin/test', requirement.$2, requirement.$3],
      ));
    }
    checks.add((
      label: '$label.sudo_permission',
      command: [...prefix, 'sudo', '-n', '-l', '--', ...apply.skip(2)],
    ));
  }
  return checks;
}

String operatorFailureCategory(String stderr) {
  final value = stderr.toLowerCase();
  if (value.contains('a password is required') ||
      value.contains('password is required')) {
    return 'sudo_auth_required';
  }
  if (value.contains('permission denied (publickey') ||
      value.contains('host key verification failed')) {
    return 'ssh_auth_unavailable';
  }
  if (value.contains('no such file') || value.contains('command not found')) {
    return 'command_unavailable';
  }
  if (value.contains('permission denied') ||
      value.contains('not allowed to execute')) {
    return 'permission_denied';
  }
  if (value.contains('timed out') ||
      value.contains('connection refused') ||
      value.contains('could not resolve hostname')) {
    return 'connection_unavailable';
  }
  return 'operator_failed';
}

void requireOperatorProcessSuccess({
  required String label,
  required int exitCode,
  required String stderr,
}) {
  if (exitCode != 0) {
    throw FormatException(
      'operator_exit_failed: $label exit=$exitCode category=${operatorFailureCategory(stderr)}',
    );
  }
}

void validateSyncRecoveryOperatorReceipt({
  required int exitCode,
  required String stdoutText,
  required String stderrText,
  required String expectedMode,
}) {
  requireOperatorProcessSuccess(
    label: 'recovery',
    exitCode: exitCode,
    stderr: stderrText,
  );
  Object? receipt;
  try {
    receipt = jsonDecode(stdoutText);
  } on FormatException {
    throw const FormatException('operator_receipt_invalid_json: recovery');
  }
  if (receipt is! Map ||
      receipt.length != 3 ||
      receipt['affected_streams'] != 1 ||
      receipt['mode'] != expectedMode ||
      receipt['prepared'] != true) {
    throw const FormatException('operator_receipt_invalid_contract: recovery');
  }
}
