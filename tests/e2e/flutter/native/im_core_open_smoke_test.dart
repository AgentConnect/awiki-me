import 'dart:convert';
import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_secret_storage.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository_factory.dart';
import 'package:awiki_me/src/data/tenant/app_tenant_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../../case_attestation.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(
    () => E2eInvocationCompletionWriter.markFinished(
      failedTestCount: binding.failureMethodsDetails.length,
    ),
  );

  setUp(() async {
    const version = String.fromEnvironment('AWIKI_TEST_PACKAGE_VERSION');
    const build = String.fromEnvironment('AWIKI_TEST_PACKAGE_BUILD');
    if (version.isEmpty && build.isEmpty) return;
    expect(version, isNotEmpty);
    expect(build, isNotEmpty);
    final original = await PackageInfo.fromPlatform();
    _setPackageMetadata(original, version, build);
    addTearDown(
      () =>
          _setPackageMetadata(original, original.version, original.buildNumber),
    );
  });

  testWidgets(
    'prerelease package version reproduces invalid_input at bootstrap',
    (_) async {
      final original = await PackageInfo.fromPlatform();
      _setPackageMetadata(original, '0.1.34-test.1', '44');
      addTearDown(
        () => _setPackageMetadata(
          original,
          original.version,
          original.buildNumber,
        ),
      );
      final root = await Directory.systemTemp.createTemp(
        'awiki_me_version_rejection_',
      );
      addTearDown(() => root.delete(recursive: true));
      await expectLater(
        AppBootstrap.create(
          environment: AwikiEnvironmentConfig(
            baseUrl: 'https://awiki.info',
            didDomain: 'awiki.info',
          ),
          appStateRoot: root.path,
        ),
        throwsA(
          isA<core.AwikiImCoreException>()
              .having((error) => error.code, 'code', 'invalid_input')
              .having(
                (error) => error.field,
                'field',
                'client_version_info.version',
              ),
        ),
      );
    },
    skip: !(Platform.isMacOS || Platform.isLinux || Platform.isWindows),
  );

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
      final smsRetryAt = DateTime.now().toUtc().add(const Duration(minutes: 2));
      await first.smsOtpCooldownService.saveRetryAt(smsRetryAt);
      expect(await first.smsOtpCooldownService.loadRetryAt(), smsRetryAt);
      await first.dispose();

      final registryFile = File(
        p.join(
          root.path,
          'support',
          'awiki-me',
          'control',
          'tenant-registry.json',
        ),
      );
      final legacyRegistry =
          jsonDecode(await registryFile.readAsString()) as Map;
      final legacyTenants = (legacyRegistry['tenants'] as List).cast<Map>();
      final activeTenantProfileId =
          legacyRegistry['active_tenant_profile_id'] as String;
      final legacyTenant = legacyTenants.singleWhere(
        (item) => item['tenant_profile_id'] == activeTenantProfileId,
      );
      legacyTenant['backend_base_url'] = 'http://awiki.info';
      await registryFile.writeAsString(jsonEncode(legacyRegistry), flush: true);

      final second = await AppBootstrap.create(
        environment: environment,
        appStateRoot: root.path,
      );
      final migratedRegistry = await store.loadRegistry();
      expect(
        migratedRegistry.activeTenant.backendBaseUrl,
        'https://awiki.info',
      );
      expect(
        migratedRegistry.activeTenant.storageScopeId,
        tenant.storageScopeId,
      );
      expect(
        await second.smsOtpCooldownService.loadRetryAt(),
        smsRetryAt,
        reason: 'the tenant SMS boundary must survive a real App restart',
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
          'legacy_public_http_tenant_upgraded_in_place',
          'tenant_sms_cooldown_restored_after_restart',
          'missing_key_failed_without_recreate',
          'native_paths_validated',
        ],
      );
    },
    skip: !(Platform.isMacOS || Platform.isLinux || Platform.isWindows),
  );
}

void _setPackageMetadata(PackageInfo original, String version, String build) {
  // Native tests live in tests/e2e, outside the analyzer's test/ convention.
  // ignore: invalid_use_of_visible_for_testing_member
  PackageInfo.setMockInitialValues(
    appName: original.appName,
    packageName: original.packageName,
    version: version,
    buildNumber: build,
    buildSignature: original.buildSignature,
  );
}
