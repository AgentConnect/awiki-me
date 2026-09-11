import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/case_attestation.dart';
import '../../e2e/prepared_integration_process.dart';

void main() {
  for (final failures in <int>[0, 1]) {
    test(
      'prepared completion preserves Flutter failure count $failures',
      () async {
        final root = await Directory.systemTemp.createTemp('awiki_completion_');
        addTearDown(() => root.delete(recursive: true));
        final completion = File('${root.path}/completion.json');
        final executable = File('${root.path}/prepared.sh');
        final payload = E2eInvocationCompletion(
          scenario: 'fixture',
          runId: 'fixture-run',
          expectedCaseIds: const <String>['CASE-001'],
          finishedAt: '2026-09-06T00:00:00Z',
          failedTestCount: failures,
        );
        await executable.writeAsString(
          '#!/bin/sh\n'
          'cat > "${completion.path}.tmp" <<\'PAYLOAD\'\n'
          '${jsonEncode(payload.toJson())}\n'
          'PAYLOAD\n'
          'mv "${completion.path}.tmp" "${completion.path}"\n'
          'sleep 30\n',
        );
        expect(
          (await Process.run('chmod', <String>[
            '700',
            executable.path,
          ])).exitCode,
          0,
        );
        final execution = runPreparedIntegrationExecutable(
          executable: executable,
          operatingSystem: Platform.isLinux ? 'linux' : 'macos',
          environment: const <String, String>{},
          completionFile: completion,
          expectedScenario: 'fixture',
          expectedRunId: 'fixture-run',
          expectedCaseIds: const <String>['CASE-001'],
          timeout: const Duration(seconds: 10),
        );
        if (failures == 0) {
          expect((await execution).terminatedAfterCompletion, isTrue);
        } else {
          await expectLater(
            execution,
            throwsA(
              isA<PreparedIntegrationProcessException>().having(
                (error) => error.message,
                'message',
                contains('1 failed Flutter tests'),
              ),
            ),
          );
        }
      },
      skip: !Platform.isLinux && !Platform.isMacOS,
    );
  }
}
