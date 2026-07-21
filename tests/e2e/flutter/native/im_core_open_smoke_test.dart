import 'dart:io';

import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_secret_storage.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository_factory.dart';
import 'package:awiki_me/src/data/tenant/app_tenant_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../case_attestation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real App bootstrap provisions once and runtime only opens existing key',
    (_) async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_me_scope_runtime_smoke_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final environment = AwikiEnvironmentConfig(
        baseUrl: 'https://awiki.info',
        didDomain: 'awiki.info',
      );
      final first = await AppBootstrap.create(
        environment: environment,
        appStateRoot: root.path,
      );
      final repository = buildScopeSecretRepository(appStateRoot: root.path);
      final store = AppTenantStore(
        appStateRoot: root.path,
        secretRepository: repository,
      );
      final registry = await store.loadRegistry();
      final tenant = registry.activeTenant;
      expect(tenant.backendBaseUrl, 'https://awiki.info');
      expect(tenant.didHost, 'awiki.info');
      final firstRecord = await repository.readExisting(tenant.storageScopeId);
      expect(firstRecord.status, ScopeSecretReadStatus.present);
      expect(first.storageScopeLayout?.scopeId, tenant.storageScopeId);
      await first.dispose();

      final second = await AppBootstrap.create(
        environment: environment,
        appStateRoot: root.path,
      );
      await second.dispose();
      final restored = await repository.readExisting(tenant.storageScopeId);
      expect(restored.status, ScopeSecretReadStatus.present);
      expect(
        restored.record!.envelope.identityVaultRoot.copyMaterial(),
        firstRecord.record!.envelope.identityVaultRoot.copyMaterial(),
      );

      await repository.delete(tenant.storageScopeId);
      await expectLater(
        AppBootstrap.create(environment: environment, appStateRoot: root.path),
        throwsA(
          isA<AwikiVaultOpenException>().having(
            (error) => error.code,
            'code',
            'vault_key_missing',
          ),
        ),
      );
      expect(
        (await repository.readExisting(tenant.storageScopeId)).status,
        ScopeSecretReadStatus.missing,
      );
      await E2eCaseAttestationWriter.markPassed(
        'NATIVE-E2E-001',
        phases: const <String>[
          'scope_provisioned_exclusive',
          'real_app_bootstrap_open_existing',
          'same_process_reopen_same_root',
          'missing_key_failed_without_recreate',
          'native_paths_validated',
        ],
      );
    },
    skip: !(Platform.isMacOS || Platform.isLinux || Platform.isWindows),
  );
}
