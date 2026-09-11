import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'test_catalog.dart';
import 'runner/manifest.dart';

void main() {
  test(
    'full E2E entry covers all active oracles without duplicate execution',
    () {
      final root = Directory.current;
      final catalog = AppTestCatalog.load(root);
      final leaves = DesktopE2eSuiteManifest.load(root).fullSuites();
      final ids = leaves.expand((suite) => suite.caseIds).toList();
      expect(ids.length, ids.toSet().length);
      expect(
        ids.toSet(),
        catalog.cases
            .where((c) => c.catalogStatus == 'active')
            .map((c) => c.caseId)
            .toSet(),
      );
      expect(
        leaves.map((s) => s.name),
        containsAll(<String>[
          'multi-device-app-pair',
          'multi-device-remote-recovery',
          'root-transfer',
        ]),
      );
    },
  );

  group('active case attestation registration', () {
    test('rejects a case ID that is only declared', () {
      const source = '''
const String readCaseId = 'READ-SYNC-E2E-001';
bool expectsRead(String value) => value == readCaseId;
''';

      expect(
        hasActiveCaseAttestationRegistration(source, 'READ-SYNC-E2E-001'),
        isFalse,
      );
    });

    test('accepts a declared case ID passed to markPassed', () {
      const source = '''
const String readCaseId = 'READ-SYNC-E2E-001';
Future<void> complete() {
  return E2eCaseAttestationWriter.markPassed(
    readCaseId,
    phases: const <String>['read_converged'],
  );
}
''';

      expect(
        hasActiveCaseAttestationRegistration(source, 'READ-SYNC-E2E-001'),
        isTrue,
      );
    });

    test('accepts an explicit phase-map registration', () {
      const source = '''
const phasesByCase = <String, List<String>>{
  'READ-SYNC-E2E-001': <String>['read_converged'],
};
Future<void> complete() async {
  for (final entry in phasesByCase.entries) {
    await E2eCaseAttestationWriter.markPassed(entry.key, phases: entry.value);
  }
}
''';

      expect(
        hasActiveCaseAttestationRegistration(source, 'READ-SYNC-E2E-001'),
        isTrue,
      );
    });
  });

  test('desktop robot waits for the App to restore its active session', () {
    final source = File(
      'tests/e2e/flutter/desktop_cli_peer/support/ui_robot.dart',
    ).readAsStringSync();

    expect(source, contains('awaitRestoredSession'));
    expect(source, isNot(contains('.activateSession(')));
    expect(source, contains('ownerIdentityId: ownerIdentityId'));
    expect(source, contains('ownerIdentityId: patch.ownerIdentityId'));
  });
}
