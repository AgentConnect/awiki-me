// [INPUT]: Operator-provided Account State test-action argv.
// [OUTPUT]: Exact reviewed Mac-to-Ali managed-release command or a closed error.
// [POS]: Shared App-pair runner/product-test boundary; environment input cannot
//        select another host, script, config, shell, or mutable workspace.

import 'dart:convert';

const List<String> reviewedAccountStateOperatorCommand = <String>[
  'ssh',
  'ali',
  '--',
  'sudo',
  '-n',
  '/usr/bin/env',
  'PYTHONDONTWRITEBYTECODE=1',
  'PYTHONPATH=/opt/awiki/services/user-service/v1/current/src',
  '/opt/awiki/services/user-service/v1/current/.venv/bin/python',
  '/opt/awiki/services/user-service/v1/current/scripts/'
      'run_account_state_sync_test_action.py',
  '--env-file',
  '/etc/awiki/user-service.env',
  '--apply',
];

List<String> parseAccountStateOperatorCommand(String encoded) {
  Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on Object {
    throw const FormatException(
      'The App-pair Account State operator command is invalid.',
    );
  }
  if (decoded is! List ||
      decoded.isEmpty ||
      decoded.any((value) => value is! String || value.trim().isEmpty)) {
    throw const FormatException(
      'The App-pair Account State operator command is invalid.',
    );
  }
  final command = List<String>.unmodifiable(decoded.cast<String>());
  if (!_sameCommand(command, reviewedAccountStateOperatorCommand)) {
    throw const FormatException(
      'The App-pair Account State operator command is not reviewed.',
    );
  }
  return command;
}

bool _sameCommand(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
