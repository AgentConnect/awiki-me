import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/desktop_shell_service.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/storage/scope_secret_repository.dart';
import 'package:awiki_me/src/data/storage/scope_manifest.dart';
import 'package:awiki_me/src/data/tenant/app_tenant_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppTenantStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('awiki_scope_registry_test_');
    store = AppTenantStore(
      appStateRoot: root.path,
      secretRepository: FakeScopeSecretRepository(),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('creates strict registry v1 and immutable UUID scope layout', () async {
    final registry = await store.loadRegistry();
    final tenant = registry.activeTenant;
    final layout = await store.layoutForScope(tenant.storageScopeId);

    expect(registry.revision, 1);
    expect(tenant.backendBaseUrl, primaryTenantBaseUrl);
    expect(tenant.didHost, primaryTenantDomain);
    expect(tenant.tenantProfileId.value, isNot(tenant.storageScopeId.value));
    expect(
      layout.scopeRoot,
      contains('storage-scopes/${tenant.storageScopeId}'),
    );
    expect(await File(layout.manifestPath).exists(), isTrue);
    expect(await Directory(layout.identityVaultRoot).exists(), isTrue);
    final raw = await File(
      p.join(
        root.path,
        'support',
        'awiki-me',
        'control',
        'tenant-registry.json',
      ),
    ).readAsString();
    expect(raw, isNot(contains('state_namespace')));
    expect(raw, isNot(contains('tenant-default')));
  });

  test('explicit test realm binds the fresh built-in scope manifest', () async {
    store = AppTenantStore(
      appStateRoot: root.path,
      secretRepository: FakeScopeSecretRepository(),
      initialTenantFactory: () => defaultTenantProfile().copyWith(
        backendBaseUrl: 'https://awiki.info',
        didHost: 'awiki.info',
      ),
    );

    final registry = await store.loadRegistry();
    final layout = await store.layoutForScope(
      registry.activeTenant.storageScopeId,
    );
    final manifest = await const StorageScopeManifestStore().readExisting(
      layout.manifestPath,
    );

    expect(registry.activeTenant.backendBaseUrl, 'https://awiki.info');
    expect(manifest.didHostAtCreation, 'awiki.info');
  });

  test(
    'existing registry ignores new build defaults and preserves scope data',
    () async {
      final secrets = FakeScopeSecretRepository();
      final originalStore = AppTenantStore(
        appStateRoot: root.path,
        secretRepository: secrets,
        initialTenantFactory: () => defaultTenantProfile().copyWith(
          backendBaseUrl: 'https://awiki.ai',
          didHost: 'awiki.ai',
        ),
      );
      final original = await originalStore.loadRegistry();
      final originalTenant = original.activeTenant;
      final layout = await originalStore.layoutForScope(
        originalTenant.storageScopeId,
      );
      final imCoreSentinel = File(layout.imCoreSqlitePath);
      final productSentinel = File(layout.productDatabasePath);
      await imCoreSentinel.parent.create(recursive: true);
      await productSentinel.parent.create(recursive: true);
      await imCoreSentinel.writeAsBytes(<int>[1, 2, 3, 4]);
      await productSentinel.writeAsBytes(<int>[5, 6, 7, 8]);
      final registryFile = File(
        p.join(
          root.path,
          'support',
          'awiki-me',
          'control',
          'tenant-registry.json',
        ),
      );
      final registryBeforeUpgrade = await registryFile.readAsString();

      final upgradedStore = AppTenantStore(
        appStateRoot: root.path,
        secretRepository: secrets,
        initialTenantFactory: () => throw StateError(
          'existing registry must not consult new build defaults',
        ),
      );
      final reopened = await upgradedStore.loadRegistry();

      expect(reopened.revision, original.revision);
      expect(reopened.activeTenantProfileId, original.activeTenantProfileId);
      expect(
        reopened.activeTenant.storageScopeId,
        originalTenant.storageScopeId,
      );
      expect(reopened.activeTenant.backendBaseUrl, 'https://awiki.ai');
      expect(await registryFile.readAsString(), registryBeforeUpgrade);
      expect(await imCoreSentinel.readAsBytes(), <int>[1, 2, 3, 4]);
      expect(await productSentinel.readAsBytes(), <int>[5, 6, 7, 8]);
      expect(
        (await secrets.readExisting(originalTenant.storageScopeId)).status,
        ScopeSecretReadStatus.present,
      );
    },
  );

  test('two tenants have distinct profile IDs scopes and paths', () async {
    final first = await store.loadRegistry();
    final second = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://tenant.example.com/',
        didHost: 'Tenant.Example.com.',
      ),
    );
    final custom = second.visibleTenants.singleWhere(
      (item) => !item.isPrimaryTenant,
    );

    expect(custom.tenantProfileId, isNot(first.activeTenant.tenantProfileId));
    expect(custom.storageScopeId, isNot(first.activeTenant.storageScopeId));
    expect(
      (await store.layoutForScope(custom.storageScopeId)).scopeRoot,
      isNot(
        (await store.layoutForScope(
          first.activeTenant.storageScopeId,
        )).scopeRoot,
      ),
    );
  });

  test('rename never changes storage scope or layout', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );
    final tenant = created.visibleTenants.singleWhere(
      (item) => !item.isPrimaryTenant,
    );
    final before = (await store.layoutForScope(
      tenant.storageScopeId,
    )).scopeRoot;
    final updated = await store.updateTenant(
      AppTenantUpdateInput(
        id: tenant.id,
        name: '客户一号',
        backendBaseUrl: tenant.backendBaseUrl,
        didHost: tenant.didHost,
      ),
    );
    final renamed = updated.tenants.singleWhere((item) => item.id == tenant.id);

    expect(renamed.storageScopeId, tenant.storageScopeId);
    expect(
      (await store.layoutForScope(renamed.storageScopeId)).scopeRoot,
      before,
    );
  });

  test(
    'prepared tenant update is not persisted before activation commit',
    () async {
      final created = await store.createTenant(
        const AppTenantCreateInput(
          name: 'Prepared Tenant',
          backendBaseUrl: 'https://prepared.example.com',
          didHost: 'prepared.example.com',
        ),
      );
      final tenant = created.visibleTenants.singleWhere(
        (item) => !item.isPrimaryTenant,
      );

      final prepared = await store.prepareUpdateTenant(
        AppTenantUpdateInput(
          id: tenant.id,
          name: 'Prepared Rename',
          backendBaseUrl: tenant.backendBaseUrl,
          didHost: tenant.didHost,
        ),
      );

      expect(
        (await store.loadRegistry()).tenants
            .singleWhere((item) => item.id == tenant.id)
            .name,
        'Prepared Tenant',
      );

      await store.saveRegistry(
        prepared,
        expectedRevision: prepared.revision - 1,
      );
      expect(
        (await store.loadRegistry()).tenants
            .singleWhere((item) => item.id == tenant.id)
            .name,
        'Prepared Rename',
      );
    },
  );

  test('DID realm change requires a new tenant profile and scope', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );
    final tenant = created.tenants.singleWhere((item) => !item.isPrimaryTenant);

    await expectLater(
      store.updateTenant(
        AppTenantUpdateInput(
          id: tenant.id,
          name: tenant.name,
          backendBaseUrl: 'https://two.example.com',
          didHost: 'two.example.com',
        ),
      ),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_realm_change_requires_new_scope',
        ),
      ),
    );
    expect(
      (await store.loadRegistry()).tenants
          .singleWhere((item) => item.id == tenant.id)
          .storageScopeId,
      tenant.storageScopeId,
    );
  });

  test('rejects unknown schema duplicate scope and stale revision', () async {
    final registry = await store.loadRegistry();
    final registryFile = File(
      p.join(
        root.path,
        'support',
        'awiki-me',
        'control',
        'tenant-registry.json',
      ),
    );
    final unknown = registry.toJson()..['schema_version'] = 2;
    await registryFile.writeAsString(jsonEncode(unknown));
    await expectLater(store.loadRegistry(), throwsFormatException);

    await registryFile.writeAsString(jsonEncode(registry.toJson()));
    final duplicate = AppTenantProfile(
      tenantProfileId: TenantProfileId.generate(),
      storageScopeId: registry.activeTenant.storageScopeId,
      kind: AppTenantKind.custom,
      name: 'Duplicate',
      backendBaseUrl: 'https://duplicate.example.com',
      didHost: 'duplicate.example.com',
      lifecycle: AppTenantLifecycle.active,
      createdAt: DateTime.utc(2026).toIso8601String(),
      updatedAt: DateTime.utc(2026).toIso8601String(),
    );
    expect(
      () => AppTenantRegistry(
        revision: 2,
        activeTenantProfileId: registry.activeTenantProfileId,
        tenants: <AppTenantProfile>[registry.activeTenant, duplicate],
      ).validate(),
      throwsFormatException,
    );
    await expectLater(
      store.saveRegistry(registry.copyWith(revision: 3), expectedRevision: 2),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_registry_stale_revision',
        ),
      ),
    );
  });

  test('strict UUID rejects labels traversal and non-v4 values', () {
    for (final value in <String>[
      'tenant-default',
      '../scope',
      '00000000-0000-1000-8000-000000000000',
      'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
    ]) {
      expect(() => StorageScopeId.parse(value), throwsFormatException);
    }
  });

  test('registry and manifest binding mismatch fails closed', () async {
    final registry = await store.loadRegistry();
    final layout = await store.layoutForScope(
      registry.activeTenant.storageScopeId,
    );
    final manifestFile = File(layout.manifestPath);
    final manifest = jsonDecode(await manifestFile.readAsString()) as Map;
    manifest['owner_tenant_profile_id'] = TenantProfileId.generate().value;
    await manifestFile.writeAsString(jsonEncode(manifest));

    await expectLater(store.loadRegistry(), throwsFormatException);
  });

  test('archiving tenant preserves ready scope and secret', () async {
    final secrets = FakeScopeSecretRepository();
    store = AppTenantStore(appStateRoot: root.path, secretRepository: secrets);
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Archived Tenant',
        backendBaseUrl: 'https://archive.example.com',
        didHost: 'archive.example.com',
      ),
    );
    final tenant = created.tenants.singleWhere((item) => !item.isPrimaryTenant);

    final archived = await store.deleteTenant(tenant.id);
    final layout = await store.layoutForScope(tenant.storageScopeId);
    final manifest = await const StorageScopeManifestStore().readExisting(
      layout.manifestPath,
    );

    expect(
      archived.tenants.singleWhere((item) => item.id == tenant.id).isArchived,
      isTrue,
    );
    expect(manifest.lifecycle, StorageScopeLifecycle.ready);
    expect(
      (await secrets.readExisting(tenant.storageScopeId)).status,
      ScopeSecretReadStatus.present,
    );
  });

  test(
    'ready scope missing key is never reprovisioned during registry load',
    () async {
      final secrets = FakeScopeSecretRepository();
      store = AppTenantStore(
        appStateRoot: root.path,
        secretRepository: secrets,
      );
      final registry = await store.loadRegistry();
      final scope = registry.activeTenant.storageScopeId;
      await secrets.delete(scope);

      final reloaded = await store.loadRegistry();

      expect(reloaded.activeTenant.storageScopeId, scope);
      expect(
        (await secrets.readExisting(scope)).status,
        ScopeSecretReadStatus.missing,
      );
    },
  );

  test('Windows layout uses injected LocalAppData Known Folder roots', () async {
    final windowsStore = AppTenantStore(
      appStateRoot: null,
      secretRepository: FakeScopeSecretRepository(),
      isWindows: () => true,
      platformStorageRoots: () async => const DesktopStorageRoots(
        support: r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\support',
        cache: r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\cache',
        temp: r'C:\Users\tester\AppData\Local\Temp\AWikiMe',
      ),
    );

    final layout = await windowsStore.layoutForScope(
      StorageScopeId.parse('11111111-1111-4111-8111-111111111111'),
    );

    expect(
      layout.scopeRoot,
      r'C:\Users\tester\AppData\Local\AWiki\AWikiMe\support\awiki-me\storage-scopes\11111111-1111-4111-8111-111111111111',
    );
    expect(layout.pathContext.style, p.Style.windows);
  });

  test(
    'explicit app state root wins over Windows Known Folder roots',
    () async {
      var rootCalls = 0;
      final explicitStore = AppTenantStore(
        appStateRoot: root.path,
        secretRepository: FakeScopeSecretRepository(),
        isWindows: () => true,
        platformStorageRoots: () async {
          rootCalls += 1;
          throw StateError('must not be called');
        },
      );

      final layout = await explicitStore.layoutForScope(
        StorageScopeId.parse('11111111-1111-4111-8111-111111111111'),
      );

      expect(rootCalls, 0);
      expect(layout.scopeRoot, startsWith(p.join(root.path, 'support')));
    },
  );
}
