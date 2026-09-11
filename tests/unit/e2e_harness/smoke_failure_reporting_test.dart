import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/case_attestation.dart';
import '../../e2e/runner.dart';

void main() {
  test('every completion producer reports framework failures', () {
    final producers = Directory('tests/e2e/flutter')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    var count = 0;
    for (final file in producers) {
      final source = file.readAsStringSync();
      if (!source.contains('E2eInvocationCompletionWriter.markFinished')) {
        continue;
      }
      count++;
      expect(
        source,
        isNot(
          contains('tearDownAll(E2eInvocationCompletionWriter.markFinished)'),
        ),
        reason: file.path,
      );
      expect(
        source,
        contains('failedTestCount: binding.failureMethodsDetails.length'),
        reason: file.path,
      );
    }
    expect(count, greaterThan(0));
  });

  for (final missingCount in [false, true]) {
    test(
      'smoke rejects ${missingCount ? 'unknown' : 'failed'} invocation despite passing registered cases',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'smoke_failure_reporting_',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final commands = _SmokeFixtureCommands(
          root,
          missingCount: missingCount,
        );
        final runner = DesktopE2eRunner(
          root: root,
          options: DesktopE2eOptions.parse([
            '--case',
            'smoke',
            '--run-id',
            'failure-fixture',
          ]),
          commands: commands,
        );
        commands.runner = runner;
        await expectLater(
          runner.run(),
          throwsA(
            missingCount
                ? isA<FormatException>()
                : isA<E2eFailure>().having(
                    (error) => error.toString(),
                    'message',
                    contains('1 failed Flutter tests'),
                  ),
          ),
        );
        expect(File('${root.path}/core-started').existsSync(), isFalse);
        final report =
            jsonDecode(
                  File(
                    '${runner.reportDir.path}/timings.json',
                  ).readAsStringSync(),
                )
                as Map;
        expect(report['status'], 'failed');
        // The invocation failure is independent of registered case attestations.
        final cases = report['caseResults'] as List;
        expect(cases, hasLength(DesktopE2eCase.smoke.caseIds.length));
        expect(
          cases.every((result) => (result as Map)['status'] == 'passed'),
          isTrue,
        );
        final completion =
            jsonDecode(runner.invocationCompletionFile.readAsStringSync())
                as Map;
        expect(completion['expectedCaseIds'], isNot(['NATIVE-E2E-001']));
        if (!missingCount) expect(completion['failedTestCount'], 1);
      },
      skip: !Platform.isLinux && !Platform.isMacOS,
    );
  }
}

// Replace only the build/tool discovery boundary. The real runner, process
// supervisor, completion parser and final report writer execute unchanged.
class _SmokeFixtureCommands extends DesktopCommandRunner {
  _SmokeFixtureCommands(Directory root, {required this.missingCount})
    : super(
        root: root,
        dryRun: false,
        redactor: DesktopSecretRedactor([]),
        logLine: (_) {},
      );

  final bool missingCount;
  late DesktopE2eRunner runner;

  @override
  Future<void> requireExecutable(String executable) async {}

  @override
  Future<DesktopCommandResult> captureResult(
    String executable,
    List<String> args, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool allowFailure = false,
    Duration timeout = const Duration(minutes: 5),
    String? stdinText,
  }) async {
    if (executable == 'bash') {
      return const DesktopCommandResult(exitCode: 0, output: '');
    }
    expect(executable, 'dart');
    String option(String key) => args
        .singleWhere((arg) => arg.startsWith('--$key='))
        .split('=')
        .skip(1)
        .join('=');
    final name = option('name');
    final app = Directory('${root.path}/$name')..createSync();
    final script = File('${app.path}/fixture.sh');
    final caseIds = DesktopE2eCase.smoke.caseIds;
    final now = DateTime.now().toUtc().toIso8601String();
    final attestation = E2eCaseAttestation(
      scenario: DesktopE2eCase.smoke.scenario,
      runId: runner.runId,
      mode: 'real',
      cases: [
        for (final id in caseIds)
          E2eCaseAttestationResult(
            caseId: id,
            status: 'passed',
            startedAt: now,
            finishedAt: now,
            phases: ['fixture'],
            assertions: [
              E2eAssertionEvidence(
                assertionId: '$id:fixture',
                status: 'passed',
                observedAt: now,
              ),
            ],
          ),
      ],
    );
    final completion = E2eInvocationCompletion(
      scenario: DesktopE2eCase.smoke.scenario,
      runId: runner.runId,
      expectedCaseIds: caseIds.where((id) => id != 'NATIVE-E2E-001').toList(),
      finishedAt: now,
      failedTestCount: 1,
    ).toJson();
    if (missingCount) completion.remove('failedTestCount');
    script.writeAsStringSync(
      name == 'smoke-app'
          ? '''#!/bin/sh
cat > '${runner.caseAttestationFile.path}' <<'ATTESTATION'
${jsonEncode(attestation.toJson())}
ATTESTATION
cat > '${runner.invocationCompletionFile.path}.tmp' <<'COMPLETION'
${jsonEncode(completion)}
COMPLETION
mv '${runner.invocationCompletionFile.path}.tmp' '${runner.invocationCompletionFile.path}'
sleep 30
'''
          : '''#!/bin/sh
touch '${root.path}/core-started'
cat > '${runner.invocationCompletionFile.path}.tmp' <<'COMPLETION'
${jsonEncode({
              ...completion,
              'expectedCaseIds': ['NATIVE-E2E-001'],
              'failedTestCount': 0,
            })}
COMPLETION
mv '${runner.invocationCompletionFile.path}.tmp' '${runner.invocationCompletionFile.path}'
sleep 30
''',
    );
    expect((await Process.run('chmod', ['700', script.path])).exitCode, 0);
    final digest = '0' * 64;
    return DesktopCommandResult(
      exitCode: 0,
      output: jsonEncode({
        'schemaVersion': 1,
        'name': name,
        'target': option('target'),
        'bundleId': option('bundle-id'),
        'projectRelativeAppPath': name,
        'executableRelativePath': 'fixture.sh',
        'fingerprint': digest,
        'compileKey': digest,
        'compileKeySchemaVersion': 1,
        'compileKeyPayload': {},
        'provenance': {},
        'cacheHit': false,
        'consumerSuites': ['smoke'],
        'cachePrunedEntries': 0,
        'cachePrunedBytes': 0,
        'artifactSha256': digest,
      }),
    );
  }
}
