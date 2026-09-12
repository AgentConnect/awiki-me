import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/test_catalog.dart';

const _registrations = <({String caseId, String variable, String suite})>[
  (
    caseId: 'HANDLE-RECOVERY-V1-E2E-001',
    variable: '_caseId',
    suite: 'multi-device-remote-recovery',
  ),
  (
    caseId: 'MLS-MULTI-DEVICE-E2E-002',
    variable: '_mlsRevokeCaseId',
    suite: 'step4-revoke-mls',
  ),
  (
    caseId: 'ROOT-TRANSFER-E2E-001',
    variable: '_rootTransferCaseId',
    suite: 'root-transfer',
  ),
];

void main() {
  final catalog = AppTestCatalog.load(Directory.current);
  for (final registration in _registrations) {
    test(
      '${registration.caseId} emits the exact catalog assertion contract',
      () {
        final phases = _emittedPhases(catalog, registration);
        expect(
          () => catalog.validateReport(_report(catalog, registration, phases)),
          returnsNormally,
        );
      },
    );

    for (final mutation in <String>['missing', 'extra', 'reordered']) {
      test('${registration.caseId} rejects $mutation assertion evidence', () {
        final changed = _emittedPhases(catalog, registration);
        switch (mutation) {
          case 'missing':
            changed.removeLast();
          case 'extra':
            changed.add('unregistered_check');
          case 'reordered':
            final first = changed[0];
            changed[0] = changed[1];
            changed[1] = first;
        }
        expect(
          () => catalog.validateReport(_report(catalog, registration, changed)),
          throwsA(isA<FormatException>()),
        );
      });
    }
  }

  test('basic Recovery does not attest separately selected group continuity', () {
    final phases = _emittedPhases(catalog, _registrations.first);
    expect(
      phases,
      isNot(contains('old_transport_group_rebound_to_recovered_did')),
    );
    expect(
      phases,
      isNot(contains('old_group_message_recognized_as_account_owned')),
    );
    expect(phases, isNot(contains('recovered_identity_sent_in_old_group')));
    final groupCase =
        catalog.caseById['HANDLE-RECOVERY-FRESH-GROUP-REBIND-E2E-001']!;
    expect(groupCase.catalogStatus, 'active');
    expect(
      groupCase.assertionContract!.assertionIds,
      contains(
        'HANDLE-RECOVERY-FRESH-GROUP-REBIND-E2E-001:public_product_projection_rebind_converged_exactly_once',
      ),
    );
  });

  test('MLS revocation attests readiness after removal convergence', () {
    expect(
      _emittedPhases(catalog, _registrations[1]),
      contains('app_ready_only_after_remove_convergence'),
    );
  });
}

// These three emitters deliberately declare literal ordered phases. Read the
// declarations rather than copying catalog phases into an always-valid report.
List<String> _emittedPhases(
  AppTestCatalog catalog,
  ({String caseId, String variable, String suite}) registration,
) {
  final source = File(
    catalog.caseById[registration.caseId]!.implementationPath,
  ).readAsStringSync();
  final variable = RegExp.escape(registration.variable);
  expect(
    RegExp(
      "const String $variable\\s*=\\s*'${registration.caseId}'",
    ).hasMatch(source),
    isTrue,
  );
  final matches = RegExp(
    r'E2eCaseAttestationWriter\.markPassed\(\s*' +
        variable +
        r',[\s\S]*?phases:\s*const <String>\[([^\]]*)\]',
  ).allMatches(source).toList();
  expect(matches, hasLength(1));
  final phases = RegExp("'([a-z0-9_]+)'")
      .allMatches(matches.single.group(1)!)
      .map((match) => match.group(1)!)
      .toList();
  expect(phases, isNotEmpty);
  return phases;
}

Map<String, Object?> _report(
  AppTestCatalog catalog,
  ({String caseId, String variable, String suite}) registration,
  List<String> phases,
) => <String, Object?>{
  'case': registration.suite,
  'caseIds': catalog.suiteCaseIds[registration.suite],
  'caseResults': <Map<String, Object?>>[
    for (final caseId in catalog.suiteCaseIds[registration.suite]!)
      <String, Object?>{
        'caseId': caseId,
        'status': caseId == registration.caseId ? 'passed' : 'not_run',
        if (caseId == registration.caseId) ...<String, Object?>{
          'phases': phases,
          'assertions': <Map<String, Object?>>[
            for (final phase in phases)
              <String, Object?>{
                'assertionId': '$caseId:$phase',
                'status': 'passed',
                'observedAt': '2026-09-12T00:00:00Z',
              },
          ],
        },
      },
  ],
};
