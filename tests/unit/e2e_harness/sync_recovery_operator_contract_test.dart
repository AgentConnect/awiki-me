import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/sync_recovery_operator_contract.dart';

void main() {
  test('local operator is rejected on macOS before any command is started', () {
    expect(
      () => reviewedOperatorPreflightChecks(
        mode: 'local',
        operatingSystem: 'macos',
        accountState: true,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('local_requires_linux'),
        ),
      ),
    );
  });

  test('SSH probes both services without executing an apply action', () {
    final checks = reviewedOperatorPreflightChecks(
      mode: 'ali',
      operatingSystem: 'macos',
      accountState: true,
    );
    expect(checks.length, 8);
    for (final check in checks) {
      expect(check.command.take(7), [
        'ssh',
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=10',
        'ali',
        '--',
      ]);
      final remote = check.command.skip(7).toList();
      if (check.label.endsWith('sudo_permission')) {
        expect(remote.take(4), ['sudo', '-n', '-l', '--']);
      } else {
        expect(remote.first, '/usr/bin/test');
        expect(remote, isNot(contains('--apply')));
      }
    }
    expect(
      checks.map((check) => check.label),
      contains('account_state.config'),
    );
  });

  test('Linux local probes omit SSH and can require only recovery', () {
    final checks = reviewedOperatorPreflightChecks(
      mode: 'local',
      operatingSystem: 'linux',
      accountState: false,
    );
    expect(checks.length, 4);
    expect(checks.every((check) => check.command.first != 'ssh'), isTrue);
    expect(
      checks.every((check) => check.label.startsWith('recovery.')),
      isTrue,
    );
  });

  test(
    'nonzero exit is reported before parsing empty or successful stdout',
    () {
      for (final output in [
        '',
        '{"affected_streams":1,"mode":"messages_501","prepared":true}',
      ]) {
        expect(
          () => validateSyncRecoveryOperatorReceipt(
            exitCode: 1,
            stdoutText: output,
            stderrText: 'sudo: a password is required private-token',
            expectedMode: 'messages_501',
          ),
          throwsA(
            isA<FormatException>()
                .having(
                  (error) => error.message,
                  'category',
                  contains('sudo_auth_required'),
                )
                .having((error) => error.message, 'exit', contains('exit=1'))
                .having(
                  (error) => error.message,
                  'redaction',
                  isNot(contains('private-token')),
                ),
          ),
        );
      }
    },
  );

  test('successful process still needs the exact closed recovery receipt', () {
    for (final mode in ['retention_gap', 'messages_501']) {
      validateSyncRecoveryOperatorReceipt(
        exitCode: 0,
        stdoutText: jsonEncode({
          'affected_streams': 1,
          'mode': mode,
          'prepared': true,
        }),
        stderrText: '',
        expectedMode: mode,
      );
    }
    for (final output in [
      '',
      'private-token',
      '{}',
      '{"affected_streams":2,"mode":"messages_501","prepared":true}',
      '{"affected_streams":1,"mode":"wrong","prepared":true}',
      '{"affected_streams":1,"mode":"messages_501","prepared":false}',
      '{"affected_streams":1,"mode":"messages_501","prepared":true,"extra":1}',
    ]) {
      expect(
        () => validateSyncRecoveryOperatorReceipt(
          exitCode: 0,
          stdoutText: output,
          stderrText: '',
          expectedMode: 'messages_501',
        ),
        throwsFormatException,
      );
    }
  });

  test('operator diagnostics expose only closed categories', () {
    expect(
      operatorFailureCategory('Permission denied (publickey). private-key'),
      'ssh_auth_unavailable',
    );
    expect(
      operatorFailureCategory('No such file or directory: /private/path'),
      'command_unavailable',
    );
    expect(
      operatorFailureCategory('unknown private-secret'),
      'operator_failed',
    );
  });

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

  test(
    'recovery operator supports the reviewed same-host release boundary',
    () {
      expect(
        reviewedSyncRecoveryOperatorCommandForMode('local'),
        reviewedLocalSyncRecoveryOperatorCommand,
      );
      expect(
        reviewedLocalSyncRecoveryOperatorCommand.join(' '),
        isNot(contains('/home/ecs-user/awiki-space')),
      );
      expect(
        () => reviewedSyncRecoveryOperatorCommandForMode('unknown'),
        throwsArgumentError,
      );
    },
  );
}
