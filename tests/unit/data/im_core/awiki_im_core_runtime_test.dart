import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/data/im_core/awiki_im_core_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_runtime.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_secret_storage.dart';
import 'package:flutter_test/flutter_test.dart';

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
    );
    var openerCalled = false;
    final vaultProvider = _FakeVaultSecretProvider(
      secrets: core.DeviceVaultRootKey.fromList(List<int>.filled(32, 7)),
      deviceId: 'device-a',
    );
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: layout,
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
            expect(openOptions?.identitySecretVault?.deviceId, 'device-a');
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
    final runtime = AwikiImCoreRuntime(
      config: const AwikiImCoreEnvironmentConfig(
        serviceBaseUrl: 'https://awiki.ai',
        didDomain: 'awiki.ai',
      ),
      paths: AwikiImCorePathLayout.fromRoots(
        appSupportRoot: '${root.path}/support',
        cacheRoot: '${root.path}/cache',
        tempRoot: '${root.path}/tmp',
      ),
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

    await expectLater(runtime.open(), throwsA(isA<StateError>()));
    expect(openerCalled, isFalse);
    expect(runtime.isOpen, isFalse);
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
      ),
      vaultSecretProvider: _FakeVaultSecretProvider(),
    );

    await expectLater(runtime.currentClient(), throwsA(isA<StateError>()));
  });

  test('legacy identity without vault metadata is eligible for migration', () {
    final status = _vaultStatus(
      selectedBackend: core.IdentitySecretStorageBackend.fileCompat,
      vaultMetadataPresent: false,
      vaultMetadataVerified: false,
    );

    expect(shouldMigrateLegacyIdentityVault(status), isTrue);
  });

  test(
    'unverified existing vault metadata fails closed instead of remigrating',
    () {
      final status = _vaultStatus(
        selectedBackend: core.IdentitySecretStorageBackend.fileCompat,
        vaultMetadataPresent: true,
        vaultMetadataVerified: false,
        missing: const <String>['identity_vault_metadata_verified'],
      );

      expect(
        () => shouldMigrateLegacyIdentityVault(status),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            allOf(
              contains('identity_vault_unverified'),
              contains('identity-test'),
            ),
          ),
        ),
      );
    },
  );

  test('vault backend does not request migration', () {
    final status = _vaultStatus(
      selectedBackend: core.IdentitySecretStorageBackend.vault,
      vaultMetadataPresent: true,
      vaultMetadataVerified: true,
    );

    expect(shouldMigrateLegacyIdentityVault(status), isFalse);
  });
}

core.IdentityVaultStatus _vaultStatus({
  required core.IdentitySecretStorageBackend selectedBackend,
  required bool vaultMetadataPresent,
  required bool vaultMetadataVerified,
  List<String> missing = const <String>[],
}) {
  return core.IdentityVaultStatus(
    identity: const core.IdentitySummary(
      id: 'identity-test',
      did: 'did:wba:awiki.ai:alice:e1_identity-test',
      isDefault: true,
      readyForAuth: true,
      readyForMessaging: true,
    ),
    storagePolicy: core.IdentitySecretStoragePolicy.vaultRequired,
    selectedBackend: selectedBackend,
    vaultAvailable: true,
    vaultMetadataPresent: vaultMetadataPresent,
    vaultMetadataVerified: vaultMetadataVerified,
    workspaceId: 'awiki-me-default',
    deviceId: 'device-test',
    plaintextCompatRetained: vaultMetadataPresent,
    missing: missing,
  );
}

class _FakeVaultSecretProvider implements AwikiImCoreVaultSecretProvider {
  _FakeVaultSecretProvider({
    core.DeviceVaultRootKey? secrets,
    this.deviceId = 'device-test',
  }) : _rootKey =
           secrets ?? core.DeviceVaultRootKey.fromList(List<int>.filled(32, 3));

  final core.DeviceVaultRootKey _rootKey;
  final String deviceId;
  int calls = 0;

  @override
  Future<AwikiImCoreVaultSecrets> getOrCreateSecrets({
    required String stateNamespace,
  }) async {
    calls += 1;
    return AwikiImCoreVaultSecrets(rootKey: _rootKey, deviceId: deviceId);
  }
}

class _FailingVaultSecretProvider implements AwikiImCoreVaultSecretProvider {
  @override
  Future<AwikiImCoreVaultSecrets> getOrCreateSecrets({
    required String stateNamespace,
  }) async {
    throw StateError('identity_vault_root_key_unavailable');
  }
}
