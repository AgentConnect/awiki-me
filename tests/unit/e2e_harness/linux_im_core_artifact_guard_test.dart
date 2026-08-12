// [INPUT]: Current IM Core source/artifact identity and recorded provenance.
// [OUTPUT]: Fail-closed freshness decisions for Linux desktop E2E.
// [POS]: Unit contract for rejecting stale native Core artifacts before E2E.

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/ensure_linux_im_core.dart';

void main() {
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
