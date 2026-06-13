import '../tests/e2e_test/harness/desktop_e2e_runner.dart' as runner;

Future<void> main(List<String> args) {
  final hasPlatform = args.any(
    (arg) => arg == '--platform' || arg.startsWith('--platform='),
  );
  return runner.main(
    hasPlatform ? args : <String>['--platform=macos', ...args],
  );
}
