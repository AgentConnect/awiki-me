// Fixed managed-release boundary for the SSH-only Message Sync recovery operator.

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
