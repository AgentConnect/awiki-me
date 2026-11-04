import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../tests/e2e/runner/redaction.dart';
import '../tests/e2e/runner/process_runner.dart';

/// Writes redacted output while the child is alive. stdout remains JSON-only
/// at the builder entrypoint, including when its parent terminates this tree.
Future<ProcessResult> runStreamedBuildProcess(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required Map<String, String> environment,
  required File logFile,
  Duration timeout = const Duration(minutes: 12),
}) async {
  final redactor = DesktopSecretRedactor([
    workingDirectory,
    for (final entry in environment.entries)
      if (RegExp(
        r'TOKEN|PASSWORD|SECRET|OTP|PHONE|PIN|API_KEY',
        caseSensitive: false,
      ).hasMatch(entry.key))
        entry.value,
  ]);
  logFile.parent.createSync(recursive: true);
  if (FileSystemEntity.typeSync(logFile.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw StateError('Build log cannot be a link.');
  }
  if (logFile.existsSync() && logFile.lengthSync() > 0) {
    final stem =
        '${logFile.path}.${DateTime.now().toUtc().microsecondsSinceEpoch}.$pid';
    var archive = '$stem.previous';
    var collision = 0;
    while (FileSystemEntity.typeSync(archive, followLinks: false) !=
        FileSystemEntityType.notFound) {
      archive = '$stem.${++collision}.previous';
    }
    logFile.renameSync(archive);
  }
  logFile.writeAsStringSync('');
  final watch = Stopwatch()..start();
  var bytes = 0;
  void record(String stream, String raw) {
    var line = redactor.redact(raw);
    if (line.length > 8192) line = '${line.substring(0, 8192)}<truncated>';
    final value =
        '${jsonEncode({'stream': stream, 'elapsedMs': watch.elapsedMilliseconds, 'line': line})}\n';
    final size = utf8.encode(value).length;
    if (bytes + size > 8 * 1024 * 1024) return;
    bytes += size;
    logFile.writeAsStringSync(value, mode: FileMode.append, flush: true);
  }

  final child = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: false,
  );
  var childExited = false;
  final exitFuture = child.exitCode.then((code) {
    childExited = true;
    return code;
  });
  record('stage', 'started pid=${child.pid}');
  final runner = DesktopCommandRunner(
    root: Directory(workingDirectory),
    dryRun: false,
    redactor: redactor,
    logLine: (_) {},
  );
  final tails = <String, List<String>>{'stdout': [], 'stderr': []};
  Future<void> capture(Stream<List<int>> stream, String name) async {
    await for (final line
        in stream.transform(utf8.decoder).transform(const LineSplitter())) {
      record(name, line);
      final tail = tails[name]!;
      final safe = redactor.redact(line);
      tail.add(
        safe.length > 8192 ? '${safe.substring(0, 8192)}<truncated>' : safe,
      );
      if (tail.length > 12) tail.removeAt(0);
    }
  }

  Object? captureFailure;
  final captures =
      Future.wait([
        capture(child.stdout, 'stdout'),
        capture(child.stderr, 'stderr'),
      ]).catchError((Object error) {
        captureFailure = error;
        return <void>[];
      });
  try {
    final code = await Future.any<int>([
      exitFuture,
      captures.then((_) {
        if (captureFailure != null) {
          throw StateError('Build output capture failed.');
        }
        return exitFuture;
      }),
    ]).timeout(timeout);
    await captures.timeout(const Duration(seconds: 5));
    if (captureFailure != null) {
      throw StateError('Build output capture failed.');
    }
    record('stage', 'exited code=$code');
    return ProcessResult(
      child.pid,
      code,
      tails['stdout']!.join('\n'),
      tails['stderr']!.join('\n'),
    );
  } catch (error, stack) {
    try {
      record('stage', 'build_failed');
    } catch (_) {
      /* Preserve the owning failure even if its log is unavailable. */
    }
    try {
      if (!childExited) await runner.terminateProcessTree(child);
      await exitFuture.timeout(const Duration(seconds: 5), onTimeout: () => -1);
      if (!childExited) record('stage', 'cleanup_failed');
    } catch (_) {
      try {
        record('stage', 'cleanup_failed');
      } catch (_) {
        /* Primary error wins. */
      }
    }
    Error.throwWithStackTrace(error, stack);
  } finally {
    watch.stop();
  }
}
