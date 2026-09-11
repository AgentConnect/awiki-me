// [INPUT]: Redacted executable invocation, bounded environment, stdin, and timeout.
// [OUTPUT]: Captured process result or durable redacted failure diagnostics.
// [POS]: Process lifecycle boundary shared by E2E scenarios; owns no business oracle.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'failure.dart';
import 'redaction.dart';

class DesktopCommandRunner {
  DesktopCommandRunner({
    required this.root,
    required this.dryRun,
    required this.redactor,
    void Function(String line)? logLine,
  }) : logLine = logLine ?? _defaultLogLine;

  final Directory root;
  final bool dryRun;
  final DesktopSecretRedactor redactor;
  final void Function(String line) logLine;
  Directory? diagnosticDirectory;
  int _diagnosticSequence = 0;

  Future<void> requireExecutable(String executable) async {
    final command = Platform.isWindows ? 'where' : 'which';
    final result = await captureResult(command, <String>[
      executable,
    ], allowFailure: true);
    if (result.output.trim().isEmpty && !dryRun) {
      throw E2eFailure('Required executable was not found: $executable');
    }
    logLine(
      '$executable: ${result.output.trim().isEmpty ? 'dry-run' : 'found'}',
    );
  }

  Future<void> requireFile(String path) async {
    logLine('check file: ${redactor.redact(path)}');
    if (!dryRun && !File(path).existsSync()) {
      throw E2eFailure('Required file was not found: $path');
    }
  }

  Future<void> run(
    String executable,
    List<String> args, {
    Directory? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool allowFailure = false,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final result = await captureResult(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      allowFailure: allowFailure,
      timeout: timeout,
    );
    if (result.exitCode != 0 && !allowFailure) {
      throw E2eFailure('$executable exited with code ${result.exitCode}.');
    }
  }

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
    _command(executable, args);
    if (dryRun) {
      return const DesktopCommandResult(exitCode: 0, output: '');
    }
    final process = await Process.start(
      executable,
      args,
      workingDirectory: (workingDirectory ?? root).path,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    if (stdinText != null) {
      process.stdin.write(stdinText);
      await process.stdin.close();
    }
    final exitFuture = process.exitCode;
    final startedAt = DateTime.now().toUtc();
    int processExitCode;
    try {
      processExitCode = await exitFuture.timeout(timeout);
    } on TimeoutException {
      final terminated = await terminateProcessTree(process);
      try {
        await exitFuture.timeout(const Duration(seconds: 2));
      } on Object {
        // The tree has already received a hard-kill fallback below.
      }
      final out = await stdoutFuture;
      final err = await stderrFuture;
      await _writeFailureDiagnostics(
        executable: executable,
        args: args,
        exitCode: null,
        timedOut: true,
        startedAt: startedAt,
        stdoutText: out,
        stderrText: err,
      );
      throw DesktopCommandTimeout(
        executable: executable,
        timeout: timeout,
        terminated: terminated,
      );
    }
    final out = await stdoutFuture;
    final err = await stderrFuture;
    final output = out.isNotEmpty ? out : err;
    if (processExitCode != 0 && !allowFailure) {
      await _writeFailureDiagnostics(
        executable: executable,
        args: args,
        exitCode: processExitCode,
        timedOut: false,
        startedAt: startedAt,
        stdoutText: out,
        stderrText: err,
      );
      throw E2eFailure(
        redactor.redact(
          '$executable ${args.join(' ')} failed with code $processExitCode.\n'
          'stdout:\n$out\n'
          'stderr:\n$err',
        ),
      );
    }
    return DesktopCommandResult(exitCode: processExitCode, output: output);
  }

  Future<void> _writeFailureDiagnostics({
    required String executable,
    required List<String> args,
    required int? exitCode,
    required bool timedOut,
    required DateTime startedAt,
    required String stdoutText,
    required String stderrText,
  }) async {
    final directory = diagnosticDirectory;
    if (directory == null) {
      return;
    }
    await directory.create(recursive: true);
    _diagnosticSequence += 1;
    final stem =
        'command-failure-${_diagnosticSequence.toString().padLeft(3, '0')}';
    final stdoutFile = File('${directory.path}/$stem.stdout.log');
    final stderrFile = File('${directory.path}/$stem.stderr.log');
    final metadataFile = File('${directory.path}/$stem.json');
    await stdoutFile.writeAsString(redactor.redact(stdoutText), flush: true);
    await stderrFile.writeAsString(redactor.redact(stderrText), flush: true);
    await metadataFile.writeAsString(
      const JsonEncoder.withIndent(' ').convert(<String, Object?>{
        'schemaVersion': 1,
        'executable': _basename(executable),
        'arguments': args.map(redactor.redact).toList(growable: false),
        'exitCode': exitCode,
        'timedOut': timedOut,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': DateTime.now().toUtc().toIso8601String(),
        'stdoutFile': stdoutFile.uri.pathSegments.last,
        'stderrFile': stderrFile.uri.pathSegments.last,
      }),
      flush: true,
    );
  }

  Future<bool> terminateProcessTree(Process process) async {
    if (Platform.isWindows) {
      final result = await Process.run('taskkill', <String>[
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ]);
      return result.exitCode == 0;
    }
    final descendants = await _descendantPids(process.pid);
    var signalled = false;
    for (final pid in descendants.reversed) {
      signalled = Process.killPid(pid, ProcessSignal.sigterm) || signalled;
    }
    signalled = process.kill(ProcessSignal.sigterm) || signalled;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (final pid in descendants.reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    process.kill(ProcessSignal.sigkill);
    return signalled;
  }

  Future<List<int>> _descendantPids(int parentPid) async {
    final descendants = <int>[];
    final queue = <int>[parentPid];
    while (queue.isNotEmpty) {
      final parent = queue.removeLast();
      ProcessResult result;
      try {
        result = await Process.run('pgrep', <String>[
          '-P',
          '$parent',
        ]).timeout(const Duration(seconds: 1));
      } on Object {
        continue;
      }
      if (result.exitCode != 0) {
        continue;
      }
      final children = (result.stdout as String)
          .split(RegExp(r'\s+'))
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      descendants.addAll(children);
      queue.addAll(children);
    }
    return descendants;
  }

  void _command(String executable, List<String> args) {
    final rendered = <String>[
      executable,
      ...args,
    ].map(_quoteIfNeeded).join(' ');
    logLine(r'$ ' + redactor.redact(rendered));
  }
}

class DesktopCommandResult {
  const DesktopCommandResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

class DesktopCommandTimeout extends E2eFailure {
  DesktopCommandTimeout({
    required this.executable,
    required this.timeout,
    required this.terminated,
  }) : super(
         '$executable timed out after ${timeout.inMilliseconds}ms; '
         'child process tree termination ${terminated ? 'was requested' : 'could not be confirmed'}.',
       );

  final String executable;
  final Duration timeout;
  final bool terminated;

  String get safeSummary =>
      'Command ${_basename(executable)} timed out after '
      '${timeout.inMilliseconds}ms; child process tree terminated=$terminated.';
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

String _quoteIfNeeded(String value) {
  if (value.isEmpty) {
    return "''";
  }
  if (!RegExp(r'''[\s'"$]''').hasMatch(value)) {
    return value;
  }
  return "'${value.replaceAll("'", "'\\''")}'";
}

void _defaultLogLine(String line) {
  stdout.writeln(line);
}
