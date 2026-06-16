import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromRoots builds the expected awiki-me im-core layout', () {
    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: '/app/support/',
      cacheRoot: '/cache/',
      tempRoot: '/tmp/',
    );

    expect(layout.identityRootDir, '/app/support/awiki-me/im-core/identities');
    expect(
      layout.registryPath,
      '/app/support/awiki-me/im-core/identities/registry.json',
    );
    expect(
      layout.defaultIdentityPath,
      '/app/support/awiki-me/im-core/identities/default',
    );
    expect(
      layout.sqlitePath,
      '/app/support/awiki-me/im-core/state/im_core.sqlite',
    );
    expect(layout.cacheDir, '/cache/awiki-me/im-core');
    expect(layout.tempDir, '/tmp/awiki-me/im-core');

    final corePaths = layout.toCorePaths();
    expect(corePaths, isA<core.AwikiImCorePaths>());
    expect(corePaths.identityRootDir, layout.identityRootDir);
    expect(corePaths.sqlitePath, layout.sqlitePath);
  });

  test(
    'ensureDirectories creates identity state cache and temp directories',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_me_paths_test_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });

      final layout = AwikiImCorePathLayout.fromRoots(
        appSupportRoot: '${root.path}/support',
        cacheRoot: '${root.path}/cache',
        tempRoot: '${root.path}/tmp',
      );

      await layout.ensureDirectories();

      expect(await Directory(layout.identityRootDir).exists(), isTrue);
      expect(
        await Directory('${root.path}/support/awiki-me/im-core/state').exists(),
        isTrue,
      );
      expect(await Directory(layout.cacheDir).exists(), isTrue);
      expect(await Directory(layout.tempDir).exists(), isTrue);
    },
  );

  test('archives pre-owner-identity local state before SDK open', () async {
    final root = await Directory.systemTemp.createTemp('awiki_me_paths_test_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: '${root.path}/support',
      cacheRoot: '${root.path}/cache',
      tempRoot: '${root.path}/tmp',
    );
    await layout.ensureDirectories();
    await _writeSqliteHeaderWithUserVersion(layout.sqlitePath, 15);
    await File('${layout.sqlitePath}-wal').writeAsString('wal');

    final archived = await layout.archiveIncompatibleLocalStateIfNeeded(
      clock: () => DateTime.utc(2026, 6, 1, 3, 4, 5),
    );

    expect(archived, isNotNull);
    expect(archived!.schemaVersion, 15);
    expect(await File(layout.sqlitePath).exists(), isFalse);
    expect(await File('${layout.sqlitePath}-wal').exists(), isFalse);
    expect(archived.archivedPaths, hasLength(2));
    expect(
      archived.archivedPaths.first,
      endsWith('legacy-state/im_core.sqlite.schema15.20260601T030405Z'),
    );
    expect(await File(archived.archivedPaths.first).exists(), isTrue);
  });

  test('keeps identity-owned local state untouched', () async {
    final root = await Directory.systemTemp.createTemp('awiki_me_paths_test_');
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: '${root.path}/support',
      cacheRoot: '${root.path}/cache',
      tempRoot: '${root.path}/tmp',
    );
    await layout.ensureDirectories();
    await _writeSqliteHeaderWithUserVersion(
      layout.sqlitePath,
      identityOwnedLocalStateSchemaVersion,
    );

    final archived = await layout.archiveIncompatibleLocalStateIfNeeded();

    expect(archived, isNull);
    expect(await File(layout.sqlitePath).exists(), isTrue);
  });
}

Future<void> _writeSqliteHeaderWithUserVersion(String path, int version) async {
  final bytes = Uint8List(100);
  bytes.setAll(0, 'SQLite format 3\u0000'.codeUnits);
  ByteData.sublistView(bytes, 60, 64).setInt32(0, version);
  await File(path).writeAsBytes(bytes);
}
