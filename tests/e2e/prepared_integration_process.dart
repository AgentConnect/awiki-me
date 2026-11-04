// [INPUT]: One prepared desktop integration executable plus runtime invocation identity.
// [OUTPUT]: Bounded execution that requires both a valid completion marker and Flutter's terminal result.
// [POS]: Execute-only lifecycle boundary; never builds artifacts or replaces case attestation.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'case_attestation.dart';
import 'runtime_control/invocation.dart';
import 'protected_files.dart';

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
    this.terminatedAfterCheckpoint = false,
  });

  final Duration elapsed;
  final int processExitCode;
  final bool terminatedAfterCompletion;
  final bool terminatedAfterCheckpoint;
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
  bool macosForeground = false,
  Future<Process> Function(int processId)? startForegroundKeeper,
  void Function(String line)? outputLine,
  E2eInvocation? expectedInterruption,
}) async {
  if (expectedInterruption != null) {
    if (operatingSystem != 'windows' ||
        expectedInterruption.interruption.isEmpty ||
        expectedInterruption.runId != expectedRunId ||
        expectedInterruption.scenario != expectedScenario ||
        !_sameStrings(expectedInterruption.caseIds, expectedCaseIds) ||
        E2eInvocation.load(environment)?.digest !=
            expectedInterruption.digest) {
      throw const PreparedIntegrationProcessException(
        'Expected interruption is not bound to this Windows invocation.',
      );
    }
    final checkpoint = File(
      '${environment[invocationPathEnvironment]}.checkpoint',
    );
    if (FileSystemEntity.typeSync(checkpoint.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const PreparedIntegrationProcessException(
        'Expected checkpoint already exists.',
      );
    }
  }
  if (!executable.existsSync()) {
    throw const PreparedIntegrationProcessException(
      'Prepared integration executable is missing.',
    );
  }
  if (!const <String>{'linux', 'macos', 'windows'}.contains(operatingSystem)) {
    throw const PreparedIntegrationProcessException(
      'Prepared integration execution requires Linux, macOS, or Windows.',
    );
  }
  if (macosForeground && operatingSystem != 'macos') {
    throw const PreparedIntegrationProcessException(
      'Foreground activation requires a macOS target.',
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
  Process? foregroundKeeper;
  final watch = Stopwatch()..start();
  final exitFuture = process.exitCode;
  try {
    outputLine?.call('macOS foreground activation: $macosForeground');
    if (macosForeground) {
      // This is a headed verification option, scoped to the child we own.
      // The runner owns activation so it cannot be stranded behind a pending
      // Flutter frame. It never changes application lifecycle facts in Dart.
      foregroundKeeper =
          await (startForegroundKeeper ?? _startMacosForegroundKeeper)(
            process.pid,
          );
      unawaited(foregroundKeeper.stdout.drain<void>());
      unawaited(foregroundKeeper.stderr.drain<void>());
    }
    while (watch.elapsed < timeout) {
      if (expectedInterruption != null) {
        final checkpoint = File(
          '${environment[invocationPathEnvironment]}.checkpoint',
        );
        if (checkpoint.existsSync()) {
          if (!isPrivateE2eFile(checkpoint) ||
              checkpoint.lengthSync() > 16384) {
            throw const PreparedIntegrationProcessException(
              'Checkpoint is not a bounded private file.',
            );
          }
          final event = jsonDecode(checkpoint.readAsStringSync());
          if (event is! Map ||
              event.length != 6 ||
              event['schemaVersion'] != 1 ||
              event['invocationId'] != expectedInterruption.invocationId ||
              event['planDigest'] != expectedInterruption.digest ||
              event['checkpoint'] != expectedInterruption.interruption ||
              event['pid'] != process.pid ||
              event['occurrence'] != 1 ||
              !await _processStillRunning(exitFuture) ||
              completionFile.existsSync()) {
            throw const PreparedIntegrationProcessException(
              'Checkpoint identity or lifecycle is invalid.',
            );
          }
          final killed = await Process.run('taskkill.exe', [
            '/PID',
            '${process.pid}',
            '/T',
            '/F',
          ]);
          if (killed.exitCode != 0) {
            throw const PreparedIntegrationProcessException(
              'Owned checkpoint process could not be terminated.',
            );
          }
          final code = await exitFuture.timeout(const Duration(seconds: 5));
          return PreparedIntegrationExecution(
            elapsed: watch.elapsed,
            processExitCode: code,
            terminatedAfterCompletion: false,
            terminatedAfterCheckpoint: true,
          );
        }
      }
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
    foregroundKeeper?.kill(ProcessSignal.sigterm);
    if (foregroundKeeper != null) {
      await foregroundKeeper.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          foregroundKeeper?.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
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

Future<Process> _startMacosForegroundKeeper(int processId) {
  return Process.start('/usr/bin/swift', <String>[
    '-e',
    'import AppKit; import Darwin; '
        'while kill($processId, 0) == 0 { '
        'if let app = NSRunningApplication(processIdentifier: $processId) { '
        '_ = app.unhide(); _ = app.activate(options: [.activateAllWindows]) }; '
        'Thread.sleep(forTimeInterval: 1) }',
  ], mode: ProcessStartMode.normal);
}

Future<int> _terminatePreparedIntegrationProcess(
  Process process, {
  required String operatingSystem,
  required Future<int> exitFuture,
}) async {
  if (!await _processStillRunning(exitFuture)) return exitFuture;
  if (operatingSystem == 'windows') {
    await Process.run('taskkill.exe', <String>[
      '/PID',
      '${process.pid}',
      '/T',
      '/F',
    ]);
    return exitFuture.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  }
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
