import 'dart:convert';
import 'dart:io';

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
}
