import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../e2e/bounded_cli_process.dart';

String dartExecutable() {
  final configured = Platform.environment['AWIKI_E2E_DART_BIN'];
  if (configured != null && File(configured).existsSync()) return configured;
  final flutter = Platform.environment['FLUTTER_ROOT'];
  final path =
      '$flutter/bin/cache/dart-sdk/bin/dart${Platform.isWindows ? '.exe' : ''}';
  if (!File(path).existsSync()) {
    throw StateError('A real Dart SDK executable is required.');
  }
  return path;
}

void main() {
  test(
    'timeout keeps the original stage when owned cleanup also fails',
    () async {
      final process = _CleanupFailureProcess();
      await expectLater(
        runBoundedCliProcess(
          executable: 'sensitive-executable-must-not-be-recorded',
          arguments: ['sensitive-argument-must-not-be-recorded'],
          environment: const {},
          timeout: const Duration(milliseconds: 30),
          processStarter: () async => process,
        ),
        throwsA(
          isA<CliProcessTimeout>()
              .having(
                (error) => error.stage,
                'original stage',
                CliProcessStage.exit,
              )
              .having((error) => error.exitDone, 'exit before cleanup', false)
              .having(
                (error) => error.cleanupFailed,
                'secondary cleanup failure',
                true,
              )
              .having(
                (error) => error.toString(),
                'private command metadata',
                isNot(contains('sensitive-')),
              ),
        ),
      );
      expect(process.killCalled, isTrue);
    },
  );
  test('group readiness keeps one 45-second budget across commands', () {
    const total = Duration(seconds: 45);
    expect(remainingCliOperationBudget(total, Duration.zero), total);
    expect(
      remainingCliOperationBudget(total, const Duration(seconds: 31)),
      const Duration(seconds: 14),
    );
    expect(
      () => remainingCliOperationBudget(total, total),
      throwsA(isA<TimeoutException>()),
    );
    expect(
      () => remainingCliOperationBudget(total, const Duration(seconds: 46)),
      throwsA(isA<TimeoutException>()),
    );
  });
  test('bounded process returns the actual child exit and output', () async {
    final result = await runBoundedCliProcess(
      executable: dartExecutable(),
      arguments: ['--version'],
      environment: Platform.environment,
      timeout: const Duration(seconds: 5),
    );
    expect(result.exitCode, 0);
    expect('${result.stdout}${result.stderr}', contains('Dart SDK version'));
  });
  test('timeout waits for an owned child to release its lock', () async {
    final root = await Directory.systemTemp.createTemp('awiki-cli-budget-');
    final lock = File('${root.path}/lock');
    final ready = File('${root.path}/ready');
    final script = File('${root.path}/child.dart');
    await script.writeAsString(
      "import 'dart:io'; import 'dart:async'; Future<void> main(List<String> a)async{final f=File(a[0]).openSync(mode:FileMode.write);f.lockSync(FileLock.exclusive);File(a[1]).writeAsStringSync('ready');await Future<void>.delayed(const Duration(seconds:30));f.closeSync();}",
    );
    try {
      final future = runBoundedCliProcess(
        executable: dartExecutable(),
        arguments: [script.path, lock.path, ready.path],
        environment: Platform.environment,
        timeout: const Duration(seconds: 2),
      );
      final expectation = expectLater(
        future,
        throwsA(
          isA<CliProcessTimeout>()
              .having(
                (error) => error.stage,
                'waiting stage',
                CliProcessStage.exit,
              )
              .having(
                (error) => error.exitDone,
                'exit observed before cleanup',
                false,
              )
              .having((error) => error.cleanupFailed, 'owned cleanup', false),
        ),
      );
      final clock = Stopwatch()..start();
      while (!await ready.exists() &&
          clock.elapsed < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(await ready.exists(), isTrue);
      await expectation;
      final handle = await lock.open(mode: FileMode.append);
      try {
        await handle
            .lock(FileLock.exclusive)
            .timeout(const Duration(milliseconds: 500));
        await handle.unlock();
      } finally {
        await handle.close();
      }
    } finally {
      if (!root.absolute.path.startsWith(Directory.systemTemp.absolute.path) ||
          !root.path.contains('awiki-cli-budget-')) {
        throw StateError('Unexpected test root');
      }
      await root.delete(recursive: true);
    }
  });
}

class _CleanupFailureProcess implements Process {
  final _exit = Completer<int>();
  bool killCalled = false;
  @override
  final IOSink stdin = IOSink(_DiscardInput());
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode => _exit.future;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCalled = true;
    if (!_exit.isCompleted) {
      _exit.completeError(StateError('synthetic cleanup failure'));
    }
    return false;
  }
}

class _DiscardInput implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<void> close() async {}
}
