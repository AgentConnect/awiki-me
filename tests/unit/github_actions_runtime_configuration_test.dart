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
  test('development CI explicitly selects locked source integration', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final inputs = workflow['on']['workflow_dispatch']['inputs'] as YamlMap;
    expect(inputs['sdk_dependencies']['options'], ['source', 'registry']);
    expect(inputs['sdk_dependencies']['default'], 'source');
    final environment = workflow['env'] as YamlMap;
    expect(
      environment['AWIKI_SOURCE_INTEGRATION'],
      contains("github.event.inputs.sdk_dependencies == 'source'"),
    );
    expect(environment['AWIKI_RELEASE_REGISTRY'], contains("&& '0' || '1'"));
    final jobs = workflow['jobs'] as YamlMap;
    for (final name in ['validate', 'remote-product']) {
      final builds = (jobs[name]['steps'] as YamlList).cast<YamlMap>().where(
        (step) => (step['run']?.toString() ?? '').contains('native_root='),
      );
      expect(builds, hasLength(1));
      final command = builds.single['run'].toString();
      expect(
        command,
        contains(
          '--deps source --source-manifest dependencies.source.json --cargo-command build -p im-core-dart -p awiki-cli --locked',
        ),
      );
      expect(
        command,
        contains('native_root=.artifacts/dependencies/source/target'),
      );
      expect(command, contains('scripts/release/registry-build.py'));
    }
    final windowsSteps = (jobs['windows-pr']['steps'] as YamlList)
        .cast<YamlMap>()
        .toList();
    final entryCheck = windowsSteps.indexWhere(
      (step) => step['name'] == 'Check Windows native build entrypoint',
    );
    final hostTests = windowsSteps.indexWhere(
      (step) => step['name'] == 'Run IM Core Rust host tests',
    );
    expect(entryCheck, greaterThanOrEqualTo(0));
    expect(entryCheck, lessThan(hostTests));
    expect(
      windowsSteps[entryCheck]['run'],
      './scripts/flutter/test-build-windows.ps1',
    );
    final windows = (jobs['windows-pr']['steps'] as YamlList)
        .cast<YamlMap>()
        .singleWhere(
          (step) => step['name'] == 'Run IM Core Rust host tests',
        )['run']
        .toString();
    expect(windows, contains('--cargo-command @cargoArgs'));
    expect(
      windows,
      contains(r'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'),
    );
  });

  test('release/0910 pull requests use the locked Core source', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    const selection =
        "github.event.inputs.sdk_dependencies == 'source' || (github.event_name == 'pull_request' && github.base_ref == 'release/0910')";
    expect(
      workflow['env']['AWIKI_SOURCE_INTEGRATION'],
      '\u0024{{ ($selection) && \'1\' || \'0\' }}',
    );
    expect(
      workflow['env']['AWIKI_RELEASE_REGISTRY'],
      '\u0024{{ ($selection) && \'0\' || \'1\' }}',
    );
    final source = File('.github/workflows/ci.yml').readAsStringSync();
    // Every fixed consumer pin (including shell/report refs) must be scoped to
    // the release baseline; unrelated branches retain the registry fallback.
    final pins = source
        .split('\n')
        .where(
          (line) => line.contains('950487d61a7dee0ad5cb4910a86e73e5f91a8893'),
        );
    expect(pins, hasLength(10));
    for (final line in pins) {
      expect(
        line,
        contains(
          "github.base_ref == 'release/0910' && '950487d61a7dee0ad5cb4910a86e73e5f91a8893'",
        ),
      );
      expect(line, contains('d3289db6732f6028fa7e54909b768bd48838f7fb'));
    }
  });

  test('validation-only dispatch cannot start remote account and OTP jobs', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final inputs = workflow['on']['workflow_dispatch']['inputs'] as YamlMap;
    expect(inputs['validation_only']['type'], 'boolean');
    expect(inputs['validation_only']['default'], isFalse);
    expect(inputs['cli_ref']['required'], isTrue);
    final jobs = workflow['jobs'] as YamlMap;
    expect(
      jobs['remote-product']['if'],
      "github.event_name == 'schedule' || (github.event_name == 'workflow_dispatch' && !inputs.validation_only)",
    );
    expect(jobs['validate'].containsKey('if'), isFalse);
    expect(jobs['remote-product']['needs'], [
      'validate',
      'cross-repository-contracts',
    ]);
    // Registry source and exact input selection remain shared with native CI.
    expect(
      jobs['windows-pr']['env']['WINDOWS_CORE_REF'],
      contains('github.event.inputs.cli_ref'),
    );
  });

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

  test('release/0910 consumers select the compatible Core baseline', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    const pin =
        "(github.base_ref == 'release/0910' && '950487d61a7dee0ad5cb4910a86e73e5f91a8893')";
    for (final name in [
      'validate',
      'cross-repository-contracts',
      'remote-product',
    ]) {
      final checkout = (jobs[name]['steps'] as YamlList)
          .cast<YamlMap>()
          .singleWhere(
            (step) =>
                step['with'] is YamlMap &&
                step['with']['path'] == 'awiki-cli-rs2',
          );
      expect(
        checkout['with']['ref'],
        '\u0024{{ github.event.inputs.cli_ref || $pin || \'d3289db6732f6028fa7e54909b768bd48838f7fb\' }}',
      );
    }
    expect(
      jobs['windows-pr']['env']['WINDOWS_CORE_REF'],
      '\u0024{{ github.event.inputs.cli_ref || $pin || \'d3289db6732f6028fa7e54909b768bd48838f7fb\' }}',
    );
  });

  test('PR checkout credentials are scoped to private contract sources', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    final validateSteps =
        (jobs['cross-repository-contracts'] as YamlMap)['steps'] as YamlList;
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

  test('private contract failure cannot block App validation', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;
    for (final entry in {
      'validate': 'app',
      'cross-repository-contracts': 'system',
    }.entries) {
      final job = jobs[entry.key] as YamlMap;
      expect(job.containsKey('needs'), isFalse);
      expect(job.containsKey('if'), isFalse);
      expect(job.containsKey('continue-on-error'), isFalse);
      final steps = (job['steps'] as YamlList).cast<YamlMap>().toList();
      expect(
        steps.any((step) => step.containsKey('continue-on-error')),
        isFalse,
      );
      final profile = steps.singleWhere(
        (step) =>
            (step['run']?.toString() ?? '').contains('--profile pr') &&
            !(step['run']?.toString() ?? '').contains('--prepare-only'),
      );
      expect(
        profile['run'],
        contains('--profile pr --component ${entry.value}'),
      );
      final repositories = steps
          .where((step) => step['with'] is YamlMap)
          .map((step) => step['with']['repository']?.toString() ?? '')
          .join('\n');
      for (final repository in [
        'awiki-web',
        'user-service',
        'dsh-awiki',
        'deepseek-harness-desktop',
      ]) {
        expect(repositories.contains('/$repository'), entry.value == 'system');
      }
      if (entry.value == 'app') {
        expect(
          job.toString(),
          isNot(contains('access to awiki-system-test, user-service')),
        );
        expect(
          steps.map((step) => step['name']),
          containsAll([
            'Dart analyze',
            'Flutter unit/widget/provider gate',
            'Validate case catalog and generated documentation',
            'Real desktop smoke (no service dependency)',
          ]),
        );
      }
    }
  });

  test('contract cache reuse cannot bypass tests or require Flutter', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    final job = workflow['jobs']['cross-repository-contracts'] as YamlMap;
    final steps = (job['steps'] as YamlList).cast<YamlMap>().toList();
    expect(job.toString(), isNot(contains('subosito/flutter-action')));
    final cache = steps.singleWhere(
      (step) => step['uses'] == 'actions/cache@v5',
    );
    expect(cache['with'].containsKey('restore-keys'), isFalse);
    final paths = cache['with']['path'].toString().trim().split('\n');
    expect(
      paths,
      contains('test-awiki-system-test/.artifacts/awiki-test-cache'),
    );
    expect(paths, isNot(contains('test-awiki-system-test/.artifacts')));
    final prepare = steps.singleWhere(
      (step) => (step['run']?.toString() ?? '').contains('--prepare-only'),
    );
    final execute = steps.singleWhere(
      (step) => step['name'] == 'Run cross-repository System PR contracts',
    );
    expect(prepare['env']['AWIKI_CLI_RUST_CARGO_OFFLINE'], '0');
    expect(job['env'].containsKey('AWIKI_CLI_RUST_CARGO_OFFLINE'), isFalse);
    expect(steps.indexOf(cache), lessThan(steps.indexOf(prepare)));
    expect(steps.indexOf(prepare), lessThan(steps.indexOf(execute)));
    expect(prepare.containsKey('if'), isFalse);
    expect(execute.containsKey('if'), isFalse);
    expect(execute['run'], contains('--profile pr --component system'));
    expect(execute['run'], isNot(contains('--exclude-suite')));
  });

  test('registry branches retain the published SDK build entrypoint', () {
    final workflow =
        loadYaml(File('.github/workflows/ci.yml').readAsStringSync())
            as YamlMap;
    expect(
      (workflow['env'] as YamlMap)['AWIKI_RELEASE_REGISTRY'],
      contains("&& '0' || '1'"),
    );
    final jobs = workflow['jobs'] as YamlMap;
    var cargoCommands = 0;
    for (final job in jobs.values.cast<YamlMap>()) {
      for (final step in (job['steps'] as YamlList).cast<YamlMap>()) {
        final script = step['run'];
        if (script is! String) continue;
        for (final line in script.split('\n')) {
          if (!RegExp(
            r'\bcargo (?:\+\S+ )?(?:build|test|@cargoArgs)\b',
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
  });

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
