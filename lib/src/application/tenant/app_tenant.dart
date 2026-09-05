import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/awiki_environment_config.dart';
import 'builtin_tenant_config.dart';

const int officialTenantCatalogVersion = 2;
String get primaryBuiltinTenantName => builtinTenantCatalog.primary.displayName;
String get primaryBuiltinTenantBackendBaseUrl =>
    builtinTenantCatalog.primary.backendOrigin;
String get primaryBuiltinTenantDidHost => builtinTenantCatalog.primary.didHost;
String get secondaryBuiltinTenantName =>
    builtinTenantCatalog.secondary.displayName;
String get secondaryBuiltinTenantBackendBaseUrl =>
    builtinTenantCatalog.secondary.backendOrigin;
String get secondaryBuiltinTenantDidHost =>
    builtinTenantCatalog.secondary.didHost;
String get primaryTenantName =>
    builtinTenantCatalog.forSlot(builtinTenantCatalog.defaultSlot).displayName;
String get primaryTenantBackendBaseUrl => primaryTenantBaseUrl;
String get primaryTenantDidHost => primaryTenantDomain;

final RegExp _canonicalUuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

abstract base class CanonicalUuidV4 {
  const CanonicalUuidV4._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is CanonicalUuidV4 &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

final class TenantProfileId extends CanonicalUuidV4 {
  TenantProfileId.parse(String value) : super._(_validateUuid(value));

  factory TenantProfileId.generate({Random? random}) =>
      TenantProfileId.parse(_generateUuidV4(random ?? Random.secure()));
}

final class StorageScopeId extends CanonicalUuidV4 {
  StorageScopeId.parse(String value) : super._(_validateUuid(value));

  factory StorageScopeId.generate({Random? random}) =>
      StorageScopeId.parse(_generateUuidV4(random ?? Random.secure()));
}

enum AppTenantKind {
  builtInAwiki('built_in_awiki'),
  custom('custom');

  const AppTenantKind(this.wireName);
  final String wireName;

  static AppTenantKind parse(Object? value) => values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => throw const FormatException('tenant_kind_invalid'),
  );
}

enum AppTenantOfficialKey {
  primary('builtin-primary'),
  secondary('builtin-secondary');

  const AppTenantOfficialKey(this.wireName);
  final String wireName;

  static AppTenantOfficialKey? parseOptional(Object? value) {
    if (value == null) return null;
    return switch (value) {
      'builtin-primary' || 'china' => AppTenantOfficialKey.primary,
      'builtin-secondary' || 'global' => AppTenantOfficialKey.secondary,
      _ => throw const FormatException('tenant_official_key_invalid'),
    };
  }
}

enum AppTenantLifecycle {
  active('active'),
  archived('archived');

  const AppTenantLifecycle(this.wireName);
  final String wireName;

  static AppTenantLifecycle parse(Object? value) => values.firstWhere(
    (item) => item.wireName == value,
    orElse: () => throw const FormatException('tenant_lifecycle_invalid'),
  );
}

class AppTenantProfile {
  const AppTenantProfile({
    required this.tenantProfileId,
    required this.storageScopeId,
    required this.kind,
    required this.name,
    required this.backendBaseUrl,
    required this.didHost,
    required this.lifecycle,
    required this.createdAt,
    required this.updatedAt,
    this.officialKey,
    this.remoteRealmId,
  });

  factory AppTenantProfile.fromJson(Map<String, Object?> json) {
    return AppTenantProfile(
      tenantProfileId: TenantProfileId.parse(
        _requiredString(json, 'tenant_profile_id'),
      ),
      storageScopeId: StorageScopeId.parse(
        _requiredString(json, 'storage_scope_id'),
      ),
      kind: AppTenantKind.parse(json['kind']),
      officialKey: AppTenantOfficialKey.parseOptional(json['official_key']),
      name: _requiredString(json, 'display_name'),
      backendBaseUrl: _requiredString(json, 'backend_base_url'),
      didHost: _requiredString(json, 'did_host'),
      remoteRealmId: _optionalString(json['remote_realm_id']),
      lifecycle: AppTenantLifecycle.parse(json['lifecycle']),
      createdAt: _requiredTimestamp(json, 'created_at'),
      updatedAt: _requiredTimestamp(json, 'updated_at'),
    );
  }

  final TenantProfileId tenantProfileId;
  final StorageScopeId storageScopeId;
  final AppTenantKind kind;
  final AppTenantOfficialKey? officialKey;
  final String name;
  final String backendBaseUrl;
  final String didHost;
  final String? remoteRealmId;
  final AppTenantLifecycle lifecycle;
  final String createdAt;
  final String updatedAt;

  String get id => tenantProfileId.value;

  bool get isArchived => lifecycle == AppTenantLifecycle.archived;
  bool get isPrimaryTenant => kind == AppTenantKind.builtInAwiki;
  bool get isOfficialTenant => officialKey != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'tenant_profile_id': tenantProfileId.value,
    'storage_scope_id': storageScopeId.value,
    'kind': kind.wireName,
    'official_key': officialKey?.wireName,
    'display_name': name,
    'backend_base_url': backendBaseUrl,
    'did_host': didHost,
    'remote_realm_id': remoteRealmId,
    'lifecycle': lifecycle.wireName,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  AppTenantProfile copyWith({
    AppTenantKind? kind,
    AppTenantOfficialKey? officialKey,
    bool clearOfficialKey = false,
    String? name,
    String? backendBaseUrl,
    String? didHost,
    String? remoteRealmId,
    AppTenantLifecycle? lifecycle,
    String? updatedAt,
  }) => AppTenantProfile(
    tenantProfileId: tenantProfileId,
    storageScopeId: storageScopeId,
    kind: kind ?? this.kind,
    officialKey: clearOfficialKey ? null : officialKey ?? this.officialKey,
    name: name ?? this.name,
    backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
    didHost: didHost ?? this.didHost,
    remoteRealmId: remoteRealmId ?? this.remoteRealmId,
    lifecycle: lifecycle ?? this.lifecycle,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

class AppTenantRegistry {
  const AppTenantRegistry({
    required this.revision,
    required this.activeTenantProfileId,
    required this.tenants,
    this.officialCatalogVersion = 0,
  });

  factory AppTenantRegistry.fromJson(Map<String, Object?> json) {
    if (json['schema_version'] != 1) {
      throw const FormatException('tenant_registry_schema_unsupported');
    }
    final revision = json['revision'];
    final rawTenants = json['tenants'];
    if (revision is! int || revision < 1 || rawTenants is! List) {
      throw const FormatException('tenant_registry_invalid');
    }
    final registry = AppTenantRegistry(
      revision: revision,
      officialCatalogVersion: json['official_catalog_version'] is int
          ? json['official_catalog_version']! as int
          : 0,
      activeTenantProfileId: TenantProfileId.parse(
        _requiredString(json, 'active_tenant_profile_id'),
      ),
      tenants: rawTenants
          .map((item) {
            if (item is! Map) {
              throw const FormatException('tenant_registry_invalid');
            }
            return AppTenantProfile.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            );
          })
          .toList(growable: false),
    );
    registry.validate();
    return registry;
  }

  final int revision;
  final int officialCatalogVersion;
  final TenantProfileId activeTenantProfileId;
  final List<AppTenantProfile> tenants;

  List<AppTenantProfile> get visibleTenants =>
      tenants.where((tenant) => !tenant.isArchived).toList(growable: false);
  AppTenantProfile get activeTenant => tenants.singleWhere(
    (tenant) =>
        tenant.tenantProfileId == activeTenantProfileId && !tenant.isArchived,
    orElse: () => throw StateError('active_tenant_missing'),
  );

  void validate() {
    final profiles = <TenantProfileId>{};
    final scopes = <StorageScopeId>{};
    final officialKeys = <AppTenantOfficialKey>{};
    for (final tenant in tenants) {
      if (!profiles.add(tenant.tenantProfileId)) {
        throw const FormatException('tenant_profile_duplicate');
      }
      if (!scopes.add(tenant.storageScopeId)) {
        throw const FormatException('storage_scope_duplicate');
      }
      final officialKey = tenant.officialKey;
      if (officialKey != null) {
        if (tenant.kind != AppTenantKind.builtInAwiki) {
          throw const FormatException('tenant_official_kind_invalid');
        }
        if (!officialKeys.add(officialKey)) {
          throw const FormatException('tenant_official_key_duplicate');
        }
      }
    }
    if (!tenants.any(
      (tenant) =>
          tenant.tenantProfileId == activeTenantProfileId && !tenant.isArchived,
    )) {
      throw const FormatException('active_tenant_missing');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema_version': 1,
    'official_catalog_version': officialCatalogVersion,
    'revision': revision,
    'active_tenant_profile_id': activeTenantProfileId.value,
    'tenants': tenants.map((tenant) => tenant.toJson()).toList(),
  };

  AppTenantRegistry copyWith({
    int? revision,
    int? officialCatalogVersion,
    TenantProfileId? activeTenantProfileId,
    List<AppTenantProfile>? tenants,
  }) {
    final nextTenants = tenants ?? this.tenants;
    return AppTenantRegistry(
      revision: revision ?? this.revision,
      officialCatalogVersion:
          officialCatalogVersion ?? this.officialCatalogVersion,
      activeTenantProfileId:
          activeTenantProfileId ?? this.activeTenantProfileId,
      tenants: nextTenants,
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

final appTenantRegistryProvider = Provider<AppTenantRegistry>((ref) {
  return defaultTenantRegistry();
});
final activeAppTenantProvider = Provider<AppTenantProfile>(
  (ref) => ref.watch(appTenantRegistryProvider).activeTenant,
);
final appTenantActionsProvider = Provider<AppTenantActions>(
  (ref) => const DisabledAppTenantActions(),
);

AppTenantProfile defaultTenantProfile({DateTime? now}) {
  final officialKey =
      builtinTenantCatalog.defaultSlot == BuiltinTenantSlot.primary
      ? AppTenantOfficialKey.primary
      : AppTenantOfficialKey.secondary;
  final name = switch (officialKey) {
    AppTenantOfficialKey.primary => primaryBuiltinTenantName,
    AppTenantOfficialKey.secondary => secondaryBuiltinTenantName,
  };
  final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
  return AppTenantProfile(
    tenantProfileId: TenantProfileId.generate(),
    storageScopeId: StorageScopeId.generate(),
    kind: AppTenantKind.builtInAwiki,
    officialKey: officialKey,
    name: name,
    backendBaseUrl: primaryTenantBackendBaseUrl,
    didHost: primaryTenantDidHost,
    lifecycle: AppTenantLifecycle.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

AppTenantProfile officialTenantProfile(
  AppTenantOfficialKey key, {
  DateTime? now,
}) {
  final timestamp = (now ?? DateTime.now()).toUtc().toIso8601String();
  return AppTenantProfile(
    tenantProfileId: TenantProfileId.generate(),
    storageScopeId: StorageScopeId.generate(),
    kind: AppTenantKind.builtInAwiki,
    officialKey: key,
    name: key == AppTenantOfficialKey.primary
        ? primaryBuiltinTenantName
        : secondaryBuiltinTenantName,
    backendBaseUrl: key == AppTenantOfficialKey.primary
        ? primaryBuiltinTenantBackendBaseUrl
        : secondaryBuiltinTenantBackendBaseUrl,
    didHost: key == AppTenantOfficialKey.primary
        ? primaryBuiltinTenantDidHost
        : secondaryBuiltinTenantDidHost,
    lifecycle: AppTenantLifecycle.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

AppTenantRegistry defaultTenantRegistry({DateTime? now}) {
  final initial = defaultTenantProfile(now: now);
  final tenants = <AppTenantProfile>[initial];
  for (final key in AppTenantOfficialKey.values) {
    if (initial.officialKey != key) {
      tenants.add(officialTenantProfile(key, now: now));
    }
  }
  return AppTenantRegistry(
    revision: 1,
    officialCatalogVersion: officialTenantCatalogVersion,
    activeTenantProfileId: initial.tenantProfileId,
    tenants: tenants,
  );
}

String appTenantFeatureUnsupportedCode(String feature) =>
    'tenant_feature_unsupported:$feature';

String _validateUuid(String value) {
  if (!_canonicalUuidV4.hasMatch(value)) {
    throw const FormatException('uuid_v4_invalid');
  }
  return value;
}

String _generateUuidV4(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('${key}_invalid');
  }
  return value;
}

String _requiredTimestamp(Map<String, Object?> json, String key) {
  final value = _requiredString(json, key);
  if (DateTime.tryParse(value) == null) {
    throw FormatException('${key}_invalid');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('optional_string_invalid');
  }
  return value;
}
