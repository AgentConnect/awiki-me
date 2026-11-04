import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/app/e2e_build_metadata.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import '../../e2e/app_artifact_spec.dart';
import '../../e2e/host_platform.dart';
import '../../e2e/runtime_control/invocation.dart';
import '../../e2e/runtime_control/shared_host_contract.dart';
import '../../e2e/flutter/shared_desktop_host.dart' as implementation;
import '../../../tool/isolated_e2e_app_builder.dart';
import '../../../tool/prepare_e2e_app_artifacts.dart' as prepare;

E2eInvocation invocation(String name) => E2eInvocation(
  artifact: name,
  runId: 'unit-run',
  scenario: 'unit-scenario',
  invocationId: 'invocation-$name',
  platform: Platform.operatingSystem,
  caseIds: const ['CASE-001'],
  artifactSha256: 'a' * 64,
);

Map<String, Object?> payload(E2eAppArtifactSpec spec, Directory root) =>
    isolatedCompileKeyPayload(
      request: IsolatedE2eAppBuildRequest(
        projectRoot: root,
        name: spec.name,
        target: spec.target,
        stateRoot: Directory('${root.path}/.e2e/state'),
        workRoot: Directory('${root.path}/.e2e/work'),
        artifactRoot: Directory('${root.path}/.e2e/artifacts'),
        bundleId: spec.bundleId,
        platform: IsolatedE2eAppPlatform.windows,
        flutterBin: 'compiler-must-not-run',
        dartDefines: spec.dartDefines,
        dryRun: true,
      ),
      hostPlatform: const E2eHostPlatform(
        operatingSystem: 'windows',
        processArchitecture: 'x86_64',
        hardwareArchitecture: 'x86_64',
        translated: false,
      ),
      sourceDigest: 'one-common-source',
      pubspecLockSha256: 'lock',
      pubspecOverridesSha256: 'overrides',
      pathDependencySha256: 'dependency',
      nativeCoreSha256: 'native-core',
      nativeCoreProvenanceSha256: 'native-provenance',
      flutterIdentity: {'revision': 'flutter'},
      rustcVersion: 'rustc',
    );

void main() {
  final specs = E2eAppArtifactSpecManifest.load(
    File('tests/e2e/app_artifact_specs.json'),
  );
  test(
    'batch preparation computes only A and B despite different runtime roots',
    () async {
      final root = Directory.current;
      final requests = [
        for (final spec in specs.specs.values)
          IsolatedE2eAppBuildRequest(
            projectRoot: root,
            name: spec.name,
            target: spec.target,
            stateRoot: Directory('${root.path}/.e2e/state/${spec.name}'),
            workRoot: Directory('${root.path}/.e2e/work/${spec.name}'),
            artifactRoot: Directory('${root.path}/.e2e/artifacts'),
            bundleId: spec.bundleId,
            platform: IsolatedE2eAppPlatform.windows,
            flutterBin: 'compiler-must-not-run',
            dartDefines: spec.dartDefines,
            consumerSuites: spec.consumerSuites,
            dryRun: true,
          ),
      ];
      var computations = 0;
      final identities = await prepare.computePrepareBuildIdentities(requests, (
        request,
      ) async {
        computations++;
        return (
          compileKey: sharedHostSlot(request.name),
          compileKeyPayload: <String, Object?>{},
          provenance: <String, Object?>{},
        );
      });
      expect(computations, 2);
      expect(identities, hasLength(specs.specs.length));
      for (var i = 0; i < requests.length; i++) {
        expect(identities[i].compileKey, sharedHostSlot(requests[i].name));
      }
    },
  );
  test(
    'all declared scenarios use exactly two complete compile identities',
    () {
      expect(specs.specs.keys.toSet(), sharedHostEntries.keys.toSet());
      final keys = {
        for (final spec in specs.specs.values)
          jsonEncode(payload(spec, Directory.current)),
      };
      expect(keys, hasLength(2));
      expect(specs.specs.values.map((s) => s.target).toSet(), {
        sharedDesktopHostTarget,
      });
      expect(
        specs.specs.values
            .where((s) => sharedHostSlot(s.name) == 'b')
            .map((s) => s.name),
        ['joiner'],
      );
      final paths = {
        for (final spec in specs.specs.values)
          IsolatedE2eAppBuildRequest(
            projectRoot: Directory.current,
            name: spec.name,
            target: spec.target,
            stateRoot: Directory('.e2e/state'),
            workRoot: Directory('.e2e/work'),
            artifactRoot: Directory('.e2e/artifacts'),
            bundleId: spec.bundleId,
            platform: IsolatedE2eAppPlatform.windows,
            flutterBin: 'flutter',
            dartDefines: spec.dartDefines,
            dryRun: true,
          ).windowsSourceProject.path,
      };
      expect(paths, hasLength(2));
      final a = payload(specs.requireSpec('admin'), Directory.current);
      final b = payload(specs.requireSpec('joiner'), Directory.current);
      String digest(Map<String, Object?> value) =>
          sha256.convert(utf8.encode(jsonEncode(value))).toString();
      expect(companionSharedHostCompileKeys(a), {digest(b)});
      expect(companionSharedHostCompileKeys(b), {digest(a)});
      // Former messaging's explicit compile define equals the product default.
      expect(defaultMultiDeviceDeviceRevokeEnabled, isTrue);
    },
  );
  test(
    'one invocation selects one handler and rejects the other native slot',
    () {
      final actual = implementation.sharedDesktopHostHandlers(
        invocation('admin'),
      );
      expect(actual.keys.toSet(), SharedHostEntry.values.toSet());
      for (final name in specs.specs.keys) {
        final called = <SharedHostEntry>[];
        final handlers = {
          for (final entry in SharedHostEntry.values)
            entry: () => called.add(entry),
        };
        dispatchSharedHost(
          artifact: name,
          compiledSlot: sharedHostSlot(name),
          handlers: handlers,
        );
        expect(called, [sharedHostEntry(name)]);
        expect(
          () => dispatchSharedHost(
            artifact: name,
            compiledSlot: sharedHostSlot(name) == 'a' ? 'b' : 'a',
            handlers: handlers,
          ),
          throwsFormatException,
        );
        expect(called, hasLength(1));
      }
      expect(() => sharedHostEntry('unknown-scenario'), throwsFormatException);
    },
  );
  test(
    'manifest rejects a third build, extra define, old target or unknown scenario',
    () async {
      final root = await Directory.systemTemp.createTemp('two-host-contract-');
      addTearDown(() => root.delete(recursive: true));
      final original = File(
        'tests/e2e/app_artifact_specs.json',
      ).readAsStringSync();
      final file = File('${root.path}/specs.json');
      for (final change in <void Function(Map)>[
        (a) => a['bundleId'] = 'ai.awiki.third',
        (a) => a['target'] =
            'integration_test/registration_domain_discovery_test.dart',
        (a) => a['dartDefines'] = [
          'AWIKI_E2E=true',
          'AWIKI_E2E_HOST_SLOT=a',
          'AWIKI_RELEASE=1015',
        ],
        (a) => a['name'] = 'third-program',
      ]) {
        final object = jsonDecode(original) as Map;
        change((object['artifacts'] as List).first as Map);
        file.writeAsStringSync(jsonEncode(object));
        expect(
          () => E2eAppArtifactSpecManifest.load(file),
          throwsFormatException,
        );
      }
      final missingContract = jsonDecode(original) as Map;
      missingContract.remove('sharedHostContractVersion');
      file.writeAsStringSync(jsonEncode(missingContract));
      expect(
        () => E2eAppArtifactSpecManifest.load(file),
        throwsFormatException,
      );
      expect(
        () => validateSharedHostBuild(
          name: 'avatars',
          target: sharedDesktopHostTarget,
          bundleId: 'ai.awiki.third',
          defines: sharedHostDefines('a'),
        ),
        throwsFormatException,
      );
      expect(
        () => validateSharedHostExecutionEnvironment({
          'AWIKI_E2E_USE_FLUTTER_TEST': '1',
        }),
        throwsFormatException,
      );
      validateSharedHostExecutionEnvironment({});
      await expectLater(
        IsolatedE2eAppBuilder().build(
          IsolatedE2eAppBuildRequest(
            projectRoot: root,
            name: 'avatars',
            target: sharedDesktopHostTarget,
            bundleId: 'ai.awiki.third',
            dartDefines: sharedHostDefines('a'),
            stateRoot: Directory('${root.path}/.e2e/state'),
            workRoot: Directory('${root.path}/.e2e/work'),
            artifactRoot: Directory('${root.path}/.e2e/artifacts'),
            platform: IsolatedE2eAppPlatform.windows,
            flutterBin: 'compiler-must-not-run',
            dryRun: false,
          ),
        ),
        throwsA(
          isA<IsolatedE2eAppBuildException>().having(
            (e) => e.message,
            'two-host guard',
            contains('two declared host builds'),
          ),
        ),
      );
    },
  );
  test(
    'legacy release override stays test-only and preserves default metadata',
    () {
      final release = E2eBuildMetadata(enabled: false);
      expect(() => release.useLegacyHostedRelease(), throwsStateError);
      expect(release.releaseLine('0815'), '0815');
      final test = E2eBuildMetadata(enabled: true);
      expect(test.releaseLine('0815'), '0815');
      test.useLegacyHostedRelease();
      expect(test.releaseLine('0815'), '1015');
    },
  );
  test(
    'every logical alias restores one of two physical cached bundles without compilation',
    () async {
      final root = await Directory.systemTemp.createTemp('two-host-cache-');
      addTearDown(() => root.delete(recursive: true));
      final identities = <String, IsolatedE2eAppBuildIdentity>{};
      for (final name in ['admin', 'joiner']) {
        final spec = specs.requireSpec(name);
        final data = payload(spec, root);
        final key = sha256.convert(utf8.encode(jsonEncode(data))).toString();
        identities[sharedHostSlot(name)] = (
          compileKey: key,
          compileKeyPayload: data,
          provenance: {'worktreeDirty': false},
        );
        final cache = isolatedArtifactCacheDirectory(
          projectRoot: root,
          platform: IsolatedE2eAppPlatform.windows,
          processArchitecture: 'x86_64',
          compileKey: key,
        );
        final app = await Directory(
          '${cache.path}/app',
        ).create(recursive: true);
        await File(
          '${app.path}/AWikiMe.exe',
        ).writeAsBytes([0x4d, 0x5a, name == 'admin' ? 1 : 2]);
        final digest = await directorySha256(app);
        await File('${cache.path}/manifest.json').writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'fingerprint': key,
            'bundleId': spec.bundleId,
            'artifactSha256': digest,
          }),
        );
      }
      final appPaths = <String>{}, hashes = <String>{};
      for (final spec in specs.specs.values) {
        final artifact = await IsolatedE2eAppBuilder().build(
          IsolatedE2eAppBuildRequest(
            projectRoot: root,
            name: spec.name,
            target: spec.target,
            stateRoot: Directory('${root.path}/.e2e/state/${spec.name}'),
            workRoot: Directory('${root.path}/.e2e/work'),
            artifactRoot: Directory('${root.path}/.e2e/artifacts'),
            bundleId: spec.bundleId,
            platform: IsolatedE2eAppPlatform.windows,
            flutterBin: 'compiler-must-not-run',
            dartDefines: spec.dartDefines,
            dryRun: false,
          ),
          precomputedIdentity: identities[sharedHostSlot(spec.name)],
        );
        expect(artifact.cacheHit, isTrue);
        appPaths.add(artifact.appPath);
        hashes.add(artifact.artifactSha256);
      }
      expect(appPaths, hasLength(2));
      expect(hashes, hasLength(2));
    },
    skip: !Platform.isWindows,
  );
}
