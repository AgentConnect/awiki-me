import 'package:flutter_riverpod/flutter_riverpod.dart';

const String primaryTenantName = 'AWiki';
const String primaryTenantBackendBaseUrl = 'https://awiki.ai';
const String primaryTenantDidHost = 'awiki.ai';
const String defaultTenantId = 'default';
// Keep the built-in AWiki tenant on the pre-multi-tenant namespace so existing
// identities, contacts and conversations remain visible after the registry is
// introduced. Custom tenants continue to use `tenant-<id>` namespaces.
const String defaultTenantStateNamespace = 'awiki.ai';

class AppTenantProfile {
  const AppTenantProfile({
    required this.id,
    required this.name,
    required this.backendBaseUrl,
    required this.didHost,
    required this.stateNamespace,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  factory AppTenantProfile.fromJson(Map<String, Object?> json) {
    return AppTenantProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      backendBaseUrl: json['backend_base_url']?.toString() ?? '',
      didHost: json['did_host']?.toString() ?? '',
      stateNamespace: json['state_namespace']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      archivedAt: _optionalString(json['archived_at']),
    );
  }

  final String id;
  final String name;
  final String backendBaseUrl;
  final String didHost;
  final String stateNamespace;
  final String createdAt;
  final String updatedAt;
  final String? archivedAt;

  bool get isArchived => archivedAt != null && archivedAt!.trim().isNotEmpty;

  bool get isPrimaryTenant =>
      _normalizeUrl(backendBaseUrl) == primaryTenantBackendBaseUrl &&
      _normalizeHost(didHost) == primaryTenantDidHost;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'backend_base_url': backendBaseUrl,
      'did_host': didHost,
      'state_namespace': stateNamespace,
      'created_at': createdAt,
      'updated_at': updatedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
    };
  }

  AppTenantProfile copyWith({
    String? name,
    String? backendBaseUrl,
    String? didHost,
    String? stateNamespace,
    String? updatedAt,
    String? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return AppTenantProfile(
      id: id,
      name: name ?? this.name,
      backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
      didHost: didHost ?? this.didHost,
      stateNamespace: stateNamespace ?? this.stateNamespace,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: clearArchivedAt ? null : archivedAt ?? this.archivedAt,
    );
  }
}

class AppTenantRegistry {
  const AppTenantRegistry({
    required this.activeTenantId,
    required this.tenants,
  });

  factory AppTenantRegistry.fromJson(Map<String, Object?> json) {
    final rawTenants = json['tenants'];
    return AppTenantRegistry(
      activeTenantId: json['active_tenant_id']?.toString() ?? defaultTenantId,
      tenants: rawTenants is Iterable
          ? rawTenants
                .whereType<Map>()
                .map(
                  (item) => AppTenantProfile.fromJson(
                    item.map<String, Object?>(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  ),
                )
                .where((tenant) => tenant.id.trim().isNotEmpty)
                .toList()
          : const <AppTenantProfile>[],
    );
  }

  final String activeTenantId;
  final List<AppTenantProfile> tenants;

  List<AppTenantProfile> get visibleTenants =>
      tenants.where((tenant) => !tenant.isArchived).toList();

  AppTenantProfile get activeTenant {
    for (final tenant in tenants) {
      if (tenant.id == activeTenantId && !tenant.isArchived) {
        return tenant;
      }
    }
    for (final tenant in tenants) {
      if (tenant.id == defaultTenantId && !tenant.isArchived) {
        return tenant;
      }
    }
    return defaultTenantProfile();
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema_version': 1,
      'active_tenant_id': activeTenantId,
      'tenants': tenants.map((tenant) => tenant.toJson()).toList(),
    };
  }

  AppTenantRegistry copyWith({
    String? activeTenantId,
    List<AppTenantProfile>? tenants,
  }) {
    return AppTenantRegistry(
      activeTenantId: activeTenantId ?? this.activeTenantId,
      tenants: tenants ?? this.tenants,
    );
  }
}

class AppTenantCreateInput {
  const AppTenantCreateInput({
    required this.name,
    required this.backendBaseUrl,
    required this.didHost,
  });

  final String name;
  final String backendBaseUrl;
  final String didHost;
}

class AppTenantUpdateInput {
  const AppTenantUpdateInput({
    required this.id,
    required this.name,
    required this.backendBaseUrl,
    required this.didHost,
  });

  final String id;
  final String name;
  final String backendBaseUrl;
  final String didHost;
}

abstract interface class AppTenantActions {
  Future<AppTenantRegistry> createTenant(AppTenantCreateInput input);

  Future<AppTenantRegistry> useTenant(String tenantId);

  Future<AppTenantRegistry> updateTenant(AppTenantUpdateInput input);

  Future<AppTenantRegistry> deleteTenant(String tenantId);

  Future<bool> tenantHasData(String tenantId);
}

class DisabledAppTenantActions implements AppTenantActions {
  const DisabledAppTenantActions();

  @override
  Future<AppTenantRegistry> createTenant(AppTenantCreateInput input) {
    throw StateError('tenant_actions_unavailable');
  }

  @override
  Future<AppTenantRegistry> useTenant(String tenantId) {
    throw StateError('tenant_actions_unavailable');
  }

  @override
  Future<AppTenantRegistry> updateTenant(AppTenantUpdateInput input) {
    throw StateError('tenant_actions_unavailable');
  }

  @override
  Future<AppTenantRegistry> deleteTenant(String tenantId) {
    throw StateError('tenant_actions_unavailable');
  }

  @override
  Future<bool> tenantHasData(String tenantId) async => false;
}

final appTenantRegistryProvider = Provider<AppTenantRegistry>(
  (ref) => AppTenantRegistry(
    activeTenantId: defaultTenantId,
    tenants: <AppTenantProfile>[defaultTenantProfile()],
  ),
);

final activeAppTenantProvider = Provider<AppTenantProfile>(
  (ref) => ref.watch(appTenantRegistryProvider).activeTenant,
);

final appTenantActionsProvider = Provider<AppTenantActions>(
  (ref) => const DisabledAppTenantActions(),
);

AppTenantProfile defaultTenantProfile({DateTime? now}) {
  final timestamp = _timestamp(now ?? DateTime.now().toUtc());
  return AppTenantProfile(
    id: defaultTenantId,
    name: primaryTenantName,
    backendBaseUrl: primaryTenantBackendBaseUrl,
    didHost: primaryTenantDidHost,
    stateNamespace: defaultTenantStateNamespace,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

String appTenantFeatureUnsupportedCode(String feature) {
  return 'tenant_feature_unsupported:$feature';
}

String _timestamp(DateTime value) => value.toUtc().toIso8601String();

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _normalizeUrl(String value) {
  return value.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
}

String _normalizeHost(String value) {
  return value.trim().replaceAll(RegExp(r'\.+$'), '').toLowerCase();
}
