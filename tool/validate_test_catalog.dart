import 'dart:convert';
import 'dart:io';

import '../tests/e2e/test_catalog.dart';

Future<void> main(List<String> args) async {
  try {
    var write = false;
    String? reportPath;
    for (var index = 0; index < args.length; index += 1) {
      switch (args[index]) {
        case '--write':
          write = true;
        case '--report':
          if (index + 1 >= args.length) {
            throw const FormatException('--report requires a path');
          }
          reportPath = args[index += 1];
        default:
          throw FormatException(
            'unknown argument ${args[index]}; usage: '
            'dart run tool/validate_test_catalog.dart '
            '[--write] [--report <path>]',
          );
      }
    }
    final root = Directory.current;
    final catalog = AppTestCatalog.load(root);
    final document = File('${root.path}/$appCaseCatalogDocumentPath');
    final rendered = catalog.renderMarkdown();
    if (write) {
      document.writeAsStringSync(rendered);
    } else if (!document.existsSync() ||
        document.readAsStringSync() != rendered) {
      throw const FormatException(
        'generated catalog doc is stale; run with --write and commit the result',
      );
    }
    if (reportPath != null) {
      final reportFile = File(reportPath);
      final decoded = jsonDecode(reportFile.readAsStringSync());
      if (decoded is! Map) {
        throw const FormatException('report must be a JSON object');
      }
      catalog.validateReport(<String, Object?>{
        for (final entry in decoded.entries) entry.key.toString(): entry.value,
      });
    }
    stdout.writeln(
      'Validated ${catalog.cases.length} App cases and '
      '${catalog.suiteCaseIds.length} audited suites.',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
