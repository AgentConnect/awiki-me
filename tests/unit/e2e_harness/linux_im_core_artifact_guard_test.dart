// [INPUT]: Current IM Core source/artifact identity and recorded provenance.
// [OUTPUT]: Fail-closed freshness decisions for Linux desktop E2E.
// [POS]: Unit contract for rejecting stale native Core artifacts before E2E.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ensure_linux_im_core.dart';

void main() {
  final layout = LinuxImCoreLayout(
    sourceRepository: Directory('/workspace/core'),
    artifact: File(
      '/workspace/core/packages/awiki_im_core/linux/lib/libawiki_im_core.so',
    ),
    buildScript: File('/workspace/core/scripts/flutter/build-sdk-native.sh'),
    manifest: File(
      '/workspace/app/.e2e/native-core/linux-im-core-provenance.json',
    ),
  );

  test('Debug CI keeps the published registry build and locked dependencies', () {
    final plan = linuxImCoreBuildPlan(
      layout,
      debugBuild: true,
      environment: const <String, String>{'AWIKI_RELEASE_REGISTRY': '1'},
    );
    expect(plan.command, <String>[
      'python3',
      '/workspace/core/scripts/release/registry-build.py',
      '--',
      'cargo',
      'build',
      '-p',
      'im-core-dart',
      '--locked',
      '--no-default-features',
      '--features',
      'blocking,sqlite,http,linux,group-e2ee,secure-direct,identity-native-anp',
    ]);
    expect(plan.command, isNot(contains('--release')));
    expect(
      plan.artifactToCopy!.path,
      '/workspace/core/target/debug/libawiki_im_core.so',
    );
  });

  test(
    'Debug artifact follows the Cargo target directory used by its build',
    () {
      for (final target in <String>['build/native', '/tmp/core-cache']) {
        final plan = linuxImCoreBuildPlan(
          layout,
          debugBuild: true,
          environment: <String, String>{'CARGO_TARGET_DIR': target},
        );
        expect(plan.command.take(5), <String>[
          'cargo',
          'build',
          '-p',
          'im-core-dart',
          '--locked',
        ]);
        final root = target.startsWith('/')
            ? target
            : '/workspace/core/$target';
        expect(plan.artifactToCopy!.path, '$root/debug/libawiki_im_core.so');
      }
    },
  );

  test(
    'Default SDK rebuild retains the owning native and codegen entrypoint',
    () {
      final plan = linuxImCoreBuildPlan(
        layout,
        debugBuild: false,
        environment: const <String, String>{'AWIKI_RELEASE_REGISTRY': '1'},
      );
      expect(plan.command, <String>[
        '/workspace/core/scripts/flutter/build-sdk-native.sh',
        '--linux-only',
      ]);
      expect(plan.artifactToCopy, isNull);
    },
  );

  const source = LinuxImCoreSourceSnapshot(
    commit: '1111111111111111111111111111111111111111',
    digest: 'source-digest',
    fileCount: 42,
  );
  const current = LinuxImCoreProvenance(
    sourceCommit: '1111111111111111111111111111111111111111',
    sourceDigest: 'source-digest',
    sourceFileCount: 42,
    artifactSha256: 'artifact-digest',
    artifactSize: 1024,
  );

  test('An existing library still requires a valid provenance manifest', () {
    expect(
      linuxImCoreProvenanceIssues(
        provenance: null,
        source: source,
        artifactSha256: 'artifact-digest',
        artifactSize: 1024,
      ),
      contains('manifest_missing_or_invalid'),
    );
  });

  test('accepts a library bound to the current source and artifact hash', () {
    expect(
      linuxImCoreProvenanceIssues(
        provenance: current,
        source: source,
        artifactSha256: 'artifact-digest',
        artifactSize: 1024,
      ),
      isEmpty,
    );
  });

  test('rejects stale source identity even when the library still exists', () {
    expect(
      linuxImCoreProvenanceIssues(
        provenance: current,
        source: const LinuxImCoreSourceSnapshot(
          commit: '2222222222222222222222222222222222222222',
          digest: 'new-source-digest',
          fileCount: 43,
        ),
        artifactSha256: 'artifact-digest',
        artifactSize: 1024,
      ),
      containsAll(<String>['source_commit_changed', 'source_inputs_changed']),
    );
  });

  test('rejects a replaced or missing shared library', () {
    expect(
      linuxImCoreProvenanceIssues(
        provenance: current,
        source: source,
        artifactSha256: 'old-artifact-digest',
        artifactSize: 900,
      ),
      containsAll(<String>['artifact_hash_changed', 'artifact_size_changed']),
    );
    expect(
      linuxImCoreProvenanceIssues(
        provenance: current,
        source: source,
        artifactSha256: null,
        artifactSize: null,
      ),
      contains('artifact_missing'),
    );
  });
}
