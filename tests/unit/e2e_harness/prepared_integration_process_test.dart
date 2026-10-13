import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/case_attestation.dart';
import '../../e2e/prepared_integration_process.dart';

void main() {
  for (final failures in <int>[0, 1]) {
    for (final foreground in [false, true]) {
      test(
        'prepared completion failures=$failures foreground=$foreground cleans up',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'awiki_completion_',
          );
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
            'echo "00:00 +0${failures == 0 ? '' : ' -1'}: ${failures == 0 ? 'All tests passed!' : 'Some tests failed.'}"\n'
            'exec sleep 30\n',
          );
          expect(
            (await Process.run('chmod', <String>[
              '700',
              executable.path,
            ])).exitCode,
            0,
          );
          final keeper = _FakeForegroundKeeper();
          var keeperStarts = 0;
          final execution = runPreparedIntegrationExecutable(
            executable: executable,
            // A shell fixture has no window. Exercise the macOS control boundary
            // on either host without launching AppKit or a real App.
            operatingSystem: 'macos',
            environment: const {'AWIKI_E2E_MACOS_FOREGROUND': '1'},
            macosForeground: foreground,
            startForegroundKeeper: (pid) async {
              expect(pid, greaterThan(0));
              keeperStarts += 1;
              return keeper;
            },
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
          expect(keeperStarts, foreground ? 1 : 0);
          expect(
            keeper.signals,
            foreground ? [ProcessSignal.sigterm] : isEmpty,
          );
        },
        skip: !Platform.isLinux && !Platform.isMacOS,
      );
    }
  }

  test('Linux foreground request fails before starting a process', () async {
    await expectLater(
      runPreparedIntegrationExecutable(
        executable: File(Platform.resolvedExecutable),
        operatingSystem: 'linux',
        environment: {},
        completionFile: File('/unused-completion'),
        expectedScenario: 'fixture',
        expectedRunId: 'fixture-run',
        expectedCaseIds: [],
        timeout: const Duration(seconds: 1),
        macosForeground: true,
      ),
      throwsA(
        isA<PreparedIntegrationProcessException>().having(
          (error) => error.message,
          'message',
          contains('requires a macOS target'),
        ),
      ),
    );
  });

  test(
    'Flutter teardown failure overrides a zero completion failure count',
    () async {
      final root = await Directory.systemTemp.createTemp('awiki_completion_');
      addTearDown(() => root.delete(recursive: true));
      final completion = File('${root.path}/completion.json');
      final executable = File('${root.path}/prepared.sh');
      const payload = E2eInvocationCompletion(
        scenario: 'fixture',
        runId: 'fixture-run',
        expectedCaseIds: <String>['CASE-001'],
        finishedAt: '2026-09-06T00:00:00Z',
        failedTestCount: 0,
      );
      await executable.writeAsString(
        '#!/bin/sh\n'
        'cat > "${completion.path}.tmp" <<\'PAYLOAD\'\n'
        '${jsonEncode(payload.toJson())}\n'
        'PAYLOAD\n'
        'mv "${completion.path}.tmp" "${completion.path}"\n'
        'sleep 0.1\n'
        'echo "flutter: 00:01 +0 -1: Some tests failed."\n'
        'sleep 30\n',
      );
      expect(
        (await Process.run('chmod', <String>['700', executable.path])).exitCode,
        0,
      );
      await expectLater(
        runPreparedIntegrationExecutable(
          executable: executable,
          operatingSystem: Platform.isLinux ? 'linux' : 'macos',
          environment: const <String, String>{},
          completionFile: completion,
          expectedScenario: 'fixture',
          expectedRunId: 'fixture-run',
          expectedCaseIds: const <String>['CASE-001'],
          timeout: const Duration(seconds: 10),
        ),
        throwsA(
          isA<PreparedIntegrationProcessException>().having(
            (error) => error.message,
            'message',
            contains('Flutter tests failed'),
          ),
        ),
      );
    },
    skip: !Platform.isLinux && !Platform.isMacOS,
  );
}

final class _FakeForegroundKeeper implements Process {
  final signals = <ProcessSignal>[];
  final _exit = Completer<int>();

  @override
  Future<int> get exitCode => _exit.future;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
