import 'dart:convert';
import 'dart:io';

const int e2eCaseAttestationSchemaVersion = 2;
const String e2eCaseAttestationPathDefine = 'AWIKI_E2E_ATTESTATION_PATH';
const String e2eCaseScenarioDefine = 'AWIKI_E2E_SCENARIO';
const String e2eCaseRunIdDefine = 'AWIKI_E2E_RUN_ID';
const String e2eCaseIdsDefine = 'AWIKI_E2E_CASE_IDS';
const String e2eScenarioProgressFileName = 'scenario_progress.json';
const String e2eFailureObservationFileName = 'failure_observation.json';

File e2eScenarioProgressFileForAttestation(File attestationFile) =>
    File('${attestationFile.parent.path}/$e2eScenarioProgressFileName');

File e2eFailureObservationFileForAttestation(File attestationFile) =>
    File('${attestationFile.parent.path}/$e2eFailureObservationFileName');

/// First fail-closed E2E observation retained independently from case pass
/// attestation. Codes are stable diagnostics and must not contain payloads,
/// handles, DIDs, credentials, or local paths.
class E2eFailureObservation {
  const E2eFailureObservation({
    required this.scenario,
    required this.runId,
    required this.layer,
    required this.status,
    required this.code,
    required this.observedAt,
    this.caseId,
  });

  final String scenario;
  final String runId;
  final String layer;
  final String status;
  final String code;
  final String observedAt;
  final String? caseId;

  factory E2eFailureObservation.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException(
        'failure observation schemaVersion must be 1',
      );
    }
    final layer = _requiredString(json, 'layer');
    if (!const <String>{
      'visible_ui',
      'app_projection',
      'core_canonical',
      'remote_service',
    }.contains(layer)) {
      throw FormatException('unsupported failure observation layer "$layer"');
    }
    final status = _requiredString(json, 'status');
    if (!const <String>{'fatal', 'timeout', 'unstable'}.contains(status)) {
      throw FormatException('unsupported failure observation status "$status"');
    }
    final code = _requiredString(json, 'code');
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(code)) {
      throw const FormatException(
        'failure observation code must be a stable snake_case identifier',
      );
    }
    final caseId = _optionalString(json, 'caseId');
    if (caseId != null && !RegExp(r'^[A-Z0-9-]+$').hasMatch(caseId)) {
      throw const FormatException(
        'failure observation caseId must be a stable case identifier',
      );
    }
    return E2eFailureObservation(
      scenario: _requiredString(json, 'scenario'),
      runId: _requiredString(json, 'runId'),
      layer: layer,
      status: status,
      code: code,
      observedAt: _requiredString(json, 'observedAt'),
      caseId: caseId,
    );
  }

  static E2eFailureObservation read(File file) {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) {
      throw const FormatException('failure observation must be an object');
    }
    return E2eFailureObservation.fromJson(<String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'scenario': scenario,
    'runId': runId,
    'layer': layer,
    'status': status,
    'code': code,
    'observedAt': observedAt,
    if (caseId != null) 'caseId': caseId,
  };
}

class E2eFailureObservationWriter {
  E2eFailureObservationWriter._();

  static Future<void> recordFirst({
    required String layer,
    required String status,
    required String code,
    String? caseId,
  }) async {
    const attestationPath = String.fromEnvironment(
      e2eCaseAttestationPathDefine,
    );
    const scenario = String.fromEnvironment(e2eCaseScenarioDefine);
    const runId = String.fromEnvironment(e2eCaseRunIdDefine);
    if (attestationPath.trim().isEmpty ||
        scenario.trim().isEmpty ||
        runId.trim().isEmpty) {
      return;
    }
    final observation = E2eFailureObservation.fromJson(<String, Object?>{
      'schemaVersion': 1,
      'scenario': scenario,
      'runId': runId,
      'layer': layer,
      'status': status,
      'code': code,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      if (caseId?.trim().isNotEmpty == true) 'caseId': caseId!.trim(),
    });
    final file = e2eFailureObservationFileForAttestation(File(attestationPath));
    if (file.existsSync()) {
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(observation.toJson()),
      flush: true,
    );
    if (!file.existsSync()) {
      await temporary.rename(file.path);
    } else if (temporary.existsSync()) {
      await temporary.delete();
    }
  }
}

/// One scenario-owned case result written from inside the Flutter test body.
class E2eCaseAttestationResult {
  const E2eCaseAttestationResult({
    required this.caseId,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.phases,
    required this.assertions,
  });

  final String caseId;
  final String status;
  final String startedAt;
  final String finishedAt;
  final List<String> phases;
  final List<E2eAssertionEvidence> assertions;

  factory E2eCaseAttestationResult.fromJson(Map<String, Object?> json) {
    final caseId = _requiredString(json, 'caseId');
    final status = _requiredString(json, 'status');
    if (!const <String>{'passed', 'failed', 'skipped'}.contains(status)) {
      throw FormatException(
        'case result $caseId has unsupported status "$status"',
      );
    }
    final rawPhases = json['phases'];
    if (rawPhases is! List || rawPhases.any((value) => value is! String)) {
      throw FormatException('case result $caseId must contain string phases');
    }
    final phases = rawPhases.cast<String>();
    if (phases.isEmpty || phases.any((phase) => phase.trim().isEmpty)) {
      throw FormatException(
        'case result $caseId must contain non-empty phases',
      );
    }
    final rawAssertions = json['assertions'];
    if (rawAssertions is! List || rawAssertions.isEmpty) {
      throw FormatException(
        'case result $caseId must contain structured assertions',
      );
    }
    final assertions = <E2eAssertionEvidence>[];
    final seenAssertionIds = <String>{};
    for (final rawAssertion in rawAssertions) {
      if (rawAssertion is! Map) {
        throw FormatException(
          'case result $caseId assertion must be an object',
        );
      }
      final assertion = E2eAssertionEvidence.fromJson(<String, Object?>{
        for (final entry in rawAssertion.entries)
          entry.key.toString(): entry.value,
      });
      if (!seenAssertionIds.add(assertion.assertionId)) {
        throw FormatException(
          'case result $caseId contains duplicate assertionId '
          '${assertion.assertionId}',
        );
      }
      assertions.add(assertion);
    }
    final expectedAssertionIds = phases
        .map((phase) => '$caseId:${phase.trim()}')
        .toList(growable: false);
    final actualAssertionIds = assertions
        .map((assertion) => assertion.assertionId)
        .toList(growable: false);
    if (!_sameStringSequence(actualAssertionIds, expectedAssertionIds)) {
      throw FormatException(
        'case result $caseId assertion IDs must exactly follow phase order',
      );
    }
    return E2eCaseAttestationResult(
      caseId: caseId,
      status: status,
      startedAt: _requiredString(json, 'startedAt'),
      finishedAt: _requiredString(json, 'finishedAt'),
      phases: List<String>.unmodifiable(phases),
      assertions: List<E2eAssertionEvidence>.unmodifiable(assertions),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'caseId': caseId,
    'status': status,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'phases': phases,
    'assertions': <Map<String, Object?>>[
      for (final assertion in assertions) assertion.toJson(),
    ],
  };
}

/// One scenario-owned assertion checkpoint. IDs are stable and payload-free;
/// the outer runner rejects missing, duplicate, or reordered evidence.
class E2eAssertionEvidence {
  const E2eAssertionEvidence({
    required this.assertionId,
    required this.status,
    required this.observedAt,
  });

  final String assertionId;
  final String status;
  final String observedAt;

  factory E2eAssertionEvidence.fromJson(Map<String, Object?> json) {
    final assertionId = _requiredString(json, 'assertionId');
    if (!RegExp(r'^[A-Z0-9-]+:[a-z0-9_]+$').hasMatch(assertionId)) {
      throw const FormatException(
        'assertionId must be a stable CASE-ID:snake_case identifier',
      );
    }
    final status = _requiredString(json, 'status');
    if (status != 'passed') {
      throw FormatException('assertion $assertionId status must be passed');
    }
    return E2eAssertionEvidence(
      assertionId: assertionId,
      status: status,
      observedAt: _requiredString(json, 'observedAt'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'assertionId': assertionId,
    'status': status,
    'observedAt': observedAt,
  };
}

/// Versioned attestation emitted by the real scenario, never by the runner.
class E2eCaseAttestation {
  const E2eCaseAttestation({
    required this.scenario,
    required this.runId,
    required this.mode,
    required this.cases,
  });

  final String scenario;
  final String runId;
  final String mode;
  final List<E2eCaseAttestationResult> cases;

  factory E2eCaseAttestation.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion != e2eCaseAttestationSchemaVersion) {
      throw FormatException(
        'unsupported case attestation schemaVersion $schemaVersion',
      );
    }
    final mode = _requiredString(json, 'mode');
    if (mode != 'real') {
      throw const FormatException('case attestation mode must be "real"');
    }
    final rawCases = json['cases'];
    if (rawCases is! List) {
      throw const FormatException('case attestation cases must be a list');
    }
    final cases = <E2eCaseAttestationResult>[];
    final seen = <String>{};
    for (final rawCase in rawCases) {
      if (rawCase is! Map) {
        throw const FormatException('case attestation entry must be an object');
      }
      final result = E2eCaseAttestationResult.fromJson(<String, Object?>{
        for (final entry in rawCase.entries) entry.key.toString(): entry.value,
      });
      if (!seen.add(result.caseId)) {
        throw FormatException(
          'case attestation contains duplicate caseId ${result.caseId}',
        );
      }
      cases.add(result);
    }
    return E2eCaseAttestation(
      scenario: _requiredString(json, 'scenario'),
      runId: _requiredString(json, 'runId'),
      mode: mode,
      cases: List<E2eCaseAttestationResult>.unmodifiable(cases),
    );
  }

  static E2eCaseAttestation read(File file) {
    if (!file.existsSync()) {
      throw const FormatException('case attestation is missing');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on Object catch (error) {
      throw FormatException('case attestation is not valid JSON: $error');
    }
    if (decoded is! Map) {
      throw const FormatException('case attestation must be an object');
    }
    return E2eCaseAttestation.fromJson(<String, Object?>{
      for (final entry in decoded.entries) entry.key.toString(): entry.value,
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': e2eCaseAttestationSchemaVersion,
    'scenario': scenario,
    'runId': runId,
    'mode': mode,
    'cases': <Map<String, Object?>>[
      for (final result in cases) result.toJson(),
    ],
  };
}

/// Strict comparison between scenario-owned evidence and runner expectations.
class E2eCaseAttestationValidation {
  const E2eCaseAttestationValidation({
    required this.caseById,
    required this.errors,
  });

  final Map<String, E2eCaseAttestationResult> caseById;
  final List<String> errors;

  bool get passed => errors.isEmpty;

  factory E2eCaseAttestationValidation.validate({
    required E2eCaseAttestation attestation,
    required String expectedScenario,
    required String expectedRunId,
    required List<String> expectedCaseIds,
  }) {
    final errors = <String>[];
    if (attestation.scenario != expectedScenario) {
      errors.add(
        'scenario ${attestation.scenario} does not match $expectedScenario',
      );
    }
    if (attestation.runId != expectedRunId) {
      errors.add('runId ${attestation.runId} does not match $expectedRunId');
    }
    final expected = expectedCaseIds.toSet();
    if (expected.length != expectedCaseIds.length) {
      errors.add('runner expectedCaseIds contain duplicates');
    }
    final caseById = <String, E2eCaseAttestationResult>{
      for (final result in attestation.cases) result.caseId: result,
    };
    final actual = caseById.keys.toSet();
    final unexpected = actual.difference(expected).toList()..sort();
    final missing = expected.difference(actual).toList()..sort();
    final nonPassed =
        caseById.values
            .where((result) => result.status != 'passed')
            .map((result) => '${result.caseId}:${result.status}')
            .toList(growable: false)
          ..sort();
    if (unexpected.isNotEmpty) {
      errors.add('unexpected caseIds: ${unexpected.join(', ')}');
    }
    if (missing.isNotEmpty) {
      errors.add('missing caseIds: ${missing.join(', ')}');
    }
    if (nonPassed.isNotEmpty) {
      errors.add('non-passed caseIds: ${nonPassed.join(', ')}');
    }
    return E2eCaseAttestationValidation(
      caseById: Map<String, E2eCaseAttestationResult>.unmodifiable(caseById),
      errors: List<String>.unmodifiable(errors),
    );
  }
}

/// Writes case evidence from inside a real Flutter scenario.
///
/// Direct shim debugging may omit all attestation dart-defines. A runner-owned
/// invocation must provide the complete define set and is validated later by
/// the outer runner before it can report `passed`.
class E2eCaseAttestationWriter {
  E2eCaseAttestationWriter._();

  static Future<void> markPassed(
    String caseId, {
    required List<String> phases,
    DateTime? startedAt,
  }) async {
    const path = String.fromEnvironment(e2eCaseAttestationPathDefine);
    const scenario = String.fromEnvironment(e2eCaseScenarioDefine);
    const runId = String.fromEnvironment(e2eCaseRunIdDefine);
    const encodedCaseIds = String.fromEnvironment(e2eCaseIdsDefine);
    if (path.trim().isEmpty &&
        scenario.trim().isEmpty &&
        runId.trim().isEmpty &&
        encodedCaseIds.trim().isEmpty) {
      return;
    }
    if (path.trim().isEmpty ||
        scenario.trim().isEmpty ||
        runId.trim().isEmpty ||
        encodedCaseIds.trim().isEmpty) {
      throw StateError(
        'Runner-owned E2E case attestation requires the complete dart-define set.',
      );
    }
    final expectedCaseIds = encodedCaseIds
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (!expectedCaseIds.contains(caseId)) {
      throw StateError('Case $caseId is not expected by this E2E invocation.');
    }
    final normalizedPhases = phases
        .map((phase) => phase.trim())
        .where((phase) => phase.isNotEmpty)
        .toList(growable: false);
    if (normalizedPhases.isEmpty) {
      throw StateError('Case $caseId must attest at least one phase.');
    }

    final file = File(path);
    E2eCaseAttestation existing;
    if (file.existsSync()) {
      existing = E2eCaseAttestation.read(file);
      if (existing.scenario != scenario || existing.runId != runId) {
        throw StateError(
          'Existing E2E attestation belongs to another scenario or run.',
        );
      }
    } else {
      existing = const E2eCaseAttestation(
        scenario: scenario,
        runId: runId,
        mode: 'real',
        cases: <E2eCaseAttestationResult>[],
      );
    }

    final now = DateTime.now().toUtc();
    final result = E2eCaseAttestationResult(
      caseId: caseId,
      status: 'passed',
      startedAt: (startedAt ?? now).toUtc().toIso8601String(),
      finishedAt: now.toIso8601String(),
      phases: normalizedPhases,
      assertions: <E2eAssertionEvidence>[
        for (final phase in normalizedPhases)
          E2eAssertionEvidence(
            assertionId: '$caseId:$phase',
            status: 'passed',
            observedAt: now.toIso8601String(),
          ),
      ],
    );
    final byCaseId = <String, E2eCaseAttestationResult>{
      for (final value in existing.cases) value.caseId: value,
      caseId: result,
    };
    final updated = E2eCaseAttestation(
      scenario: scenario,
      runId: runId,
      mode: 'real',
      cases: byCaseId.values.toList(growable: false),
    );
    await file.parent.create(recursive: true);
    final temporary = File('$path.tmp')
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(updated.toJson()),
        flush: true,
      );
    if (Platform.isWindows && file.existsSync()) {
      file.deleteSync();
    }
    await temporary.rename(file.path);
  }
}

/// Writes non-acceptance breadcrumbs that survive an App/test-process exit.
///
/// Progress never converts a case to passed; it only identifies the last
/// completed scenario phase when the strict attestation is incomplete.
class E2eScenarioProgressWriter {
  E2eScenarioProgressWriter._();

  static Future<void> record(String phase) async {
    const attestationPath = String.fromEnvironment(
      e2eCaseAttestationPathDefine,
    );
    const scenario = String.fromEnvironment(e2eCaseScenarioDefine);
    const runId = String.fromEnvironment(e2eCaseRunIdDefine);
    final normalized = phase.trim();
    if (attestationPath.trim().isEmpty ||
        scenario.trim().isEmpty ||
        runId.trim().isEmpty ||
        normalized.isEmpty) {
      return;
    }
    final file = e2eScenarioProgressFileForAttestation(File(attestationPath));
    final phases = <Map<String, Object?>>[];
    if (file.existsSync()) {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['phases'] is List) {
        for (final entry in decoded['phases'] as List) {
          if (entry is Map) {
            phases.add(<String, Object?>{
              for (final item in entry.entries) item.key.toString(): item.value,
            });
          }
        }
      }
    }
    phases.add(<String, Object?>{
      'phase': normalized,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'scenario': scenario,
        'runId': runId,
        'phases': phases,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string when present');
  }
  return value.trim();
}

bool _sameStringSequence(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
