import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/account_state_operator_contract.dart';

void main() {
  test('accepts only the reviewed Mac-to-Ali managed-release argv', () {
    expect(
      parseAccountStateOperatorCommand(
        jsonEncode(reviewedAccountStateOperatorCommand),
      ),
      reviewedAccountStateOperatorCommand,
    );
  });

  test('rejects the obsolete same-host mutable-workspace argv', () {
    expect(
      () => parseAccountStateOperatorCommand(
        jsonEncode(<String>[
          '/home/ecs-user/awiki-space/user-service/v1/.venv/bin/python',
          '/home/ecs-user/awiki-space/user-service/v1/scripts/'
              'run_account_state_sync_test_action.py',
          '--apply',
        ]),
      ),
      throwsFormatException,
    );
  });

  test('rejects alternate SSH hosts and missing bytecode protection', () {
    final alternateHost = List<String>.of(reviewedAccountStateOperatorCommand)
      ..[1] = 'other-host';
    final bytecodeWriting = List<String>.of(reviewedAccountStateOperatorCommand)
      ..remove('PYTHONDONTWRITEBYTECODE=1');

    expect(
      () => parseAccountStateOperatorCommand(jsonEncode(alternateHost)),
      throwsFormatException,
    );
    expect(
      () => parseAccountStateOperatorCommand(jsonEncode(bytecodeWriting)),
      throwsFormatException,
    );
  });
}
