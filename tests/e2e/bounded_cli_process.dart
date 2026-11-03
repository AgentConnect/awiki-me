// Test-only subprocess ownership and one monotonic operation deadline.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
}) async {
  final clock = Stopwatch()..start();
  remainingCliOperationBudget(timeout, clock.elapsed);
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  Duration remaining() => remainingCliOperationBudget(timeout, clock.elapsed);
  try {
    if (stdinText != null) process.stdin.write(stdinText);
    await process.stdin.close().timeout(remaining());
    final exitCode = await process.exitCode.timeout(remaining());
    return ProcessResult(
      process.pid,
      exitCode,
      await out.timeout(remaining()),
      await err.timeout(remaining()),
    );
  } on Object {
    // The cleanup bound is separate from permission to do more product work.
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
    await Future.wait([out, err]).timeout(const Duration(seconds: 5));
    rethrow;
  }
}
