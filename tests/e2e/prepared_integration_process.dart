// [INPUT]: One prepared desktop integration executable plus runtime invocation identity.
// [OUTPUT]: Bounded execution that requires both a valid completion marker and Flutter's terminal result.
// [POS]: Execute-only lifecycle boundary; never builds artifacts or replaces case attestation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'case_attestation.dart';

final class PreparedIntegrationProcessException implements Exception {
  const PreparedIntegrationProcessException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class PreparedIntegrationExecution {
  const PreparedIntegrationExecution({
    required this.elapsed,
    required this.processExitCode,
    required this.terminatedAfterCompletion,
  });

  final Duration elapsed;
  final int processExitCode;
  final bool terminatedAfterCompletion;
}

Future<PreparedIntegrationExecution> runPreparedIntegrationExecutable({
  required File executable,
  required String operatingSystem,
  required Map<String, String> environment,
  required File completionFile,
  required String expectedScenario,
  required String expectedRunId,
  required List<String> expectedCaseIds,
  required Duration timeout,
  void Function(String line)? outputLine,
}) async {
  if (!executable.existsSync()) {
    throw const PreparedIntegrationProcessException(
      'Prepared integration executable is missing.',
    );
  }
  if (!const <String>{'linux', 'macos'}.contains(operatingSystem)) {
    throw const PreparedIntegrationProcessException(
      'Prepared integration execution requires Linux or macOS.',
    );
  }
  if (completionFile.existsSync()) completionFile.deleteSync();
  final completionTemporary = File('${completionFile.path}.tmp');
  if (completionTemporary.existsSync()) completionTemporary.deleteSync();

  final command = operatingSystem == 'linux' ? 'setsid' : executable.path;
  final arguments = operatingSystem == 'linux'
      ? <String>[
          'xvfb-run',
          '-a',
          '--server-args=-screen 0 1280x720x24 -nolisten tcp',
          executable.path,
          '--enable-vm-service=0',
        ]
      : const <String>['--enable-vm-service=0'];
  final process = await Process.start(
    command,
    arguments,
    environment: <String, String>{...Platform.environment, ...environment},
    runInShell: false,
  );
  final terminalResult = Completer<bool>();
  void recordOutput(String line) {
    final result = _flutterTerminalResult(line);
    if (result != null && !terminalResult.isCompleted) {
      terminalResult.complete(result);
    }
    outputLine?.call(line);
  }

  final outputSubscriptions = <StreamSubscription<String>>[
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(recordOutput),
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(recordOutput),
  ];
  final watch = Stopwatch()..start();
  final exitFuture = process.exitCode;
  try {
    while (watch.elapsed < timeout) {
      if (completionFile.existsSync()) {
        final completion = E2eInvocationCompletion.read(completionFile);
        if (completion.scenario != expectedScenario ||
            completion.runId != expectedRunId ||
            !_sameStrings(completion.expectedCaseIds, expectedCaseIds)) {
          throw const PreparedIntegrationProcessException(
            'Prepared integration completion identity is invalid.',
          );
        }
        if (completion.failedTestCount > 0) {
          await _terminatePreparedIntegrationProcess(
            process,
            operatingSystem: operatingSystem,
            exitFuture: exitFuture,
          );
          throw PreparedIntegrationProcessException(
            'Prepared integration reported ${completion.failedTestCount} failed Flutter tests; inspect the captured Flutter log.',
          );
        }
        // tearDownAll can write the marker before Flutter reports a failure in
        // a per-test addTearDown. Wait for the terminal test result before
        // accepting a zero failure count or stopping the desktop process.
        final passed = await terminalResult.future.timeout(
          timeout - watch.elapsed,
          onTimeout: () => throw const PreparedIntegrationProcessException(
            'Prepared integration did not report a terminal Flutter test result.',
          ),
        );
        final exitCode = await _terminatePreparedIntegrationProcess(
          process,
          operatingSystem: operatingSystem,
          exitFuture: exitFuture,
        );
        if (!passed) {
          throw const PreparedIntegrationProcessException(
            'Prepared integration Flutter tests failed; inspect the captured Flutter log.',
          );
        }
        return PreparedIntegrationExecution(
          elapsed: watch.elapsed,
          processExitCode: exitCode,
          terminatedAfterCompletion: true,
        );
      }
      final exited = await Future.any<bool>(<Future<bool>>[
        exitFuture.then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 100), () => false),
      ]);
      if (exited) {
        if (completionFile.existsSync()) continue;
        throw PreparedIntegrationProcessException(
          'Prepared integration process exited before completion '
          '(code=${await exitFuture}).',
        );
      }
    }
    throw const PreparedIntegrationProcessException(
      'Prepared integration process timed out before completion.',
    );
  } finally {
    watch.stop();
    if (await _processStillRunning(exitFuture)) {
      await _terminatePreparedIntegrationProcess(
        process,
        operatingSystem: operatingSystem,
        exitFuture: exitFuture,
      );
    }
    for (final subscription in outputSubscriptions) {
      await subscription.cancel();
    }
  }
}

Future<int> _terminatePreparedIntegrationProcess(
  Process process, {
  required String operatingSystem,
  required Future<int> exitFuture,
}) async {
  if (operatingSystem == 'linux') {
    await Process.run('/bin/kill', <String>['-TERM', '--', '-${process.pid}']);
  } else {
    process.kill(ProcessSignal.sigterm);
  }
  try {
    return await exitFuture.timeout(const Duration(seconds: 5));
  } on TimeoutException {
    if (operatingSystem == 'linux') {
      await Process.run('/bin/kill', <String>[
        '-KILL',
        '--',
        '-${process.pid}',
      ]);
    } else {
      process.kill(ProcessSignal.sigkill);
    }
    return exitFuture.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
}

Future<bool> _processStillRunning(Future<int> exitFuture) {
  return Future.any<bool>(<Future<bool>>[
    exitFuture.then((_) => false),
    Future<bool>.delayed(const Duration(milliseconds: 1), () => true),
  ]);
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool? _flutterTerminalResult(String line) {
  final match = RegExp(
    r'^(?:flutter: )?\d{2}:\d{2}(?::\d{2})? [0-9+~ -]+: (All tests passed!|Some tests failed\.)$',
  ).firstMatch(line.trim());
  if (match == null) return null;
  return match.group(1) == 'All tests passed!';
}
