import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/tenant/app_tenant.dart';
import '../im_core/awiki_im_core_paths.dart' show awikiE2eAppStateRoot;
import '../storage/awiki_storage_scope_layout.dart';
import '../storage/scope_manifest.dart';
import '../storage/scope_secret_repository.dart';
import '../storage/storage_scope_provisioner.dart';

class AppTenantValidationException implements Exception {
  const AppTenantValidationException(this.code);
  final String code;
  @override
  String toString() => code;
}

class AppTenantStore {
  AppTenantStore({
    required this.appStateRoot,
    ScopeSecretRepository? secretRepository,
    StorageScopeFaultInjector? faultInjector,
  }) : _secretRepository =
           secretRepository ?? const UnavailableScopeSecretRepository(),
       _faultInjector = faultInjector;

  final String? appStateRoot;
  final ScopeSecretRepository _secretRepository;
  final StorageScopeFaultInjector? _faultInjector;

  static const int _maxTenantNameLength = 40;

  Future<AppTenantRegistry> loadRegistry() async {
    final file = await _registryFile();
    if (!await file.exists()) {
      return _createInitialRegistry();
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('tenant_registry_invalid');
    }
    final registry = AppTenantRegistry.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
    await _validateRegistryScopes(registry);
    return registry;
  }

  Future<void> saveRegistry(
    AppTenantRegistry registry, {
    int? expectedRevision,
  }) async {
    registry.validate();
    await _validateRegistryScopes(registry);
    final file = await _registryFile();
    await StorageScopeProcessLock('${file.path}.lock').synchronized(() async {
      if (await file.exists()) {
        final current = await _readRegistryFile(file);
        final expected = expectedRevision ?? registry.revision - 1;
        if (current.revision != expected) {
          throw const AppTenantValidationException(
            'tenant_registry_stale_revision',
          );
        }
      } else if (expectedRevision != null && expectedRevision != 0) {
        throw const AppTenantValidationException(
          'tenant_registry_stale_revision',
        );
      }
      await _writeRegistryAtomic(file, registry);
    });
  }

  Future<AppTenantRegistry> createTenant(AppTenantCreateInput input) async {
    final registry = await loadRegistry();
    final now = DateTime.now().toUtc();
    final name = normalizeTenantName(input.name);
    final backend = normalizeTenantBackendBaseUrl(input.backendBaseUrl);
    final didHost = normalizeTenantDidHost(input.didHost);
    _assertUniqueName(registry, name);
    _assertUniqueEndpoint(registry, backend, didHost);
    final tenant = AppTenantProfile(
      tenantProfileId: TenantProfileId.generate(),
      storageScopeId: StorageScopeId.generate(),
      kind: AppTenantKind.custom,
      name: name,
      backendBaseUrl: backend,
      didHost: didHost,
      lifecycle: AppTenantLifecycle.active,
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
    await _provision(tenant);
    final next = AppTenantRegistry(
      revision: registry.revision + 1,
      activeTenantProfileId: registry.activeTenantProfileId,
      tenants: _sort(<AppTenantProfile>[...registry.tenants, tenant]),
    );
    await saveRegistry(next, expectedRevision: registry.revision);
    return next;
  }

  Future<AppTenantRegistry> useTenant(String tenantId) async {
    final next = await prepareUseTenant(tenantId);
    await saveRegistry(next, expectedRevision: next.revision - 1);
    return next;
  }

  Future<AppTenantRegistry> prepareUseTenant(String tenantId) async {
    final registry = await loadRegistry();
    final tenant = _findVisible(registry, tenantId);
    final manifest = await _manifestStore.readExisting(
      (await layoutForScope(tenant.storageScopeId)).manifestPath,
    );
    if (manifest.lifecycle != StorageScopeLifecycle.ready ||
        manifest.ownerTenantProfileId != tenant.tenantProfileId) {
      throw const AppTenantValidationException('scope_not_ready');
    }
    return registry.copyWith(
      revision: registry.revision + 1,
      activeTenantProfileId: tenant.tenantProfileId,
    );
  }

  Future<AppTenantRegistry> updateTenant(AppTenantUpdateInput input) async {
    final registry = await loadRegistry();
    final index = registry.tenants.indexWhere(
      (tenant) => tenant.id == input.id,
    );
    if (index < 0 || registry.tenants[index].isArchived) {
      throw const AppTenantValidationException('tenant_not_found');
    }
    final existing = registry.tenants[index];
    if (existing.isPrimaryTenant) {
      throw const AppTenantValidationException('tenant_default_edit_forbidden');
    }
    final name = normalizeTenantName(input.name);
    final backend = normalizeTenantBackendBaseUrl(input.backendBaseUrl);
    final didHost = normalizeTenantDidHost(input.didHost);
    if (await tenantHasData(existing.id) &&
        (backend.toLowerCase() != existing.backendBaseUrl.toLowerCase() ||
            didHost != existing.didHost)) {
      throw const AppTenantValidationException('tenant_has_data');
    }
    _assertUniqueName(registry, name, exceptId: existing.id);
    _assertUniqueEndpoint(registry, backend, didHost, exceptId: existing.id);
    final tenants = <AppTenantProfile>[...registry.tenants];
    tenants[index] = existing.copyWith(
      name: name,
      backendBaseUrl: backend,
      didHost: didHost,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    final next = AppTenantRegistry(
      revision: registry.revision + 1,
      activeTenantProfileId: registry.activeTenantProfileId,
      tenants: _sort(tenants),
    );
    await saveRegistry(next, expectedRevision: registry.revision);
    return next;
  }

  Future<AppTenantRegistry> deleteTenant(String tenantId) async {
    final registry = await loadRegistry();
    final target = _findVisible(registry, tenantId);
    if (target.isPrimaryTenant) {
      throw const AppTenantValidationException(
        'tenant_default_delete_forbidden',
      );
    }
    if (target.tenantProfileId == registry.activeTenantProfileId) {
      throw const AppTenantValidationException(
        'tenant_active_delete_forbidden',
      );
    }
    final tenants = registry.tenants
        .map(
          (tenant) => tenant.id == tenantId
              ? tenant.copyWith(
                  lifecycle: AppTenantLifecycle.archived,
                  updatedAt: DateTime.now().toUtc().toIso8601String(),
                )
              : tenant,
        )
        .toList();
    final next = AppTenantRegistry(
      revision: registry.revision + 1,
      activeTenantProfileId: registry.activeTenantProfileId,
      tenants: tenants,
    );
    await saveRegistry(next, expectedRevision: registry.revision);
    return next;
  }

  Future<bool> tenantHasData(String tenantId) async {
    final tenant = _findAny(await loadRegistry(), tenantId);
    final layout = await layoutForScope(tenant.storageScopeId);
    return await _hasData(File(layout.identityRegistryPath)) ||
        await _hasData(File(layout.defaultIdentityPath)) ||
        await _directoryHasData(Directory(layout.identityVaultRoot)) ||
        await _hasData(File(layout.imCoreSqlitePath)) ||
        await _hasData(File(layout.productDatabasePath)) ||
        await _directoryHasData(Directory(layout.attachmentsRoot));
  }

  Future<List<StorageScopeManifest>> discoverOrphanScopes() async {
    final registry = await loadRegistry();
    final owned = registry.tenants.map((item) => item.storageScopeId).toSet();
    final roots = Directory((await _layoutRoots()).scopesRoot);
    if (!await roots.exists()) return const [];
    final orphans = <StorageScopeManifest>[];
    await for (final entity in roots.list(followLinks: false)) {
      if (entity is! Directory) continue;
      StorageScopeId scopeId;
      try {
        scopeId = StorageScopeId.parse(p.basename(entity.path));
      } on FormatException {
        continue;
      }
      if (owned.contains(scopeId)) continue;
      final layout = await layoutForScope(scopeId);
      final recovered = await _provisioner.recoverOrphan(layout: layout);
      if (recovered != null) orphans.add(recovered);
    }
    return orphans;
  }

  Future<AwikiStorageScopeLayout> layoutForScope(StorageScopeId scopeId) async {
    final roots = await _roots();
    return AwikiStorageScopeLayout.fromRoots(
      appSupportRoot: roots.$1,
      cacheRoot: roots.$2,
      tempRoot: roots.$3,
      scopeId: scopeId,
    );
  }

  StorageScopeManifestStore get _manifestStore =>
      const StorageScopeManifestStore();
  StorageScopeProvisioner get _provisioner => StorageScopeProvisioner(
    secrets: _secretRepository,
    manifests: _manifestStore,
    secretFactory: (scopeId) =>
        ScopeSecretRecord(scopeId: scopeId, opaqueValue: Object()),
    faultInjector: _faultInjector,
  );

  Future<AppTenantRegistry> _createInitialRegistry() async {
    final tenant = defaultTenantProfile();
    await _provision(tenant);
    final registry = AppTenantRegistry(
      revision: 1,
      activeTenantProfileId: tenant.tenantProfileId,
      tenants: <AppTenantProfile>[tenant],
    );
    await saveRegistry(registry, expectedRevision: 0);
    return registry;
  }

  Future<void> _provision(AppTenantProfile tenant) async {
    await _provisioner.provision(
      layout: await layoutForScope(tenant.storageScopeId),
      owner: tenant,
    );
  }

  Future<void> _validateRegistryScopes(AppTenantRegistry registry) async {
    for (final tenant in registry.tenants) {
      final layout = await layoutForScope(tenant.storageScopeId);
      final manifest = await _manifestStore.readExisting(layout.manifestPath);
      if (manifest.storageScopeId != tenant.storageScopeId ||
          manifest.ownerTenantProfileId != tenant.tenantProfileId) {
        throw const FormatException('scope_manifest_mismatch');
      }
      if (!tenant.isArchived &&
          manifest.lifecycle != StorageScopeLifecycle.ready) {
        throw const FormatException('scope_not_ready');
      }
    }
  }

  Future<File> _registryFile() async =>
      File((await _layoutRoots()).registryPath);

  Future<AwikiStorageScopeLayout> _layoutRoots() async => layoutForScope(
    StorageScopeId.parse('00000000-0000-4000-8000-000000000000'),
  );

  Future<(String, String, String)> _roots() async {
    final explicit = _firstNonEmpty(appStateRoot, awikiE2eAppStateRoot());
    if (explicit != null) {
      return (
        p.join(explicit, 'support'),
        p.join(explicit, 'cache'),
        p.join(explicit, 'tmp'),
      );
    }
    return (
      (await getApplicationSupportDirectory()).path,
      (await getApplicationCacheDirectory()).path,
      Directory.systemTemp.path,
    );
  }
}

Future<AppTenantRegistry> _readRegistryFile(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) throw const FormatException('tenant_registry_invalid');
  return AppTenantRegistry.fromJson(
    decoded.map((key, value) => MapEntry(key.toString(), value)),
  );
}

Future<void> _writeRegistryAtomic(File file, AppTenantRegistry registry) async {
  await file.parent.create(recursive: true);
  final temp = File(
    '${file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
  );
  await temp.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(registry.toJson())}\n',
    flush: true,
  );
  await temp.rename(file.path);
}

String normalizeTenantName(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+', unicode: true), ' ');
  if (name.characters.isEmpty ||
      name.characters.length > AppTenantStore._maxTenantNameLength ||
      _containsInvisible(name)) {
    throw const AppTenantValidationException('tenant_name_invalid');
  }
  return name;
}

String normalizeTenantBackendBaseUrl(String raw) {
  final value = raw.trim().replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const AppTenantValidationException('tenant_backend_invalid');
  }
  return value;
}

String normalizeTenantDidHost(String raw) {
  final value = raw.trim().replaceAll(RegExp(r'^\.+|\.+$'), '').toLowerCase();
  if (!RegExp(r'^[a-z0-9.-]+\.[a-z0-9.-]+$').hasMatch(value)) {
    throw const AppTenantValidationException('tenant_did_host_invalid');
  }
  return value;
}

void _assertUniqueName(
  AppTenantRegistry registry,
  String name, {
  String? exceptId,
}) {
  if (registry.tenants.any(
    (tenant) =>
        tenant.id != exceptId &&
        !tenant.isArchived &&
        tenant.name.trim().toLowerCase() == name.toLowerCase(),
  )) {
    throw const AppTenantValidationException('tenant_name_exists');
  }
}

void _assertUniqueEndpoint(
  AppTenantRegistry registry,
  String backend,
  String didHost, {
  String? exceptId,
}) {
  if (registry.tenants.any(
    (tenant) =>
        tenant.id != exceptId &&
        !tenant.isArchived &&
        tenant.backendBaseUrl.toLowerCase() == backend.toLowerCase() &&
        tenant.didHost == didHost,
  )) {
    throw const AppTenantValidationException('tenant_endpoint_exists');
  }
}

AppTenantProfile _findVisible(AppTenantRegistry registry, String id) {
  final tenant = _findAny(registry, id);
  if (tenant.isArchived) {
    throw const AppTenantValidationException('tenant_not_found');
  }
  return tenant;
}

AppTenantProfile _findAny(AppTenantRegistry registry, String id) {
  for (final tenant in registry.tenants) {
    if (tenant.id == id) return tenant;
  }
  throw const AppTenantValidationException('tenant_not_found');
}

List<AppTenantProfile> _sort(List<AppTenantProfile> tenants) {
  tenants.sort((a, b) {
    if (a.isPrimaryTenant != b.isPrimaryTenant) {
      return a.isPrimaryTenant ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return tenants;
}

Future<bool> _hasData(File file) async =>
    await file.exists() && await file.length() > 0;

Future<bool> _directoryHasData(Directory directory) async {
  if (!await directory.exists()) return false;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && await entity.length() > 0) return true;
  }
  return false;
}

bool _containsInvisible(String value) => value.runes.any(
  (rune) =>
      rune <= 0x1f ||
      (rune >= 0x7f && rune <= 0x9f) ||
      (rune >= 0x200b && rune <= 0x200f) ||
      (rune >= 0x202a && rune <= 0x202e) ||
      (rune >= 0x2060 && rune <= 0x206f) ||
      rune == 0xfeff,
);

String? _firstNonEmpty(String? first, String? second) {
  if (first?.trim().isNotEmpty == true) return first!.trim();
  if (second?.trim().isNotEmpty == true) return second!.trim();
  return null;
}
