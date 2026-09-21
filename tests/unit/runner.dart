import 'dart:async';
import 'dart:io';

({List<String> targets, List<String> arguments}) unitTestSelection(
  List<String> args,
) {
  final arguments = [...args];
  final index = arguments.indexOf('--suite');
  if (index < 0) return (targets: ['tests/unit'], arguments: arguments);
  if (index + 1 >= arguments.length || arguments[index + 1] != 'acp') {
    throw ArgumentError('--suite only supports acp');
  }
  arguments.removeRange(index, index + 2);
  final targets =
      Directory('tests/unit')
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.uri.pathSegments.last.startsWith('acp_') &&
                f.path.endsWith('_test.dart'),
          )
          .map((f) => f.path)
          .toList()
        ..sort();
  if (targets.isEmpty) {
    throw StateError('No ACP unit tests found; run from the APP repository');
  }
  targets.addAll([
    'tests/unit/chat_composer_paste_test.dart',
    'tests/unit/chat_page_test.dart',
    'tests/unit/group_flow_test.dart',
    'tests/unit/agents/runtime_client_inspection_test.dart',
    'tests/unit/agents/acp_migration_test.dart',
    'tests/unit/agents/agent_control_service_test.dart',
    'tests/unit/agents/agents_provider_test.dart',
    'tests/unit/agents/agent_type_catalog_test.dart',
    'tests/unit/agents/agent_control_service_test.dart',
    'tests/unit/agents/agents_provider_test.dart',
    'tests/unit/agents/agents_page_layout_test.dart',
  ]);
  return (targets: targets, arguments: arguments);
}

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
Run all AWiki Me unit/widget/provider tests.

Usage:
  dart run tests/unit/runner.dart [--suite acp] [flutter test args...]

Examples:
  dart run tests/unit/runner.dart
  dart run tests/unit/runner.dart --name mention
  dart run tests/unit/runner.dart --suite acp

ACP tests use fake services and protocol snapshots; no Agent CLI, model key or backend is required.
''');
    return;
  }

  final selection = unitTestSelection(args);
  final result = await Process.start('flutter', <String>[
    'test',
    ...selection.targets,
    ...selection.arguments,
  ], mode: ProcessStartMode.inheritStdio);
  final exit = await result.exitCode;
  if (exit != 0) {
    exitCode = exit;
  }
}
