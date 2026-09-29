import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../runner.dart';

void main() {
  test('default selection preserves full unit scope and Flutter arguments', () {
    final selected = unitTestSelection(['--name', 'conversation']);
    expect(selected.targets, ['tests/unit']);
    expect(selected.arguments, ['--name', 'conversation']);
  });
  test(
    'ACP selection includes protocol UI and adjacent regressions without E2E',
    () {
      final arguments = ['--suite', 'acp', '--no-pub'];
      final selected = unitTestSelection(arguments);
      expect(arguments, ['--suite', 'acp', '--no-pub']);
      expect(selected.arguments, ['--no-pub']);
      expect(
        selected.targets,
        contains('tests/unit/acp_model_refresh_test.dart'),
      );
      expect(
        selected.targets,
        contains('tests/unit/acp_task_projection_test.dart'),
      );
      expect(
        selected.targets,
        contains('tests/unit/chat_composer_paste_test.dart'),
      );
      expect(selected.targets.toSet().length, selected.targets.length);
      expect(
        selected.targets.every(
          (path) => path.startsWith('tests/unit/') && File(path).existsSync(),
        ),
        isTrue,
      );
    },
  );
  test('unknown or missing suite cannot silently run a different scope', () {
    expect(() => unitTestSelection(['--suite']), throwsArgumentError);
    expect(() => unitTestSelection(['--suite', 'live']), throwsArgumentError);
  });
}
