import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const List<String> packageTargetOrder = <String>[
  'android-arm64',
  'macos-arm64',
  'macos-x64',
  'windows-x64',
];

const String artifactMetadataFileName = 'artifact-metadata.json';

class PackageSourceRefs {
  const PackageSourceRefs({
    required this.app,
    required this.imCore,
    required this.anp,
  });

  final String app;
  final String imCore;
  final String anp;

  Map<String, Object?> toJson() => <String, Object?>{
    'app': app,
    'imCore': imCore,
    'anp': anp,
  };

  factory PackageSourceRefs.fromJson(Map<String, Object?> json) {
    return PackageSourceRefs(
      app: _requiredSha(json, 'app'),
      imCore: _requiredSha(json, 'imCore'),
      anp: _requiredSha(json, 'anp'),
    );
  }

  void validate() {
    _validateSha(app, 'app source ref');
    _validateSha(imCore, 'IM Core source ref');
    _validateSha(anp, 'ANP source ref');
  }

  bool matches(PackageSourceRefs other) =>
      app == other.app && imCore == other.imCore && anp == other.anp;
}

class PackageArtifactMetadata {
  const PackageArtifactMetadata({
    required this.target,
    required this.filename,
    required this.signingState,
    required this.version,
    required this.buildNumber,
    required this.sourceRefs,
    this.runtimeFiles = const <String>[],
  });

  final String target;
  final String filename;
  final String signingState;
  final String version;
  final int buildNumber;
  final PackageSourceRefs sourceRefs;
  final List<String> runtimeFiles;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'target': target,
    'filename': filename,
    'signingState': signingState,
    'version': version,
    'buildNumber': buildNumber,
    'sourceRefs': sourceRefs.toJson(),
    if (runtimeFiles.isNotEmpty) 'runtimeFiles': runtimeFiles,
  };

  factory PackageArtifactMetadata.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('artifact metadata must use schemaVersion 1');
    }
    return PackageArtifactMetadata(
      target: _requiredString(json, 'target'),
      filename: _requiredString(json, 'filename'),
      signingState: _requiredString(json, 'signingState'),
      version: _requiredString(json, 'version'),
      buildNumber: _requiredInt(json, 'buildNumber'),
      sourceRefs: PackageSourceRefs.fromJson(
        _requiredObject(json, 'sourceRefs'),
      ),
      runtimeFiles: _optionalStringList(json, 'runtimeFiles'),
    );
  }

  void validate() {
    if (!packageTargetOrder.contains(target)) {
      throw FormatException('unsupported package target: $target');
    }
    _validateVersion(version);
    if (buildNumber <= 0) {
      throw const FormatException('buildNumber must be greater than zero');
    }
    if (filename != _expectedFilename(target, version)) {
      throw FormatException(
        '$target filename must be ${_expectedFilename(target, version)}',
      );
    }
    final expectedSigningState = target == 'windows-x64'
        ? 'unsigned'
        : 'signed';
    if (signingState != expectedSigningState) {
      throw FormatException(
        '$target signingState must be $expectedSigningState',
      );
    }
    if (target == 'windows-x64') {
      const requiredRuntimeFiles = <String>{
        'AWikiMe.exe',
        'awiki_im_core.dll',
        'flutter_windows.dll',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'msvcp140.dll',
        'data',
        'awiki-runtime-files.txt',
        'awiki-runtime-manifest.json',
      };
      final missing = requiredRuntimeFiles.difference(runtimeFiles.toSet());
      if (missing.isNotEmpty) {
        throw FormatException(
          'windows-x64 runtimeFiles is missing: ${missing.join(', ')}',
        );
      }
    }
    sourceRefs.validate();
  }
}

class PackageManifestBuilder {
  const PackageManifestBuilder({
    required this.version,
    required this.buildNumber,
    required this.requestId,
    required this.sourceRefs,
    required this.targets,
    required this.downloadBaseUrl,
    required this.downloadPageUrl,
  });

  final String version;
  final int buildNumber;
  final String requestId;
  final PackageSourceRefs sourceRefs;
  final Set<String> targets;
  final String downloadBaseUrl;
  final String downloadPageUrl;

  Future<Map<String, Object?>> aggregate({
    required Directory artifactsRoot,
    required Directory outputDirectory,
    DateTime? publishedAt,
  }) async {
    _validateInputs();
    if (!await artifactsRoot.exists()) {
      throw FormatException(
        'artifacts root does not exist: ${artifactsRoot.path}',
      );
    }

    final metadataFiles = await artifactsRoot
        .list(recursive: true, followLinks: false)
        .where(
          (entry) =>
              entry is File &&
              _basename(entry.path) == artifactMetadataFileName,
        )
        .cast<File>()
        .toList();
    final metadataByTarget =
        <String, ({PackageArtifactMetadata metadata, File file})>{};
    for (final metadataFile in metadataFiles) {
      final decoded = jsonDecode(await metadataFile.readAsString());
      if (decoded is! Map) {
        throw FormatException(
          '${metadataFile.path} must contain a JSON object',
        );
      }
      final metadata = PackageArtifactMetadata.fromJson(
        decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      metadata.validate();
      if (!targets.contains(metadata.target)) {
        continue;
      }
      if (metadata.version != version || metadata.buildNumber != buildNumber) {
        throw FormatException(
          '${metadata.target} version/build does not match the aggregate request',
        );
      }
      if (!metadata.sourceRefs.matches(sourceRefs)) {
        throw FormatException(
          '${metadata.target} sourceRefs do not match the aggregate request',
        );
      }
      if (metadataByTarget.containsKey(metadata.target)) {
        throw FormatException(
          'duplicate artifact metadata for ${metadata.target}',
        );
      }
      final artifactFile = File(
        '${metadataFile.parent.path}${Platform.pathSeparator}${metadata.filename}',
      );
      if (!await artifactFile.exists()) {
        throw FormatException(
          '${metadata.target} artifact is missing: ${artifactFile.path}',
        );
      }
      metadataByTarget[metadata.target] = (
        metadata: metadata,
        file: artifactFile,
      );
    }

    final missingTargets = targets.difference(metadataByTarget.keys.toSet());
    if (missingTargets.isNotEmpty) {
      throw FormatException(
        'missing artifact metadata for: ${_orderedTargets(missingTargets).join(', ')}',
      );
    }

    await outputDirectory.create(recursive: true);
    final artifactEntries = <String, Object?>{};
    for (final target in _orderedTargets(targets)) {
      final item = metadataByTarget[target]!;
      final sourceFile = item.file;
      final length = await sourceFile.length();
      if (length <= 0) {
        throw FormatException('$target artifact is empty');
      }
      final digest = await sha256.bind(sourceFile.openRead()).first;
      final destination = File(
        '${outputDirectory.path}${Platform.pathSeparator}${item.metadata.filename}',
      );
      if (sourceFile.absolute.path != destination.absolute.path) {
        if (await destination.exists()) {
          await destination.delete();
        }
        await sourceFile.copy(destination.path);
      }
      artifactEntries[target] = <String, Object?>{
        'target': target,
        'filename': item.metadata.filename,
        'sizeBytes': length,
        'sha256': digest.toString(),
        'signingState': item.metadata.signingState,
        if (item.metadata.runtimeFiles.isNotEmpty)
          'runtimeFiles': item.metadata.runtimeFiles,
      };
    }

    final isCompleteRelease =
        targets.length == packageTargetOrder.length &&
        targets.containsAll(packageTargetOrder);
    final manifest = <String, Object?>{
      'schemaVersion': 1,
      'packageSet': isCompleteRelease ? 'release' : 'validation',
      'complete': isCompleteRelease,
      'requestId': requestId,
      'version': version,
      'buildNumber': buildNumber,
      'publishedAt': (publishedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'sourceRefs': sourceRefs.toJson(),
      'releaseNotesUrl': downloadPageUrl,
      'githubReleaseUrl': downloadPageUrl,
      'artifacts': artifactEntries,
      'platforms': _platformEntries(artifactEntries),
    };
    final encoded = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
    await File(
      '${outputDirectory.path}${Platform.pathSeparator}package-manifest.json',
    ).writeAsString(encoded, flush: true);
    final latest = File(
      '${outputDirectory.path}${Platform.pathSeparator}latest.json',
    );
    if (isCompleteRelease) {
      await latest.writeAsString(encoded, flush: true);
    } else if (await latest.exists()) {
      await latest.delete();
    }
    return manifest;
  }

  void _validateInputs() {
    _validateVersion(version);
    if (buildNumber <= 0) {
      throw const FormatException('buildNumber must be greater than zero');
    }
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(requestId)) {
      throw const FormatException('requestId must be a UUID');
    }
    sourceRefs.validate();
    if (targets.isEmpty ||
        targets.any((target) => !packageTargetOrder.contains(target))) {
      throw const FormatException(
        'targets must contain supported package targets',
      );
    }
    final downloadBase = Uri.tryParse(downloadBaseUrl);
    final downloadPage = Uri.tryParse(downloadPageUrl);
    if (downloadBase == null ||
        !downloadBase.hasScheme ||
        (downloadBase.scheme != 'https' && downloadBase.scheme != 'http')) {
      throw const FormatException('downloadBaseUrl must be an http(s) URL');
    }
    if (downloadPage == null ||
        !downloadPage.hasScheme ||
        (downloadPage.scheme != 'https' && downloadPage.scheme != 'http')) {
      throw const FormatException('downloadPageUrl must be an http(s) URL');
    }
  }

  Map<String, Object?> _platformEntries(Map<String, Object?> artifacts) {
    Map<String, Object?> entryFor(String target) {
      final artifact = artifacts[target]! as Map<String, Object?>;
      final filename = artifact['filename']! as String;
      return <String, Object?>{
        'downloadUrl':
            '${_withoutTrailingSlash(downloadBaseUrl)}/$version/$filename',
        'sha256': artifact['sha256'],
      };
    }

    final platforms = <String, Object?>{};
    if (artifacts.containsKey('android-arm64')) {
      platforms['android'] = entryFor('android-arm64');
    }
    final defaultMacTarget = artifacts.containsKey('macos-arm64')
        ? 'macos-arm64'
        : artifacts.containsKey('macos-x64')
        ? 'macos-x64'
        : null;
    if (defaultMacTarget != null) {
      platforms['macos'] = entryFor(defaultMacTarget);
    }
    for (final target in <String>['macos-arm64', 'macos-x64', 'windows-x64']) {
      if (artifacts.containsKey(target)) {
        platforms[target] = entryFor(target);
      }
    }
    return platforms;
  }
}

Future<void> writeArtifactMetadata({
  required PackageArtifactMetadata metadata,
  required File output,
}) async {
  metadata.validate();
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(metadata.toJson())}\n',
    flush: true,
  );
}

Future<void> main(List<String> args) async {
  try {
    if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
      stdout.writeln(_usage);
      return;
    }
    final command = args.first;
    final options = _parseOptions(args.skip(1).toList());
    final refs = PackageSourceRefs(
      app: _option(options, '--app-ref'),
      imCore: _option(options, '--core-ref'),
      anp: _option(options, '--anp-ref'),
    );
    final version = _option(options, '--version');
    final buildNumber = int.tryParse(_option(options, '--build-number'));
    if (buildNumber == null) {
      throw const FormatException('--build-number must be an integer');
    }

    switch (command) {
      case 'metadata':
        await writeArtifactMetadata(
          metadata: PackageArtifactMetadata(
            target: _option(options, '--target'),
            filename: _option(options, '--filename'),
            signingState: _option(options, '--signing-state'),
            version: version,
            buildNumber: buildNumber,
            sourceRefs: refs,
            runtimeFiles: _parseOptionalList(options['--runtime-files']),
          ),
          output: File(_option(options, '--output')),
        );
      case 'aggregate':
        final targets = _parseTargets(_option(options, '--targets'));
        final publishedAtRaw = options['--published-at'];
        final publishedAt = publishedAtRaw == null
            ? null
            : DateTime.tryParse(publishedAtRaw);
        if (publishedAtRaw != null && publishedAt == null) {
          throw const FormatException('--published-at must be ISO-8601');
        }
        await PackageManifestBuilder(
          version: version,
          buildNumber: buildNumber,
          requestId: _option(options, '--request-id'),
          sourceRefs: refs,
          targets: targets,
          downloadBaseUrl: _option(options, '--download-base-url'),
          downloadPageUrl: _option(options, '--download-page-url'),
        ).aggregate(
          artifactsRoot: Directory(_option(options, '--artifacts-root')),
          outputDirectory: Directory(_option(options, '--output-dir')),
          publishedAt: publishedAt,
        );
      default:
        throw FormatException('unknown command: $command');
    }
  } on FormatException catch (error) {
    stderr.writeln('package-manifest: ${error.message}');
    exitCode = 64;
  }
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var index = 0; index < args.length; index += 2) {
    if (index + 1 >= args.length || !args[index].startsWith('--')) {
      throw FormatException('invalid option list near ${args[index]}');
    }
    if (options.containsKey(args[index])) {
      throw FormatException('duplicate option: ${args[index]}');
    }
    options[args[index]] = args[index + 1];
  }
  return options;
}

String _option(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('missing required option: $name');
  }
  return value;
}

Set<String> _parseTargets(String raw) {
  final targets = raw
      .split(RegExp(r'[,\s]+'))
      .where((value) => value.isNotEmpty)
      .toSet();
  if (targets.isEmpty ||
      targets.any((value) => !packageTargetOrder.contains(value))) {
    throw const FormatException('--targets contains an unsupported target');
  }
  return targets;
}

List<String> _parseOptionalList(String? raw) => raw == null
    ? const <String>[]
    : raw
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

List<String> _orderedTargets(Iterable<String> targets) => <String>[
  for (final target in packageTargetOrder)
    if (targets.contains(target)) target,
];

String _expectedFilename(String target, String version) {
  return switch (target) {
    'android-arm64' => 'AWiki-Me-Android-arm64-$version.apk',
    'macos-arm64' => 'AWiki-Me-macOS-arm64-$version.dmg',
    'macos-x64' => 'AWiki-Me-macOS-x64-$version.dmg',
    'windows-x64' => 'AWiki-Me-Windows-x64-$version.exe',
    _ => throw FormatException('unsupported package target: $target'),
  };
}

void _validateVersion(String value) {
  if (!RegExp(
    r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$',
  ).hasMatch(value)) {
    throw FormatException('version must use semantic version format: $value');
  }
}

void _validateSha(String value, String label) {
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(value)) {
    throw FormatException('$label must be a lowercase 40-character SHA');
  }
}

String _requiredSha(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  _validateSha(value, key);
  return value;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$key must be an integer');
  }
  return value;
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('$key must be an object');
  }
  return value.map<String, Object?>(
    (objectKey, objectValue) => MapEntry(objectKey.toString(), objectValue),
  );
}

List<String> _optionalStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const <String>[];
  }
  if (value is! List || value.any((item) => item is! String || item.isEmpty)) {
    throw FormatException('$key must be an array of non-empty strings');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

String _withoutTrailingSlash(String value) =>
    value.endsWith('/') ? value.substring(0, value.length - 1) : value;

const String _usage = '''
Create or aggregate AWiki Me package metadata.

Metadata:
  dart run tool/package_manifest.dart metadata \\
    --target TARGET --filename FILE --signing-state signed|unsigned \\
    --version VERSION --build-number NUMBER \\
    --app-ref SHA --core-ref SHA --anp-ref SHA --output FILE
    [--runtime-files COMMA_SEPARATED_FILES]

Aggregate:
  dart run tool/package_manifest.dart aggregate \\
    --targets TARGETS --artifacts-root DIR --output-dir DIR \\
    --version VERSION --build-number NUMBER --request-id UUID \\
    --app-ref SHA --core-ref SHA --anp-ref SHA \\
    --download-base-url URL --download-page-url URL \\
    [--published-at ISO8601]
''';
