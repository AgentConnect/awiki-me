// [INPUT]: Isolated E2E App builder arguments and temporary local roots.
// [OUTPUT]: Deterministic Debug build plans with distinct bundle/build/state paths.
// [POS]: Side-effect-free contract for the reusable multi-process App builder.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/build_isolated_e2e_app.dart';

void main() {
  test('build plan isolates bundle, state, build, and artifact paths', () {
    final project = Directory('/tmp/awiki-app-pair-builder-test/project');
    final root = Directory('${project.path}/.e2e/pair');
    final request = IsolatedE2eAppBuildRequest.parse(<String>[
      '--name=joiner',
      '--target=integration_test/multi_device_app_pair_test.dart',
      '--state-root=${root.path}/state/joiner',
      '--work-root=${root.path}/work/joiner',
      '--artifact-root=${root.path}/artifacts',
      '--bundle-id=ai.awiki.awikime.dev.e2e.pair.joiner',
      '--flutter-bin=/opt/flutter/bin/flutter',
      '--dart-define=AWIKI_MULTI_DEVICE_APP_PAIR_ROLE=joiner',
      '--dry-run',
    ], projectRoot: project);

    final plan = request.toPlan();

    expect(request.dryRun, isTrue);
    expect(
      plan.sourceApp.path,
      '${root.path}/work/joiner/flutter-build/macos/Build/Products/Debug/AWikiMe.app',
    );
    expect(
      plan.flutterBuildDirectorySetting,
      '.e2e/pair/work/joiner/flutter-build',
    );
    expect(plan.artifactApp.path, '${root.path}/artifacts/AWikiMe-joiner.app');
    expect(
      plan.executable.path,
      endsWith('AWikiMe-joiner.app/Contents/MacOS/AWikiMe'),
    );
    expect(plan.flutterArguments, contains('--debug'));
    expect(plan.flutterArguments, contains('--no-pub'));
    expect(
      plan.flutterArguments,
      contains(
        '--dart-define=AWIKI_E2E_APP_STATE_ROOT=${root.path}/state/joiner',
      ),
    );
    expect(
      plan.flutterArguments,
      contains('--dart-define=AWIKI_MULTI_DEVICE_APP_PAIR_ROLE=joiner'),
    );
  });

  test('builder rejects non-integration and path-traversal targets', () {
    expect(
      () => IsolatedE2eAppBuildRequest.parse(<String>[
        '--name=admin',
        '--target=lib/main.dart',
        '--state-root=/tmp/state',
        '--work-root=/tmp/work',
        '--artifact-root=/tmp/artifacts',
        '--bundle-id=ai.awiki.awikime.dev.e2e.pair.admin',
      ], projectRoot: Directory('/workspace/awiki-me')),
      throwsA(isA<IsolatedE2eAppBuildException>()),
    );
    expect(
      () => IsolatedE2eAppBuildRequest.parse(<String>[
        '--name=admin',
        '--target=integration_test/../unsafe_test.dart',
        '--state-root=/tmp/state',
        '--work-root=/tmp/work',
        '--artifact-root=/tmp/artifacts',
        '--bundle-id=ai.awiki.awikime.dev.e2e.pair.admin',
      ], projectRoot: Directory('/workspace/awiki-me')),
      throwsA(isA<IsolatedE2eAppBuildException>()),
    );
  });

  test('builder rejects unknown and duplicate singleton options', () {
    final required = <String>[
      '--name=admin',
      '--target=integration_test/multi_device_app_pair_test.dart',
      '--state-root=/tmp/state',
      '--work-root=/tmp/work',
      '--artifact-root=/tmp/artifacts',
      '--bundle-id=ai.awiki.awikime.dev.e2e.pair.admin',
    ];
    expect(
      () => IsolatedE2eAppBuildRequest.parse(<String>[
        ...required,
        '--unknown=value',
      ], projectRoot: Directory('/workspace/awiki-me')),
      throwsA(isA<IsolatedE2eAppBuildException>()),
    );
    expect(
      () => IsolatedE2eAppBuildRequest.parse(<String>[
        ...required,
        '--flutter-bin=flutter-a',
        '--flutter-bin=flutter-b',
      ], projectRoot: Directory('/workspace/awiki-me')),
      throwsA(isA<IsolatedE2eAppBuildException>()),
    );
  });

  test(
    'builder rejects roots outside the project or overlapping each other',
    () {
      final project = Directory('/workspace/awiki-me');
      final required = <String>[
        '--name=admin',
        '--target=integration_test/multi_device_app_pair_test.dart',
        '--bundle-id=ai.awiki.awikime.dev.e2e.pair.admin',
      ];
      expect(
        () => IsolatedE2eAppBuildRequest.parse(<String>[
          ...required,
          '--state-root=/tmp/state',
          '--work-root=${project.path}/.e2e/work',
          '--artifact-root=${project.path}/.e2e/artifacts',
        ], projectRoot: project),
        throwsA(isA<IsolatedE2eAppBuildException>()),
      );
      expect(
        () => IsolatedE2eAppBuildRequest.parse(<String>[
          ...required,
          '--state-root=${project.path}/.e2e/state',
          '--work-root=${project.path}/.e2e/work',
          '--artifact-root=${project.path}/.e2e/work/artifacts',
        ], projectRoot: project),
        throwsA(isA<IsolatedE2eAppBuildException>()),
      );
    },
  );
}
