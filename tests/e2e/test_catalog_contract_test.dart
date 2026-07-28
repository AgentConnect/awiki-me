import 'package:flutter_test/flutter_test.dart';

import 'test_catalog.dart';

void main() {
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
}
