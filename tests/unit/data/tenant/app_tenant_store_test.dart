import 'dart:io';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/im_core/awiki_im_core_paths.dart';
import 'package:awiki_me/src/data/local/awiki_product_local_store_sqlite.dart';
import 'package:awiki_me/src/data/tenant/app_tenant_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppTenantStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('awiki_tenant_store_test_');
    store = AppTenantStore(appStateRoot: root.path);
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('loadRegistry creates the default AWiki tenant', () async {
    final registry = await store.loadRegistry();

    expect(registry.activeTenantId, defaultTenantId);
    expect(registry.visibleTenants, hasLength(1));
    expect(registry.activeTenant.name, primaryTenantName);
    expect(registry.activeTenant.backendBaseUrl, primaryTenantBackendBaseUrl);
    expect(registry.activeTenant.didHost, primaryTenantDidHost);
    expect(registry.activeTenant.stateNamespace, defaultTenantStateNamespace);
  });

  test('creates and switches tenants with normalized endpoints', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: ' Customer One ',
        backendBaseUrl: 'https://tenant.example.com/',
        didHost: 'Tenant.Example.com.',
      ),
    );

    final tenant = created.visibleTenants.singleWhere(
      (item) => item.name == 'Customer One',
    );
    expect(tenant.backendBaseUrl, 'https://tenant.example.com');
    expect(tenant.didHost, 'tenant.example.com');
    expect(tenant.stateNamespace, 'tenant-customer-one');

    final switched = await store.useTenant(tenant.id);

    expect(switched.activeTenant.id, tenant.id);
  });

  test(
    'creates unicode display names with safe internal identifiers',
    () async {
      final created = await store.createTenant(
        const AppTenantCreateInput(
          name: ' 测试环境 ',
          backendBaseUrl: 'https://tenant.example.com/',
          didHost: 'Tenant.Example.com.',
        ),
      );

      final tenant = created.visibleTenants.singleWhere(
        (item) => item.name == '测试环境',
      );

      expect(tenant.id, 'tenant-example-com');
      expect(tenant.stateNamespace, 'tenant-tenant-example-com');
      expect(tenant.backendBaseUrl, 'https://tenant.example.com');
      expect(tenant.didHost, 'tenant.example.com');
    },
  );

  test('accepts one-character and punctuated local tenant display names', () {
    expect(normalizeTenantName('测'), '测');
    expect(normalizeTenantName('杭州测试 · Dev 🚀'), '杭州测试 · Dev 🚀');
  });

  test('rejects empty, too long, and invisible tenant display names', () {
    expect(
      () => normalizeTenantName(' '),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_name_invalid',
        ),
      ),
    );
    expect(
      () => normalizeTenantName('${List.filled(20, '租户').join()}x'),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_name_invalid',
        ),
      ),
    );
    expect(
      () => normalizeTenantName('测试\u200B环境'),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_name_invalid',
        ),
      ),
    );
  });

  test('prepareUseTenant does not persist the active tenant', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://tenant.example.com',
        didHost: 'tenant.example.com',
      ),
    );
    final tenant = created.visibleTenants.singleWhere(
      (item) => item.name == 'Customer One',
    );

    final prepared = await store.prepareUseTenant(tenant.id);

    expect(prepared.activeTenant.id, tenant.id);
    expect((await store.loadRegistry()).activeTenant.id, defaultTenantId);
  });

  test('rejects duplicate names and endpoint pairs', () async {
    await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );

    await expectLater(
      store.createTenant(
        const AppTenantCreateInput(
          name: 'customer one',
          backendBaseUrl: 'https://two.example.com',
          didHost: 'two.example.com',
        ),
      ),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_name_exists',
        ),
      ),
    );

    await expectLater(
      store.createTenant(
        const AppTenantCreateInput(
          name: 'Customer Two',
          backendBaseUrl: 'https://one.example.com/',
          didHost: 'ONE.EXAMPLE.COM',
        ),
      ),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_endpoint_exists',
        ),
      ),
    );
  });

  test('updates empty custom tenant and blocks default tenant edits', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );
    final tenant = created.visibleTenants.singleWhere(
      (item) => item.name == 'Customer One',
    );

    final updated = await store.updateTenant(
      AppTenantUpdateInput(
        id: tenant.id,
        name: 'Customer Renamed',
        backendBaseUrl: 'https://renamed.example.com',
        didHost: 'renamed.example.com',
      ),
    );

    expect(
      updated.visibleTenants.singleWhere((item) => item.id == tenant.id).name,
      'Customer Renamed',
    );

    await expectLater(
      store.updateTenant(
        const AppTenantUpdateInput(
          id: defaultTenantId,
          name: 'Default Renamed',
          backendBaseUrl: 'https://default.example.com',
          didHost: 'default.example.com',
        ),
      ),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_default_edit_forbidden',
        ),
      ),
    );
  });

  test('blocks tenant endpoint edits once local data exists', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );
    final tenant = created.visibleTenants.singleWhere(
      (item) => item.name == 'Customer One',
    );
    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: p.join(root.path, 'support'),
      cacheRoot: p.join(root.path, 'cache'),
      tempRoot: p.join(root.path, 'tmp'),
      stateNamespace: tenant.stateNamespace,
    );
    await File(layout.registryPath).parent.create(recursive: true);
    await File(layout.registryPath).writeAsString('{"identities":[]}');

    expect(await store.tenantHasData(tenant.id), isTrue);
    await expectLater(
      store.updateTenant(
        AppTenantUpdateInput(
          id: tenant.id,
          name: tenant.name,
          backendBaseUrl: 'https://changed.example.com',
          didHost: 'changed.example.com',
        ),
      ),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_has_data',
        ),
      ),
    );
  });

  test('allows renaming a custom tenant after local data exists', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );
    final tenant = created.visibleTenants.singleWhere(
      (item) => item.name == 'Customer One',
    );
    final layout = AwikiImCorePathLayout.fromRoots(
      appSupportRoot: p.join(root.path, 'support'),
      cacheRoot: p.join(root.path, 'cache'),
      tempRoot: p.join(root.path, 'tmp'),
      stateNamespace: tenant.stateNamespace,
    );
    await File(layout.registryPath).parent.create(recursive: true);
    await File(layout.registryPath).writeAsString('{"identities":[]}');

    final updated = await store.updateTenant(
      AppTenantUpdateInput(
        id: tenant.id,
        name: '客户一号',
        backendBaseUrl: tenant.backendBaseUrl,
        didHost: tenant.didHost,
      ),
    );
    final renamed = updated.visibleTenants.singleWhere(
      (item) => item.id == tenant.id,
    );

    expect(renamed.name, '客户一号');
    expect(renamed.id, tenant.id);
    expect(renamed.stateNamespace, tenant.stateNamespace);
  });

  test('soft deletes inactive custom tenants only', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );
    final tenant = created.visibleTenants.singleWhere(
      (item) => item.name == 'Customer One',
    );
    final deleted = await store.deleteTenant(tenant.id);

    expect(
      deleted.visibleTenants.map((item) => item.id),
      isNot(contains(tenant.id)),
    );

    await expectLater(
      store.deleteTenant(defaultTenantId),
      throwsA(
        isA<AppTenantValidationException>().having(
          (error) => error.code,
          'code',
          'tenant_default_delete_forbidden',
        ),
      ),
    );
  });

  test('product database marker also counts as tenant data', () async {
    final created = await store.createTenant(
      const AppTenantCreateInput(
        name: 'Customer One',
        backendBaseUrl: 'https://one.example.com',
        didHost: 'one.example.com',
      ),
    );
    final tenant = created.visibleTenants.singleWhere(
      (item) => item.name == 'Customer One',
    );
    final productDb = File(
      p.join(
        root.path,
        'support',
        'awiki-me',
        'environments',
        tenant.stateNamespace,
        'product',
        AwikiProductLocalStoreSqlite.databaseName,
      ),
    );
    await productDb.parent.create(recursive: true);
    await productDb.writeAsString('data');

    expect(await store.tenantHasData(tenant.id), isTrue);
  });
}
