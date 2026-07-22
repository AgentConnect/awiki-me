import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const Map<String, int> _minimumNode24ActionMajors = <String, int>{
  'checkout': 5,
  'cache': 5,
  'upload-artifact': 6,
  'download-artifact': 7,
};

void main() {
  test('GitHub workflows use actions with native Node 24 runtimes', () {
    final workflowFiles = Directory('.github/workflows')
        .listSync()
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.yml') || file.path.endsWith('.yaml'),
        )
        .toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    expect(workflowFiles, isNotEmpty);

    final observedActions = <String>{};
    for (final workflowFile in workflowFiles) {
      final source = workflowFile.readAsStringSync();
      expect(
        source,
        isNot(contains('ACTIONS_ALLOW_USE_UNSECURE_NODE_VERSION')),
        reason: workflowFile.path,
      );
      _visitYaml(
        loadYaml(source),
        workflowPath: workflowFile.path,
        observedActions: observedActions,
      );
    }

    expect(
      observedActions,
      containsAll(<String>[
        'checkout',
        'upload-artifact',
        'download-artifact',
      ]),
    );
  });
}

void _visitYaml(
  Object? value, {
  required String workflowPath,
  required Set<String> observedActions,
}) {
  if (value is YamlMap) {
    for (final entry in value.entries) {
      if (entry.key.toString() == 'uses') {
        _verifyActionReference(
          entry.value.toString(),
          workflowPath: workflowPath,
          observedActions: observedActions,
        );
      }
      _visitYaml(
        entry.value,
        workflowPath: workflowPath,
        observedActions: observedActions,
      );
    }
    return;
  }
  if (value is YamlList) {
    for (final item in value) {
      _visitYaml(
        item,
        workflowPath: workflowPath,
        observedActions: observedActions,
      );
    }
  }
}

void _verifyActionReference(
  String reference, {
  required String workflowPath,
  required Set<String> observedActions,
}) {
  for (final entry in _minimumNode24ActionMajors.entries) {
    final prefix = 'actions/${entry.key}@';
    if (!reference.startsWith(prefix)) continue;

    observedActions.add(entry.key);
    final version = reference.substring(prefix.length);
    final match = RegExp(r'^v([0-9]+)(?:\.|$)').firstMatch(version);
    expect(match, isNotNull, reason: '$workflowPath: $reference');
    final major = int.parse(match!.group(1)!);
    expect(
      major,
      greaterThanOrEqualTo(entry.value),
      reason: '$workflowPath: $reference does not use a native Node 24 major',
    );
  }
}
