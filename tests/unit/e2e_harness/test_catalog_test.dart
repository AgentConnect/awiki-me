import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/test_catalog.dart';

void main() {
  test(
    'checked-in catalog matches every audited suite case and implementation',
    () {
      final catalog = AppTestCatalog.load(Directory.current);

      expect(catalog.cases, hasLength(43));
      expect(
        catalog.suiteCaseIds.keys,
        containsAll(<String>['smoke', 'full', 'direct']),
      );
      expect(catalog.renderMarkdown(), contains('global unread increased by'));
    },
  );

  test('catalog rejects missing metadata and manifest cases', () async {
    final root = await _temporaryCatalogRoot();
    addTearDown(() => root.delete(recursive: true));
    final catalogFile = File('${root.path}/$appCaseCatalogPath');
    final decoded =
        jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
    (decoded['cases'] as List<dynamic>).clear();
    catalogFile.writeAsStringSync(jsonEncode(decoded));

    expect(
      () => AppTestCatalog.load(root),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('missing manifest caseIds'),
        ),
      ),
    );
  });

  test(
    'catalog report validation rejects unknown duplicate and missing IDs',
    () async {
      final root = await _temporaryCatalogRoot();
      addTearDown(() => root.delete(recursive: true));
      final catalog = AppTestCatalog.load(root);
      final valid = <String, Object?>{
        'case': 'focused',
        'caseIds': <String>['CASE-001'],
        'caseResults': <Map<String, Object?>>[
          <String, Object?>{'caseId': 'CASE-001', 'status': 'not_run'},
        ],
      };

      catalog.validateReport(valid);

      final unknown = Map<String, Object?>.from(valid)
        ..['caseResults'] = <Map<String, Object?>>[
          <String, Object?>{'caseId': 'CASE-UNKNOWN'},
        ];
      expect(
        () => catalog.validateReport(unknown),
        throwsA(isA<FormatException>()),
      );

      final duplicate = Map<String, Object?>.from(valid)
        ..['caseResults'] = <Map<String, Object?>>[
          <String, Object?>{'caseId': 'CASE-001'},
          <String, Object?>{'caseId': 'CASE-001'},
        ];
      expect(
        () => catalog.validateReport(duplicate),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicate caseId'),
          ),
        ),
      );

      final missing = Map<String, Object?>.from(valid)
        ..['caseResults'] = <Map<String, Object?>>[];
      expect(
        () => catalog.validateReport(missing),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('caseResults mismatch'),
          ),
        ),
      );
    },
  );
}

Future<Directory> _temporaryCatalogRoot() async {
  final root = await Directory.systemTemp.createTemp('awiki_test_catalog_');
  final e2e = Directory('${root.path}/tests/e2e')..createSync(recursive: true);
  File('${e2e.path}/suite_manifest.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'suites': <String, Object?>{
        'focused': <String, Object?>{
          'tier': 'product_ui',
          'requiredFor': <String>['release'],
          'owner': 'owner-a',
          'cleanupPolicy': 'none',
          'allowedHosts': <String>[],
          'caseIds': <String>['CASE-001'],
        },
      },
    }),
  );
  File(
    '${e2e.path}/implementation.dart',
  ).writeAsStringSync("const caseId = 'CASE-001';\n");
  File('${e2e.path}/case_catalog.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'sourceRevision': 'unit-test',
      'cases': <Map<String, Object?>>[
        <String, Object?>{
          'caseId': 'CASE-001',
          'catalogStatus': 'active',
          'feature': 'Feature',
          'layer': 'product_ui',
          'preconditions': 'A precondition.',
          'action': 'Perform an action.',
          'exactOracles': <String>['Exactly one result.'],
          'negativeChecks': <String>['Duplicates fail.'],
          'environment': 'no_service',
          'cleanupPolicy': 'none',
          'requiredFor': <String>['release'],
          'owner': 'owner-a',
          'implementationPath': 'tests/e2e/implementation.dart',
          'evidenceType': 'case_attestation',
        },
      ],
    }),
  );
  return root;
}
