import 'package:flutter_test/flutter_test.dart';

import '../../e2e/sync_recovery_operator_contract.dart';

void main() {
  test('recovery operator uses only the reviewed managed Ali boundary', () {
    expect(reviewedSyncRecoveryOperatorCommand, <String>[
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
    ]);
    expect(
      reviewedSyncRecoveryOperatorCommand.join(' '),
      isNot(contains('/home/ecs-user/awiki-space')),
    );
    expect(
      reviewedSyncRecoveryOperatorCommand.join(' '),
      isNot(contains('ACCOUNT_ALLOWLIST')),
    );
  });
}
