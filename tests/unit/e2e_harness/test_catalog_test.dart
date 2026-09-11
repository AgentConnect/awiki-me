import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/test_catalog.dart';

void main() {
  test('Recovery continuation retains existing and new exact UI attestations', () {
    final catalog = AppTestCatalog.load(Directory.current);
    final contract = catalog
        .caseById['HANDLE-RECOVERY-STATE-MACHINE-RESUME-E2E-001']!
        .assertionContract!;
    expect(
      contract.assertionIds,
      containsAll(<String>[
        'HANDLE-RECOVERY-STATE-MACHINE-RESUME-E2E-001:local_continuation_without_login_otp',
        'HANDLE-RECOVERY-STATE-MACHINE-RESUME-E2E-001:committed_reentry_hides_factor_and_first_commit',
        'HANDLE-RECOVERY-STATE-MACHINE-RESUME-E2E-001:registration_redirected_to_exact_recovery',
        'HANDLE-RECOVERY-STATE-MACHINE-RESUME-E2E-001:recovered_session_entered_messages',
      ]),
    );
    final source = File(
      'tests/e2e/flutter/app/handle_recovery_state_machine_test.part.dart',
    ).readAsStringSync();
    final tap = source.substring(
      source.indexOf('Future<void> _smTap('),
      source.indexOf('Future<void> _smOpenSettingsRecovery('),
    );
    expect(tap, contains('finder.hitTestable().evaluate().length == 1'));
    expect(tap, contains('await _tapOne('));
    expect(tap, isNot(contains('onPressed')));
  });

  test('root-transfer retains retry and full completion attestations', () {
    final catalog = AppTestCatalog.load(Directory.current);
    expect(
      catalog
          .caseById['ROOT-TRANSFER-E2E-001']!
          .assertionContract!
          .assertionIds,
      containsAll(<String>[
        'ROOT-TRANSFER-E2E-001:active_join_missing_prekey_retryable',
        'ROOT-TRANSFER-E2E-001:active_join_retry_requires_fresh_confirmation',
        'ROOT-TRANSFER-E2E-001:receiver_completion_ready',
      ]),
    );
  });

  test(
    'checked-in catalog matches every audited suite case and implementation',
    () {
      final catalog = AppTestCatalog.load(Directory.current);

      final manifest =
          jsonDecode(File(appSuiteManifestPath).readAsStringSync())
              as Map<String, dynamic>;
      final suites = manifest['suites'] as Map<String, dynamic>;
      final activeManifestCaseIds = suites.values
          .expand((suite) => (suite as Map<String, dynamic>)['caseIds'] as List)
          .cast<String>()
          .where((id) => catalog.caseById[id]?.catalogStatus == 'active')
          .toSet();
      expect(
        catalog.cases
            .where((entry) => entry.catalogStatus == 'active')
            .map((entry) => entry.caseId),
        unorderedEquals(activeManifestCaseIds),
      );
      expect(catalog.cases, hasLength(catalog.caseById.length));
      expect(
        catalog.caseById.keys,
        containsAll(<String>[
          'APP-UPDATE-SMOKE-E2E-001',
          'ROOT-TRANSFER-E2E-001',
          'ROOT-TRANSFER-APP-PAIR-E2E-001',
          'ROOT-TRANSFER-E2E-002',
          'DEVICE-JOIN-E2E-001',
          'DEVICE-JOIN-E2E-002',
          'DEVICE-JOIN-E2E-006',
          'DEVICE-JOIN-MESSAGE-CORE-E2E-001',
          'DEVICE-JOIN-E2E-004',
          'DEVICE-AGENT-SYNC-E2E-001',
          'DEVICE-MESSAGE-SYNC-E2E-001',
          'DEVICE-MESSAGE-SYNC-E2E-002',
          'DEVICE-MESSAGE-HINT-LOSS-E2E-001',
          'DEVICE-MESSAGE-RECONNECT-E2E-001',
          'DEVICE-MESSAGE-PATCH-READY-E2E-001',
          'DEVICE-MESSAGE-DIAGNOSTICS-E2E-001',
          'DEVICE-MESSAGE-GENERATION-FENCE-E2E-001',
          'MESSAGE-PATCH-RESTART-E2E-001',
          'DEVICE-REVOKE-E2E-001',
          'STEP4-GROUP-PAGINATION-E2E-001',
          'MLS-MULTI-DEVICE-E2E-001',
          'MLS-MULTI-DEVICE-E2E-002',
          'MULTI-DEVICE-CAPABILITY-GATE-E2E-001',
          'HANDLE-RECOVERY-STATE-MACHINE-TARGET-E2E-001',
          'HANDLE-RECOVERY-STATE-MACHINE-RESUME-E2E-001',
          'HANDLE-RECOVERY-STATE-MACHINE-REPEAT-E2E-001',
          'HANDLE-RECOVERY-V1-E2E-001',
          'HANDLE-RECOVERY-V1-E2E-002',
          'HANDLE-RECOVERY-V1-E2E-003',
          'HANDLE-RECOVERY-SETTINGS-CONTINUITY-E2E-001',
          'HANDLE-RECOVERY-RETIREMENT-ORDINARY-REJOIN-E2E-001',
          'IDENTITY-DELETE-E2E-001',
          'ANDROID-DEVICE-JOIN-E2E-001',
          'IOS-DEVICE-JOIN-E2E-001',
          'WINDOWS-DEVICE-JOIN-E2E-001',
          'WINDOWS-ATTACHMENT-LONG-PATH-E2E-001',
          'ANDROID-PUSH-PRODUCT-E2E-001',
          'ANDROID-PUSH-NATIVE-E2E-001',
        ]),
      );
      expect(
        catalog.suiteCaseIds.keys,
        containsAll(<String>[
          'smoke',
          'multi-device',
          'multi-device-remote-join',
          'multi-device-remote-recovery',
          'multi-device-remote-recovery-fresh',
          'handle-recovery-local-data',
          'multi-device-app-pair-recovery-retirement-ordinary-rejoin',
          'multi-device-app-pair',
          'multi-device-app-pair-functional',
          'step4-revoke-mls',
          'root-transfer',
          'full',
          'direct',
          'identity-switch',
        ]),
      );
      expect(catalog.caseById['DEVICE-JOIN-E2E-001']!.catalogStatus, 'active');
      expect(catalog.caseById['DEVICE-JOIN-E2E-002']!.catalogStatus, 'active');
      expect(catalog.caseById['DEVICE-JOIN-E2E-004']!.catalogStatus, 'active');
      expect(
        catalog.caseById['ROOT-TRANSFER-E2E-001']!.catalogStatus,
        'active',
      );
      expect(
        catalog.caseById['DEVICE-REVOKE-E2E-001']!.catalogStatus,
        'active',
      );
      expect(catalog.suiteCaseIds['multi-device-remote-join'], <String>[
        'DEVICE-JOIN-E2E-001',
        'DEVICE-JOIN-E2E-002',
        'DEVICE-JOIN-E2E-006',
        'DEVICE-JOIN-MESSAGE-CORE-E2E-001',
      ]);
      expect(catalog.suiteCaseIds['multi-device-remote-recovery'], <String>[
        'HANDLE-RECOVERY-V1-E2E-001',
        'HANDLE-RECOVERY-V1-E2E-002',
        'HANDLE-RECOVERY-V1-E2E-003',
      ]);
      expect(catalog.suiteCaseIds['handle-recovery-local-data'], <String>[
        'HANDLE-RECOVERY-SETTINGS-CONTINUITY-E2E-001',
      ]);
      expect(
        catalog
            .suiteCaseIds['multi-device-app-pair-recovery-retirement-ordinary-rejoin'],
        <String>['HANDLE-RECOVERY-RETIREMENT-ORDINARY-REJOIN-E2E-001'],
      );
      expect(
        catalog.suiteCaseIds['multi-device-remote-recovery-fresh'],
        <String>[
          'HANDLE-RECOVERY-FRESH-AGENT-INVENTORY-E2E-001',
          'HANDLE-RECOVERY-FRESH-AGENT-MESSAGE-E2E-001',
          'HANDLE-RECOVERY-FRESH-DIRECT-INBOUND-E2E-001',
          'HANDLE-RECOVERY-FRESH-GROUP-REBIND-E2E-001',
          'HANDLE-RECOVERY-FRESH-GROUP-INBOUND-E2E-001',
          'HANDLE-RECOVERY-FRESH-RESTART-E2E-001',
        ],
      );
      expect(catalog.suiteCaseIds['multi-device-app-pair'], <String>[
        'DEVICE-JOIN-E2E-004',
        'DEVICE-JOIN-E2E-005',
        'ROOT-TRANSFER-APP-PAIR-E2E-001',
      ]);
      expect(catalog.suiteCaseIds['multi-device-app-pair-functional'], <String>[
        'DEVICE-AGENT-SYNC-E2E-001',
        'DEVICE-AGENT-MESSAGE-SYNC-E2E-001',
        'DEVICE-MESSAGE-SYNC-E2E-001',
        'DEVICE-MESSAGE-SYNC-E2E-002',
        'DEVICE-MESSAGE-ONLINE-SYNC-E2E-001',
        'DEVICE-MESSAGE-TAIL-ONLY-E2E-001',
        'DEVICE-MESSAGE-READ-SYNC-E2E-001',
        'DEVICE-MESSAGE-OFFLINE-RECOVERY-E2E-001',
        'DEVICE-MESSAGE-HINT-LOSS-E2E-001',
        'DEVICE-MESSAGE-RECONNECT-E2E-001',
        'DEVICE-MESSAGE-PATCH-READY-E2E-001',
        'DEVICE-MESSAGE-DIAGNOSTICS-E2E-001',
        'DEVICE-AGENT-ADD-SYNC-E2E-001',
        'DEVICE-AGENT-RENAME-SYNC-E2E-001',
        'DEVICE-AGENT-DELETE-SYNC-E2E-001',
        'DEVICE-AGENT-UNBIND-SYNC-E2E-001',
        'DEVICE-AGENT-ARCHIVE-SYNC-E2E-001',
        'DEVICE-PROFILE-SYNC-E2E-001',
        'DEVICE-ACCOUNT-DOMAIN-ISOLATION-E2E-001',
        'DEVICE-REGISTRY-SYNC-E2E-001',
        'DEVICE-MESSAGE-GENERATION-FENCE-E2E-001',
      ]);
      expect(catalog.suiteCaseIds['full'], contains('ROOT-TRANSFER-E2E-001'));
      expect(catalog.suiteCaseIds['root-transfer'], <String>[
        'ROOT-TRANSFER-E2E-001',
      ]);
      expect(catalog.suiteCaseIds['step4-revoke-mls'], <String>[
        'STEP4-GROUP-PAGINATION-E2E-001',
        'DEVICE-REVOKE-E2E-001',
        'MLS-MULTI-DEVICE-E2E-002',
      ]);
      expect(
        catalog.caseById['MLS-MULTI-DEVICE-E2E-001']!.catalogStatus,
        'planned',
      );
      expect(
        catalog.caseById['MLS-MULTI-DEVICE-E2E-002']!.catalogStatus,
        'active',
      );
      expect(
        catalog.caseById['ANDROID-DEVICE-JOIN-E2E-001']!.catalogStatus,
        'planned',
      );
      expect(
        catalog.caseById['IOS-DEVICE-JOIN-E2E-001']!.catalogStatus,
        'planned',
      );
      expect(
        catalog.caseById['WINDOWS-DEVICE-JOIN-E2E-001']!.catalogStatus,
        'planned',
      );
      expect(
        catalog.caseById['WINDOWS-ATTACHMENT-LONG-PATH-E2E-001']!.catalogStatus,
        'planned',
      );
      expect(
        catalog.caseById['ANDROID-PUSH-PRODUCT-E2E-001']!.catalogStatus,
        'planned',
      );
      expect(
        catalog.caseById['ANDROID-PUSH-NATIVE-E2E-001']!.catalogStatus,
        'planned',
      );
      final executableCaseIds = catalog.suiteCaseIds.values.expand(
        (caseIds) => caseIds,
      );
      expect(executableCaseIds, isNot(contains('ANDROID-DEVICE-JOIN-E2E-001')));
      expect(executableCaseIds, isNot(contains('IOS-DEVICE-JOIN-E2E-001')));
      expect(executableCaseIds, isNot(contains('WINDOWS-DEVICE-JOIN-E2E-001')));
      expect(
        executableCaseIds,
        isNot(contains('WINDOWS-ATTACHMENT-LONG-PATH-E2E-001')),
      );
      expect(
        executableCaseIds,
        isNot(contains('ANDROID-PUSH-PRODUCT-E2E-001')),
      );
      expect(executableCaseIds, isNot(contains('ANDROID-PUSH-NATIVE-E2E-001')));
      expect(catalog.suiteCaseIds, isNot(contains('multi-device-remote-mls')));
      expect(catalog.renderMarkdown(), contains('global unread increases by'));
    },
  );

  test('future Root recovery Revoke and MLS cases have one planned anchor', () {
    final source = File(
      'tests/e2e/planned/multi_device_future_cases.md',
    ).readAsStringSync();

    for (final caseId in <String>[
      'ROOT-TRANSFER-E2E-002',
      'MLS-MULTI-DEVICE-E2E-001',
    ]) {
      expect(source, contains('`$caseId`'));
    }
    expect(source, contains('non-executable catalog anchor'));
    expect(source, contains('have been deleted'));
  });

  test('every active case has a machine-checkable claim mapping', () {
    final catalog = AppTestCatalog.load(Directory.current);
    for (final catalogCase in catalog.cases.where(
      (value) => value.catalogStatus == 'active',
    )) {
      expect(
        catalogCase.assertionContract,
        isNotNull,
        reason:
            '${catalogCase.caseId} must map every claim to executable evidence',
      );
    }
  });

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

      final passed = <String, Object?>{
        'case': 'focused',
        'caseIds': <String>['CASE-001'],
        'caseResults': <Map<String, Object?>>[_passedCaseResult()],
      };
      catalog.validateReport(passed);

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

      final missingAssertions = <String, Object?>{
        ...passed,
        'caseResults': <Map<String, Object?>>[
          _passedCaseResult()..remove('assertions'),
        ],
      };
      expect(
        () => catalog.validateReport(missingAssertions),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('structured assertions'),
          ),
        ),
      );

      final duplicateAssertions = _passedCaseResult();
      duplicateAssertions['phases'] = <String>['first_check', 'second_check'];
      duplicateAssertions['assertions'] = <Map<String, Object?>>[
        _assertionResult('CASE-001:first_check'),
        _assertionResult('CASE-001:first_check'),
      ];
      expect(
        () => catalog.validateReport(<String, Object?>{
          ...passed,
          'caseResults': <Map<String, Object?>>[duplicateAssertions],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicate assertionId'),
          ),
        ),
      );

      final reorderedAssertions = _passedCaseResult();
      reorderedAssertions['phases'] = <String>['first_check', 'second_check'];
      reorderedAssertions['assertions'] = <Map<String, Object?>>[
        _assertionResult('CASE-001:second_check'),
        _assertionResult('CASE-001:first_check'),
      ];
      expect(
        () => catalog.validateReport(<String, Object?>{
          ...passed,
          'caseResults': <Map<String, Object?>>[reorderedAssertions],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('exactly follow phase order'),
          ),
        ),
      );
    },
  );

  test(
    'catalog assertion contract traces claims and rejects report drift',
    () async {
      final root = await _temporaryCatalogRoot();
      addTearDown(() => root.delete(recursive: true));
      final catalogFile = File('${root.path}/$appCaseCatalogPath');
      final decoded =
          jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
      final catalogCase =
          (decoded['cases'] as List<dynamic>).single as Map<String, dynamic>;
      catalogCase['assertionContract'] = <String, Object?>{
        'assertionIds': <String>['CASE-001:assertion_completed'],
        'exactOracleAssertions': <List<String>>[
          <String>['CASE-001:assertion_completed'],
        ],
        'negativeCheckAssertions': <List<String>>[
          <String>['CASE-001:assertion_completed'],
        ],
      };
      catalogFile.writeAsStringSync(jsonEncode(decoded));
      final catalog = AppTestCatalog.load(root);
      catalog.validateReport(<String, Object?>{
        'case': 'focused',
        'caseIds': <String>['CASE-001'],
        'caseResults': <Map<String, Object?>>[_passedCaseResult()],
      });

      final drifted = _passedCaseResult()
        ..['phases'] = <String>['different_assertion']
        ..['assertions'] = <Map<String, Object?>>[
          _assertionResult('CASE-001:different_assertion'),
        ];
      expect(
        () => catalog.validateReport(<String, Object?>{
          'case': 'focused',
          'caseIds': <String>['CASE-001'],
          'caseResults': <Map<String, Object?>>[drifted],
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('catalog assertion contract'),
          ),
        ),
      );

      final invalidDecoded =
          jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
      final invalidCase =
          (invalidDecoded['cases'] as List<dynamic>).single
              as Map<String, dynamic>;
      final contract = invalidCase['assertionContract'] as Map<String, dynamic>;
      contract['negativeCheckAssertions'] = <List<String>>[];
      catalogFile.writeAsStringSync(jsonEncode(invalidDecoded));
      expect(
        () => AppTestCatalog.load(root),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('one entry per catalog claim'),
          ),
        ),
      );
    },
  );
}

Map<String, Object?> _passedCaseResult() => <String, Object?>{
  'caseId': 'CASE-001',
  'status': 'passed',
  'phases': <String>['assertion_completed'],
  'assertions': <Map<String, Object?>>[
    _assertionResult('CASE-001:assertion_completed'),
  ],
};

Map<String, Object?> _assertionResult(String assertionId) => <String, Object?>{
  'assertionId': assertionId,
  'status': 'passed',
  'observedAt': '2026-07-16T00:00:00.000Z',
};

Future<Directory> _temporaryCatalogRoot() async {
  final root = await Directory.systemTemp.createTemp('awiki_test_catalog_');
  final e2e = Directory('${root.path}/tests/e2e')..createSync(recursive: true);
  File('${e2e.path}/suite_manifest.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'sourceRevision': 'unit-test',
      'suites': <String, Object?>{
        'focused': <String, Object?>{
          'tier': 'remote_product_ui',
          'supportedPlatforms': <String>['macos', 'linux'],
          'requiredTools': <String>['flutter', 'awiki-cli'],
          'requiredFor': <String>['release'],
          'owner': 'owner-a',
          'cleanupPolicy': 'none',
          'allowedHosts': <String>[],
          'caseIds': <String>['CASE-001'],
        },
      },
    }),
  );
  File('${e2e.path}/implementation.dart').writeAsStringSync('''
const String caseId = 'CASE-001';
Future<void> complete() {
  return E2eCaseAttestationWriter.markPassed(
    caseId,
    phases: const <String>['assertion_completed'],
  );
}
''');
  File('${e2e.path}/case_catalog.json').writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'sourceRevision': 'unit-test',
      'cases': <Map<String, Object?>>[
        <String, Object?>{
          'caseId': 'CASE-001',
          'catalogStatus': 'active',
          'feature': 'Feature',
          'layer': 'remote_product_ui',
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
