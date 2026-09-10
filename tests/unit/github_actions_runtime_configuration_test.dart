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
  test('E2E report uploads include hidden reports without runtime secrets', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    for (final name in <String>['validate', 'remote-product']) {
      final uploads = ((jobs[name] as YamlMap)['steps'] as YamlList)
          .cast<YamlMap>()
          .where((step) => step['uses'] == 'actions/upload-artifact@v7');
      final reports = uploads
          .map((step) => step['with'] as YamlMap)
          .singleWhere(
            (options) => options['name'].toString().startsWith('awiki-me-'),
          );
      expect(reports['include-hidden-files'], isTrue);
      expect(reports['if-no-files-found'], 'error');
      expect(reports['path'].toString().trim().split('\n'), <String>[
        'test-awiki-me/.e2e/*/*/reports/**',
        'test-awiki-me/.e2e/native-core/*-provenance.json',
      ]);
    }
  });

  test('Linux CI prepares native provenance before desktop E2E', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    for (final name in <String>['validate', 'remote-product']) {
      final steps = ((jobs[name] as YamlMap)['steps'] as YamlList)
          .cast<YamlMap>()
          .toList();
      final dependencies = steps.indexWhere(
        (step) => step['name'] == 'Install Flutter dependencies',
      );
      final nativeGuard = steps.indexWhere(
        (step) => step['name'] == 'Verify Linux native Core provenance',
      );
      final desktop = steps.indexWhere(
        (step) => (step['run']?.toString() ?? '').contains(
          'dart run tests/e2e/runner.dart',
        ),
      );
      expect(nativeGuard, greaterThan(dependencies), reason: name);
      expect(nativeGuard, lessThan(desktop), reason: name);
      expect(steps[nativeGuard]['working-directory'], 'test-awiki-me');
      expect(
        steps[nativeGuard]['run'],
        'dart run tool/ensure_linux_im_core.dart --debug',
      );
    }
  });

  test('PR checkout credentials are scoped to private contract sources', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    final validateSteps = (jobs['validate'] as YamlMap)['steps'] as YamlList;
    final coordinator =
        validateSteps.cast<YamlMap>().singleWhere(
              (step) =>
                  step['name'] == 'Checkout unified System Test coordinator',
            )['with']
            as YamlMap;
    expect(coordinator['ref'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(coordinator['token'], r'${{ secrets.AWIKI_CI_READ_TOKEN }}');
    expect(coordinator['persist-credentials'], isFalse);
    expect(coordinator.containsKey('ssh-key'), isFalse);
    final dsh =
        validateSteps.cast<YamlMap>().singleWhere(
              (step) => step['name'] == 'Checkout pinned DSH contract source',
            )['with']
            as YamlMap;
    expect(dsh['path'], 'dsh-awiki');
    expect(dsh['ref'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(dsh['persist-credentials'], isFalse);
    final userService =
        validateSteps.cast<YamlMap>().singleWhere(
              (step) =>
                  step['name'] ==
                  'Checkout pinned User Service contract source',
            )['with']
            as YamlMap;
    expect(userService['path'], 'user-service');
    expect(userService['ref'], matches(RegExp(r'^[0-9a-f]{40}$')));
    expect(userService['token'], r'${{ secrets.AWIKI_CI_READ_TOKEN }}');
    expect(userService['persist-credentials'], isFalse);
    final canonicalApp = validateSteps.cast<YamlMap>().singleWhere(
      (step) =>
          step['name'] == 'Prepare canonical App source path for contracts',
    );
    expect(canonicalApp['run'], 'ln -s test-awiki-me awiki-me');

    for (final job in jobs.values.cast<YamlMap>()) {
      expect(job.containsKey('environment'), isFalse);
      for (final step in (job['steps'] as YamlList).cast<YamlMap>()) {
        final options = step['with'];
        if (options is! YamlMap || options['path'] != 'awiki-cli-rs2') {
          continue;
        }
        expect(options['token'], r'${{ github.token }}');
        expect(options['persist-credentials'], isFalse);
      }
    }
  });

  test(
    'CI native consumers use the published registry SDK build entrypoint',
    () {
      final workflow =
          loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
              as YamlMap;
      expect((workflow['env'] as YamlMap)['AWIKI_RELEASE_REGISTRY'], '1');
      final jobs = workflow['jobs'] as YamlMap;
      var cargoCommands = 0;
      for (final job in jobs.values.cast<YamlMap>()) {
        for (final step in (job['steps'] as YamlList).cast<YamlMap>()) {
          final script = step['run'];
          if (script is! String) continue;
          for (final line in script.split('\n')) {
            if (!RegExp(
              r'\bcargo (?:\+\S+ )?(?:build|test)\b',
            ).hasMatch(line)) {
              continue;
            }
            cargoCommands++;
            expect(
              line,
              contains('python3 scripts/release/registry-build.py -- cargo'),
            );
          }
        }
      }
      expect(cargoCommands, 3);
    },
  );

  test('GitHub workflows use actions with native Node 24 runtimes', () {
    final workflowFiles =
        Directory('.github/workflows')
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
      containsAll(<String>['checkout', 'upload-artifact', 'download-artifact']),
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
