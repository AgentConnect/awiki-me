import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _appRef = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _coreRef = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _anpRef = 'cccccccccccccccccccccccccccccccccccccccc';
const _allTargets = <String>[
  'android-arm64',
  'macos-arm64',
  'macos-x64',
  'windows-x64',
];

void main() {
  test('package dispatch separates the controller from source revisions', () {
    final script = File('scripts/package_app.sh').readAsStringSync();
    final workflowSource = File(
      '.github/workflows/package-app.yml',
    ).readAsStringSync();
    final workflow = loadYaml(workflowSource) as YamlMap;

    expect(script, contains(r'gh repo view "$repository"'));
    expect(script, contains('--json defaultBranchRef'));
    expect(script, contains("--jq '.defaultBranchRef.name'"));
    expect(script, contains(r'--ref "$WORKFLOW_REF"'));
    expect(script, contains(r'--branch "$WORKFLOW_REF"'));
    expect(script, contains('--raw-field "app_ref=\$APP_SOURCE_REF"'));
    expect(script, contains('--raw-field "core_ref=\$IM_CORE_SOURCE_REF"'));
    expect(script, isNot(contains(r'--ref "$APP_SOURCE_BRANCH"')));
    expect(script, isNot(contains(r'--branch "$APP_SOURCE_BRANCH"')));
    expect(script, isNot(contains('WORKFLOW_REF="main"')));
    expect(script, isNot(contains('AWIKI_APP_RELEASE_ACTORS')));
    expect(script, contains('trap rollback_release_output EXIT'));
    expect(script, contains(r'$latest_backup'));
    expect(script, isNot(contains(r'mv "$backup_dir" "$output_dir" || true')));

    final jobs = workflow['jobs'] as YamlMap;
    final authorize = jobs['authorize'] as YamlMap;
    final validate = jobs['validate'] as YamlMap;
    final build = jobs['build'] as YamlMap;
    final aggregate = jobs['aggregate'] as YamlMap;
    expect(authorize.containsKey('environment'), isFalse);
    expect(authorize['permissions'], isA<YamlMap>());
    expect((authorize['permissions'] as YamlMap), isEmpty);
    expect(validate['needs'], 'authorize');
    expect(validate['environment'], 'app-packaging');

    final aggregateStep = _stepNamed(
      aggregate['steps'] as YamlList,
      'Recompute checksums and generate manifests',
    );
    expect(
      (aggregateStep['env'] as YamlMap)['REQUEST_ID'],
      r'${{ inputs.request_id }}',
    );
    expect(
      aggregateStep['run'].toString(),
      contains(r'--request-id "$REQUEST_ID"'),
    );

    final authorizeSteps = authorize['steps'] as YamlList;
    final authorization = _stepNamed(
      authorizeSteps,
      'Require an authorized release actor and stable controller',
    );
    final authorizationEnvironment = authorization['env'] as YamlMap;
    expect(
      authorizationEnvironment['RELEASE_ACTORS'],
      r'${{ vars.AWIKI_APP_RELEASE_ACTORS }}',
    );
    expect(authorizationEnvironment['ACTOR'], r'${{ github.actor }}');
    expect(
      authorizationEnvironment['TRIGGERING_ACTOR'],
      r'${{ github.triggering_actor }}',
    );
    expect(
      authorizationEnvironment['DEFAULT_BRANCH'],
      r'${{ github.event.repository.default_branch }}',
    );
    expect(
      authorizationEnvironment['WORKFLOW_REF'],
      r'${{ github.workflow_ref }}',
    );
    final authorizationScript = authorization['run'].toString();
    expect(authorizationScript, contains('json.loads'));
    expect(authorizationScript, contains('ACTOR'));
    expect(authorizationScript, contains('TRIGGERING_ACTOR'));
    expect(
      authorizationScript,
      contains('package workflow controller must run from the default branch'),
    );
    expect(
      authorizationScript,
      contains('package workflow file does not come from the default branch'),
    );

    const expectedPrivilegedJobCondition = r'''
${{
  github.event_name == 'workflow_dispatch' &&
  github.ref == format('refs/heads/{0}', github.event.repository.default_branch) &&
  endsWith(github.workflow_ref, format('@refs/heads/{0}', github.event.repository.default_branch)) &&
  contains(fromJSON(vars.AWIKI_APP_RELEASE_ACTORS), github.actor) &&
  contains(fromJSON(vars.AWIKI_APP_RELEASE_ACTORS), github.triggering_actor)
}}
''';
    for (final jobName in <String>['validate', 'build', 'aggregate']) {
      final condition = (jobs[jobName] as YamlMap)['if'].toString();
      expect(
        _normalizeWhitespace(condition),
        _normalizeWhitespace(expectedPrivilegedJobCondition),
        reason: '$jobName must independently authorize every run attempt',
      );
    }

    final steps = validate['steps'] as YamlList;
    final appCheckout = _stepNamed(steps, 'Checkout exact AWiki Me source');
    final coreCheckout = _stepNamed(
      steps,
      'Checkout exact CLI / IM Core source',
    );
    final anpCheckout = _stepNamed(steps, 'Checkout exact ANP source');
    final verification = _stepNamed(
      steps,
      'Verify source refs and committed version',
    );

    expect((appCheckout['with'] as YamlMap)['ref'], r'${{ inputs.app_ref }}');
    expect((coreCheckout['with'] as YamlMap)['ref'], r'${{ inputs.core_ref }}');
    expect((anpCheckout['with'] as YamlMap)['ref'], r'${{ inputs.anp_ref }}');

    final verificationScript = verification['run'].toString();
    expect(verificationScript, isNot(contains(r'$GITHUB_SHA')));
    expect(verificationScript, contains(r'git -C awiki-me rev-parse HEAD'));
    expect(
      verificationScript,
      contains(r'git -C awiki-cli-rs2 rev-parse HEAD'),
    );
    expect(verificationScript, contains(r'git -C anp/anp rev-parse HEAD'));

    final buildSteps = build['steps'] as YamlList;
    final flutterSetup = _stepNamed(buildSteps, 'Setup Flutter 3.44.0');
    final flutterSetupInputs = flutterSetup['with'] as YamlMap;
    expect(flutterSetupInputs['cache'], isFalse);
    expect(flutterSetupInputs['pub-cache'], isTrue);

    final rustCache = _stepNamed(
      buildSteps,
      'Restore Rust dependency and build cache',
    );
    expect(rustCache['uses'], 'actions/cache@v5');
    final rustCacheInputs = rustCache['with'] as YamlMap;
    final rustCachePaths = rustCacheInputs['path'].toString();
    expect(rustCachePaths, contains('~/.cargo/registry'));
    expect(rustCachePaths, contains('~/.cargo/git'));
    expect(rustCachePaths, contains('awiki-cli-rs2/target'));
    final rustCacheKey = rustCacheInputs['key'].toString();
    expect(rustCacheKey, contains(r'${{ runner.os }}'));
    expect(rustCacheKey, contains(r'${{ runner.arch }}'));
    expect(rustCacheKey, contains(r'${{ matrix.target }}'));
    expect(rustCacheKey, contains(r'${{ env.RUST_VERSION }}'));
    expect(
      rustCacheKey,
      contains(r"${{ hashFiles('awiki-cli-rs2/Cargo.lock') }}"),
    );

    final androidNativeTool = _stepNamed(
      buildSteps,
      'Install pinned Android native build tool',
    );
    expect(androidNativeTool['if'], "matrix.target == 'android-arm64'");
    expect(
      androidNativeTool['run'].toString(),
      contains(
        'cargo install cargo-ndk --version "\$CARGO_NDK_VERSION" --locked',
      ),
    );
    expect(
      (workflow['env'] as YamlMap)['CARGO_NDK_VERSION'].toString(),
      '4.1.2',
    );

    final unixWorker = File(
      'scripts/package_unix_worker.sh',
    ).readAsStringSync();
    expect(unixWorker, contains('--macos-arch "\$arch"'));
    expect(unixWorker, contains('--android-abi arm64-v8a'));

    final aggregateSteps = aggregate['steps'] as YamlList;
    final aggregateFlutterSetup = _stepNamed(
      aggregateSteps,
      'Setup Flutter 3.44.0',
    );
    final aggregateFlutterInputs = aggregateFlutterSetup['with'] as YamlMap;
    expect(aggregateFlutterInputs['cache'], isFalse);
    expect(aggregateFlutterInputs['pub-cache'], isTrue);

    final androidSettings = File('android/settings.gradle').readAsStringSync();
    final androidBuild = File('android/build.gradle').readAsStringSync();
    _expectBefore(
      androidSettings,
      'google()',
      "maven { url 'https://maven.aliyun.com/repository/google' }",
    );
    _expectBefore(
      androidSettings,
      'mavenCentral()',
      "maven { url 'https://maven.aliyun.com/repository/central' }",
    );
    _expectBefore(
      androidSettings,
      'gradlePluginPortal()',
      "maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }",
    );
    _expectBefore(
      androidBuild,
      'google()',
      "maven { url 'https://maven.aliyun.com/repository/google' }",
    );
    _expectBefore(
      androidBuild,
      'mavenCentral()',
      "maven { url 'https://maven.aliyun.com/repository/central' }",
    );

    for (final job in jobs.values.cast<YamlMap>()) {
      final jobSteps = job['steps'];
      if (jobSteps is! YamlList) continue;
      for (final step in jobSteps.cast<YamlMap>()) {
        final action = step['uses']?.toString() ?? '';
        if (!action.startsWith('actions/checkout@')) continue;
        expect(
          (step['with'] as YamlMap)['persist-credentials'],
          isFalse,
          reason: step['name'].toString(),
        );
      }
    }
  });

  test('release authorization fails closed for actors and controller refs', () {
    expect(_runAuthorization().exitCode, 0);

    final unauthorizedActor = _runAuthorization(actor: 'untrusted-user');
    expect(unauthorizedActor.exitCode, isNot(0));
    expect(unauthorizedActor.stderr, contains('ACTOR is not authorized'));

    final unauthorizedRerun = _runAuthorization(
      triggeringActor: 'untrusted-user',
    );
    expect(unauthorizedRerun.exitCode, isNot(0));
    expect(
      unauthorizedRerun.stderr,
      contains('TRIGGERING_ACTOR is not authorized'),
    );

    final malformedAllowlist = _runAuthorization(releaseActors: '{bad-json');
    expect(malformedAllowlist.exitCode, isNot(0));
    expect(malformedAllowlist.stderr, contains('must be a JSON array'));

    final wrongControlBranch = _runAuthorization(controlBranch: 'feature/x');
    expect(wrongControlBranch.exitCode, isNot(0));
    expect(
      wrongControlBranch.stderr,
      contains('controller must run from the default branch'),
    );

    final wrongWorkflowRef = _runAuthorization(
      workflowRef:
          'AgentConnect/awiki-me/.github/workflows/package-app.yml@refs/heads/feature/x',
    );
    expect(wrongWorkflowRef.exitCode, isNot(0));
    expect(
      wrongWorkflowRef.stderr,
      contains('workflow file does not come from the default branch'),
    );
  });

  test(
    'subset output stays isolated and a full run replaces the release set',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_package_output_boundary_',
      );
      try {
        final dist = Directory('${root.path}/dist');
        final previousRelease = Directory('${dist.path}/1.2.3');
        await previousRelease.create(recursive: true);
        await File(
          '${previousRelease.path}/stale-package.bin',
        ).writeAsString('stale-release');
        final globalLatest = File('${dist.path}/latest.json');
        await globalLatest.writeAsString('previous-global-latest\n');

        final subsetDownload = Directory('${root.path}/subset-download');
        const subsetRequestId = '11111111-1111-4111-8111-111111111111';
        await _writeAggregate(
          subsetDownload,
          targets: const <String>['windows-x64'],
          requestId: subsetRequestId,
        );
        final subsetResult = _installAggregate(
          download: subsetDownload,
          dist: dist,
          targets: const <String>['windows-x64'],
          requestId: subsetRequestId,
        );
        expect(
          subsetResult.exitCode,
          0,
          reason: subsetResult.stderr.toString(),
        );

        final validation = Directory(
          '${dist.path}/validation/1.2.3+42/'
          '11111111-1111-4111-8111-111111111111',
        );
        expect(await validation.exists(), isTrue);
        expect(await File('${validation.path}/latest.json').exists(), isFalse);
        expect(await globalLatest.readAsString(), 'previous-global-latest\n');
        expect(
          await File(
            '${previousRelease.path}/stale-package.bin',
          ).readAsString(),
          'stale-release',
        );

        final fullDownload = Directory('${root.path}/full-download');
        const fullRequestId = '22222222-2222-4222-8222-222222222222';
        await _writeAggregate(
          fullDownload,
          targets: _allTargets,
          requestId: fullRequestId,
        );
        final fullResult = _installAggregate(
          download: fullDownload,
          dist: dist,
          targets: _allTargets,
          requestId: fullRequestId,
        );
        expect(fullResult.exitCode, 0, reason: fullResult.stderr.toString());

        final releaseFiles =
            previousRelease
                .listSync()
                .map((entry) => entry.uri.pathSegments.last)
                .toList()
              ..sort();
        expect(releaseFiles, <String>[
          'AWiki-Me-1.2.3-windows-x64.exe',
          'AWiki-Me-Android-arm64-1.2.3.apk',
          'AWiki-Me-macOS-arm64-1.2.3.dmg',
          'AWiki-Me-macOS-x64-1.2.3.dmg',
          'package-manifest.json',
        ]);
        expect(
          await globalLatest.readAsBytes(),
          await File(
            '${previousRelease.path}/package-manifest.json',
          ).readAsBytes(),
        );
        expect(await validation.exists(), isTrue);
        expect(
          dist
              .listSync()
              .map((entry) => entry.uri.pathSegments.last)
              .where(
                (name) =>
                    name.startsWith('.package-') || name.startsWith('.latest-'),
              ),
          isEmpty,
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('invalid downloaded latest leaves dist unchanged', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_package_output_failure_',
    );
    try {
      final dist = Directory('${root.path}/dist');
      await dist.create();
      await File('${dist.path}/latest.json').writeAsString('existing-latest\n');
      final release = Directory('${dist.path}/1.2.3');
      await release.create();
      await File('${release.path}/existing.bin').writeAsString('existing');
      final before = await _directorySnapshot(dist);

      final download = Directory('${root.path}/invalid-download');
      const requestId = '33333333-3333-4333-8333-333333333333';
      await _writeAggregate(
        download,
        targets: _allTargets,
        requestId: requestId,
      );
      await File('${download.path}/latest.json').writeAsString('{}\n');
      final result = _installAggregate(
        download: download,
        dist: dist,
        targets: _allTargets,
        requestId: requestId,
      );

      expect(result.exitCode, isNot(0));
      expect(
        result.stderr.toString(),
        contains('latest.json does not match package-manifest.json'),
      );
      expect(await _directorySnapshot(dist), before);

      final validationDownload = Directory(
        '${root.path}/invalid-validation-download',
      );
      const validationRequestId = '66666666-6666-4666-8666-666666666666';
      await _writeAggregate(
        validationDownload,
        targets: const <String>['windows-x64'],
        requestId: validationRequestId,
      );
      await File(
        '${validationDownload.path}/package-manifest.json',
      ).copy('${validationDownload.path}/latest.json');
      final validationResult = _installAggregate(
        download: validationDownload,
        dist: dist,
        targets: const <String>['windows-x64'],
        requestId: validationRequestId,
      );
      expect(validationResult.exitCode, isNot(0));
      expect(
        validationResult.stderr.toString(),
        contains('validation aggregate must not contain latest.json'),
      );
      expect(await _directorySnapshot(dist), before);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('release manifest identity mismatches leave dist unchanged', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_package_output_identity_',
    );
    try {
      final dist = Directory('${root.path}/dist');
      await dist.create();
      await File('${dist.path}/latest.json').writeAsString('existing-latest\n');
      final release = Directory('${dist.path}/1.2.3');
      await release.create();
      await File('${release.path}/existing.bin').writeAsString('existing');
      final before = await _directorySnapshot(dist);
      const requestId = '44444444-4444-4444-8444-444444444444';
      final cases =
          <
            ({
              String expectedError,
              void Function(Map<String, Object?> manifest) mutate,
            })
          >[
            (
              expectedError: 'packageSet does not match selected targets',
              mutate: (manifest) => manifest['packageSet'] = 'validation',
            ),
            (
              expectedError: 'complete does not match selected targets',
              mutate: (manifest) => manifest['complete'] = false,
            ),
            (
              expectedError: 'requestId does not match dispatch input',
              mutate: (manifest) => manifest['requestId'] =
                  '55555555-5555-4555-8555-555555555555',
            ),
            (
              expectedError: 'publishedAt must be ISO-8601',
              mutate: (manifest) => manifest.remove('publishedAt'),
            ),
            (
              expectedError: 'platforms do not match selected artifacts',
              mutate: (manifest) => manifest['platforms'] = <String, Object?>{},
            ),
          ];

      for (var index = 0; index < cases.length; index++) {
        final fixture = cases[index];
        final download = Directory('${root.path}/identity-$index');
        await _writeAggregate(
          download,
          targets: _allTargets,
          requestId: requestId,
        );
        await _rewriteAggregateManifest(download, fixture.mutate);
        final result = _installAggregate(
          download: download,
          dist: dist,
          targets: _allTargets,
          requestId: requestId,
        );

        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains(fixture.expectedError));
        expect(await _directorySnapshot(dist), before);
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
}

YamlMap _stepNamed(YamlList steps, String name) {
  return steps.cast<YamlMap>().singleWhere((step) => step['name'] == name);
}

ProcessResult _runAuthorization({
  String releaseActors = '["smartGrey"]',
  String actor = 'smartGrey',
  String triggeringActor = 'SMARTGREY',
  String controlBranch = 'main',
  String workflowRef =
      'AgentConnect/awiki-me/.github/workflows/package-app.yml@refs/heads/main',
}) {
  final workflow =
      loadYaml(File('.github/workflows/package-app.yml').readAsStringSync())
          as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;
  final authorize = jobs['authorize'] as YamlMap;
  final authorization = _stepNamed(
    authorize['steps'] as YamlList,
    'Require an authorized release actor and stable controller',
  );
  final script = authorization['run'].toString();
  return Process.runSync(
    'bash',
    <String>['-c', script],
    environment: <String, String>{
      'RELEASE_ACTORS': releaseActors,
      'ACTOR': actor,
      'TRIGGERING_ACTOR': triggeringActor,
      'EVENT_NAME': 'workflow_dispatch',
      'CONTROL_REF_TYPE': 'branch',
      'CONTROL_BRANCH': controlBranch,
      'CONTROL_REF': 'refs/heads/$controlBranch',
      'WORKFLOW_REF': workflowRef,
      'DEFAULT_BRANCH': 'main',
    },
  );
}

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void _expectBefore(String source, String first, String second) {
  final firstIndex = source.indexOf(first);
  final secondIndex = source.indexOf(second);
  expect(firstIndex, isNonNegative, reason: '$first must be configured');
  expect(secondIndex, isNonNegative, reason: '$second must be configured');
  expect(
    firstIndex,
    lessThan(secondIndex),
    reason: '$first must be preferred over $second',
  );
}

Future<void> _writeAggregate(
  Directory output, {
  required List<String> targets,
  required String requestId,
}) async {
  await output.create(recursive: true);
  final artifacts = <String, Object?>{};
  for (final target in targets) {
    final filename = switch (target) {
      'android-arm64' => 'AWiki-Me-Android-arm64-1.2.3.apk',
      'macos-arm64' => 'AWiki-Me-macOS-arm64-1.2.3.dmg',
      'macos-x64' => 'AWiki-Me-macOS-x64-1.2.3.dmg',
      'windows-x64' => 'AWiki-Me-1.2.3-windows-x64.exe',
      _ => throw StateError('unsupported fixture target: $target'),
    };
    final bytes = utf8.encode('package-$target');
    await File('${output.path}/$filename').writeAsBytes(bytes);
    artifacts[target] = <String, Object?>{
      'target': target,
      'filename': filename,
      'sizeBytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'signingState': target == 'windows-x64' ? 'unsigned' : 'signed',
    };
  }
  final isComplete =
      targets.length == _allTargets.length &&
      targets.toSet().containsAll(_allTargets);
  Map<String, Object?> platformEntry(String target) {
    final artifact = artifacts[target]! as Map<String, Object?>;
    return <String, Object?>{
      'downloadUrl':
          'https://awiki.ai/downloads/awiki-me/1.2.3/'
          '${artifact['filename']}',
      'sha256': artifact['sha256'],
    };
  }

  final platforms = <String, Object?>{};
  if (artifacts.containsKey('android-arm64')) {
    platforms['android'] = platformEntry('android-arm64');
  }
  final defaultMac = artifacts.containsKey('macos-arm64')
      ? 'macos-arm64'
      : artifacts.containsKey('macos-x64')
      ? 'macos-x64'
      : null;
  if (defaultMac != null) {
    platforms['macos'] = platformEntry(defaultMac);
  }
  for (final target in <String>['macos-arm64', 'macos-x64', 'windows-x64']) {
    if (artifacts.containsKey(target)) {
      platforms[target] = platformEntry(target);
    }
  }
  final encoded =
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schemaVersion': 1,
        'packageSet': isComplete ? 'release' : 'validation',
        'complete': isComplete,
        'requestId': requestId,
        'version': '1.2.3',
        'buildNumber': 42,
        'publishedAt': '2026-07-22T00:00:00.000Z',
        'sourceRefs': <String, String>{'app': _appRef, 'imCore': _coreRef, 'anp': _anpRef},
        'releaseNotesUrl': 'https://awiki.ai/#download',
        'githubReleaseUrl': 'https://awiki.ai/#download',
        'artifacts': artifacts,
        'platforms': platforms,
      })}\n';
  await File('${output.path}/package-manifest.json').writeAsString(encoded);
  if (isComplete) {
    await File('${output.path}/latest.json').writeAsString(encoded);
  }
}

Future<void> _rewriteAggregateManifest(
  Directory output,
  void Function(Map<String, Object?> manifest) mutate,
) async {
  final manifestFile = File('${output.path}/package-manifest.json');
  final decoded = jsonDecode(await manifestFile.readAsString()) as Map;
  final manifest = decoded.map<String, Object?>(
    (key, value) => MapEntry(key.toString(), value),
  );
  mutate(manifest);
  final encoded = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  await manifestFile.writeAsString(encoded);
  await File('${output.path}/latest.json').writeAsString(encoded);
}

ProcessResult _installAggregate({
  required Directory download,
  required Directory dist,
  required List<String> targets,
  required String requestId,
}) {
  final script = File('scripts/package_app.sh').absolute.path;
  return Process.runSync('/bin/bash', <String>[
    '-c',
    r'''
source "$1"
install_aggregate_output \
  "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}"
''',
    'package-output-test',
    script,
    download.path,
    dist.path,
    '1.2.3',
    '42',
    _appRef,
    _coreRef,
    _anpRef,
    targets.join(','),
    requestId,
    'https://awiki.ai/downloads/awiki-me',
    'https://awiki.ai/#download',
  ]);
}

Future<Map<String, String>> _directorySnapshot(Directory directory) async {
  final entries = await directory
      .list(recursive: true, followLinks: false)
      .toList();
  entries.sort((left, right) => left.path.compareTo(right.path));
  final snapshot = <String, String>{};
  for (final entry in entries) {
    final relative = entry.path.substring(directory.path.length + 1);
    if (entry is Directory) {
      snapshot[relative] = 'directory';
    } else if (entry is File) {
      snapshot[relative] = sha256.convert(await entry.readAsBytes()).toString();
    } else {
      snapshot[relative] = 'other';
    }
  }
  return snapshot;
}
