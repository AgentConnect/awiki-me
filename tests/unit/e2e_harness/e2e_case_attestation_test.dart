import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/case_attestation.dart';

void main() {
  group('E2eCaseAttestation', () {
    test('accepts an exact all-passed real scenario', () {
      final attestation = E2eCaseAttestation.fromJson(
        _attestationJson(<Map<String, Object?>>[
          _caseJson('CASE-001'),
          _caseJson('CASE-002'),
        ]),
      );

      final validation = E2eCaseAttestationValidation.validate(
        attestation: attestation,
        expectedScenario: 'scenario-a',
        expectedRunId: 'run-a',
        expectedCaseIds: const <String>['CASE-001', 'CASE-002'],
      );

      expect(validation.passed, isTrue);
      expect(validation.errors, isEmpty);
      expect(validation.caseById.keys, <String>['CASE-001', 'CASE-002']);
    });

    test('fails closed for missing skipped and unexpected cases', () {
      final attestation = E2eCaseAttestation.fromJson(
        _attestationJson(<Map<String, Object?>>[
          _caseJson('CASE-001', status: 'skipped'),
          _caseJson('CASE-EXTRA'),
        ]),
      );

      final validation = E2eCaseAttestationValidation.validate(
        attestation: attestation,
        expectedScenario: 'scenario-a',
        expectedRunId: 'run-a',
        expectedCaseIds: const <String>['CASE-001', 'CASE-002'],
      );

      expect(validation.passed, isFalse);
      expect(
        validation.errors.join('\n'),
        contains('missing caseIds: CASE-002'),
      );
      expect(
        validation.errors.join('\n'),
        contains('unexpected caseIds: CASE-EXTRA'),
      );
      expect(
        validation.errors.join('\n'),
        contains('non-passed caseIds: CASE-001:skipped'),
      );
    });

    test('rejects wrong scenario run and duplicate expected IDs', () {
      final attestation = E2eCaseAttestation.fromJson(
        _attestationJson(<Map<String, Object?>>[_caseJson('CASE-001')]),
      );

      final validation = E2eCaseAttestationValidation.validate(
        attestation: attestation,
        expectedScenario: 'scenario-b',
        expectedRunId: 'run-b',
        expectedCaseIds: const <String>['CASE-001', 'CASE-001'],
      );

      expect(validation.passed, isFalse);
      expect(validation.errors.join('\n'), contains('scenario'));
      expect(validation.errors.join('\n'), contains('runId'));
      expect(validation.errors.join('\n'), contains('contain duplicates'));
    });

    test('rejects duplicate actual case IDs', () {
      expect(
        () => E2eCaseAttestation.fromJson(
          _attestationJson(<Map<String, Object?>>[
            _caseJson('CASE-001'),
            _caseJson('CASE-001'),
          ]),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicate caseId CASE-001'),
          ),
        ),
      );
    });

    test('rejects corrupt and missing attestation files', () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_e2e_attestation_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final missing = File('${root.path}/missing.json');
      expect(
        () => E2eCaseAttestation.read(missing),
        throwsA(isA<FormatException>()),
      );
      final corrupt = File('${root.path}/corrupt.json')
        ..writeAsStringSync('{not-json');
      expect(
        () => E2eCaseAttestation.read(corrupt),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('round trips without local paths or payload data', () {
      final attestation = E2eCaseAttestation.fromJson(
        _attestationJson(<Map<String, Object?>>[_caseJson('CASE-001')]),
      );
      final encoded = jsonEncode(attestation.toJson());

      expect(encoded, isNot(contains(Directory.current.path)));
      expect(encoded, isNot(contains('token')));
      expect(encoded, isNot(contains('messageBody')));
    });
  });
}

Map<String, Object?> _attestationJson(List<Map<String, Object?>> cases) =>
    <String, Object?>{
      'schemaVersion': e2eCaseAttestationSchemaVersion,
      'scenario': 'scenario-a',
      'runId': 'run-a',
      'mode': 'real',
      'cases': cases,
    };

Map<String, Object?> _caseJson(String caseId, {String status = 'passed'}) =>
    <String, Object?>{
      'caseId': caseId,
      'status': status,
      'startedAt': '2026-07-10T10:00:00.000Z',
      'finishedAt': '2026-07-10T10:00:01.000Z',
      'phases': <String>['assertion_completed'],
    };
