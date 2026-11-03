// Test-only subprocess ownership and one monotonic operation deadline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum CliProcessStage { stdinClose, exit, standardOutput, standardError }

/// Closed diagnostics only: never retain executable, arguments, or output.
class CliProcessTimeout extends TimeoutException {
  CliProcessTimeout({
    required Duration timeout,
    required this.stage,
    required this.elapsedMs,
    required this.exitDone,
    required this.stdoutDone,
    required this.stderrDone,
    this.stdoutHasData = false,
    this.stderrHasData = false,
    required this.cleanupFailed,
  }) : super('CLI operation deadline expired.', timeout);

  final CliProcessStage stage;
  final int elapsedMs;
  final bool exitDone;
  final bool stdoutDone;
  final bool stderrDone;
  final bool stdoutHasData;
  final bool stderrHasData;
  final bool cleanupFailed;
}

Duration remainingCliOperationBudget(Duration total, Duration elapsed) {
  if (total <= Duration.zero || elapsed.isNegative || elapsed >= total) {
    throw TimeoutException('The CLI operation budget has expired.', total);
  }
  return total - elapsed;
}

Future<ProcessResult> runBoundedCliProcess({
  required String executable,
  required List<String> arguments,
  required Map<String, String> environment,
  required Duration timeout,
  String? stdinText,
  Future<Process> Function()? processStarter,
}) async {
  final clock = Stopwatch()..start();
  remainingCliOperationBudget(timeout, clock.elapsed);
  final process = processStarter != null
      ? await processStarter()
      : await Process.start(
          executable,
          arguments,
          environment: environment,
          includeParentEnvironment: false,
          runInShell: false,
        );
  var exitDone = false;
  var stdoutDone = false;
  var stderrDone = false;
  var stdoutHasData = false;
  var stderrHasData = false;
  final exited = process.exitCode.whenComplete(() => exitDone = true);
  final out = process.stdout
      .transform(utf8.decoder)
      .map((text) {
        if (text.isNotEmpty) stdoutHasData = true;
        return text;
      })
      .join()
      .whenComplete(() => stdoutDone = true);
  final err = process.stderr
      .transform(utf8.decoder)
      .map((text) {
        if (text.isNotEmpty) stderrHasData = true;
        return text;
      })
      .join()
      .whenComplete(() => stderrDone = true);
  Duration remaining() => remainingCliOperationBudget(timeout, clock.elapsed);
  var stage = CliProcessStage.stdinClose;
  try {
    if (stdinText != null) process.stdin.write(stdinText);
    await process.stdin.close().timeout(remaining());
    stage = CliProcessStage.exit;
    final exitCode = await exited.timeout(remaining());
    stage = CliProcessStage.standardOutput;
    final output = await out.timeout(remaining());
    stage = CliProcessStage.standardError;
    final errors = await err.timeout(remaining());
    return ProcessResult(process.pid, exitCode, output, errors);
  } on Object catch (error, stack) {
    final atFailure = (
      exitDone: exitDone,
      stdoutDone: stdoutDone,
      stderrDone: stderrDone,
      stdoutHasData: stdoutHasData,
      stderrHasData: stderrHasData,
    );
    final elapsedMs = clock.elapsedMilliseconds;
    var cleanupFailed = false;
    // The cleanup bound is separate from permission to do more product work.
    try {
      process.kill();
      await exited.timeout(const Duration(seconds: 5));
      await Future.wait([out, err]).timeout(const Duration(seconds: 5));
    } on Object {
      cleanupFailed = true;
    }
    if (error is TimeoutException) {
      Error.throwWithStackTrace(
        CliProcessTimeout(
          timeout: error.duration ?? timeout,
          stage: stage,
          elapsedMs: elapsedMs,
          exitDone: atFailure.exitDone,
          stdoutDone: atFailure.stdoutDone,
          stderrDone: atFailure.stderrDone,
          stdoutHasData: atFailure.stdoutHasData,
          stderrHasData: atFailure.stderrHasData,
          cleanupFailed: cleanupFailed,
        ),
        stack,
      );
    }
    Error.throwWithStackTrace(error, stack);
  }
}
