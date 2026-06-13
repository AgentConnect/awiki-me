import 'dart:convert';
import 'dart:io';

import 'secret_redactor.dart';

final class E2eReportWriter {
  const E2eReportWriter({
    required this.directory,
    this.redactor = const SecretRedactor(),
  });

  final Directory directory;
  final SecretRedactor redactor;

  void writeJson(String fileName, Map<String, Object?> payload) {
    directory.createSync(recursive: true);
    final redacted = redactor.redactJson(payload);
    File(
      '${directory.path}/$fileName',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(redacted));
  }
}
