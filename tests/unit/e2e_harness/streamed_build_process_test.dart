import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../tool/streamed_build_process.dart';

void main() {
  test('build output is durable and redacted before the process exits', () async {
    final root = await Directory.systemTemp.createTemp('build-stream-');
    addTearDown(() => root.delete(recursive: true));
    final log = File('${root.path}/build.jsonl');
    await log.writeAsString('retained-prior-diagnostic');
    var exited = false;
    final result = runStreamedBuildProcess(
      Platform.isWindows ? 'powershell.exe' : '/bin/sh',
      Platform.isWindows
          ? [
              '-NoProfile',
              '-Command',
              r'Write-Output "build-marker"; Write-Output $env:PRIVATE_TOKEN; Start-Sleep -Seconds 3',
            ]
          : ['-c', 'echo build-marker; echo "\$PRIVATE_TOKEN"; sleep 3'],
      workingDirectory: root.path,
      environment: {'PRIVATE_TOKEN': 'test-sensitive-token'},
      logFile: log,
    ).whenComplete(() => exited = true);
    final watch = Stopwatch()..start();
    while ((!log.existsSync() ||
            !log.readAsStringSync().contains('build-marker')) &&
        watch.elapsed < const Duration(seconds: 15)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(log.readAsStringSync(), contains('build-marker'));
    expect(exited, isFalse);
    expect((await result).exitCode, 0);
    expect(log.readAsStringSync(), isNot(contains('test-sensitive-token')));
    expect(log.readAsStringSync(), contains('<redacted>'));
    final previous = root
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.previous'))
        .toList();
    expect(previous, hasLength(1));
    expect(previous.single.readAsStringSync(), 'retained-prior-diagnostic');
  });
  test('a stalled build is bounded and retains failure diagnostics', () async {
    final root = await Directory.systemTemp.createTemp('build-timeout-');
    addTearDown(() => root.delete(recursive: true));
    final log = File('${root.path}/build.jsonl');
    await expectLater(
      runStreamedBuildProcess(
        Platform.isWindows ? 'powershell.exe' : '/bin/sh',
        Platform.isWindows
            ? ['-NoProfile', '-Command', 'Start-Sleep -Seconds 30']
            : ['-c', 'sleep 30'],
        workingDirectory: root.path,
        environment: {},
        logFile: log,
        timeout: const Duration(milliseconds: 250),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(log.readAsStringSync(), contains('build_failed'));
  });
}
