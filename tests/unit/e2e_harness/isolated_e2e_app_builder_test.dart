// [INPUT]: Isolated E2E App builder arguments and temporary local roots.
// [OUTPUT]: Deterministic Debug build plans with distinct bundle/build/state paths and run-independent compile inputs.
// [POS]: Side-effect-free contract for the reusable multi-process App builder.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../e2e/host_platform.dart';
import '../../../tool/build_isolated_e2e_app.dart';

void main() {
  test(
    'compile inputs follow only the selected target local Dart graph',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'awiki-target-inputs-',
      );
      addTearDown(() => project.delete(recursive: true));
      await Directory(
        '${project.path}/integration_test',
      ).create(recursive: true);
      await Directory(
        '${project.path}/tests/e2e/shared',
      ).create(recursive: true);
      await File(
        '${project.path}/integration_test/selected.dart',
      ).writeAsString("import '../tests/e2e/shared/selected.dart';\n");
      await File(
        '${project.path}/integration_test/unrelated.dart',
      ).writeAsString("import '../tests/e2e/shared/unrelated.dart';\n");
      await File(
        '${project.path}/tests/e2e/shared/selected.dart',
      ).writeAsString(
        "part 'selected_part.dart';\n"
        "final part = 'not-a-directive.dart';\n"
        "final suffix = part\n"
        "    .length.toString();\n",
      );
      await File(
        '${project.path}/tests/e2e/shared/selected_part.dart',
      ).writeAsString("part of 'selected.dart';\n");
      await File(
        '${project.path}/tests/e2e/shared/unrelated.dart',
      ).writeAsString('const unrelated = true;\n');

      final inputs = await transitiveLocalDartInputsSha256Paths(
        project,
        'integration_test/selected.dart',
      );

      expect(inputs, <String>[
        'integration_test/selected.dart',
        'tests/e2e/shared/selected.dart',
        'tests/e2e/shared/selected_part.dart',
      ]);
      expect(inputs, isNot(contains('integration_test/unrelated.dart')));
      expect(inputs, isNot(contains('tests/e2e/shared/unrelated.dart')));
    },
  );

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

  test('Linux build plan selects the detected arm64 bundle directory', () {
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
      '--dry-run',
    ], projectRoot: project);

    expect(
      request.toPlan(processArchitecture: 'aarch64').sourceApp.path,
      '${root.path}/work/admin/flutter-build/linux/arm64/debug/bundle',
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

  test('immutable cache is content-addressed outside per-name scratch', () {
    final compileKey = List<String>.filled(64, 'a').join();
    final cache = isolatedArtifactCacheDirectory(
      projectRoot: Directory('/workspace/awiki-me'),
      platform: IsolatedE2eAppPlatform.linux,
      processArchitecture: 'x86_64',
      compileKey: compileKey,
    );

    expect(
      cache.path,
      '/workspace/awiki-me/.e2e/build-cache/v2/linux/x86_64/$compileKey',
    );
    expect(cache.path, isNot(contains('/work/admin')));
  });

  test('export manifest is relocatable and records evidence provenance', () {
    final artifact = IsolatedE2eAppArtifact(
      name: 'full',
      target: 'integration_test/desktop_cli_peer_smoke_test.dart',
      bundleId: 'ai.awiki.awikime.dev.e2e.full',
      appPath: '/workspace/awiki-me/.e2e/build-cache/v2/linux/x86_64/key/app',
      executablePath:
          '/workspace/awiki-me/.e2e/build-cache/v2/linux/x86_64/key/app/awiki_me',
      stateRoot: '/workspace/awiki-me/.e2e/run/state',
      buildDirectory: '/workspace/awiki-me/.e2e/build-scratch',
      dryRun: false,
      hostPlatform: const E2eHostPlatform(
        operatingSystem: 'linux',
        processArchitecture: 'x86_64',
        hardwareArchitecture: 'x86_64',
        translated: false,
      ),
      fingerprint: List<String>.filled(64, 'a').join(),
      cacheHit: true,
      artifactSha256: List<String>.filled(64, 'b').join(),
      projectRelativeAppPath: '.e2e/build-cache/v2/linux/x86_64/key/app',
      executableRelativePath: 'awiki_me',
      consumerSuites: const <String>['full'],
      compileKeyPayload: const <String, Object?>{'cacheContractVersion': 4},
      provenance: const <String, Object?>{
        'sourceRef': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'worktreeDirty': true,
      },
      cachePrunedEntries: 0,
      cachePrunedBytes: 0,
    );

    final manifest = artifact.toJson();
    expect(manifest, isNot(contains('appPath')));
    expect(manifest, isNot(contains('executablePath')));
    expect(manifest, isNot(contains('stateRoot')));
    expect(manifest, isNot(contains('buildDirectory')));
    expect(
      manifest['projectRelativeAppPath'],
      '.e2e/build-cache/v2/linux/x86_64/key/app',
    );
    expect(manifest['consumerSuites'], const <String>['full']);
    expect(manifest['evidenceEligible'], isFalse);
  });

  test('disk budget keeps post-job reserve separate from peak usage', () {
    expect(
      e2eBuildRequiredFreeBytes(
        minFreeAfterJob: 4 * 1024,
        estimatedPeakBytes: 6 * 1024,
      ),
      10 * 1024,
    );
  });

  test('LRU pruning preserves pinned compile keys', () async {
    final project = await Directory.systemTemp.createTemp(
      'awiki_app_cache_lru_test_',
    );
    addTearDown(() => project.delete(recursive: true));
    final oldKey = List<String>.filled(64, 'a').join();
    final pinnedKey = List<String>.filled(64, 'b').join();
    final newestKey = List<String>.filled(64, 'c').join();

    Directory entry(String key, DateTime usedAt) {
      final directory = Directory(
        '${project.path}/.e2e/build-cache/v2/linux/x86_64/$key',
      )..createSync(recursive: true);
      File('${directory.path}/app.bin').writeAsBytesSync(<int>[1, 2, 3]);
      File('${directory.path}/manifest.json')
        ..writeAsStringSync('{}')
        ..setLastModifiedSync(usedAt);
      return directory;
    }

    final old = entry(oldKey, DateTime.utc(2026, 1, 1));
    final pinned = entry(pinnedKey, DateTime.utc(2025, 1, 1));
    final newest = entry(newestKey, DateTime.utc(2026, 2, 1));

    final report = await pruneIsolatedArtifactCache(
      projectRoot: project,
      pinnedCompileKeys: <String>{pinnedKey},
      bytesToFree: 1,
    );

    expect(report.prunedEntries, 1);
    expect(report.prunedBytes, greaterThanOrEqualTo(3));
    expect(old.existsSync(), isFalse);
    expect(pinned.existsSync(), isTrue);
    expect(newest.existsSync(), isTrue);
  });

  test(
    'temporary cache recovery removes only dead owner directories',
    () async {
      final project = await Directory.systemTemp.createTemp(
        'awiki_app_cache_temp_recovery_test_',
      );
      addTearDown(() => project.delete(recursive: true));
      final key = List<String>.filled(64, 'd').join();
      final parent = Directory(
        '${project.path}/.e2e/build-cache/v2/linux/x86_64',
      )..createSync(recursive: true);
      final stale = Directory('${parent.path}/.$key.99999999.tmp')
        ..createSync();
      final live = Directory('${parent.path}/.$key.$pid.tmp')..createSync();

      await recoverStaleIsolatedArtifactTemps(project);

      expect(stale.existsSync(), isFalse);
      expect(live.existsSync(), isTrue);
    },
  );

  test('dart defines are canonical and duplicate keys fail closed', () {
    expect(
      canonicalDartDefines(const <String>['Z=value', 'A=first']),
      const <String>['A=first', 'Z=value'],
    );
    expect(
      () => canonicalDartDefines(const <String>['A=first', 'A=second']),
      throwsA(isA<IsolatedE2eAppBuildException>()),
    );
  });

  test('artifact identity name is not part of the compile key payload', () {
    IsolatedE2eAppBuildRequest request(String name) {
      final project = Directory('/tmp/awiki-compile-key-test/project');
      return IsolatedE2eAppBuildRequest.parse(<String>[
        '--name=$name',
        '--target=integration_test/app_smoke_test.dart',
        '--state-root=${project.path}/.e2e/state/$name',
        '--work-root=${project.path}/.e2e/work/$name',
        '--artifact-root=${project.path}/.e2e/artifacts/$name',
        '--bundle-id=ai.awiki.awikime.dev.e2e.shared',
        '--platform=linux',
        '--dart-define=Z=value',
        '--dart-define=A=first',
        '--dry-run',
      ], projectRoot: project);
    }

    Map<String, Object?> payload(String name) => isolatedCompileKeyPayload(
      request: request(name),
      hostPlatform: const E2eHostPlatform(
        operatingSystem: 'linux',
        processArchitecture: 'x86_64',
        hardwareArchitecture: 'x86_64',
        translated: false,
      ),
      sourceDigest: 'source',
      pubspecLockSha256: 'lock',
      pubspecOverridesSha256: 'overrides',
      pathDependencySha256: 'dependency',
      nativeCoreSha256: 'native',
      nativeCoreProvenanceSha256: 'provenance',
      flutterIdentity: const <String, String>{'frameworkVersion': '1'},
      rustcVersion: 'rustc 1',
    );

    expect(payload('first-name'), payload('second-name'));
    expect(payload('first-name'), isNot(contains('name')));
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

    final compatibility = prepareIsolatedLinuxNativeAssetsCompatibility(
      projectRoot: project,
      buildDirectory: isolatedBuild,
      platform: IsolatedE2eAppPlatform.linux,
    );

    expect(compatibility, isNotNull);
    final link = compatibility!.linuxLink;
    expect(link.targetSync(), '${isolatedBuild.absolute.path}/linux');
    final nativeAssetsLink = Link('${project.path}/build/native_assets');
    expect(
      nativeAssetsLink.targetSync(),
      '${isolatedBuild.absolute.path}/native_assets',
    );
    expect(
      Directory('${isolatedBuild.path}/native_assets/linux').existsSync(),
      isTrue,
    );
    removeIsolatedLinuxNativeAssetsCompatibility(
      compatibility,
      buildDirectory: isolatedBuild,
    );
    expect(
      FileSystemEntity.typeSync(link.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
    expect(
      FileSystemEntity.typeSync(nativeAssetsLink.path, followLinks: false),
      FileSystemEntityType.notFound,
    );
  });

  test('Linux native-assets compatibility restores build-hook output', () {
    final project = Directory.systemTemp.createTempSync(
      'awiki_isolated_native_assets_restore_test_',
    );
    addTearDown(() => project.delete(recursive: true));
    final original = File(
      '${project.path}/build/native_assets/linux/native_assets.json',
    )..createSync(recursive: true);
    original.writeAsStringSync('original');
    final isolatedBuild = Directory('${project.path}/work/flutter-build');

    final compatibility = prepareIsolatedLinuxNativeAssetsCompatibility(
      projectRoot: project,
      buildDirectory: isolatedBuild,
      platform: IsolatedE2eAppPlatform.linux,
    );

    expect(
      FileSystemEntity.typeSync(
        original.parent.parent.path,
        followLinks: false,
      ),
      FileSystemEntityType.link,
    );
    removeIsolatedLinuxNativeAssetsCompatibility(
      compatibility,
      buildDirectory: isolatedBuild,
    );
    expect(original.readAsStringSync(), 'original');
  });

  test('Linux compatibility recovers one interrupted owned build', () {
    final project = Directory.systemTemp.createTempSync(
      'awiki_isolated_interrupted_restore_test_',
    );
    addTearDown(() => project.delete(recursive: true));
    final buildRoot = Directory('${project.path}/build')..createSync();
    final oldWork = Directory(
      '${project.path}/.e2e/build-cache/v2/work/linux/old/flutter-build',
    );
    Directory('${oldWork.path}/linux').createSync(recursive: true);
    Directory('${oldWork.path}/native_assets').createSync(recursive: true);
    Link('${buildRoot.path}/linux').createSync('${oldWork.path}/linux');
    Link(
      '${buildRoot.path}/native_assets',
    ).createSync('${oldWork.path}/native_assets');
    final backup = Directory(
      '${buildRoot.path}/native_assets.awiki-isolated-backup-99999999',
    )..createSync();
    File('${backup.path}/original').writeAsStringSync('preserved');

    recoverStaleIsolatedLinuxNativeAssetsCompatibility(
      projectRoot: project,
      buildDirectory: Directory(
        '${project.path}/.e2e/build-cache/v2/work/linux/shared/flutter-build',
      ),
    );

    expect(Link('${buildRoot.path}/linux').existsSync(), isFalse);
    expect(
      File('${buildRoot.path}/native_assets/original').readAsStringSync(),
      'preserved',
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
