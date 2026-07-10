import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../application/tenant/app_tenant.dart';
import '../im_core/awiki_im_core_paths.dart';
import '../local/awiki_product_local_store_sqlite.dart';

class AppTenantValidationException implements Exception {
  const AppTenantValidationException(this.code);

  final String code;

  @override
  String toString() => code;
}

class AppTenantStore {
  AppTenantStore({required this.appStateRoot});

  final String? appStateRoot;

  static const String registryFileName = 'registry.json';
  static const int _maxTenantNameLength = 40;
  static const int _maxTenantIdBaseLength = 48;

  Future<AppTenantRegistry> loadRegistry() async {
    final file = await _registryFile();
    if (!await file.exists()) {
      final registry = normalizeTenantRegistry(
        AppTenantRegistry(
          activeTenantId: defaultTenantId,
          tenants: <AppTenantProfile>[defaultTenantProfile()],
        ),
      );
      await saveRegistry(registry);
      return registry;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      final registry = normalizeTenantRegistry(
        AppTenantRegistry(
          activeTenantId: defaultTenantId,
          tenants: <AppTenantProfile>[defaultTenantProfile()],
        ),
      );
      await saveRegistry(registry);
      return registry;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('tenant registry must be an object');
    }
    final registry = normalizeTenantRegistry(
      AppTenantRegistry.fromJson(
        decoded.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      ),
    );
    if (jsonEncode(decoded) != jsonEncode(registry.toJson())) {
      await saveRegistry(registry);
    }
    return registry;
  }

  Future<void> saveRegistry(AppTenantRegistry registry) async {
    final file = await _registryFile();
    await file.parent.create(recursive: true);
    final tmp = File(
      '${file.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString(
      '${encoder.convert(registry.toJson())}\n',
      flush: true,
    );
    await tmp.rename(file.path);
  }

  Future<AppTenantRegistry> createTenant(AppTenantCreateInput input) async {
    final registry = await loadRegistry();
    final now = DateTime.now().toUtc();
    final name = normalizeTenantName(input.name);
    final backendBaseUrl = normalizeTenantBackendBaseUrl(input.backendBaseUrl);
    final didHost = normalizeTenantDidHost(input.didHost);
    _assertUniqueName(registry, name);
    _assertUniqueEndpoint(registry, backendBaseUrl, didHost);
    final id = _uniqueTenantId(
      registry,
      name: name,
      backendBaseUrl: backendBaseUrl,
      didHost: didHost,
    );
    final tenant = AppTenantProfile(
      id: id,
      name: name,
      backendBaseUrl: backendBaseUrl,
      didHost: didHost,
      stateNamespace: 'tenant-$id',
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
    await _ensureTenantDirectories(tenant);
    final next = registry.copyWith(
      tenants: _sortTenants(<AppTenantProfile>[...registry.tenants, tenant]),
    );
    await saveRegistry(next);
    return next;
  }

  Future<AppTenantRegistry> useTenant(String tenantId) async {
    final next = await prepareUseTenant(tenantId);
    await saveRegistry(next);
    return next;
  }

  Future<AppTenantRegistry> prepareUseTenant(String tenantId) async {
    final registry = await loadRegistry();
    final tenant = _findVisibleTenant(registry, tenantId);
    await _ensureTenantDirectories(tenant);
    return registry.copyWith(activeTenantId: tenant.id);
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
    if (existing.id == defaultTenantId || existing.isPrimaryTenant) {
      throw const AppTenantValidationException('tenant_default_edit_forbidden');
    }
    final name = normalizeTenantName(input.name);
    final backendBaseUrl = normalizeTenantBackendBaseUrl(input.backendBaseUrl);
    final didHost = normalizeTenantDidHost(input.didHost);
    if (await tenantHasData(existing.id)) {
      final backendChanged =
          backendBaseUrl.toLowerCase() != existing.backendBaseUrl.toLowerCase();
      final didHostChanged =
          didHost.toLowerCase() != existing.didHost.toLowerCase();
      if (backendChanged || didHostChanged) {
        throw const AppTenantValidationException('tenant_has_data');
      }
    }
    _assertUniqueName(registry, name, exceptId: existing.id);
    _assertUniqueEndpoint(
      registry,
      backendBaseUrl,
      didHost,
      exceptId: existing.id,
    );
    final updated = existing.copyWith(
      name: name,
      backendBaseUrl: backendBaseUrl,
      didHost: didHost,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    final tenants = <AppTenantProfile>[...registry.tenants];
    tenants[index] = updated;
    final next = registry.copyWith(tenants: _sortTenants(tenants));
    await saveRegistry(next);
    return next;
  }

  Future<AppTenantRegistry> deleteTenant(String tenantId) async {
    final registry = await loadRegistry();
    final target = _findVisibleTenant(registry, tenantId);
    if (target.id == defaultTenantId || target.isPrimaryTenant) {
      throw const AppTenantValidationException(
        'tenant_default_delete_forbidden',
      );
    }
    if (target.id == registry.activeTenantId) {
      throw const AppTenantValidationException(
        'tenant_active_delete_forbidden',
      );
    }
    final tenants = registry.tenants.map((tenant) {
      if (tenant.id != target.id) {
        return tenant;
      }
      return tenant.copyWith(
        archivedAt: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }).toList();
    final next = registry.copyWith(tenants: tenants);
    await saveRegistry(next);
    return next;
  }

  Future<bool> tenantHasData(String tenantId) async {
    final registry = await loadRegistry();
    final tenant = registry.tenants.firstWhere(
      (item) => item.id == tenantId,
      orElse: () =>
          throw const AppTenantValidationException('tenant_not_found'),
    );
    final layout = await _pathLayoutForTenant(tenant);
    final productDb = await _productDatabaseFileForTenant(tenant);
    return await _fileHasData(File(layout.registryPath)) ||
        await _fileHasData(File(layout.defaultIdentityPath)) ||
        await _directoryHasAnyFile(Directory(layout.identityRootDir)) ||
        await _directoryHasAnyFile(Directory(layout.vaultDir)) ||
        await _fileHasData(File(layout.sqlitePath)) ||
        await _fileHasData(productDb);
  }

  Future<File> _registryFile() async {
    final root = await _globalSupportRoot();
    return File(p.join(root, 'awiki-me', 'tenants', registryFileName));
  }

  Future<String> _globalSupportRoot() async {
    final e2eRoot = awikiE2eAppStateRoot();
    final stateRoot = _firstNonEmpty(appStateRoot, e2eRoot);
    if (stateRoot != null) {
      return p.join(stateRoot, 'support');
    }
    return (await getApplicationSupportDirectory()).path;
  }

  Future<String> _globalCacheRoot() async {
    final e2eRoot = awikiE2eAppStateRoot();
    final stateRoot = _firstNonEmpty(appStateRoot, e2eRoot);
    if (stateRoot != null) {
      return p.join(stateRoot, 'cache');
    }
    return (await getApplicationCacheDirectory()).path;
  }

  Future<String> _globalTempRoot() async {
    final e2eRoot = awikiE2eAppStateRoot();
    final stateRoot = _firstNonEmpty(appStateRoot, e2eRoot);
    if (stateRoot != null) {
      return p.join(stateRoot, 'tmp');
    }
    return Directory.systemTemp.path;
  }

  Future<AwikiImCorePathLayout> _pathLayoutForTenant(
    AppTenantProfile tenant,
  ) async {
    return AwikiImCorePathLayout.fromRoots(
      appSupportRoot: await _globalSupportRoot(),
      cacheRoot: await _globalCacheRoot(),
      tempRoot: await _globalTempRoot(),
      stateNamespace: tenant.stateNamespace,
    );
  }

  Future<File> _productDatabaseFileForTenant(AppTenantProfile tenant) async {
    final e2eRoot = awikiE2eAppStateRoot();
    final stateRoot = _firstNonEmpty(appStateRoot, e2eRoot);
    if (stateRoot != null) {
      return File(
        p.join(
          stateRoot,
          'support',
          'awiki-me',
          'environments',
          tenant.stateNamespace,
          'product',
          AwikiProductLocalStoreSqlite.databaseName,
        ),
      );
    }
    final support = await getApplicationSupportDirectory();
    return File(
      p.join(
        support.path,
        'awiki-me',
        'environments',
        tenant.stateNamespace,
        'product',
        AwikiProductLocalStoreSqlite.databaseName,
      ),
    );
  }

  Future<void> _ensureTenantDirectories(AppTenantProfile tenant) async {
    await (await _pathLayoutForTenant(tenant)).ensureDirectories();
    await (await _productDatabaseFileForTenant(
      tenant,
    )).parent.create(recursive: true);
  }

  String _uniqueTenantId(
    AppTenantRegistry registry, {
    required String name,
    required String backendBaseUrl,
    required String didHost,
  }) {
    final backendHost = Uri.tryParse(backendBaseUrl)?.host ?? '';
    final base =
        _safeSegmentCandidate(name) ??
        _safeSegmentCandidate(didHost) ??
        _safeSegmentCandidate(backendHost) ??
        'tenant';
    final used = registry.tenants.map((tenant) => tenant.id).toSet();
    if (!used.contains(base)) {
      return base;
    }
    var suffix = 2;
    while (used.contains('$base-$suffix')) {
      suffix += 1;
    }
    return '$base-$suffix';
  }
}

AppTenantRegistry normalizeTenantRegistry(AppTenantRegistry registry) {
  final defaultTenant = defaultTenantProfile();
  final byId = <String, AppTenantProfile>{};
  for (final tenant in <AppTenantProfile>[defaultTenant, ...registry.tenants]) {
    final normalized = _normalizeProfile(tenant);
    if (normalized.id.trim().isEmpty) {
      continue;
    }
    byId[normalized.id] = normalized;
  }
  var active = registry.activeTenantId.trim();
  if (active.isEmpty ||
      byId[active]?.isArchived == true ||
      byId[active] == null) {
    active = defaultTenantId;
  }
  return AppTenantRegistry(
    activeTenantId: active,
    tenants: _sortTenants(byId.values.toList()),
  );
}

AppTenantProfile _normalizeProfile(AppTenantProfile tenant) {
  final fallback = defaultTenantProfile();
  final id = tenant.id.trim().isEmpty ? _safeSegment(tenant.name) : tenant.id;
  final stateNamespace = tenant.stateNamespace.trim().isEmpty
      ? 'tenant-$id'
      : normalizeAwikiStateNamespace(tenant.stateNamespace);
  return AppTenantProfile(
    id: id,
    name: _normalizeTenantNameOrFallback(tenant.name, fallback.name),
    backendBaseUrl: normalizeTenantBackendBaseUrl(
      tenant.backendBaseUrl.trim().isEmpty
          ? fallback.backendBaseUrl
          : tenant.backendBaseUrl,
    ),
    didHost: normalizeTenantDidHost(
      tenant.didHost.trim().isEmpty ? fallback.didHost : tenant.didHost,
    ),
    stateNamespace: stateNamespace,
    createdAt: tenant.createdAt.trim().isEmpty
        ? fallback.createdAt
        : tenant.createdAt,
    updatedAt: tenant.updatedAt.trim().isEmpty
        ? fallback.updatedAt
        : tenant.updatedAt,
    archivedAt: tenant.archivedAt,
  );
}

String normalizeTenantName(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+', unicode: true), ' ');
  final length = name.characters.length;
  if (length < 1 || length > AppTenantStore._maxTenantNameLength) {
    throw const AppTenantValidationException('tenant_name_invalid');
  }
  if (_containsUnsupportedTenantNameCharacter(name)) {
    throw const AppTenantValidationException('tenant_name_invalid');
  }
  return name;
}

String _normalizeTenantNameOrFallback(String raw, String fallback) {
  try {
    return normalizeTenantName(raw);
  } on AppTenantValidationException {
    return normalizeTenantName(fallback);
  }
}

String normalizeTenantBackendBaseUrl(String raw) {
  final value = raw.trim().replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.trim().isEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const AppTenantValidationException('tenant_backend_invalid');
  }
  return value;
}

String normalizeTenantDidHost(String raw) {
  final value = raw.trim().replaceAll(RegExp(r'^\.+|\.+$'), '').toLowerCase();
  if (value.isEmpty ||
      value.contains('/') ||
      value.contains(':') ||
      !RegExp(r'^[a-z0-9.-]+$').hasMatch(value) ||
      !value.contains('.')) {
    throw const AppTenantValidationException('tenant_did_host_invalid');
  }
  return value;
}

void _assertUniqueName(
  AppTenantRegistry registry,
  String name, {
  String? exceptId,
}) {
  final normalized = _tenantNameKey(name);
  final exists = registry.tenants.any(
    (tenant) =>
        tenant.id != exceptId &&
        !tenant.isArchived &&
        _tenantNameKey(tenant.name) == normalized,
  );
  if (exists) {
    throw const AppTenantValidationException('tenant_name_exists');
  }
}

void _assertUniqueEndpoint(
  AppTenantRegistry registry,
  String backendBaseUrl,
  String didHost, {
  String? exceptId,
}) {
  final base = backendBaseUrl.toLowerCase();
  final host = didHost.toLowerCase();
  final exists = registry.tenants.any(
    (tenant) =>
        tenant.id != exceptId &&
        !tenant.isArchived &&
        tenant.backendBaseUrl.toLowerCase() == base &&
        tenant.didHost.toLowerCase() == host,
  );
  if (exists) {
    throw const AppTenantValidationException('tenant_endpoint_exists');
  }
}

AppTenantProfile _findVisibleTenant(
  AppTenantRegistry registry,
  String tenantId,
) {
  for (final tenant in registry.tenants) {
    if (tenant.id == tenantId && !tenant.isArchived) {
      return tenant;
    }
  }
  throw const AppTenantValidationException('tenant_not_found');
}

List<AppTenantProfile> _sortTenants(List<AppTenantProfile> tenants) {
  tenants.sort((left, right) {
    if (left.id == defaultTenantId) {
      return -1;
    }
    if (right.id == defaultTenantId) {
      return 1;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
  return tenants;
}

Future<bool> _fileHasData(File file) async {
  if (!await file.exists()) {
    return false;
  }
  return file.length().then((length) => length > 0);
}

Future<bool> _directoryHasAnyFile(Directory directory) async {
  if (!await directory.exists()) {
    return false;
  }
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && await entity.length() > 0) {
      return true;
    }
  }
  return false;
}

bool _containsUnsupportedTenantNameCharacter(String value) {
  for (final rune in value.runes) {
    if (rune <= 0x1F || (rune >= 0x7F && rune <= 0x9F)) {
      return true;
    }
    if ((rune >= 0x200B && rune <= 0x200F) ||
        (rune >= 0x202A && rune <= 0x202E) ||
        (rune >= 0x2060 && rune <= 0x206F) ||
        rune == 0xFEFF) {
      return true;
    }
  }
  return false;
}

String _tenantNameKey(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'\s+', unicode: true), ' ')
      .toLowerCase();
}

String _safeSegment(String raw) {
  return _safeSegmentCandidate(raw) ?? 'tenant';
}

String? _safeSegmentCandidate(String raw) {
  final safe = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
  if (safe.isEmpty) {
    return null;
  }
  if (safe.length <= AppTenantStore._maxTenantIdBaseLength) {
    return safe;
  }
  final capped = safe
      .substring(0, AppTenantStore._maxTenantIdBaseLength)
      .replaceAll(RegExp(r'[-_]+$'), '');
  return capped.isEmpty ? null : capped;
}

String? _firstNonEmpty(String? first, String? second) {
  final firstTrimmed = first?.trim();
  if (firstTrimmed != null && firstTrimmed.isNotEmpty) {
    return firstTrimmed;
  }
  final secondTrimmed = second?.trim();
  if (secondTrimmed != null && secondTrimmed.isNotEmpty) {
    return secondTrimmed;
  }
  return null;
}
