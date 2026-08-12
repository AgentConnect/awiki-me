// [INPUT]: The awiki_im_core path dependency, its Rust source tree, and Linux shared library.
// [OUTPUT]: A verified current libawiki_im_core.so plus a local provenance manifest.
// [POS]: Fail-closed native Core freshness gate for Linux desktop E2E builds.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final checkOnly = arguments.contains('--check-only');
  if (arguments.any((argument) => argument != '--check-only')) {
    stderr.writeln(
      'Usage: dart run tool/ensure_linux_im_core.dart [--check-only]',
    );
    exitCode = 2;
    return;
  }
  try {
    final result = await LinuxImCoreArtifactGuard(
      projectRoot: Directory.current,
    ).ensure(rebuildIfStale: !checkOnly);
    stdout.writeln(jsonEncode(result.toJson()));
  } on LinuxImCoreArtifactException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}

class LinuxImCoreArtifactGuard {
  LinuxImCoreArtifactGuard({required this.projectRoot});

  final Directory projectRoot;

  Future<LinuxImCoreArtifactResult> ensure({bool rebuildIfStale = true}) async {
    if (!Platform.isLinux) {
      throw const LinuxImCoreArtifactException(
        'The Linux IM Core artifact guard requires a Linux host.',
      );
    }
    final layout = await LinuxImCoreLayout.resolve(projectRoot);
    final before = await _inspect(layout);
    if (before.issues.isEmpty) {
      return LinuxImCoreArtifactResult(
        status: 'current',
        rebuilt: false,
        sourceCommit: before.source.commit,
        sourceDigest: before.source.digest,
        artifactSha256: before.artifactSha256!,
      );
    }
    if (!rebuildIfStale) {
      throw LinuxImCoreArtifactException(
        'Linux IM Core artifact provenance is stale: ${before.issues.join(', ')}.',
      );
    }

    stdout.writeln(
      'Linux IM Core artifact is stale (${before.issues.join(', ')}); '
      'rebuilding through scripts/flutter/build-sdk-native.sh --linux-only.',
    );
    final build = await Process.start(
      layout.buildScript.path,
      const <String>['--linux-only'],
      workingDirectory: layout.sourceRepository.path,
      mode: ProcessStartMode.normal,
    );
    await Future.wait(<Future<void>>[
      stdout.addStream(build.stdout),
      stderr.addStream(build.stderr),
    ]);
    if (await build.exitCode != 0) {
      throw const LinuxImCoreArtifactException(
        'The official Linux IM Core SDK build failed.',
      );
    }

    final source = await _sourceSnapshot(layout);
    if (!layout.artifact.existsSync()) {
      throw LinuxImCoreArtifactException(
        'The official build did not create ${layout.artifact.path}.',
      );
    }
    final artifactSha256 = await fileSha256(layout.artifact);
    final manifest = LinuxImCoreProvenance(
      sourceCommit: source.commit,
      sourceDigest: source.digest,
      sourceFileCount: source.fileCount,
      artifactSha256: artifactSha256,
      artifactSize: layout.artifact.lengthSync(),
    );
    layout.manifest.parent.createSync(recursive: true);
    final temporary = File('${layout.manifest.path}.tmp');
    await temporary.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
      flush: true,
    );
    await temporary.rename(layout.manifest.path);

    final after = await _inspect(layout);
    if (after.issues.isNotEmpty) {
      throw LinuxImCoreArtifactException(
        'Linux IM Core artifact remained unverifiable after rebuild: '
        '${after.issues.join(', ')}.',
      );
    }
    return LinuxImCoreArtifactResult(
      status: 'rebuilt',
      rebuilt: true,
      sourceCommit: after.source.commit,
      sourceDigest: after.source.digest,
      artifactSha256: after.artifactSha256!,
    );
  }

  Future<_LinuxImCoreInspection> _inspect(LinuxImCoreLayout layout) async {
    final source = await _sourceSnapshot(layout);
    String? artifactSha256;
    if (layout.artifact.existsSync()) {
      artifactSha256 = await fileSha256(layout.artifact);
    }
    LinuxImCoreProvenance? provenance;
    if (layout.manifest.existsSync()) {
      try {
        provenance = LinuxImCoreProvenance.fromJson(
          jsonDecode(await layout.manifest.readAsString()),
        );
      } on Object {
        provenance = null;
      }
    }
    return _LinuxImCoreInspection(
      source: source,
      artifactSha256: artifactSha256,
      issues: linuxImCoreProvenanceIssues(
        provenance: provenance,
        source: source,
        artifactSha256: artifactSha256,
        artifactSize: layout.artifact.existsSync()
            ? layout.artifact.lengthSync()
            : null,
      ),
    );
  }

  Future<LinuxImCoreSourceSnapshot> _sourceSnapshot(
    LinuxImCoreLayout layout,
  ) async {
    final commit = await _gitOutput(layout.sourceRepository, const <String>[
      'rev-parse',
      'HEAD',
    ]);
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      throw const LinuxImCoreArtifactException(
        'The IM Core source repository HEAD is not auditable.',
      );
    }
    final listed = await _gitOutput(layout.sourceRepository, const <String>[
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '--',
      'Cargo.toml',
      'Cargo.lock',
      'rust-toolchain.toml',
      'crates/im-core',
      'crates/im-core-dart',
      'scripts/flutter',
      'packages/awiki_im_core',
    ]);
    final paths =
        listed
            .split('\n')
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false)
          ..sort();
    if (paths.isEmpty) {
      throw const LinuxImCoreArtifactException(
        'No IM Core build inputs were found.',
      );
    }
    Digest? digest;
    final digestSink = _DigestSink((value) => digest = value);
    final inputSink = sha256.startChunkedConversion(digestSink);
    for (final path in paths) {
      inputSink.add(utf8.encode('$path\u0000'));
      final file = File('${layout.sourceRepository.path}/$path');
      if (!file.existsSync()) {
        inputSink.add(const <int>[0xff]);
        continue;
      }
      await for (final chunk in file.openRead()) {
        inputSink.add(chunk);
      }
      inputSink.add(const <int>[0]);
    }
    inputSink.close();
    return LinuxImCoreSourceSnapshot(
      commit: commit,
      digest: digest!.toString(),
      fileCount: paths.length,
    );
  }
}

class LinuxImCoreLayout {
  const LinuxImCoreLayout({
    required this.sourceRepository,
    required this.artifact,
    required this.buildScript,
    required this.manifest,
  });

  final Directory sourceRepository;
  final File artifact;
  final File buildScript;
  final File manifest;

  static Future<LinuxImCoreLayout> resolve(Directory projectRoot) async {
    final packageConfig = File(
      '${projectRoot.path}/.dart_tool/package_config.json',
    );
    if (!packageConfig.existsSync()) {
      throw const LinuxImCoreArtifactException(
        'Missing .dart_tool/package_config.json; run flutter pub get first.',
      );
    }
    final decoded = jsonDecode(await packageConfig.readAsString());
    final packages = decoded is Map ? decoded['packages'] : null;
    final package = packages is List
        ? packages.whereType<Map>().cast<Map>().where(
            (entry) => entry['name'] == 'awiki_im_core',
          )
        : const Iterable<Map>.empty();
    if (package.length != 1 || package.single['rootUri'] is! String) {
      throw const LinuxImCoreArtifactException(
        'The awiki_im_core path dependency could not be resolved.',
      );
    }
    final packageRoot = Directory.fromUri(
      packageConfig.uri.resolve(package.single['rootUri'] as String),
    );
    final repositoryPath = await _gitOutput(packageRoot, const <String>[
      'rev-parse',
      '--show-toplevel',
    ]);
    final repository = Directory(repositoryPath);
    final buildScript = File(
      '${repository.path}/scripts/flutter/build-sdk-native.sh',
    );
    if (!buildScript.existsSync()) {
      throw const LinuxImCoreArtifactException(
        'Missing official Linux IM Core SDK build script.',
      );
    }
    return LinuxImCoreLayout(
      sourceRepository: repository,
      artifact: File('${packageRoot.path}/linux/lib/libawiki_im_core.so'),
      buildScript: buildScript,
      manifest: File(
        '${projectRoot.path}/.e2e/native-core/linux-im-core-provenance.json',
      ),
    );
  }
}

class LinuxImCoreSourceSnapshot {
  const LinuxImCoreSourceSnapshot({
    required this.commit,
    required this.digest,
    required this.fileCount,
  });

  final String commit;
  final String digest;
  final int fileCount;
}

class LinuxImCoreProvenance {
  const LinuxImCoreProvenance({
    required this.sourceCommit,
    required this.sourceDigest,
    required this.sourceFileCount,
    required this.artifactSha256,
    required this.artifactSize,
  });

  final String sourceCommit;
  final String sourceDigest;
  final int sourceFileCount;
  final String artifactSha256;
  final int artifactSize;

  factory LinuxImCoreProvenance.fromJson(Object? value) {
    if (value is! Map || value['schemaVersion'] != 1) {
      throw const FormatException('Unsupported provenance manifest.');
    }
    return LinuxImCoreProvenance(
      sourceCommit: value['sourceCommit'] as String,
      sourceDigest: value['sourceDigest'] as String,
      sourceFileCount: value['sourceFileCount'] as int,
      artifactSha256: value['artifactSha256'] as String,
      artifactSize: value['artifactSize'] as int,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'sourceCommit': sourceCommit,
    'sourceDigest': sourceDigest,
    'sourceFileCount': sourceFileCount,
    'artifactSha256': artifactSha256,
    'artifactSize': artifactSize,
  };
}

List<String> linuxImCoreProvenanceIssues({
  required LinuxImCoreProvenance? provenance,
  required LinuxImCoreSourceSnapshot source,
  required String? artifactSha256,
  required int? artifactSize,
}) {
  if (provenance == null) return const <String>['manifest_missing_or_invalid'];
  return <String>[
    if (artifactSha256 == null) 'artifact_missing',
    if (provenance.sourceCommit != source.commit) 'source_commit_changed',
    if (provenance.sourceDigest != source.digest ||
        provenance.sourceFileCount != source.fileCount)
      'source_inputs_changed',
    if (artifactSha256 != null && provenance.artifactSha256 != artifactSha256)
      'artifact_hash_changed',
    if (artifactSize != null && provenance.artifactSize != artifactSize)
      'artifact_size_changed',
  ];
}

Future<String> fileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

class LinuxImCoreArtifactResult {
  const LinuxImCoreArtifactResult({
    required this.status,
    required this.rebuilt,
    required this.sourceCommit,
    required this.sourceDigest,
    required this.artifactSha256,
  });

  final String status;
  final bool rebuilt;
  final String sourceCommit;
  final String sourceDigest;
  final String artifactSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'rebuilt': rebuilt,
    'sourceCommit': sourceCommit,
    'sourceDigest': sourceDigest,
    'artifactSha256': artifactSha256,
  };
}

class _LinuxImCoreInspection {
  const _LinuxImCoreInspection({
    required this.source,
    required this.artifactSha256,
    required this.issues,
  });

  final LinuxImCoreSourceSnapshot source;
  final String? artifactSha256;
  final List<String> issues;
}

class _DigestSink implements Sink<Digest> {
  _DigestSink(this.onDigest);

  final void Function(Digest digest) onDigest;

  @override
  void add(Digest data) => onDigest(data);

  @override
  void close() {}
}

class LinuxImCoreArtifactException implements Exception {
  const LinuxImCoreArtifactException(this.message);

  final String message;
}

Future<String> _gitOutput(Directory repository, List<String> arguments) async {
  final result = await Process.run('git', <String>[
    '-C',
    repository.path,
    ...arguments,
  ], runInShell: false);
  if (result.exitCode != 0) {
    throw LinuxImCoreArtifactException(
      'Git failed while inspecting IM Core sources: '
      '${result.stderr.toString().trim()}.',
    );
  }
  return result.stdout.toString().trim();
}
