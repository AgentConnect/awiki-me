// [INPUT]: Operator-provided Account State test-action argv.
// [OUTPUT]: Exact reviewed managed Python + immutable operator asset or a closed error.
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
  'PYTHONPATH=/opt/awiki/services/user-service/current/src',
  '/opt/awiki/services/user-service/current/.venv/bin/python',
  '/usr/local/libexec/awiki-system-test/user-operator-aadcaa641890/'
      'run_account_state_sync_test_action.py',
  '--env-file',
  '/etc/awiki/user-service.env',
  '--apply',
];

const List<String> reviewedLocalAccountStateOperatorCommand = <String>[
  'sudo',
  '-n',
  '/usr/bin/env',
  'PYTHONDONTWRITEBYTECODE=1',
  'PYTHONPATH=/opt/awiki/services/user-service/current/src',
  '/opt/awiki/services/user-service/current/.venv/bin/python',
  '/usr/local/libexec/awiki-system-test/user-operator-aadcaa641890/'
      'run_account_state_sync_test_action.py',
  '--env-file',
  '/etc/awiki/user-service.env',
  '--apply',
];

// Singapore uses the same closed actions with a pinned, root-owned operator.
const List<String> reviewedSingaporeAccountStateOperatorCommand = <String>[
  'ssh',
  'singapore-dev',
  '--',
  'sudo',
  '-n',
  '/usr/bin/env',
  'PYTHONDONTWRITEBYTECODE=1',
  'PYTHONPATH=/opt/awiki/services/user-service/current/src',
  '/opt/awiki/services/user-service/current/.venv/bin/python',
  '/usr/local/libexec/awiki-system-test/user-operator-cf695ae189ee/'
      'run_account_state_sync_test_action.py',
  '--env-file',
  '/etc/awiki/user-service.env',
  '--apply',
];

({String target, String domain}) reviewedOperatorTargetForMode(String mode) =>
    switch (mode) {
      'ali' || 'local' => (target: 'awiki-info-testing', domain: 'awiki.info'),
      'singapore' => (target: 'singapore-staging', domain: 'anpclaw.com'),
      _ => throw const FormatException('The operator mode is not reviewed.'),
    };

bool reviewedOperatorMatchesTarget(String? mode, String? target) {
  try {
    return reviewedOperatorTargetForMode(mode ?? '').target == target;
  } on FormatException {
    return false;
  }
}

void validateReviewedOperatorServiceTarget({
  required String mode,
  required String target,
  required String didDomain,
  required List<String> serviceUrls,
}) {
  final reviewed = reviewedOperatorTargetForMode(mode);
  if (target != reviewed.target ||
      didDomain != reviewed.domain ||
      serviceUrls.isEmpty ||
      serviceUrls.any((url) => url != 'https://${reviewed.domain}')) {
    throw const FormatException(
      'The operator and configured service target differ.',
    );
  }
}

List<String> reviewedAccountStateOperatorCommandForMode(String mode) =>
    switch (mode) {
      'ali' => reviewedAccountStateOperatorCommand,
      'local' => reviewedLocalAccountStateOperatorCommand,
      'singapore' => reviewedSingaporeAccountStateOperatorCommand,
      _ => throw const FormatException(
        'The App-pair Account State operator mode is not reviewed.',
      ),
    };

List<String> parseAccountStateOperatorCommand(
  String encoded, {
  String mode = 'ali',
}) {
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
  if (!_sameCommand(
    command,
    reviewedAccountStateOperatorCommandForMode(mode),
  )) {
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
