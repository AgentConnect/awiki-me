import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/app/e2e_fault_hooks.dart';
import '../../e2e/runtime_control/invocation.dart';
import '../../e2e/runtime_control/fault_controller.dart';
import '../../e2e/app_artifact_spec.dart';
import '../../../tool/isolated_e2e_app_builder.dart';
import '../../e2e/host_platform.dart';

void main() {
  test(
    'phase aliases restore exactly the same cached bytes without a compiler',
    () async {
      final root = await Directory.systemTemp.createTemp('alias-cache-');
      addTearDown(() => root.delete(recursive: true));
      final cache = isolatedArtifactCacheDirectory(
        projectRoot: root,
        platform: IsolatedE2eAppPlatform.windows,
        processArchitecture: 'x86_64',
        compileKey: 'a' * 64,
      );
      final app = await Directory('${cache.path}/app').create(recursive: true);
      await File('${app.path}/AWikiMe.exe').writeAsBytes([0x4d, 0x5a, 1, 2, 3]);
      final digest = await directorySha256(app);
      await File('${cache.path}/manifest.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'fingerprint': 'a' * 64,
          'bundleId': 'ai.awiki.test.shared',
          'artifactSha256': digest,
        }),
      );
      final hashes = <String>[];
      final manifests = E2eAppArtifactSpecManifest.load(
        File('tests/e2e/app_artifact_specs.json'),
      );
      for (final name in ['recovery-crash-a', 'recovery-crash-b']) {
        final artifact = await IsolatedE2eAppBuilder().build(
          IsolatedE2eAppBuildRequest(
            projectRoot: root,
            name: name,
            target: manifests.requireSpec(name).target,
            stateRoot: Directory('${root.path}/.e2e/state'),
            workRoot: Directory('${root.path}/.e2e/work/$name'),
            artifactRoot: Directory('${root.path}/.e2e/artifacts'),
            bundleId: 'ai.awiki.test.shared',
            platform: IsolatedE2eAppPlatform.windows,
            flutterBin: 'compiler-must-not-run',
            dartDefines: [],
            dryRun: false,
          ),
          precomputedIdentity: (
            compileKey: 'a' * 64,
            compileKeyPayload: {},
            provenance: {'worktreeDirty': false},
          ),
        );
        expect(artifact.cacheHit, isTrue);
        expect(
          artifact.appPath.replaceAll('\\', '/'),
          app.path.replaceAll('\\', '/'),
        );
        hashes.add(artifact.artifactSha256);
        expect(
          File('${root.path}/.e2e/artifacts/$name.json').existsSync(),
          isTrue,
        );
      }
      expect(hashes, [digest, digest]);
    },
    skip: !Platform.isWindows,
  );
  E2eInvocation plan(String artifact) => E2eInvocation(
    artifact: artifact,
    runId: 'run-1',
    scenario: 'recovery',
    invocationId: 'invocation-1',
    platform: Platform.operatingSystem,
    caseIds: const ['CASE-001'],
    artifactSha256: 'a' * 64,
  );
  test('runtime phase is immutable, strict and bound to artifact', () {
    final original = plan('recovery-crash-a');
    expect(E2eInvocation.fromJson(original.toJson()).mode.phase, 'crash_a');
    expect(() => original.caseIds.add('OTHER'), throwsUnsupportedError);
    for (final invalid in [
      {...original.toJson(), 'phase': 'crash_b'},
      {...original.toJson(), 'role': 'admin'},
      {...original.toJson(), 'unknown': 'ignored'},
      {
        ...original.toJson(),
        'caseIds': ['CASE-001', 'CASE-001'],
      },
      {...original.toJson(), 'schemaVersion': 2},
    ]) {
      expect(() => E2eInvocation.fromJson(invalid), throwsFormatException);
    }
    expect(() => original.validateEnvironment({}), throwsFormatException);
    original.validateEnvironment({
      'AWIKI_E2E_RUN_ID': 'run-1',
      'AWIKI_E2E_SCENARIO': 'recovery',
      'AWIKI_E2E_CASE_IDS': 'CASE-001',
    });
  });
  test('private invocation roundtrip rejects replay and editing', () async {
    final dir = await Directory.systemTemp.createTemp('invocation-unit-');
    addTearDown(() => dir.delete(recursive: true));
    final invocation = plan('recovery-crash-a');
    final file = File('${dir.path}/plan.json');
    invocation.write(file);
    final env = {
      invocationPathEnvironment: file.path,
      invocationDigestEnvironment: invocation.digest,
      'AWIKI_E2E_RUN_ID': 'run-1',
      'AWIKI_E2E_SCENARIO': 'recovery',
      'AWIKI_E2E_CASE_IDS': 'CASE-001',
    };
    expect(
      E2eInvocation.load(env, family: 'recovery')!.digest,
      invocation.digest,
    );
    expect(
      () => E2eInvocation.load({...env, 'AWIKI_E2E_RUN_ID': 'old'}),
      throwsFormatException,
    );
    expect(
      () => E2eInvocation.load({...env, invocationDigestEnvironment: 'bad'}),
      throwsFormatException,
    );
    expect(
      () => E2eInvocation.load(env, family: 'restart'),
      throwsFormatException,
    );
    final expired = E2eInvocation.fromJson({
      ...invocation.toJson(),
      'deadlineUnixMs': 1,
    });
    final expiredFile = File('${dir.path}/expired.json');
    expired.write(expiredFile);
    expect(
      () => E2eInvocation.load({
        ...env,
        invocationPathEnvironment: expiredFile.path,
        invocationDigestEnvironment: expired.digest,
      }),
      throwsFormatException,
    );
    expect(() => invocation.write(file), throwsFormatException);
  });
  test('Release cannot install handlers even with the E2E flag', () async {
    for (final e2e in [false, true]) {
      final registry = E2eFaultHookRegistry(
        enabled: allowE2eFaultHooks(releaseMode: true, e2eEnabled: e2e),
      );
      expect(
        () => registry.install((_) async => E2eFaultAction.throwError),
        throwsStateError,
      );
      expect(
        await registry.hit(E2eFaultCheckpoint.identityAfterProductDelete),
        E2eFaultAction.continueExecution,
      );
    }
    expect(allowE2eFaultHooks(releaseMode: false, e2eEnabled: false), isFalse);
  });
  test('unarmed checkpoints do not invoke a controller', () async {
    var calls = 0;
    final registry = E2eFaultHookRegistry(enabled: true);
    expect(
      registry.handles(E2eFaultCheckpoint.identityAfterProductDelete),
      isFalse,
    );
    registry.install((_) async {
      calls++;
      return E2eFaultAction.throwError;
    }, checkpoints: {E2eFaultCheckpoint.identityAfterProductDelete});
    expect(
      registry.handles(E2eFaultCheckpoint.recoveryBeforeProductReset),
      isFalse,
    );
    expect(
      await registry.hit(E2eFaultCheckpoint.recoveryBeforeProductReset),
      E2eFaultAction.continueExecution,
    );
    expect(calls, 0);
    registry.clear();
    expect(
      registry.handles(E2eFaultCheckpoint.identityAfterProductDelete),
      isFalse,
    );
  });
  test(
    'old exception/stop semantics remain distinct and execute once',
    () async {
      final recovery = E2eFaultController(phase: 'crash_a');
      expect(
        await recovery.hit(E2eFaultCheckpoint.identityAfterProductDelete),
        E2eFaultAction.continueExecution,
      );
      expect(
        await recovery.hit(E2eFaultCheckpoint.recoveryBeforeProductReset),
        E2eFaultAction.stopBeforeReset,
      );
      await expectLater(
        recovery.hit(E2eFaultCheckpoint.recoveryBeforeProductReset),
        throwsStateError,
      );
      expect(
        await E2eFaultController(
          phase: 'identity_deletion_a',
        ).hit(E2eFaultCheckpoint.identityAfterProductDelete),
        E2eFaultAction.throwError,
      );
    },
  );
  test(
    'phase variants share compile payload; role native identities stay isolated',
    () {
      final manifest = E2eAppArtifactSpecManifest.load(
        File('tests/e2e/app_artifact_specs.json'),
      );
      const host = E2eHostPlatform(
        operatingSystem: 'windows',
        processArchitecture: 'x86_64',
        hardwareArchitecture: 'x86_64',
        translated: false,
      );
      Map<String, Object?> key(String name) {
        final spec = manifest.requireSpec(name);
        final root = Directory.current;
        final request = IsolatedE2eAppBuildRequest(
          projectRoot: root,
          name: name,
          target: spec.target,
          stateRoot: Directory('${root.path}/.e2e/state'),
          workRoot: Directory('${root.path}/.e2e/work'),
          artifactRoot: Directory('${root.path}/.e2e/artifacts'),
          bundleId: spec.bundleId,
          platform: IsolatedE2eAppPlatform.windows,
          flutterBin: 'flutter',
          dartDefines: spec.dartDefines,
          dryRun: true,
        );
        return isolatedCompileKeyPayload(
          request: request,
          hostPlatform: host,
          sourceDigest: 'source',
          pubspecLockSha256: 'lock',
          pubspecOverridesSha256: 'override',
          pathDependencySha256: 'dependency',
          nativeCoreSha256: 'core',
          nativeCoreProvenanceSha256: 'provenance',
          flutterIdentity: {'revision': 'flutter'},
          rustcVersion: 'rustc',
        );
      }

      for (final group in [
        [
          'recovery-main',
          'recovery-crash-a',
          'recovery-crash-b',
          'recovery-fresh-restart',
          'recovery-registration-resume-a',
          'recovery-registration-resume-b',
        ],
        ['identity-deletion-a', 'identity-deletion-b'],
        ['restart-a', 'restart-b', 'restart-c'],
      ]) {
        for (final name in group) {
          expect(key(name), key(group.first));
        }
      }
      expect(key('admin'), isNot(key('joiner')));
      expect(
        plan('recovery-crash-a').digest,
        isNot(plan('recovery-crash-b').digest),
      );
    },
  );
}
