import 'dart:io';

final class AgentImRedactionScanner {
  const AgentImRedactionScanner();

  AgentImRedactionScanResult scanReportAndLogs({
    required Directory reportDir,
    Directory? cliWorkspaceDir,
  }) {
    final files = <File>[];
    files.addAll(_filesUnder(reportDir));
    if (cliWorkspaceDir != null) {
      files.addAll(
        _filesUnder(
          cliWorkspaceDir,
        ).where((file) => file.path.endsWith('.log')),
      );
    }

    final findings = <AgentImRedactionFinding>[];
    var scannedFiles = 0;
    for (final file in files) {
      if (!file.existsSync()) {
        continue;
      }
      String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
      scannedFiles += 1;
      for (final rule in _sensitiveRules) {
        if (rule.pattern.hasMatch(text)) {
          findings.add(
            AgentImRedactionFinding(type: rule.type, path: file.path),
          );
        }
      }
    }
    return AgentImRedactionScanResult(
      scannedFiles: scannedFiles,
      findings: findings,
    );
  }
}

final class AgentImRedactionScanResult {
  const AgentImRedactionScanResult({
    required this.scannedFiles,
    required this.findings,
  });

  final int scannedFiles;
  final List<AgentImRedactionFinding> findings;

  bool get passed => findings.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'passed': passed,
    'scannedFiles': scannedFiles,
    'findings': [for (final finding in findings) finding.toJson()],
  };
}

final class AgentImRedactionFinding {
  const AgentImRedactionFinding({required this.type, required this.path});

  final String type;
  final String path;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'path': path,
  };
}

final class _SensitiveRule {
  const _SensitiveRule({required this.type, required this.pattern});

  final String type;
  final RegExp pattern;
}

final _sensitiveRules = <_SensitiveRule>[
  _SensitiveRule(
    type: 'private-key-pem',
    pattern: RegExp(
      r'-----BEGIN (?:[A-Z0-9 ]+)?PRIVATE KEY-----',
      multiLine: true,
    ),
  ),
  _SensitiveRule(
    type: 'bearer-token',
    pattern: RegExp(r'Bearer\s+[A-Za-z0-9._~+\-/=]{12,}', caseSensitive: false),
  ),
  _SensitiveRule(
    type: 'jwt',
    pattern: RegExp(
      r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    ),
  ),
  _SensitiveRule(type: 'raw-phone', pattern: RegExp(r'\+\d{8,15}')),
  _SensitiveRule(
    type: 'otp-value',
    pattern: RegExp(
      r'(?:otp|code|verification_code|--otp)\s*[:= ]\s*\d{4,8}',
      caseSensitive: false,
    ),
  ),
  _SensitiveRule(
    type: 'fixture-private-package',
    pattern: RegExp(r'fixture-private-daemon-key-do-not-log'),
  ),
  _SensitiveRule(
    type: 'fixture-runtime-token',
    pattern: RegExp(r'fixture-runtime-token'),
  ),
];

List<File> _filesUnder(Directory directory) {
  if (!directory.existsSync()) {
    return const <File>[];
  }
  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .toList(growable: false);
}
