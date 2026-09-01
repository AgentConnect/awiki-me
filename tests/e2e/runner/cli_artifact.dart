// [INPUT]: An auditable awiki-cli Rust checkout and its stable release config.
// [OUTPUT]: A content-addressed, versioned CLI artifact isolated from shared Cargo targets.
// [POS]: E2E build-provenance boundary; performs no backend or identity operations.

part of '../runner.dart';

class VersionedCliArtifact {
  const VersionedCliArtifact({
    required this.binary,
    required this.sourceRef,
    required this.version,
  });

  final File binary;
  final String sourceRef;
  final String version;
}

String stableCliVersionFromReleaseConfig(String contents) {
  Object? decoded;
  try {
    decoded = jsonDecode(contents);
  } on Object {
    throw E2eFailure('awiki-cli release config is not valid JSON.');
  }
  final channels = decoded is Map ? decoded['channels'] : null;
  final stable = channels is Map ? channels['stable'] : null;
  final version = stable is Map ? stable['version'] : null;
  if (version is! String || !_isCanonicalNumericVersion(version)) {
    throw E2eFailure(
      'awiki-cli stable release config must contain a canonical numeric version.',
    );
  }
  return version;
}

Future<VersionedCliArtifact> prepareVersionedCliArtifact({
  required Directory root,
  required String rustRepoPath,
  required String? expectedSourceRef,
  required DesktopCommandRunner commands,
}) async {
  final repo = Directory(_resolvePath(root, rustRepoPath));
  final cargoManifest = File('${repo.path}/Cargo.toml');
  final releaseConfig = File(
    '${repo.path}/scripts/release/cli/release-config.json',
  );
  if (!cargoManifest.existsSync() || !releaseConfig.existsSync()) {
    throw E2eFailure(
      'The awiki-cli Rust checkout is missing Cargo.toml or its stable release config.',
    );
  }

  final sourceResult = await commands.captureResult(
    'git',
    const <String>['rev-parse', 'HEAD'],
    workingDirectory: repo,
    timeout: const Duration(minutes: 1),
  );
  final sourceRef = sourceResult.output.trim().toLowerCase();
  if (!isAuditableGitSha(sourceRef)) {
    throw E2eFailure(
      'The awiki-cli checkout did not report an auditable HEAD.',
    );
  }
  final expected = expectedSourceRef?.trim().toLowerCase();
  if (expected != null && expected.isNotEmpty && expected != sourceRef) {
    throw E2eFailure(
      'cliPeer.sourceRef does not match the selected awiki-cli checkout.',
    );
  }

  final version = stableCliVersionFromReleaseConfig(
    releaseConfig.readAsStringSync(),
  );
  final targetDir = Directory(
    '${root.path}/.e2e/cli-build-cache/$sourceRef/$version/target',
  )..createSync(recursive: true);
  final environment = <String, String>{
    'AWIKI_CLI_COMMIT': sourceRef,
    'AWIKI_CLI_VERSION': version,
    'CARGO_TARGET_DIR': targetDir.path,
  };
  await commands.run(
    'cargo',
    const <String>[
      'build',
      '--locked',
      '-p',
      'awiki-cli',
      '--bin',
      'awiki-cli',
    ],
    workingDirectory: repo,
    environment: environment,
    timeout: const Duration(minutes: 20),
  );
  final binary = File(
    '${targetDir.path}/debug/${Platform.isWindows ? 'awiki-cli.exe' : 'awiki-cli'}',
  );
  if (!binary.existsSync()) {
    throw E2eFailure('Versioned awiki-cli build did not produce its binary.');
  }
  return VersionedCliArtifact(
    binary: binary,
    sourceRef: sourceRef,
    version: version,
  );
}
