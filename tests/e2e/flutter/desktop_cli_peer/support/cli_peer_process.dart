part of '../desktop_cli_peer_e2e.dart';

Future<void> _waitForCliHistory({
  required _DesktopCliPeerSmokeConfig config,
  required String peerHandle,
  required String expectedText,
}) async {
  await _poll(
    description: 'CLI history contains "$expectedText"',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'msg',
        'history',
        '--with',
        peerHandle,
        '--limit',
        '20',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedText);
    },
  );
}

Future<void> _waitForCliGroupMessages({
  required _DesktopCliPeerSmokeConfig config,
  required String groupDid,
  required String expectedText,
}) async {
  await _poll(
    description: 'CLI group messages contain "$expectedText"',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'group',
        'messages',
        '--group',
        groupDid,
        '--limit',
        '20',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedText);
    },
  );
}

Future<void> _waitForCliInbox({
  required _DesktopCliPeerSmokeConfig config,
  required String expectedText,
}) async {
  await _poll(
    description: 'CLI inbox contains "$expectedText"',
    action: () async {
      final result = await _runCli(config, const <String>[
        '--format',
        'json',
        'msg',
        'inbox',
        '--limit',
        '20',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedText);
    },
  );
}

Future<_CliResult> _runCli(
  _DesktopCliPeerSmokeConfig config,
  List<String> args, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final result = await Process.run(
    config.cliBin,
    args,
    environment: <String, String>{
      for (final name in const <String>[
        'PATH',
        'LANG',
        'LC_ALL',
        'TMPDIR',
        'SSL_CERT_FILE',
        'SSL_CERT_DIR',
      ])
        if ((Platform.environment[name] ?? '').trim().isNotEmpty)
          name: Platform.environment[name]!,
      'HOME': config.cliHome,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': config.cliWorkspace,
    },
    includeParentEnvironment: false,
    runInShell: false,
  ).timeout(timeout);
  return _CliResult(
    exitCode: result.exitCode,
    stdout: ((result.stdout as String?) ?? '').trim(),
    stderr: ((result.stderr as String?) ?? '').trim(),
    secrets: config.secrets,
  );
}

bool _jsonContainsText(String output, String expectedText) {
  try {
    return _valueContainsText(jsonDecode(output), expectedText);
  } on Object {
    return output.contains(expectedText);
  }
}

bool _valueContainsText(Object? value, String expectedText) {
  if (value is String) {
    return value.contains(expectedText);
  }
  if (value is List) {
    return value.any((entry) => _valueContainsText(entry, expectedText));
  }
  if (value is Map) {
    return value.values.any((entry) => _valueContainsText(entry, expectedText));
  }
  return false;
}

String? _jsonStringAt(String output, List<Object> path) {
  Object? value;
  try {
    value = jsonDecode(output);
  } on Object {
    return null;
  }
  for (final segment in path) {
    if (value is Map) {
      value = value[segment];
      continue;
    }
    if (value is List && segment is int) {
      if (segment < 0 || segment >= value.length) {
        return null;
      }
      value = value[segment];
      continue;
    }
    return null;
  }
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  if (value is num) {
    return value.toString();
  }
  return null;
}

String _summarizeCliResult(_CliResult result) {
  final text = <String>[
    'exit=${result.exitCode}',
    if (result.stdout.isNotEmpty) 'stdout=${result.stdout}',
    if (result.stderr.isNotEmpty) 'stderr=${result.stderr}',
  ].join(' ');
  return _sanitizeDiagnostic(text, secrets: result.secrets);
}

class _CliResult {
  const _CliResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.secrets = const <String>[],
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final List<String> secrets;
}
