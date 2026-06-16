import 'dart:async';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
Run all AWiki Me unit/widget/provider tests.

Usage:
  dart run tests/unit/runner.dart [flutter test args...]

Examples:
  dart run tests/unit/runner.dart
  dart run tests/unit/runner.dart --name mention
''');
    return;
  }

  final result = await Process.start('flutter', <String>[
    'test',
    'tests/unit',
    ...args,
  ], mode: ProcessStartMode.inheritStdio);
  final exit = await result.exitCode;
  if (exit != 0) {
    exitCode = exit;
  }
}
