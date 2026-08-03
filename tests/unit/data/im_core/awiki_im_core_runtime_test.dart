import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_runtime.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_secret_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const scopeValue = '22222222-2222-4222-8222-222222222222';

void main() {
  test('open creates directories before invoking the SDK opener', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_test_',
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
    var openerCalled = false;
    var inspectionCalled = false;
    var upgradeCalled = false;
    final vaultProvider = _FakeVaultSecretProvider(
      secrets: core.DeviceVaultRootKey.fromList(List<int>.filled(32, 7)),
    );
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: layout,
      scopeId: StorageScopeId.parse(scopeValue),
      vaultSecretProvider: vaultProvider,
      multiDeviceDeviceRevokeEnabled: true,
      multiDeviceDirectE2eeEnabled: true,
      multiDeviceGroupE2eeEnabled: true,
      multiDeviceHandleRecoveryEnabled: true,
      inspectLocalStateUpgrade: (paths) async {
        inspectionCalled = true;
        expect(await Directory(paths.identityRootDir).exists(), isTrue);
        return const core.LocalStateUpgradeInspection(
          eligibility: core.LocalStateUpgradeEligibility.notRequired,
          sourceSchemaVersion: 28,
          targetSchemaVersion: 28,
        );
      },
      upgradeLocalState: (paths) async {
        upgradeCalled = true;
        expect(inspectionCalled, isTrue);
        return const core.LocalStateUpgradeResult(
          status: core.LocalStateUpgradeStatus.notRequired,
          sourceSchemaVersion: 28,
          targetSchemaVersion: 28,
          migratedPersonas: 0,
          migratedConversations: 0,
          unresolvedMessages: 0,
          aliasCount: 0,
          backupAvailable: false,
        );
      },
      openCore:
          ({
            required core.AwikiImCoreConfig config,
            required core.AwikiImCorePaths paths,
            core.AwikiImCoreOpenOptions? openOptions,
          }) async {
            openerCalled = true;
            expect(inspectionCalled, isTrue);
            expect(await Directory(paths.identityRootDir).exists(), isTrue);
            expect(await Directory(layout.vaultDir).exists(), isTrue);
            expect(await Directory(layout.cacheDir).exists(), isTrue);
            expect(await Directory(layout.tempDir).exists(), isTrue);
            expect(
              openOptions?.identitySecretStoragePolicy,
              core.IdentitySecretStoragePolicy.vaultRequired,
            );
            expect(openOptions?.identitySecretVault?.vaultDir, layout.vaultDir);
            expect(
              openOptions?.identitySecretVault?.workspaceId,
              layout.vaultWorkspaceId,
            );
            expect(
              openOptions?.identitySecretVault?.deviceId,
              layout.vaultContextDeviceId,
            );
            expect(
              openOptions?.identitySecretVault?.rootKey.bytes,
              List<int>.filled(32, 7),
            );
            expect(openOptions?.multiDeviceDeviceRevokeEnabled, isTrue);
            expect(openOptions?.multiDeviceHandleRecoveryEnabled, isTrue);
            expect(openOptions?.multiDeviceDirectE2eeEnabled, isTrue);
            expect(openOptions?.multiDeviceGroupE2eeEnabled, isTrue);
            throw UnsupportedError('fake opener stops before native load');
          },
    );

    await expectLater(runtime.open(), throwsA(isA<UnsupportedError>()));
    expect(openerCalled, isTrue);
    expect(upgradeCalled, isTrue);
    expect(vaultProvider.calls, 1);
    expect(runtime.isOpen, isFalse);
  });

  test('release 0710 local state is upgraded before SDK open', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_upgrade_test_',
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
    final events = <String>[];
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: layout,
      scopeId: StorageScopeId.parse(scopeValue),
      vaultSecretProvider: _FakeVaultSecretProvider(),
      onProgress: (progress) => events.add(progress.name),
      inspectLocalStateUpgrade: (paths) async {
        events.add('inspect');
        return const core.LocalStateUpgradeInspection(
          eligibility: core.LocalStateUpgradeEligibility.required,
          sourceSchemaVersion: 27,
          targetSchemaVersion: 28,
        );
      },
      upgradeLocalState: (paths) async {
        events.add('upgrade');
        return const core.LocalStateUpgradeResult(
          status: core.LocalStateUpgradeStatus.completed,
          sourceSchemaVersion: 27,
          targetSchemaVersion: 28,
          migratedPersonas: 1,
          migratedConversations: 2,
          unresolvedMessages: 0,
          aliasCount: 2,
          backupAvailable: true,
        );
      },
      openCore:
          ({
            required core.AwikiImCoreConfig config,
            required core.AwikiImCorePaths paths,
            core.AwikiImCoreOpenOptions? openOptions,
          }) async {
            events.add('open');
            throw UnsupportedError('fake opener stops before native load');
          },
    );

    await expectLater(runtime.open(), throwsA(isA<UnsupportedError>()));
    expect(events, <String>[
      'inspect',
      'upgradingLocalState',
      'upgrade',
      'open',
    ]);
  });

  test('pre-release local state is archived before inspection', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_legacy_state_test_',
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
    await _writeSqliteHeaderWithUserVersion(layout.sqlitePath, 25);
    await File('${layout.sqlitePath}-wal').writeAsString('wal');

    final events = <String>[];
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: layout,
      scopeId: StorageScopeId.parse(scopeValue),
      vaultSecretProvider: _FakeVaultSecretProvider(),
      inspectLocalStateUpgrade: (paths) async {
        events.add('inspect');
        expect(await File(paths.sqlitePath).exists(), isFalse);
        expect(await File('${paths.sqlitePath}-wal').exists(), isFalse);
        return const core.LocalStateUpgradeInspection(
          eligibility: core.LocalStateUpgradeEligibility.notRequired,
          sourceSchemaVersion: 0,
          targetSchemaVersion: 34,
        );
      },
      upgradeLocalState: (paths) async {
        events.add('upgrade');
        return const core.LocalStateUpgradeResult(
          status: core.LocalStateUpgradeStatus.notRequired,
          sourceSchemaVersion: 0,
          targetSchemaVersion: 34,
          migratedPersonas: 0,
          migratedConversations: 0,
          unresolvedMessages: 0,
          aliasCount: 0,
          backupAvailable: false,
        );
      },
      openCore:
          ({
            required core.AwikiImCoreConfig config,
            required core.AwikiImCorePaths paths,
            core.AwikiImCoreOpenOptions? openOptions,
          }) async {
            events.add('open');
            throw UnsupportedError('fake opener stops before native load');
          },
    );

    await expectLater(runtime.open(), throwsA(isA<UnsupportedError>()));
    expect(events, <String>['inspect', 'upgrade', 'open']);
    final archiveDir = Directory(
      '${layout.scopeLayout.imCoreStateRoot}/legacy-state',
    );
    expect(await archiveDir.exists(), isTrue);
    expect(
      await archiveDir
          .list()
          .map((entry) => entry.path)
          .where((path) => path.contains('.schema25.'))
          .length,
      2,
    );
  });

  test('upgrade failure prevents SDK open', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_upgrade_failure_test_',
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
    var openerCalled = false;
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: layout,
      scopeId: StorageScopeId.parse(scopeValue),
      vaultSecretProvider: _FakeVaultSecretProvider(),
      inspectLocalStateUpgrade: (paths) async =>
          const core.LocalStateUpgradeInspection(
            eligibility: core.LocalStateUpgradeEligibility.required,
            sourceSchemaVersion: 27,
            targetSchemaVersion: 28,
          ),
      upgradeLocalState: (paths) async {
        throw const core.AwikiImCoreException(
          code: 'local_state_upgrade_failed',
          message: 'local state upgrade failed during validation',
        );
      },
      openCore:
          ({
            required core.AwikiImCoreConfig config,
            required core.AwikiImCorePaths paths,
            core.AwikiImCoreOpenOptions? openOptions,
          }) async {
            openerCalled = true;
            throw UnsupportedError('must not open');
          },
    );

    await expectLater(
      runtime.open(),
      throwsA(
        isA<core.AwikiImCoreException>().having(
          (error) => error.code,
          'code',
          'local_state_upgrade_failed',
        ),
      ),
    );
    expect(openerCalled, isFalse);
  });

  test('open fails closed when vault secrets are unavailable', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_test_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    var openerCalled = false;
    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: '${root.path}/support',
      cacheRoot: '${root.path}/cache',
      tempRoot: '${root.path}/tmp',
      scopeId: StorageScopeId.parse(scopeValue),
    );
    await layout.scopeLayout.createScopeRootExclusive();
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: layout,
      scopeId: StorageScopeId.parse(scopeValue),
      vaultSecretProvider: _FailingVaultSecretProvider(),
      openCore:
          ({
            required core.AwikiImCoreConfig config,
            required core.AwikiImCorePaths paths,
            core.AwikiImCoreOpenOptions? openOptions,
          }) async {
            openerCalled = true;
            throw UnsupportedError('should not open');
          },
    );

    await expectLater(runtime.open(), throwsA(isA<AwikiVaultOpenException>()));
    expect(openerCalled, isFalse);
    expect(runtime.isOpen, isFalse);
    expect(await Directory(layout.identityRootDir).exists(), isFalse);
  });

  test('currentClient fails clearly before an identity is selected', () async {
    final root = await Directory.systemTemp.createTemp(
      'awiki_me_runtime_test_',
    );
    addTearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: AwikiImCorePathLayout.fromRoots(
        appSupportRoot: '${root.path}/support',
        cacheRoot: '${root.path}/cache',
        tempRoot: '${root.path}/tmp',
        scopeId: StorageScopeId.parse(scopeValue),
      ),
      scopeId: StorageScopeId.parse(scopeValue),
      vaultSecretProvider: _FakeVaultSecretProvider(),
    );

    await expectLater(runtime.currentClient(), throwsA(isA<StateError>()));
  });
}

class _FakeVaultSecretProvider implements AwikiImCoreVaultSecretProvider {
  _FakeVaultSecretProvider({core.DeviceVaultRootKey? secrets})
    : _rootKey =
          secrets ?? core.DeviceVaultRootKey.fromList(List<int>.filled(32, 3));

  final core.DeviceVaultRootKey _rootKey;
  int calls = 0;

  @override
  Future<AwikiImCoreVaultSecrets> openExisting(StorageScopeId scopeId) async {
    expect(scopeId.value, scopeValue);
    calls += 1;
    return AwikiImCoreVaultSecrets(rootKey: _rootKey);
  }
}

class _FailingVaultSecretProvider implements AwikiImCoreVaultSecretProvider {
  @override
  Future<AwikiImCoreVaultSecrets> openExisting(StorageScopeId scopeId) async {
    expect(scopeId.value, scopeValue);
    throw const AwikiVaultOpenException('vault_key_missing');
  }
}

Future<void> _writeSqliteHeaderWithUserVersion(String path, int version) async {
  final bytes = List<int>.filled(64, 0);
  const marker = 'SQLite format 3\u0000';
  for (var index = 0; index < marker.length; index++) {
    bytes[index] = marker.codeUnitAt(index);
  }
  bytes[60] = (version >> 24) & 0xff;
  bytes[61] = (version >> 16) & 0xff;
  bytes[62] = (version >> 8) & 0xff;
  bytes[63] = version & 0xff;
  await File(path).writeAsBytes(bytes, flush: true);
}
