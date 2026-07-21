import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/application/desktop_shell_service.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const scopeValue = '11111111-1111-4111-8111-111111111111';

void main() {
  test('fromRoots builds the expected awiki-me im-core layout', () {
    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: '/app/support/',
      cacheRoot: '/cache/',
      tempRoot: '/tmp/',
      scopeId: StorageScopeId.parse(scopeValue),
    );

    expect(layout.scopeId.value, scopeValue);
    expect(
      layout.identityRootDir,
      '/app/support/awiki-me/storage-scopes/$scopeValue/im-core/identities',
    );
    expect(
      layout.vaultDir,
      '/app/support/awiki-me/storage-scopes/$scopeValue/im-core/identity-vault',
    );
    expect(layout.vaultWorkspaceId, 'awiki-me.scope.v1.$scopeValue');
    expect(layout.vaultContextDeviceId, 'awiki-me.scope-device.v1.$scopeValue');
    expect(
      layout.registryPath,
      '/app/support/awiki-me/storage-scopes/$scopeValue/im-core/identities/registry.json',
    );
    expect(
      layout.defaultIdentityPath,
      '/app/support/awiki-me/storage-scopes/$scopeValue/im-core/identities/default',
    );
    expect(
      layout.sqlitePath,
      '/app/support/awiki-me/storage-scopes/$scopeValue/im-core/state/im_core.sqlite',
    );
    expect(
      layout.cacheDir,
      '/cache/awiki-me/storage-scopes/$scopeValue/im-core',
    );
    expect(layout.tempDir, '/tmp/awiki-me/storage-scopes/$scopeValue/im-core');

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
        scopeId: StorageScopeId.parse(scopeValue),
      );

      await layout.scopeLayout.createScopeRootExclusive();
      await layout.ensureDirectories();

      expect(await Directory(layout.identityRootDir).exists(), isTrue);
      expect(await Directory(layout.vaultDir).exists(), isTrue);
      expect(
        await Directory(
          '${root.path}/support/awiki-me/storage-scopes/$scopeValue/im-core/state',
        ).exists(),
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
      scopeId: StorageScopeId.parse(scopeValue),
    );
    await layout.scopeLayout.createScopeRootExclusive();
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
      scopeId: StorageScopeId.parse(scopeValue),
    );
    await layout.scopeLayout.createScopeRootExclusive();
    await layout.ensureDirectories();
    await _writeSqliteHeaderWithUserVersion(
      layout.sqlitePath,
      identityOwnedLocalStateSchemaVersion,
    );

    final archived = await layout.archiveIncompatibleLocalStateIfNeeded();

    expect(archived, isNull);
    expect(await File(layout.sqlitePath).exists(), isTrue);
  });

  test('normalizes relative E2E state root against the runner cwd', () {
    expect(
      normalizeAwikiE2eAppStateRootForLaunch(
        '.e2e/smoke/current/app',
        currentDirectory: '/workspace/awiki-me',
        homeDirectory: '/Users/alice',
        isMacOS: true,
        temporaryDirectory: '/tmp',
      ),
      '/workspace/awiki-me/.e2e/smoke/current/app',
    );
  });

  test(
    'keeps GUI-launched relative E2E state root on writable macOS support',
    () {
      expect(
        normalizeAwikiE2eAppStateRootForLaunch(
          '.e2e/manual/app',
          currentDirectory: '/',
          homeDirectory: '/Users/alice',
          isMacOS: true,
          temporaryDirectory: '/tmp',
        ),
        '/Users/alice/Library/Application Support/ai.awiki.awikime/.e2e/manual/app',
      );
    },
  );

  test(
    'falls back to temp for GUI-launched relative E2E state without HOME',
    () {
      expect(
        normalizeAwikiE2eAppStateRootForLaunch(
          '.e2e/manual/app',
          currentDirectory: '/',
          homeDirectory: '',
          isMacOS: true,
          temporaryDirectory: '/tmp',
        ),
        '/tmp/ai.awiki.awikime/.e2e/manual/app',
      );
    },
  );

  test('preserves absolute and home-relative E2E state roots', () {
    expect(
      normalizeAwikiE2eAppStateRootForLaunch(
        '/var/tmp/awiki-e2e/app',
        currentDirectory: '/',
      ),
      '/var/tmp/awiki-e2e/app',
    );
    expect(
      normalizeAwikiE2eAppStateRootForLaunch(
        '~/awiki-e2e/app',
        currentDirectory: '/',
        homeDirectory: '/Users/alice',
      ),
      '/Users/alice/awiki-e2e/app',
    );
  });

  test('builds Windows drive, Unicode, spaces and long paths', () {
    final longSegment = List<String>.filled(20, 'long directory').join(r'\');
    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: 'C:\\Users\\测试 User\\$longSegment\\support',
      cacheRoot: r'C:\Users\测试 User\AppData\Local\AWiki\AWikiMe\cache',
      tempRoot: r'C:\Users\测试 User\AppData\Local\Temp\AWikiMe',
      scopeId: StorageScopeId.parse(scopeValue),
      pathContext: p.windows,
    );

    expect(layout.scopeLayout.pathContext.style, p.Style.windows);
    expect(
      layout.sqlitePath,
      endsWith(
        'support\\awiki-me\\storage-scopes\\$scopeValue\\im-core\\state\\im_core.sqlite',
      ),
    );
    expect(layout.cacheDir, contains(r'AWiki\AWikiMe\cache\awiki-me'));
    expect(layout.tempDir, contains(r'Temp\AWikiMe\awiki-me'));
  });

  test('preserves UNC roots with Windows separators', () {
    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: r'\\server\AWiki Data\support',
      cacheRoot: r'\\server\AWiki Data\cache',
      tempRoot: r'\\server\AWiki Data\temp',
      scopeId: StorageScopeId.parse(scopeValue),
      pathContext: p.windows,
    );

    expect(
      layout.identityRootDir,
      r'\\server\AWiki Data\support\awiki-me\storage-scopes\11111111-1111-4111-8111-111111111111\im-core\identities',
    );
  });

  test('Windows platform roots come from the desktop shell boundary', () async {
    final layout = await AwikiImCorePathLayout.fromPlatform(
      scopeId: StorageScopeId.parse(scopeValue),
      isWindows: () => true,
      platformStorageRoots: () async => const DesktopStorageRoots(
        support: r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\support',
        cache: r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\cache',
        temp: r'C:\Users\tester\AppData\Local\Temp\AWikiMe',
      ),
    );

    expect(
      layout.sqlitePath,
      r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\support\awiki-me\storage-scopes\11111111-1111-4111-8111-111111111111\im-core\state\im_core.sqlite',
    );
  });

  test('explicit Windows E2E root wins over Known Folder lookup', () async {
    var rootCalls = 0;
    final layout = await AwikiImCorePathLayout.fromPlatform(
      scopeId: StorageScopeId.parse(scopeValue),
      appStateRoot: r'D:\AWiki E2E\state',
      isWindows: () => true,
      platformStorageRoots: () async {
        rootCalls += 1;
        throw StateError('must not be called');
      },
      pathContext: p.windows,
    );

    expect(rootCalls, 0);
    expect(layout.sqlitePath, startsWith(r'D:\AWiki E2E\state\support'));
  });

  test('normalizes relative Windows E2E roots with backslashes', () {
    expect(
      normalizeAwikiE2eAppStateRootForLaunch(
        r'.e2e\smoke\app',
        currentDirectory: r'C:\workspace\awiki-me',
        homeDirectory: r'C:\Users\tester',
        temporaryDirectory: r'C:\Temp',
        pathContext: p.windows,
      ),
      r'C:\workspace\awiki-me\.e2e\smoke\app',
    );
  });
}

Future<void> _writeSqliteHeaderWithUserVersion(String path, int version) async {
  final bytes = Uint8List(100);
  bytes.setAll(0, 'SQLite format 3\u0000'.codeUnits);
  ByteData.sublistView(bytes, 60, 64).setInt32(0, version);
  await File(path).writeAsBytes(bytes);
}
