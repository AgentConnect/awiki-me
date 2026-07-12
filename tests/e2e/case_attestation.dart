import 'dart:convert';
import 'dart:io';

const int e2eCaseAttestationSchemaVersion = 1;
const String e2eCaseAttestationPathDefine = 'AWIKI_E2E_ATTESTATION_PATH';
const String e2eCaseScenarioDefine = 'AWIKI_E2E_SCENARIO';
const String e2eCaseRunIdDefine = 'AWIKI_E2E_RUN_ID';
const String e2eCaseIdsDefine = 'AWIKI_E2E_CASE_IDS';
const String e2eScenarioProgressFileName = 'scenario_progress.json';

File e2eScenarioProgressFileForAttestation(File attestationFile) =>
    File('${attestationFile.parent.path}/$e2eScenarioProgressFileName');

/// One scenario-owned case result written from inside the Flutter test body.
class E2eCaseAttestationResult {
  const E2eCaseAttestationResult({
    required this.caseId,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.phases,
  });

  final String caseId;
  final String status;
  final String startedAt;
  final String finishedAt;
  final List<String> phases;

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
    return E2eCaseAttestationResult(
      caseId: caseId,
      status: status,
      startedAt: _requiredString(json, 'startedAt'),
      finishedAt: _requiredString(json, 'finishedAt'),
      phases: List<String>.unmodifiable(phases),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'caseId': caseId,
    'status': status,
    'startedAt': startedAt,
    'finishedAt': finishedAt,
    'phases': phases,
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
