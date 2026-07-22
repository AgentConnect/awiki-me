import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/package_manifest.dart';

const _appRef = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _coreRef = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _anpRef = 'cccccccccccccccccccccccccccccccccccccccc';
const _requestId = '123e4567-e89b-42d3-a456-426614174000';
const _refs = PackageSourceRefs(app: _appRef, imCore: _coreRef, anp: _anpRef);

void main() {
  late Directory root;
  late Directory artifacts;
  late Directory output;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('awiki_package_manifest_');
    artifacts = Directory('${root.path}/artifacts');
    output = Directory('${root.path}/output');
    await artifacts.create();
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'aggregates four verified artifacts into deterministic manifest shape',
    () async {
      for (final target in packageTargetOrder) {
        await _writeFixture(artifacts, target: target);
      }

      final manifest = await _builder(packageTargetOrder.toSet()).aggregate(
        artifactsRoot: artifacts,
        outputDirectory: output,
        publishedAt: DateTime.utc(2026, 7, 21, 1, 2, 3),
      );

      expect(manifest['schemaVersion'], 1);
      expect(manifest['packageSet'], 'release');
      expect(manifest['complete'], isTrue);
      expect(manifest['requestId'], _requestId);
      expect(manifest['publishedAt'], '2026-07-21T01:02:03.000Z');
      expect(manifest['sourceRefs'], _refs.toJson());
      final resultArtifacts = manifest['artifacts']! as Map<String, Object?>;
      expect(resultArtifacts.keys, packageTargetOrder);
      for (final target in packageTargetOrder) {
        final entry = resultArtifacts[target]! as Map<String, Object?>;
        final copied = File('${output.path}/${entry['filename']}');
        expect(await copied.exists(), isTrue);
        expect(entry['sizeBytes'], await copied.length());
        expect(
          entry['sha256'],
          (await sha256.bind(copied.openRead()).first).toString(),
        );
      }
      expect(
        (resultArtifacts['windows-x64']!
            as Map<String, Object?>)['signingState'],
        'unsigned',
      );
      expect(
        (resultArtifacts['windows-x64']!
            as Map<String, Object?>)['runtimeFiles'],
        containsAll(<String>[
          'vcruntime140.dll',
          'vcruntime140_1.dll',
          'msvcp140.dll',
        ]),
      );
      final platforms = manifest['platforms']! as Map<String, Object?>;
      expect(platforms.keys, <String>[
        'android',
        'macos',
        'macos-arm64',
        'macos-x64',
        'windows-x64',
      ]);
      expect(await File('${output.path}/latest.json').exists(), isTrue);
      expect(
        await File('${output.path}/package-manifest.json').exists(),
        isTrue,
      );
    },
  );

  test('rejects artifact metadata from a different source commit', () async {
    await _writeFixture(
      artifacts,
      target: 'windows-x64',
      refs: const PackageSourceRefs(
        app: 'dddddddddddddddddddddddddddddddddddddddd',
        imCore: _coreRef,
        anp: _anpRef,
      ),
    );

    await expectLater(
      _builder(<String>{
        'windows-x64',
      }).aggregate(artifactsRoot: artifacts, outputDirectory: output),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('sourceRefs do not match'),
        ),
      ),
    );
  });

  test('marks a target subset as validation without latest.json', () async {
    await _writeFixture(artifacts, target: 'windows-x64');
    await output.create();
    await File('${output.path}/latest.json').writeAsString('stale');

    final manifest = await _builder(<String>{'windows-x64'}).aggregate(
      artifactsRoot: artifacts,
      outputDirectory: output,
      publishedAt: DateTime.utc(2026, 7, 21, 1, 2, 3),
    );

    expect(manifest['packageSet'], 'validation');
    expect(manifest['complete'], isFalse);
    expect((manifest['artifacts']! as Map).keys, <String>['windows-x64']);
    expect(await File('${output.path}/package-manifest.json').exists(), isTrue);
    expect(await File('${output.path}/latest.json').exists(), isFalse);
  });

  test('rejects an incomplete selected target set', () async {
    await _writeFixture(artifacts, target: 'android-arm64');

    await expectLater(
      _builder(<String>{
        'android-arm64',
        'windows-x64',
      }).aggregate(artifactsRoot: artifacts, outputDirectory: output),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('missing artifact metadata for: windows-x64'),
        ),
      ),
    );
  });
}

PackageManifestBuilder _builder(Set<String> targets) => PackageManifestBuilder(
  version: '1.2.3',
  buildNumber: 42,
  requestId: _requestId,
  sourceRefs: _refs,
  targets: targets,
  downloadBaseUrl: 'https://awiki.ai/downloads/awiki-me',
  downloadPageUrl: 'https://awiki.ai/#download',
);

Future<void> _writeFixture(
  Directory artifacts, {
  required String target,
  PackageSourceRefs refs = _refs,
}) async {
  final directory = Directory('${artifacts.path}/artifact-$target');
  await directory.create(recursive: true);
  final filename = switch (target) {
    'android-arm64' => 'AWiki-Me-Android-arm64-1.2.3.apk',
    'macos-arm64' => 'AWiki-Me-macOS-arm64-1.2.3.dmg',
    'macos-x64' => 'AWiki-Me-macOS-x64-1.2.3.dmg',
    'windows-x64' => 'AWiki-Me-1.2.3-windows-x64.exe',
    _ => throw StateError(target),
  };
  await File(
    '${directory.path}/$filename',
  ).writeAsBytes(utf8.encode('fixture-$target'));
  await writeArtifactMetadata(
    metadata: PackageArtifactMetadata(
      target: target,
      filename: filename,
      signingState: target == 'windows-x64' ? 'unsigned' : 'signed',
      version: '1.2.3',
      buildNumber: 42,
      sourceRefs: refs,
      runtimeFiles: target == 'windows-x64'
          ? const <String>[
              'AWikiMe.exe',
              'awiki_im_core.dll',
              'flutter_windows.dll',
              'vcruntime140.dll',
              'vcruntime140_1.dll',
              'msvcp140.dll',
              'data',
              'awiki-runtime-files.txt',
              'awiki-runtime-manifest.json',
            ]
          : const <String>[],
    ),
    output: File('${directory.path}/$artifactMetadataFileName'),
  );
}
