part of '../desktop_cli_peer_e2e.dart';

Future<void> _waitForCliHistory({
  required _DesktopCliPeerSmokeConfig config,
  required String peerHandle,
  required String expectedText,
  String? expectedMessageId,
}) async {
  await _poll(
    description: 'CLI history contains exact message "$expectedText"',
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
      return _cliMessagesWithExactText(
        result.stdout,
        expectedText,
        expectedMessageId: expectedMessageId,
      ).isNotEmpty;
    },
  );
}

Future<void> _waitForCliGroupMessages({
  required _DesktopCliPeerSmokeConfig config,
  required String groupDid,
  required String expectedText,
  String? expectedMessageId,
}) async {
  await _poll(
    description: 'CLI group messages contain exact message "$expectedText"',
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
      return _cliMessagesWithExactText(
        result.stdout,
        expectedText,
        expectedMessageId: expectedMessageId,
      ).isNotEmpty;
    },
  );
}

Future<void> _waitForCliInbox({
  required _DesktopCliPeerSmokeConfig config,
  required String expectedText,
  String? expectedMessageId,
}) async {
  await _poll(
    description: 'CLI inbox contains exact message "$expectedText"',
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
      return _cliMessagesWithExactText(
        result.stdout,
        expectedText,
        expectedMessageId: expectedMessageId,
      ).isNotEmpty;
    },
  );
}

Future<_CliAttachmentMessage> _waitForCliAttachmentMessage({
  required _DesktopCliPeerSmokeConfig config,
  required String peerHandle,
  required String expectedText,
  required String expectedMessageId,
  required String expectedAttachmentId,
  required String expectedFilename,
}) async {
  _CliAttachmentMessage? matched;
  await _poll(
    description:
        'CLI history contains attachment "$expectedFilename" on message "$expectedMessageId"',
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
      matched = _cliAttachmentMessage(
        result.stdout,
        expectedText: expectedText,
        expectedMessageId: expectedMessageId,
        expectedAttachmentId: expectedAttachmentId,
        expectedFilename: expectedFilename,
      );
      return matched != null;
    },
  );
  return matched!;
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

String? _jsonStringAt(String output, List<Object> path) {
  final value = _jsonValueAt(output, path);
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  if (value is num) {
    return value.toString();
  }
  return null;
}

String? _firstNonEmptyCliStringAtAnyPath(
  String output,
  List<List<Object>> paths,
) {
  for (final path in paths) {
    final value = _jsonValueAt(output, path);
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is num) {
      return value.toString();
    }
  }
  return null;
}

List<Map<String, Object?>> _performanceDatasetGroupsFromCliOutput(
  String output, {
  required String runId,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(output);
  } on Object {
    return const <Map<String, Object?>>[];
  }
  final groups = _jsonValueAtDecoded(decoded, const <Object>['data', 'groups']);
  if (groups is! List) {
    return const <Map<String, Object?>>[];
  }
  final expectedPrefix = 'AWiki Perf $runId ';
  return groups
      .whereType<Map>()
      .map((group) => _cliStringKeyMap(group))
      .where((group) {
        final name =
            _nonEmptyCliString(group['name']) ??
            _nonEmptyCliString(group['display_name']) ??
            _nonEmptyCliString(group['group_name']);
        return name != null && name.startsWith(expectedPrefix);
      })
      .toList(growable: false);
}

Object? _jsonValueAt(String output, List<Object> path) {
  Object? value;
  try {
    value = jsonDecode(output);
  } on Object {
    return null;
  }
  return _jsonValueAtDecoded(value, path);
}

Object? _jsonValueAtDecoded(Object? value, List<Object> path) {
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
  return value;
}

List<Map<String, Object?>> _cliMessagesWithExactText(
  String output,
  String expectedText, {
  String? expectedMessageId,
}) {
  final messages = _jsonValueAt(output, const <Object>['data', 'messages']);
  if (messages is! List) {
    return const <Map<String, Object?>>[];
  }
  return messages
      .whereType<Map>()
      .map((message) => _cliStringKeyMap(message))
      .where((message) {
        if (!_cliMessageContentMatches(message, expectedText)) {
          return false;
        }
        final id =
            _nonEmptyCliString(message['message_id']) ??
            _nonEmptyCliString(message['msg_id']) ??
            _nonEmptyCliString(message['id']);
        return expectedMessageId == null || id == expectedMessageId;
      })
      .toList(growable: false);
}

bool _cliMessageContentMatches(
  Map<String, Object?> message,
  String expectedText,
) {
  final content = message['content'];
  if (content is String) {
    return content == expectedText;
  }
  if (content is Map) {
    final map = _cliStringKeyMap(content);
    return _nonEmptyCliString(map['text']) == expectedText ||
        _nonEmptyCliString(map['caption']) == expectedText;
  }
  return false;
}

_CliAttachmentMessage? _cliAttachmentMessage(
  String output, {
  required String expectedText,
  required String expectedMessageId,
  required String expectedAttachmentId,
  required String expectedFilename,
}) {
  final matches = _cliMessagesWithExactText(
    output,
    expectedText,
    expectedMessageId: expectedMessageId,
  );
  for (final message in matches) {
    final attachment = _cliAttachmentFromMessage(
      message,
      expectedAttachmentId: expectedAttachmentId,
      expectedFilename: expectedFilename,
    );
    if (attachment != null) {
      return _CliAttachmentMessage(message: message, attachment: attachment);
    }
  }
  return null;
}

Map<String, Object?>? _cliAttachmentFromMessage(
  Map<String, Object?> message, {
  required String expectedAttachmentId,
  required String expectedFilename,
}) {
  final candidates = <Map<String, Object?>>[];
  void addCandidatesFrom(Map<String, Object?> source) {
    for (final key in const <String>['attachment', 'primary_attachment']) {
      final value = source[key];
      if (value is Map) {
        candidates.add(_cliStringKeyMap(value));
      }
    }
    final attachments = source['attachments'];
    if (attachments is List) {
      for (final value in attachments) {
        if (value is Map) {
          candidates.add(_cliStringKeyMap(value));
        }
      }
    }
  }

  addCandidatesFrom(message);
  final content = message['content'];
  if (content is Map) {
    addCandidatesFrom(_cliStringKeyMap(content));
  }
  if (candidates.isEmpty) {
    candidates.add(message);
  }
  for (final candidate in candidates) {
    final attachmentId = _nonEmptyCliString(candidate['attachment_id']);
    final filename = _nonEmptyCliString(candidate['filename']);
    if (attachmentId == expectedAttachmentId && filename == expectedFilename) {
      return candidate;
    }
  }
  return null;
}

Map<String, Object?> _cliStringKeyMap(Map<dynamic, dynamic> value) {
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _nonEmptyCliString(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
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

class _CliAttachmentMessage {
  const _CliAttachmentMessage({
    required this.message,
    required this.attachment,
  });

  final Map<String, Object?> message;
  final Map<String, Object?> attachment;

  String? get digestB64u {
    final digest = attachment['digest'];
    if (digest is Map) {
      final digestMap = _cliStringKeyMap(digest);
      return _nonEmptyCliString(digestMap['value_b64u']);
    }
    return _nonEmptyCliString(attachment['digest_b64u']);
  }
}
