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
      openCore:
          ({
            required core.AwikiImCoreConfig config,
            required core.AwikiImCorePaths paths,
            core.AwikiImCoreOpenOptions? openOptions,
          }) async {
            openerCalled = true;
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
            throw UnsupportedError('fake opener stops before native load');
          },
    );

    await expectLater(runtime.open(), throwsA(isA<UnsupportedError>()));
    expect(openerCalled, isTrue);
    expect(vaultProvider.calls, 1);
    expect(runtime.isOpen, isFalse);
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
