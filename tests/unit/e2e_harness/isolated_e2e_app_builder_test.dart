// [INPUT]: Isolated E2E App builder arguments and temporary local roots.
// [OUTPUT]: Deterministic Debug build plans with distinct bundle/build/state paths and run-independent compile inputs.
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
      '--platform=macos',
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
      isNot(
        contains(
          '--dart-define=AWIKI_E2E_APP_STATE_ROOT=${root.path}/state/joiner',
        ),
      ),
    );
    expect(
      plan.flutterArguments,
      contains('--dart-define=AWIKI_MULTI_DEVICE_APP_PAIR_ROLE=joiner'),
    );
  });

  test('Linux build plan creates a relocatable isolated desktop bundle', () {
    final project = Directory('/tmp/awiki-app-pair-builder-test/project');
    final root = Directory('${project.path}/.e2e/pair');
    final request = IsolatedE2eAppBuildRequest.parse(<String>[
      '--name=admin',
      '--target=integration_test/multi_device_app_pair_test.dart',
      '--state-root=${root.path}/state/admin',
      '--work-root=${root.path}/work/admin',
      '--artifact-root=${root.path}/artifacts',
      '--bundle-id=ai.awiki.awikime.dev.e2e.pair.admin',
      '--platform=linux',
      '--dart-define=AWIKI_MULTI_DEVICE_APP_PAIR_ROLE=admin',
      '--dry-run',
    ], projectRoot: project);

    final plan = request.toPlan();

    expect(request.platform, IsolatedE2eAppPlatform.linux);
    expect(
      plan.sourceApp.path,
      '${root.path}/work/admin/flutter-build/linux/x64/debug/bundle',
    );
    expect(
      plan.flutterBuildDirectorySetting,
      '.e2e/pair/work/admin/flutter-build',
    );
    expect(plan.artifactApp.path, '${root.path}/artifacts/AWikiMe-admin-linux');
    expect(plan.executable.path, endsWith('/AWikiMe-admin-linux/awiki_me'));
    expect(plan.flutterArguments, containsAll(<String>['build', 'linux']));
    expect(
      plan.flutterArguments,
      contains('--dart-define=AWIKI_MULTI_DEVICE_APP_PAIR_ROLE=admin'),
    );
  });

  test('runtime state changes do not invalidate a role build', () {
    IsolatedE2eAppBuildPlan planFor(String runId) {
      final project = Directory('/tmp/awiki-app-pair-builder-test/project');
      return IsolatedE2eAppBuildRequest.parse(<String>[
        '--name=admin',
        '--target=integration_test/multi_device_app_pair_test.dart',
        '--state-root=${project.path}/.e2e/$runId/state/admin',
        '--work-root=${project.path}/.e2e/build-cache/admin',
        '--artifact-root=${project.path}/.e2e/$runId/artifacts',
        '--bundle-id=ai.awiki.awikime.dev.e2e.pair.admin',
        '--platform=macos',
        '--dart-define=AWIKI_MULTI_DEVICE_APP_PAIR_ROLE=admin',
        '--dry-run',
      ], projectRoot: project).toPlan();
    }

    expect(
      planFor('run-a').flutterArguments,
      planFor('run-b').flutterArguments,
    );
  });

  test('bundle digest changes for content and executable mode', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_isolated_bundle_digest_test_',
    );
    addTearDown(() => root.delete(recursive: true));
    final executable = File('${root.path}/awiki_me')
      ..writeAsStringSync('first');
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['644', executable.path]);
    }
    final baseline = await directorySha256(root);
    executable.writeAsStringSync('second');
    final contentChanged = await directorySha256(root);

    expect(contentChanged, isNot(baseline));
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['755', executable.path]);
      expect(await directorySha256(root), isNot(contentChanged));
    }
  });

  test('Linux native-assets compatibility link is bounded and temporary', () {
    final project = Directory.systemTemp.createTempSync(
      'awiki_isolated_native_assets_link_test_',
    );
    addTearDown(() => project.delete(recursive: true));
    final isolatedBuild = Directory('${project.path}/work/flutter-build');

    final link = prepareIsolatedLinuxNativeAssetsCompatibility(
      projectRoot: project,
      buildDirectory: isolatedBuild,
      platform: IsolatedE2eAppPlatform.linux,
    );

    expect(link, isNotNull);
    expect(link!.targetSync(), '${isolatedBuild.absolute.path}/linux');
    removeIsolatedLinuxNativeAssetsCompatibility(
      link,
      buildDirectory: isolatedBuild,
    );
    expect(
      FileSystemEntity.typeSync(link.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
  });

  test('Linux native-assets compatibility refuses a real default build', () {
    final project = Directory.systemTemp.createTempSync(
      'awiki_isolated_native_assets_refusal_test_',
    );
    addTearDown(() => project.delete(recursive: true));
    Directory('${project.path}/build/linux').createSync(recursive: true);

    expect(
      () => prepareIsolatedLinuxNativeAssetsCompatibility(
        projectRoot: project,
        buildDirectory: Directory('${project.path}/work/flutter-build'),
        platform: IsolatedE2eAppPlatform.linux,
      ),
      throwsA(isA<IsolatedE2eAppBuildException>()),
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
